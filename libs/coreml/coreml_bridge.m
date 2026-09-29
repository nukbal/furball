#import "coreml_bridge.h"

#import <CoreML/CoreML.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <math.h>

static MLModel *cached_models[FURBALL_COREML_MODEL_INSTANCES];
static NSString *cached_input_names[FURBALL_COREML_MODEL_INSTANCES];
static NSString *cached_output_names[FURBALL_COREML_MODEL_INSTANCES];
static uint8_t cached_package_ids[FURBALL_COREML_MODEL_INSTANCES] = { UINT8_MAX, UINT8_MAX, UINT8_MAX, UINT8_MAX };
static BOOL cached_image_ios[FURBALL_COREML_MODEL_INSTANCES];
static NSObject *model_locks[FURBALL_COREML_MODEL_INSTANCES];
static dispatch_once_t model_locks_once;

static void initialize_model_locks(void) {
    dispatch_once(&model_locks_once, ^{
        for (NSUInteger slot = 0; slot < FURBALL_COREML_MODEL_INSTANCES; slot++) {
            model_locks[slot] = [[NSObject alloc] init];
        }
    });
}

static NSString *package_name(uint8_t model_id) {
    switch (model_id) {
        case FURBALL_COREML_REAL_ESRGAN_X2:
            return @"RealESRGAN_animevideo_x2_522_fp16.mlpackage";
        case FURBALL_COREML_REAL_ESRGAN_X4:
            return @"RealESRGAN_animevideo_x4_522_fp16.mlpackage";
        case FURBALL_COREML_PIPERSR_X2:
            return @"PiperSR_2x_256.mlpackage";
        default:
            return nil;
    }
}

static NSUInteger model_input_size(uint8_t model_id) {
    switch (model_id) {
        case FURBALL_COREML_REAL_ESRGAN_X2:
        case FURBALL_COREML_REAL_ESRGAN_X4:
            return 522;
        case FURBALL_COREML_PIPERSR_X2:
            return 256;
        default:
            return 0;
    }
}

static NSUInteger prediction_scale(uint8_t model_id) {
    switch (model_id) {
        case FURBALL_COREML_REAL_ESRGAN_X2:
        case FURBALL_COREML_PIPERSR_X2:
            return 2;
        case FURBALL_COREML_REAL_ESRGAN_X4:
            return 4;
        default:
            return 0;
    }
}

static NSUInteger result_scale(uint8_t model_id) {
    switch (model_id) {
        case FURBALL_COREML_REAL_ESRGAN_X2:
        case FURBALL_COREML_PIPERSR_X2:
            return 2;
        case FURBALL_COREML_REAL_ESRGAN_X4:
            return 4;
        default:
            return 0;
    }
}

static NSURL *model_package_url(uint8_t model_id) {
    NSString *name = package_name(model_id);
    if (name == nil) return nil;

    NSFileManager *file_manager = [NSFileManager defaultManager];
    NSString *resource_path = [NSBundle mainBundle].resourcePath;
    if (resource_path != nil) {
        NSString *bundle_models = [resource_path stringByAppendingPathComponent:@"models"];
        NSURL *bundle_url = [NSURL fileURLWithPath:[bundle_models stringByAppendingPathComponent:name] isDirectory:YES];
        if ([file_manager fileExistsAtPath:bundle_url.path]) return bundle_url;
    }

    NSString *source_models = [[file_manager currentDirectoryPath] stringByAppendingPathComponent:@"src/models"];
    NSURL *source_url = [NSURL fileURLWithPath:[source_models stringByAppendingPathComponent:name] isDirectory:YES];
    if ([file_manager fileExistsAtPath:source_url.path]) return source_url;
    return nil;
}

static NSURL *compiled_model_url(NSURL *package_url) {
    NSFileManager *file_manager = [NSFileManager defaultManager];
    NSURL *cache_url = [[[[[file_manager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject]
        URLByAppendingPathComponent:@"dev.nukbal.furball" isDirectory:YES]
        URLByAppendingPathComponent:@"CoreML" isDirectory:YES]
        URLByAppendingPathComponent:@"v2" isDirectory:YES];
    if (![file_manager createDirectoryAtURL:cache_url withIntermediateDirectories:YES attributes:nil error:nil]) return nil;

    NSString *compiled_name = [[package_url.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"mlmodelc"];
    NSURL *destination_url = [cache_url URLByAppendingPathComponent:compiled_name isDirectory:YES];
    if ([file_manager fileExistsAtPath:destination_url.path]) return destination_url;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSURL *compiled_url = nil;
    [MLModel compileModelAtURL:package_url completionHandler:^(NSURL *url, NSError *error) {
        if (error == nil) compiled_url = url;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (compiled_url == nil) return nil;
    if (![file_manager copyItemAtURL:compiled_url toURL:destination_url error:nil]) return nil;
    return destination_url;
}

static BOOL load_model(uint8_t model_id, uint8_t model_slot) {
    if (cached_models[model_slot] != nil && cached_package_ids[model_slot] == model_id) return YES;

    NSURL *package_url = model_package_url(model_id);
    if (package_url == nil) return NO;
    NSURL *model_url = nil;
    @synchronized([MLModel class]) {
        model_url = compiled_model_url(package_url);
    }
    if (model_url == nil) return NO;

    NSError *error = nil;
    MLModelConfiguration *configuration = [[MLModelConfiguration alloc] init];
    configuration.computeUnits = MLComputeUnitsAll;
    MLModel *model = [MLModel modelWithContentsOfURL:model_url configuration:configuration error:&error];
    if (model == nil) return NO;

    NSDictionary<NSString *, MLFeatureDescription *> *inputs = model.modelDescription.inputDescriptionsByName;
    NSString *input_name = inputs.allKeys.firstObject;
    MLFeatureDescription *input = input_name == nil ? nil : inputs[input_name];
    if (input == nil) return NO;

    const NSUInteger input_size = model_input_size(model_id);
    BOOL image_io = input.type == MLFeatureTypeImage;
    if (image_io) {
        if (input.imageConstraint.pixelsWide != input_size || input.imageConstraint.pixelsHigh != input_size) return NO;
    } else {
        if (input.type != MLFeatureTypeMultiArray) return NO;
        NSArray<NSNumber *> *input_shape = input.multiArrayConstraint.shape;
        if (input_shape.count != 4 || input_shape[0].unsignedIntegerValue != 1 || input_shape[1].unsignedIntegerValue != 3 || input_shape[2].unsignedIntegerValue != input_size || input_shape[3].unsignedIntegerValue != input_size) return NO;
    }

    NSString *output_name = nil;
    for (NSString *name in model.modelDescription.outputDescriptionsByName) {
        MLFeatureType output_type = model.modelDescription.outputDescriptionsByName[name].type;
        if ((image_io && output_type == MLFeatureTypeImage) || (!image_io && output_type == MLFeatureTypeMultiArray)) {
            output_name = name;
            break;
        }
    }
    if (output_name == nil) return NO;

    cached_models[model_slot] = model;
    cached_input_names[model_slot] = input_name;
    cached_output_names[model_slot] = output_name;
    cached_package_ids[model_slot] = model_id;
    cached_image_ios[model_slot] = image_io;
    return YES;
}

static CVPixelBufferRef create_input_pixel_buffer(const uint8_t *input_rgb, NSUInteger dimension) {
    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVPixelBufferRef pixel_buffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, dimension, dimension, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, &pixel_buffer);
    if (status != kCVReturnSuccess || pixel_buffer == NULL) return NULL;

    CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    uint8_t *destination = CVPixelBufferGetBaseAddress(pixel_buffer);
    const size_t bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer);
    for (NSUInteger y = 0; y < dimension; y++) {
        const uint8_t *source_row = input_rgb + y * dimension * 3;
        uint8_t *destination_row = destination + y * bytes_per_row;
        for (NSUInteger x = 0; x < dimension; x++) {
            destination_row[x * 4] = source_row[x * 3 + 2];
            destination_row[x * 4 + 1] = source_row[x * 3 + 1];
            destination_row[x * 4 + 2] = source_row[x * 3];
            destination_row[x * 4 + 3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    return pixel_buffer;
}

static BOOL copy_image_output(CVPixelBufferRef pixel_buffer, uint8_t *output_rgb, NSUInteger expected_dimension) {
    if (pixel_buffer == NULL || CVPixelBufferGetWidth(pixel_buffer) != expected_dimension || CVPixelBufferGetHeight(pixel_buffer) != expected_dimension) return NO;
    if (CVPixelBufferLockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return NO;

    const OSType format = CVPixelBufferGetPixelFormatType(pixel_buffer);
    const uint8_t *source = CVPixelBufferGetBaseAddress(pixel_buffer);
    const size_t bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer);
    BOOL supported = format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32RGBA || format == kCVPixelFormatType_32ARGB || format == kCVPixelFormatType_32ABGR;
    if (supported && source != NULL) {
        for (NSUInteger y = 0; y < expected_dimension; y++) {
            const uint8_t *source_row = source + y * bytes_per_row;
            for (NSUInteger x = 0; x < expected_dimension; x++) {
                const uint8_t *pixel = source_row + x * 4;
                uint8_t *destination = output_rgb + (y * expected_dimension + x) * 3;
                if (format == kCVPixelFormatType_32BGRA) {
                    destination[0] = pixel[2];
                    destination[1] = pixel[1];
                    destination[2] = pixel[0];
                } else if (format == kCVPixelFormatType_32RGBA) {
                    destination[0] = pixel[0];
                    destination[1] = pixel[1];
                    destination[2] = pixel[2];
                } else if (format == kCVPixelFormatType_32ARGB) {
                    destination[0] = pixel[1];
                    destination[1] = pixel[2];
                    destination[2] = pixel[3];
                } else {
                    destination[0] = pixel[3];
                    destination[1] = pixel[2];
                    destination[2] = pixel[1];
                }
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
    return supported && source != NULL;
}

static uint8_t output_byte(float value) {
    if (!isfinite(value)) value = 0.0f;
    value = fminf(fmaxf(value, 0.0f), 1.0f);
    return (uint8_t)lrintf(value * 255.0f);
}

static BOOL copy_multiarray_output(MLMultiArray *output, uint8_t model_id, uint8_t *output_rgb) {
    if (output == nil || output.shape.count != 4 || output.shape[0].unsignedIntegerValue != 1 || output.shape[1].unsignedIntegerValue != 3 || output.strides.count != 4) return NO;

    const NSUInteger input_size = model_input_size(model_id);
    const NSUInteger output_size = input_size * prediction_scale(model_id);
    const NSUInteger destination_size = input_size * result_scale(model_id);
    if (output.shape[2].unsignedIntegerValue != output_size || output.shape[3].unsignedIntegerValue != output_size) return NO;

    NSInteger strides[4];
    for (NSUInteger i = 0; i < output.strides.count; i++) strides[i] = output.strides[i].integerValue;

    const float *float_data = output.dataType == MLMultiArrayDataTypeFloat32 ? (const float *)output.dataPointer : NULL;
    const __fp16 *half_data = output.dataType == MLMultiArrayDataTypeFloat16 ? (const __fp16 *)output.dataPointer : NULL;
    if (float_data == NULL && half_data == NULL) return NO;

    for (NSUInteger y = 0; y < destination_size; y++) {
        for (NSUInteger x = 0; x < destination_size; x++) {
            NSUInteger destination = (y * destination_size + x) * 3;
            for (NSUInteger channel = 0; channel < 3; channel++) {
                NSUInteger offset = channel * strides[1] + y * strides[2] + x * strides[3];
                output_rgb[destination + channel] = output_byte(float_data != NULL ? float_data[offset] : (float)half_data[offset]);
            }
        }
    }
    return YES;
}

int furball_coreml_run(uint8_t model_id, uint8_t model_slot, const uint8_t *input_rgb, uint8_t *output_rgb) {
    if (input_rgb == NULL || output_rgb == NULL || model_slot >= FURBALL_COREML_MODEL_INSTANCES || package_name(model_id) == nil) return FURBALL_COREML_INFERENCE_FAILED;

    @autoreleasepool {
        initialize_model_locks();
        @synchronized(model_locks[model_slot]) {
            if (model_package_url(model_id) == nil) return FURBALL_COREML_MODEL_FAILED;
            if (!load_model(model_id, model_slot)) return FURBALL_COREML_MODEL_FAILED;

            const NSUInteger input_size = model_input_size(model_id);
            NSError *error = nil;
            id input_value = nil;
            CVPixelBufferRef input_pixel_buffer = NULL;
            MLMultiArray *input_array = nil;
            if (cached_image_ios[model_slot]) {
                input_pixel_buffer = create_input_pixel_buffer(input_rgb, input_size);
                if (input_pixel_buffer == NULL) return FURBALL_COREML_INFERENCE_FAILED;
                input_value = [MLFeatureValue featureValueWithPixelBuffer:input_pixel_buffer];
            } else {
                NSArray<NSNumber *> *input_shape = @[@1, @3, @(input_size), @(input_size)];
                input_array = [[MLMultiArray alloc] initWithShape:input_shape dataType:MLMultiArrayDataTypeFloat32 error:&error];
                if (input_array == nil) return FURBALL_COREML_INFERENCE_FAILED;

                const NSUInteger plane_size = input_size * input_size;
                float *input_data = (float *)input_array.dataPointer;
                for (NSUInteger y = 0; y < input_size; y++) {
                    for (NSUInteger x = 0; x < input_size; x++) {
                        NSUInteger pixel = (y * input_size + x) * 3;
                        input_data[y * input_size + x] = input_rgb[pixel] / 255.0f;
                        input_data[plane_size + y * input_size + x] = input_rgb[pixel + 1] / 255.0f;
                        input_data[2 * plane_size + y * input_size + x] = input_rgb[pixel + 2] / 255.0f;
                    }
                }
                input_value = [MLFeatureValue featureValueWithMultiArray:input_array];
            }

            MLDictionaryFeatureProvider *provider = [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{
                cached_input_names[model_slot]: input_value,
            } error:&error];
            if (provider == nil) {
                if (input_pixel_buffer != NULL) CVPixelBufferRelease(input_pixel_buffer);
                return FURBALL_COREML_INFERENCE_FAILED;
            }

            id<MLFeatureProvider> prediction = [cached_models[model_slot] predictionFromFeatures:provider error:&error];
            if (input_pixel_buffer != NULL) CVPixelBufferRelease(input_pixel_buffer);
            if (prediction == nil) return FURBALL_COREML_INFERENCE_FAILED;

            MLFeatureValue *output_value = [prediction featureValueForName:cached_output_names[model_slot]];
            BOOL copied = cached_image_ios[model_slot]
                ? copy_image_output(output_value.imageBufferValue, output_rgb, input_size * result_scale(model_id))
                : copy_multiarray_output(output_value.multiArrayValue, model_id, output_rgb);
            return copied ? FURBALL_COREML_SUCCESS : FURBALL_COREML_INFERENCE_FAILED;
        }
    }
}

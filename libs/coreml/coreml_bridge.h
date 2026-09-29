#ifndef FURBALL_COREML_BRIDGE_H
#define FURBALL_COREML_BRIDGE_H

#include <stdint.h>

enum {
    FURBALL_COREML_REAL_ESRGAN_X2 = 0,
    FURBALL_COREML_REAL_ESRGAN_X4 = 1,
    FURBALL_COREML_PIPERSR_X2 = 2,
    FURBALL_COREML_MODEL_INSTANCES = 4,
    FURBALL_COREML_SUCCESS = 0,
    FURBALL_COREML_UNSUPPORTED_PLATFORM = 1,
    FURBALL_COREML_MODEL_FAILED = 2,
    FURBALL_COREML_INFERENCE_FAILED = 3,
};

int furball_coreml_run(uint8_t model_id, uint8_t model_slot, const uint8_t *input_rgb, uint8_t *output_rgb);

#endif

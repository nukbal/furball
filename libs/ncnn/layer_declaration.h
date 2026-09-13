#include "layer/binaryop.h"
namespace ncnn { DEFINE_LAYER_CREATOR(BinaryOp) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/binaryop_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(BinaryOp_arm) }
#endif
#include "layer/cast.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Cast) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/cast_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Cast_arm) }
#endif
#include "layer/convolution.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Convolution) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/convolution_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Convolution_arm) }
#endif
#include "layer/input.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Input) }
#include "layer/interp.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Interp) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/interp_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Interp_arm) }
#endif
#include "layer/pixelshuffle.h"
namespace ncnn { DEFINE_LAYER_CREATOR(PixelShuffle) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/pixelshuffle_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(PixelShuffle_arm) }
#endif
#include "layer/prelu.h"
namespace ncnn { DEFINE_LAYER_CREATOR(PReLU) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/prelu_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(PReLU_arm) }
#endif
#include "layer/padding.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Padding) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/padding_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Padding_arm) }
#endif
#include "layer/packing.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Packing) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/packing_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Packing_arm) }
#endif
#include "layer/scale.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Scale) }
#if defined(__aarch64__) || defined(__arm__)
#include "layer/arm/scale_arm.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Scale_arm) }
#endif
#include "layer/split.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Split) }

#include "layer/binaryop.h"
namespace ncnn { DEFINE_LAYER_CREATOR(BinaryOp) }
#include "layer/cast.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Cast) }
#include "layer/convolution.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Convolution) }
#include "layer/input.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Input) }
#include "layer/interp.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Interp) }
#include "layer/pixelshuffle.h"
namespace ncnn { DEFINE_LAYER_CREATOR(PixelShuffle) }
#include "layer/prelu.h"
namespace ncnn { DEFINE_LAYER_CREATOR(PReLU) }
#include "layer/padding.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Padding) }
#include "layer/scale.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Scale) }
#include "layer/split.h"
namespace ncnn { DEFINE_LAYER_CREATOR(Split) }

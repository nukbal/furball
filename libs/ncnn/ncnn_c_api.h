#ifndef FURBALL_NCNN_C_API_H
#define FURBALL_NCNN_C_API_H

#include "c_api.h"

#if defined(__APPLE__)
NCNN_EXPORT int furball_ncnn_vulkan_available(void);
#else
static inline int furball_ncnn_vulkan_available(void) {
    return 0;
}
#endif

#endif

#include "gpu.h"

#include <mutex>

namespace {

struct GpuInstance {
    std::once_flag once;
    bool available = false;
    bool initialized = false;

    ~GpuInstance() {
        if (initialized) {
            ncnn::destroy_gpu_instance();
        }
    }
};

GpuInstance gpu_instance;

}

extern "C" NCNN_EXPORT int furball_ncnn_vulkan_available(void) {
    std::call_once(gpu_instance.once, [] {
        if (ncnn::create_gpu_instance() != 0) return;
        gpu_instance.initialized = true;
        gpu_instance.available = ncnn::get_gpu_count() > 0;
    });
    return gpu_instance.available ? 1 : 0;
}

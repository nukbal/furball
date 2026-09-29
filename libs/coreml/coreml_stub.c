#include "coreml_bridge.h"

int furball_coreml_run(uint8_t model_id, uint8_t model_slot, const uint8_t *input_rgb, uint8_t *output_rgb) {
    (void)model_id;
    (void)model_slot;
    (void)input_rgb;
    (void)output_rgb;
    return FURBALL_COREML_UNSUPPORTED_PLATFORM;
}

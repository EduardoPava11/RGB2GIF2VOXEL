#ifndef YINGIF_PROCESSOR_H
#define YINGIF_PROCESSOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque processor handle
typedef struct YinGifProcessor YinGifProcessor;

// Create a new processor instance
YinGifProcessor* yingif_processor_new(void);

// Free a processor instance
void yingif_processor_free(YinGifProcessor* processor);

// Process a BGRA frame: downsize and quantize colors
// Returns 0 on success, negative error code on failure
int32_t yingif_process_frame(
    YinGifProcessor* processor,
    const uint8_t* bgra_data,
    int32_t width,
    int32_t height,
    int32_t target_size,
    int32_t palette_size,
    uint8_t* out_indices,
    uint32_t* out_palette
);

// Create a GIF89a from indexed cube tensor data
// Returns 0 on success, negative error code on failure
int32_t yingif_create_gif89a(
    const uint8_t* indices,
    const uint32_t* palette,
    int32_t cube_size,
    int32_t palette_size,
    int32_t delay_ms,
    uint8_t* out_data,
    int32_t out_capacity,
    int32_t* out_size
);

// Get estimated buffer size needed for GIF
int32_t yingif_estimate_gif_size(
    int32_t cube_size,
    int32_t palette_size
);

#ifdef __cplusplus
}
#endif

#endif // YINGIF_PROCESSOR_H
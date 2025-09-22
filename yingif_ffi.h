// yingif_ffi.h - Rust FFI header for image processing
#ifndef YINGIF_FFI_H
#define YINGIF_FFI_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Process batch of RGBA frames: downsample and quantize
// Returns 0 on success, negative error codes on failure
int32_t yx_proc_batch_rgba8(
    const uint8_t* const* frames,  // Array of N pointers to RGBA frames
    int32_t n,                      // Number of frames
    int32_t width,                  // Input frame width
    int32_t height,                 // Input frame height
    int32_t target_side,            // Output size (e.g., 256)
    int32_t palette_size,           // Palette size (max 256)
    uint8_t* out_indices,           // Output: N * target_side * target_side
    uint32_t* out_palettes          // Output: N * 256 palette entries
);

// Encode indexed frames to GIF89a
// Returns 0 on success, negative error codes on failure
int32_t yx_gif_encode(
    const uint8_t* indices,         // N * side * side indexed pixels
    const uint32_t* palettes,       // N * 256 palette entries (0x00RRGGBB)
    int32_t n,                      // Number of frames
    int32_t side,                   // Width and height
    int32_t delay_cs,               // Delay in centiseconds
    uint8_t* out_buf,               // Output buffer
    size_t* out_len                 // In: capacity, Out: bytes written
);

#ifdef __cplusplus
}
#endif

#endif // YINGIF_FFI_H
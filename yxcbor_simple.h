// yxcbor_simple.h - C header for Zig frame storage library
#ifndef YXCBOR_SIMPLE_H
#define YXCBOR_SIMPLE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Save a single RGBA frame to disk
// Returns 0 on success, negative error code on failure
int32_t yxcbor_save_frame(
    const char* path,
    const uint8_t* rgba_data,
    uint32_t width,
    uint32_t height,
    uint32_t index
);

// Load a frame from disk
// Returns 0 on success, negative error code on failure
int32_t yxcbor_load_frame(
    const char* path,
    uint8_t* out_rgba,
    uint32_t* out_width,
    uint32_t* out_height,
    uint32_t* out_index
);

// Save batch of frames to directory
// Returns 0 on success, negative error code on failure
int32_t yxcbor_save_batch(
    const char* dir_path,
    const uint8_t* const* frames,
    uint32_t n_frames,
    uint32_t width,
    uint32_t height
);

// Get frame path for given index
// Returns 0 on success, negative error code on failure
int32_t yxcbor_get_frame_path(
    const char* dir_path,
    uint32_t index,
    char* out_path,
    uint32_t max_len
);

#ifdef __cplusplus
}
#endif

#endif // YXCBOR_SIMPLE_H
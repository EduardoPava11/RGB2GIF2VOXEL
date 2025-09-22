// yxcbor.h - C header for Zig frame storage library with streaming API
#ifndef YXCBOR_H
#define YXCBOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Frame manifest structure
typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t channels;
    uint32_t frame_count;
} yx_frame_manifest;

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

// ========== Streaming API ==========

// Open writer for streaming frames to CBOR
// Returns 0 on success, negative error code on failure
int32_t yxcbor_open_writer(const char* dir_path, const yx_frame_manifest* manifest);

// Write a single frame (must call open_writer first)
// Returns 0 on success, negative error code on failure
int32_t yxcbor_write_frame(const uint8_t* rgba_ptr, uint32_t len);

// Close writer and finalize CBOR files
// Returns 0 on success
int32_t yxcbor_close_writer(void);

// Open reader for streaming frames from CBOR
// Returns 0 on success, negative error code on failure
int32_t yxcbor_open_reader(const char* dir_path, yx_frame_manifest* out_manifest);

// Read a specific frame by index
// Returns 0 on success, negative error code on failure
int32_t yxcbor_read_frame(uint32_t index, uint8_t* out_rgba, uint32_t len);

// Close reader
// Returns 0 on success
int32_t yxcbor_close_reader(void);

#ifdef __cplusplus
}
#endif

#endif // YXCBOR_H
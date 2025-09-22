// Stub implementations for yxcbor functions
#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint32_t frame_count;
    uint32_t width;
    uint32_t height;
    uint32_t format;
} yx_frame_manifest;

// Stub implementations - these should be replaced with actual Zig implementations
int32_t yxcbor_open_writer(const yx_frame_manifest* manifest) {
    // Stub: return success
    return 0;
}

int32_t yxcbor_write_frame(const uint8_t* data, size_t size) {
    // Stub: return success
    return 0;
}

void yxcbor_close_writer(void) {
    // Stub: do nothing
}

int32_t yxcbor_open_reader(yx_frame_manifest* manifest) {
    // Stub: return success
    if (manifest) {
        manifest->frame_count = 32;
        manifest->width = 64;
        manifest->height = 64;
        manifest->format = 0; // RGB
    }
    return 0;
}

int32_t yxcbor_read_frame(uint8_t* buffer, size_t size) {
    // Stub: return bytes read (0 = end of frames)
    return 0;
}

void yxcbor_close_reader(void) {
    // Stub: do nothing
}
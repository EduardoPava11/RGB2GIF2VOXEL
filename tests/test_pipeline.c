/*
 * test_pipeline.c - Test the complete Zig+Rust pipeline
 * Compile with:
 *   clang -o test_pipeline test_pipeline.c \
 *     ../libyxcbor_simple.a \
 *     ../rust-core/target/release/libyingif_processor.a \
 *     -framework CoreFoundation -framework Security -framework SystemConfiguration
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "../yxcbor_simple.h"
#include "../yingif_ffi.h"

// Generate a test frame with gradient pattern
void generate_test_frame(uint8_t* frame, int size, int index) {
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            int offset = (y * size + x) * 4;
            // Simple gradient pattern
            frame[offset + 0] = (x * 255 / size) * (index % 16) / 16;     // R
            frame[offset + 1] = (y * 255 / size) * ((index + 8) % 16) / 16; // G
            frame[offset + 2] = ((x + y) * 255 / (2 * size)) * ((index + 4) % 16) / 16; // B
            frame[offset + 3] = 255;  // A
        }
    }
}

int test_zig_save_load() {
    printf("Testing Zig save/load...\n");

    // Generate test frame
    const int size = 256;
    uint8_t* frame = (uint8_t*)malloc(size * size * 4);
    generate_test_frame(frame, size, 0);

    // Save frame
    const char* path = "test_frame.yxfr";
    int result = yxcbor_save_frame(path, frame, size, size, 0);
    assert(result == 0);
    printf("  ✅ Saved frame\n");

    // Load frame back
    uint8_t* loaded_frame = (uint8_t*)malloc(size * size * 4);
    uint32_t width, height, index;
    result = yxcbor_load_frame(path, loaded_frame, &width, &height, &index);
    assert(result == 0);
    assert(width == size);
    assert(height == size);
    assert(index == 0);

    // Verify data matches
    int matches = 1;
    for (int i = 0; i < size * size * 4; i++) {
        if (frame[i] != loaded_frame[i]) {
            matches = 0;
            break;
        }
    }
    assert(matches);
    printf("  ✅ Loaded frame matches\n");

    free(frame);
    free(loaded_frame);
    return 0;
}

int test_rust_processing() {
    printf("\nTesting Rust processing...\n");

    const int n_frames = 4;
    const int input_size = 256;
    const int output_size = 256;

    // Generate test frames
    uint8_t** frames = (uint8_t**)malloc(n_frames * sizeof(uint8_t*));
    for (int i = 0; i < n_frames; i++) {
        frames[i] = (uint8_t*)malloc(input_size * input_size * 4);
        generate_test_frame(frames[i], input_size, i);
    }

    // Prepare output buffers
    uint8_t* out_indices = (uint8_t*)malloc(n_frames * output_size * output_size);
    uint32_t* out_palettes = (uint32_t*)malloc(n_frames * 256 * sizeof(uint32_t));

    // Process frames
    int32_t result = yx_proc_batch_rgba8(
        (const uint8_t* const*)frames,
        n_frames,
        input_size,
        input_size,
        output_size,
        256,
        out_indices,
        out_palettes
    );

    if (result == 0) {
        printf("  ✅ Processed %d frames\n", n_frames);

        // Verify output
        int has_data = 0;
        for (int i = 0; i < output_size * output_size; i++) {
            if (out_indices[i] != 0) {
                has_data = 1;
                break;
            }
        }
        assert(has_data);
        printf("  ✅ Output has indexed data\n");

        // Check palette
        int has_colors = 0;
        for (int i = 0; i < 256; i++) {
            if (out_palettes[i] != 0 && out_palettes[i] != 0xFF000000) {
                has_colors = 1;
                break;
            }
        }
        assert(has_colors);
        printf("  ✅ Palette has colors\n");
    } else {
        printf("  ❌ Processing failed with code: %d\n", result);
    }

    // Cleanup
    for (int i = 0; i < n_frames; i++) {
        free(frames[i]);
    }
    free(frames);
    free(out_indices);
    free(out_palettes);

    return result;
}

int test_gif_encoding() {
    printf("\nTesting GIF encoding...\n");

    const int n_frames = 4;
    const int size = 256;

    // Generate simple test data
    uint8_t* indices = (uint8_t*)calloc(n_frames * size * size, 1);
    uint32_t* palettes = (uint32_t*)calloc(n_frames * 256, sizeof(uint32_t));

    // Create simple pattern
    for (int f = 0; f < n_frames; f++) {
        // Simple indexed pattern
        for (int i = 0; i < size * size; i++) {
            indices[f * size * size + i] = (i + f * 10) % 256;
        }

        // Simple palette
        for (int i = 0; i < 256; i++) {
            palettes[f * 256 + i] = (i << 16) | ((i + 64) << 8) | ((i + 128) & 0xFF);
        }
    }

    // Encode to GIF
    uint8_t* output = (uint8_t*)malloc(5 * 1024 * 1024);
    size_t output_len = 5 * 1024 * 1024;

    int32_t result = yx_gif_encode(
        indices,
        palettes,
        n_frames,
        size,
        10,  // 100ms delay
        output,
        &output_len
    );

    if (result == 0) {
        printf("  ✅ Encoded GIF: %zu bytes\n", output_len);

        // Verify GIF header
        assert(memcmp(output, "GIF89a", 6) == 0);
        printf("  ✅ Valid GIF89a header\n");

        // Save to file for inspection
        FILE* f = fopen("test_output.gif", "wb");
        if (f) {
            fwrite(output, 1, output_len, f);
            fclose(f);
            printf("  ✅ Saved test_output.gif\n");
        }
    } else {
        printf("  ❌ GIF encoding failed with code: %d\n", result);
    }

    free(indices);
    free(palettes);
    free(output);

    return result;
}

int main() {
    printf("========================================\n");
    printf("RGB2GIF2VOXEL Pipeline Test\n");
    printf("========================================\n");

    int failed = 0;

    // Test Zig functions
    if (test_zig_save_load() != 0) {
        failed++;
    }

    // Test Rust processing
    if (test_rust_processing() != 0) {
        failed++;
    }

    // Test GIF encoding
    if (test_gif_encoding() != 0) {
        failed++;
    }

    printf("\n========================================\n");
    if (failed == 0) {
        printf("✅ ALL TESTS PASSED!\n");
    } else {
        printf("❌ %d TEST(S) FAILED\n", failed);
    }
    printf("========================================\n");

    return failed;
}
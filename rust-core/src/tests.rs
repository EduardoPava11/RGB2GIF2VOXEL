// tests.rs - Comprehensive test suite for Rust FFI functions

#[cfg(test)]
mod tests {
    use super::super::*;
    use std::ptr;

    // Test data generator - creates synthetic RGBA frames
    fn generate_test_frame(width: u32, height: u32, seed: u8) -> Vec<u8> {
        let mut frame = Vec::with_capacity((width * height * 4) as usize);
        for y in 0..height {
            for x in 0..width {
                // Create a gradient pattern with the seed
                let r = ((x * 255 / width) as u8).wrapping_add(seed);
                let g = ((y * 255 / height) as u8).wrapping_add(seed);
                let b = (((x + y) * 255 / (width + height)) as u8).wrapping_add(seed);
                let a = 255;
                frame.extend_from_slice(&[r, g, b, a]);
            }
        }
        frame
    }

    // Test processor lifecycle
    #[test]
    fn test_processor_lifecycle() {
        println!("Testing processor lifecycle...");

        let processor = yingif_processor_new();
        assert!(!processor.is_null(), "Processor creation failed");

        yingif_processor_free(processor);
        println!("✅ Processor lifecycle test passed");
    }

    // Test single frame processing
    #[test]
    fn test_single_frame_processing() {
        println!("Testing single frame processing...");

        let processor = unsafe { yingif_processor_new() };
        assert!(!processor.is_null());

        // Generate test frame (1080x1080 BGRA)
        let width = 1080;
        let height = 1080;
        let target_size = 256;
        let palette_size = 256;

        let rgba_frame = generate_test_frame(width, height, 42);
        // Convert RGBA to BGRA
        let mut bgra_frame = Vec::with_capacity(rgba_frame.len());
        for chunk in rgba_frame.chunks_exact(4) {
            bgra_frame.push(chunk[2]); // B
            bgra_frame.push(chunk[1]); // G
            bgra_frame.push(chunk[0]); // R
            bgra_frame.push(chunk[3]); // A
        }

        let mut indices = vec![0u8; (target_size * target_size) as usize];
        let mut palette = vec![0u32; palette_size as usize];

        let result = unsafe {
            yingif_process_frame(
                processor,
                bgra_frame.as_ptr(),
                width as i32,
                height as i32,
                target_size as i32,
                palette_size as i32,
                indices.as_mut_ptr(),
                palette.as_mut_ptr()
            )
        };

        assert_eq!(result, 0, "Frame processing failed with error: {}", result);

        // Verify output
        assert!(indices.iter().any(|&i| i > 0), "Indices should have non-zero values");
        assert!(palette.iter().any(|&p| p != 0), "Palette should have non-zero colors");

        // Check palette has alpha channel set
        for &color in palette.iter().take(10) {
            if color != 0 {
                let alpha = (color >> 24) & 0xFF;
                assert_eq!(alpha, 0xFF, "Palette colors should be opaque");
            }
        }

        unsafe { yingif_processor_free(processor) };
        println!("✅ Single frame processing test passed");
    }

    // Test GIF creation
    #[test]
    fn test_gif_creation() {
        println!("Testing GIF89a creation...");

        let cube_size = 32; // Smaller for testing
        let palette_size = 256;
        let frame_count = cube_size;

        // Generate test indices (simulating processed frames)
        let total_pixels = cube_size * cube_size * frame_count;
        let mut indices = Vec::with_capacity(total_pixels as usize);
        for frame in 0..frame_count {
            for _pixel in 0..(cube_size * cube_size) {
                indices.push((frame % 256) as u8);
            }
        }

        // Generate test palette
        let mut palette = Vec::with_capacity(palette_size as usize);
        for i in 0..palette_size {
            let r = (i * 7) as u32 & 0xFF;
            let g = (i * 11) as u32 & 0xFF;
            let b = (i * 13) as u32 & 0xFF;
            palette.push(0xFF000000 | (r << 16) | (g << 8) | b);
        }

        // Estimate GIF size
        let estimated_size = unsafe {
            yingif_estimate_gif_size(cube_size, palette_size)
        };
        assert!(estimated_size > 0, "GIF size estimation failed");
        println!("  Estimated GIF size: {} bytes", estimated_size);

        // Create GIF
        let mut gif_data = vec![0u8; (estimated_size * 2) as usize]; // 2x buffer
        let mut actual_size = 0i32;

        let result = unsafe {
            yingif_create_gif89a(
                indices.as_ptr(),
                palette.as_ptr(),
                cube_size,
                palette_size,
                40, // 40ms delay
                gif_data.as_mut_ptr(),
                gif_data.len() as i32,
                &mut actual_size
            )
        };

        assert_eq!(result, 0, "GIF creation failed with error: {}", result);
        assert!(actual_size > 0, "GIF has zero size");

        // Verify GIF header
        assert_eq!(&gif_data[0..6], b"GIF89a", "Invalid GIF header");

        // Verify GIF trailer exists
        gif_data.truncate(actual_size as usize);
        assert_eq!(gif_data[gif_data.len() - 1], 0x3B, "Missing GIF trailer");

        println!("  Actual GIF size: {} bytes", actual_size);
        println!("✅ GIF creation test passed");
    }

    // Test batch processing for 256x256x256 cube
    #[test]
    fn test_batch_processing_256_cube() {
        println!("Testing 256×256×256 cube batch processing...");

        use crate::ffi::yx_proc_batch_rgba8;

        let frame_count = 8; // Test with 8 frames (full 256 would be slow)
        let width = 1080;
        let height = 1080;
        let target_side = 256;
        let palette_size = 256;

        // Generate test frames
        let mut frames_data: Vec<Vec<u8>> = Vec::new();
        let mut frame_pointers: Vec<*const u8> = Vec::new();

        for i in 0..frame_count {
            let frame = generate_test_frame(width, height, i as u8 * 10);
            frame_pointers.push(frame.as_ptr());
            frames_data.push(frame);
        }

        // Allocate output buffers
        let indices_size = (target_side * target_side * frame_count) as usize;
        let palettes_size = (palette_size * frame_count) as usize;
        let mut indices = vec![0u8; indices_size];
        let mut palettes = vec![0u32; palettes_size];

        let result = unsafe {
            yx_proc_batch_rgba8(
                frame_pointers.as_ptr() as *const *const u8,
                frame_count as i32,
                width as i32,
                height as i32,
                target_side as i32,
                palette_size as i32,
                indices.as_mut_ptr(),
                palettes.as_mut_ptr()
            )
        };

        assert_eq!(result, 0, "Batch processing failed with error: {}", result);

        // Verify each frame was processed
        for frame_idx in 0..frame_count as usize {
            let frame_start = frame_idx * (target_side * target_side) as usize;
            let frame_end = frame_start + (target_side * target_side) as usize;
            let frame_indices = &indices[frame_start..frame_end];

            assert!(
                frame_indices.iter().any(|&i| i > 0),
                "Frame {} has no non-zero indices", frame_idx
            );

            let palette_start = frame_idx * palette_size as usize;
            let palette_end = palette_start + palette_size as usize;
            let frame_palette = &palettes[palette_start..palette_end];

            assert!(
                frame_palette.iter().any(|&p| p != 0 && p != 0xFF000000),
                "Frame {} has no valid colors", frame_idx
            );
        }

        println!("  Processed {} frames successfully", frame_count);
        println!("  Output: {} indices, {} palette entries", indices.len(), palettes.len());
        println!("✅ Batch processing test passed");
    }

    // Test error handling
    #[test]
    fn test_error_handling() {
        println!("Testing error handling...");

        // Test null pointer handling
        let result = unsafe {
            yingif_process_frame(
                ptr::null_mut(),
                ptr::null(),
                0, 0, 0, 0,
                ptr::null_mut(),
                ptr::null_mut()
            )
        };
        assert_eq!(result, -1, "Should return -1 for null processor");

        // Test invalid dimensions
        let processor = unsafe { yingif_processor_new() };
        let result = unsafe {
            yingif_process_frame(
                processor,
                ptr::null(),
                -1, -1, 0, 300, // Invalid dims and palette size
                ptr::null_mut(),
                ptr::null_mut()
            )
        };
        assert_eq!(result, -2, "Should return -2 for invalid dimensions");

        unsafe { yingif_processor_free(processor) };
        println!("✅ Error handling test passed");
    }

    // Test memory safety with large cube
    #[test]
    fn test_memory_safety() {
        println!("Testing memory safety with multiple operations...");

        // Create and destroy multiple processors
        for i in 0..10 {
            let processor = unsafe { yingif_processor_new() };
            assert!(!processor.is_null(), "Failed to create processor {}", i);
            unsafe { yingif_processor_free(processor) };
        }

        // Process multiple frames with same processor
        let processor = unsafe { yingif_processor_new() };
        for i in 0..5 {
            let frame = generate_test_frame(512, 512, i * 20);
            let mut indices = vec![0u8; 128 * 128];
            let mut palette = vec![0u32; 128];

            let result = unsafe {
                yingif_process_frame(
                    processor,
                    frame.as_ptr(),
                    512, 512, 128, 128,
                    indices.as_mut_ptr(),
                    palette.as_mut_ptr()
                )
            };
            assert_eq!(result, 0, "Frame {} processing failed", i);
        }
        unsafe { yingif_processor_free(processor) };

        println!("✅ Memory safety test passed");
    }
}
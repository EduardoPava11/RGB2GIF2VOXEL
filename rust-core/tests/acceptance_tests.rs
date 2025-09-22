// Acceptance tests for RGB2GIF processor
// Validates the single-FFI interface for quality, performance, and correctness

use rgb2gif_processor::{process_all_frames, QuantizeOpts, GifOpts};
use std::time::Instant;

fn create_test_frames(count: usize, width: u32, height: u32) -> Vec<u8> {
    let mut all_frames = Vec::with_capacity((width * height * 4 * count as u32) as usize);

    for i in 0..count {
        // Create gradient pattern that changes per frame
        for y in 0..height {
            for x in 0..width {
                all_frames.push(((x * 255 / width) as u8).wrapping_add(i as u8));     // R
                all_frames.push(((y * 255 / height) as u8).wrapping_add(i as u8));    // G
                all_frames.push(128);                                                  // B
                all_frames.push(255);                                                  // A
            }
        }
    }
    all_frames
}

#[test]
fn test_single_ffi_256_frames() {
    // Test the main use case: 256 frames at 256x256
    let frames = create_test_frames(256, 256, 256);

    let quantize_opts = QuantizeOpts {
        quality_min: 70,
        quality_max: 100,
        speed: 5,
        palette_size: 256,
        dithering_level: 1.0,
        shared_palette: true,
    };

    let gif_opts = GifOpts {
        width: 256,
        height: 256,
        frame_count: 256,
        fps: 25,
        loop_count: 0,
        optimize: true,
        include_tensor: false,
    };

    let start = Instant::now();
    let result = process_all_frames(
        frames,
        256,
        256,
        256,
        quantize_opts,
        gif_opts,
    );
    let elapsed = start.elapsed();

    assert!(result.is_ok(), "Processing failed: {:?}", result.err());
    let output = result.unwrap();

    // Validate output
    assert!(!output.gif_data.is_empty(), "GIF data should not be empty");
    assert!(output.gif_data.len() > 1000, "GIF seems too small");
    assert!(output.processing_time_ms > 0.0, "Processing time should be recorded");

    // Performance check (should complete in reasonable time)
    assert!(elapsed.as_secs() < 10, "Processing took too long: {elapsed:?}");

    println!("✅ Processed 256 frames in {elapsed:?}");
    println!("   GIF size: {} KB", output.final_file_size / 1024);
    println!("   Processing time: {:.1}ms", output.processing_time_ms);
}

#[test]
fn test_with_tensor_output() {
    // Test including tensor output
    let frames = create_test_frames(32, 256, 256);

    let quantize_opts = QuantizeOpts {
        quality_min: 50,
        quality_max: 90,
        speed: 8,
        palette_size: 256,
        dithering_level: 0.5,
        shared_palette: false,
    };

    let gif_opts = GifOpts {
        width: 256,
        height: 256,
        frame_count: 32,
        fps: 30,
        loop_count: 0,
        optimize: false,
        include_tensor: true,  // Request tensor
    };

    let result = process_all_frames(
        frames,
        256,
        256,
        32,
        quantize_opts,
        gif_opts,
    );

    assert!(result.is_ok());
    let output = result.unwrap();

    assert!(output.tensor_data.is_some(), "Tensor should be included");
    let tensor = output.tensor_data.unwrap();

    // Tensor should be 16x16x256 = 65,536 bytes
    assert_eq!(tensor.len(), 16 * 16 * 256, "Tensor size mismatch");
}

#[test]
fn test_performance_targets() {
    // Test that we meet performance targets
    let test_cases = vec![
        (32, 5),   // 32 frames, quality mode
        (64, 8),   // 64 frames, fast mode
        (128, 10), // 128 frames, fastest mode
    ];

    for (frame_count, speed) in test_cases {
        let frames = create_test_frames(frame_count, 256, 256);

        let quantize_opts = QuantizeOpts {
            quality_min: 30,
            quality_max: 70,
            speed,
            palette_size: 256,
            dithering_level: 0.0,
            shared_palette: true,
        };

        let gif_opts = GifOpts {
            width: 256,
            height: 256,
            frame_count: frame_count as u16,
            fps: 25,
            loop_count: 0,
            optimize: false,
            include_tensor: false,
        };

        let start = Instant::now();
        let result = process_all_frames(
            frames,
            256,
            256,
            frame_count as u32,
            quantize_opts,
            gif_opts,
        );
        let elapsed = start.elapsed();

        assert!(result.is_ok());

        // Performance target: ~10ms per frame max
        let max_time = (frame_count * 10) as u128;
        assert!(
            elapsed.as_millis() < max_time,
            "{frame_count} frames took {elapsed:?}, target < {max_time}ms"
        );
    }
}

#[test]
fn test_gif_validation() {
    // Test that output is valid GIF89a
    let frames = create_test_frames(8, 128, 128);

    let quantize_opts = QuantizeOpts {
        quality_min: 70,
        quality_max: 100,
        speed: 5,
        palette_size: 128,
        dithering_level: 1.0,
        shared_palette: true,
    };

    let gif_opts = GifOpts {
        width: 128,
        height: 128,
        frame_count: 8,
        fps: 10,
        loop_count: 5,
        optimize: true,
        include_tensor: false,
    };

    let result = process_all_frames(
        frames,
        128,
        128,
        8,
        quantize_opts,
        gif_opts,
    );

    assert!(result.is_ok());
    let output = result.unwrap();

    // Check GIF header
    assert!(output.gif_data.len() > 6);
    assert_eq!(&output.gif_data[0..6], b"GIF89a", "Should be GIF89a format");

    // Check dimensions in header (little-endian)
    let width_bytes = &output.gif_data[6..8];
    let height_bytes = &output.gif_data[8..10];
    let width = u16::from_le_bytes([width_bytes[0], width_bytes[1]]);
    let height = u16::from_le_bytes([height_bytes[0], height_bytes[1]]);
    assert_eq!(width, 128);
    assert_eq!(height, 128);
}
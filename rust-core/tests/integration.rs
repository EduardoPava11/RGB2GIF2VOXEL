// Integration tests for RGB2GIF processor
// Validates the complete pipeline works correctly

use rgb2gif_processor::{process_all_frames, QuantizeOpts, GifOpts};
use std::time::Instant;

fn create_test_frames(count: usize, width: u32, height: u32) -> Vec<u8> {
    let mut frames = Vec::new();

    for i in 0..count {
        // Create a gradient that changes per frame
        for y in 0..height {
            for x in 0..width {
                frames.push(((x * 255 / width) as u8).wrapping_add(i as u8)); // R
                frames.push(((y * 255 / height) as u8).wrapping_add(i as u8)); // G
                frames.push(((x + y) / 2 * 255 / width) as u8);               // B
                frames.push(255);                                              // A
            }
        }
    }
    frames
}

#[test]
fn test_basic_processing() {
    let frames = create_test_frames(32, 256, 256);

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
        frame_count: 32,
        fps: 30,
        loop_count: 0,
        optimize: true,
        include_tensor: false,
    };

    let result = process_all_frames(frames, 256, 256, 32, quantize_opts, gif_opts);
    assert!(result.is_ok());

    let output = result.unwrap();
    assert!(!output.gif_data.is_empty());
    assert!(output.actual_frame_count == 32);
    assert!(output.palette_size_used <= 256);
}

#[test]
fn test_different_sizes() {
    let test_cases = vec![
        (128, 128, 16),
        (256, 256, 32),
        (512, 512, 8),
    ];

    for (width, height, frame_count) in test_cases {
        let frames = create_test_frames(frame_count, width, height);

        let quantize_opts = QuantizeOpts {
            quality_min: 50,
            quality_max: 90,
            speed: 8,
            palette_size: 256,
            dithering_level: 0.5,
            shared_palette: true,
        };

        let gif_opts = GifOpts {
            width: width as u16,
            height: height as u16,
            frame_count: frame_count as u16,
            fps: 25,
            loop_count: 0,
            optimize: false,
            include_tensor: false,
        };

        let result = process_all_frames(
            frames,
            width,
            height,
            frame_count as u32,
            quantize_opts,
            gif_opts,
        );

        assert!(result.is_ok(), "Failed for {width}x{height} with {frame_count} frames");
    }
}

#[test]
fn test_performance_256_frames() {
    // Test with full 256 frames as per spec
    let frames = create_test_frames(256, 256, 256);

    let quantize_opts = QuantizeOpts {
        quality_min: 60,
        quality_max: 100,
        speed: 8, // Fast mode
        palette_size: 256,
        dithering_level: 0.5,
        shared_palette: true,
    };

    let gif_opts = GifOpts {
        width: 256,
        height: 256,
        frame_count: 256,
        fps: 30,
        loop_count: 0,
        optimize: false, // Skip optimization for speed
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

    assert!(result.is_ok());
    let output = result.unwrap();

    println!("Performance test (256 frames):");
    println!("  Total time: {elapsed:?}");
    println!("  GIF size: {} KB", output.final_file_size / 1024);
    println!("  Reported time: {:.1}ms", output.processing_time_ms);
    println!("  Per-frame: {:.2}ms", elapsed.as_millis() as f64 / 256.0);

    // Should complete in reasonable time (< 5 seconds)
    assert!(elapsed.as_secs() < 5, "Processing took too long");
}

#[test]
fn test_error_handling() {
    // Test with invalid input (empty frames)
    let frames = Vec::new();

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
        frame_count: 0,
        fps: 30,
        loop_count: 0,
        optimize: true,
        include_tensor: false,
    };

    let result = process_all_frames(frames, 256, 256, 0, quantize_opts, gif_opts);
    assert!(result.is_err(), "Should fail with empty input");
}
// RGB2GIF Processor - Single FFI Call for 256 Frames
// High-performance color quantization and GIF89a encoding

#![allow(clippy::empty_line_after_doc_comments)] // UniFFI generates code with this pattern

use std::time::Instant;
use imagequant::{RGBA};

// Include modules
mod quantization;
mod oklab_quantization;
mod blue_noise;

// Re-export for use
use quantization::*;
use oklab_quantization::*;
use blue_noise::*;

// Type alias for Result
pub type Result<T> = std::result::Result<T, ProcessorError>;

// UniFFI Error type matching the UDL
#[derive(Debug, thiserror::Error)]
pub enum ProcessorError {
    #[error("Quantization error")]
    QuantizationError,

    #[error("Encoding error")]
    EncodingError,

    #[error("Invalid input")]
    InvalidInput,

    #[error("Memory error")]
    MemoryError,
}

// Configuration structs matching the UDL
#[derive(Debug, Clone)]
pub struct QuantizeOpts {
    pub quality_min: u8,
    pub quality_max: u8,
    pub speed: i32,
    pub palette_size: u16,
    pub dithering_level: f32,
    pub shared_palette: bool,
}

#[derive(Debug, Clone)]
pub struct GifOpts {
    pub width: u16,
    pub height: u16,
    pub frame_count: u16,
    pub fps: u16,
    pub loop_count: u16,
    pub optimize: bool,
    pub include_tensor: bool,
}

#[derive(Debug, Clone)]
pub struct ProcessResult {
    pub gif_data: Vec<u8>,
    pub tensor_data: Option<Vec<u8>>,
    pub final_file_size: u32,
    pub processing_time_ms: f32,
    pub actual_frame_count: u16,
    pub palette_size_used: u16,
}

// Enhanced processing function with OKLab and blue noise dithering
pub fn process_all_frames(
    frames_rgba: Vec<u8>,
    width: u32,
    height: u32,
    frame_count: u32,
    quantize_opts: QuantizeOpts,
    gif_opts: GifOpts,
) -> Result<ProcessResult> {
    let start = Instant::now();

    // Validate buffer size
    let expected_size = (width * height * 4 * frame_count) as usize;
    if frames_rgba.len() != expected_size {
        return Err(ProcessorError::InvalidInput);
    }

    // Split into frames
    let frame_size = (width * height * 4) as usize;
    let frames: Vec<&[u8]> = frames_rgba
        .chunks_exact(frame_size)
        .collect();

    // Use OKLab quantization for superior quality
    let use_oklab = true; // Always use OKLab for maximum quality

    if use_oklab {
        return process_with_oklab(frames, width, height, quantize_opts, gif_opts);
    }

    // Fallback to original imagequant (kept for compatibility)
    let mut attr = imagequant::new();
    attr.set_quality(quantize_opts.quality_min, quantize_opts.quality_max)
        .map_err(|_| ProcessorError::QuantizationError)?;
    attr.set_speed(quantize_opts.speed)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Collect all images for shared palette quantization
    let mut images = Vec::new();
    for frame_data in &frames {
        // Convert byte slice to RGBA pixels
        let pixels: Vec<RGBA> = frame_data
            .chunks_exact(4)
            .map(|chunk| RGBA::new(chunk[0], chunk[1], chunk[2], chunk[3]))
            .collect();

        let img = attr.new_image(&pixels[..], width as usize, height as usize, 0.0)
            .map_err(|_| ProcessorError::QuantizationError)?;
        images.push(img);
    }

    // Quantize with shared palette
    let mut quantization_result = if quantize_opts.shared_palette && !images.is_empty() {
        // Use first image as base for shared palette
        attr.quantize(&mut images[0])
            .map_err(|_| ProcessorError::QuantizationError)?
    } else {
        return Err(ProcessorError::QuantizationError);
    };
    quantization_result.set_dithering_level(quantize_opts.dithering_level)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Get palette
    let palette = quantization_result.palette();
    let palette_size = palette.len() as u16;

    // Create GIF
    let mut gif_buffer = Vec::new();
    {
        use gif::{Encoder, Frame, Repeat};

        // Convert palette to GIF format
        let mut global_palette = Vec::with_capacity(palette_size as usize * 3);
        for color in palette {
            global_palette.push(color.r);
            global_palette.push(color.g);
            global_palette.push(color.b);
        }

        let mut encoder = Encoder::new(
            &mut gif_buffer,
            gif_opts.width,
            gif_opts.height,
            &global_palette
        ).map_err(|_| ProcessorError::EncodingError)?;

        encoder.set_repeat(Repeat::Infinite)
            .map_err(|_| ProcessorError::EncodingError)?;

        // Remap and write frames
        for (i, _frame_data) in frames.iter().enumerate() {
            // Use already created image or create new one
            let (_, indexed_pixels) = quantization_result.remapped(&mut images[i])
                .map_err(|_| ProcessorError::QuantizationError)?;

            // Create frame with indexed pixels
            let frame = Frame {
                width: gif_opts.width,
                height: gif_opts.height,
                buffer: indexed_pixels.into(),
                delay: 100 / gif_opts.fps, // Convert fps to centiseconds
                ..Default::default()
            };
            encoder.write_frame(&frame)
                .map_err(|_| ProcessorError::EncodingError)?;
        }
    }

    // Build tensor if requested (16×16×256 downsampled)
    let tensor_data = if gif_opts.include_tensor {
        Some(build_tensor_from_frames(&frames, width, height)?)
    } else {
        None
    };

    let file_size = gif_buffer.len() as u32;
    Ok(ProcessResult {
        gif_data: gif_buffer,
        tensor_data,
        final_file_size: file_size,
        processing_time_ms: start.elapsed().as_millis() as f32,
        actual_frame_count: frame_count as u16,
        palette_size_used: palette_size,
    })
}

// Utility functions
pub fn calculate_buffer_size(width: u32, height: u32, frame_count: u32) -> u32 {
    width * height * 4 * frame_count
}

pub fn validate_buffer(buffer: Vec<u8>, expected_size: u32) -> bool {
    buffer.len() == expected_size as usize
}

// Helper function to build tensor
fn build_tensor_from_frames(frames: &[&[u8]], width: u32, _height: u32) -> Result<Vec<u8>> {
    // Downsample each frame to 16×16 and pack into tensor
    let tensor_size = 16 * 16 * frames.len();
    let mut tensor = Vec::with_capacity(tensor_size * 4);

    for frame in frames {
        // Simple box filter downsampling from 256×256 to 16×16
        let scale = (width / 16) as usize;
        for ty in 0..16 {
            for tx in 0..16 {
                let mut r = 0u32;
                let mut g = 0u32;
                let mut b = 0u32;
                let mut a = 0u32;

                // Average pixels in box
                for dy in 0..scale {
                    for dx in 0..scale {
                        let x = tx * scale + dx;
                        let y = ty * scale + dy;
                        let idx = (y * width as usize + x) * 4;
                        r += frame[idx] as u32;
                        g += frame[idx + 1] as u32;
                        b += frame[idx + 2] as u32;
                        a += frame[idx + 3] as u32;
                    }
                }

                let pixels = (scale * scale) as u32;
                tensor.push((r / pixels) as u8);
                tensor.push((g / pixels) as u8);
                tensor.push((b / pixels) as u8);
                tensor.push((a / pixels) as u8);
            }
        }
    }

    Ok(tensor)
}

// Enhanced processing with OKLab color space and blue noise dithering
fn process_with_oklab(
    frames: Vec<&[u8]>,
    width: u32,
    height: u32,
    quantize_opts: QuantizeOpts,
    gif_opts: GifOpts,
) -> Result<ProcessResult> {
    let start = Instant::now();

    // Convert all frames to OKLab and build shared palette
    let mut all_oklab_pixels = Vec::new();
    for frame in &frames {
        let oklab = srgb_to_oklab_batch(frame);
        all_oklab_pixels.extend(oklab);
    }

    // Build optimal palette in OKLab space (much better than RGB)
    let palette_size = quantize_opts.palette_size as usize;
    let oklab_palette = build_oklab_palette(&all_oklab_pixels, palette_size);

    // Convert palette back to sRGB for GIF encoding
    let srgb_palette = oklab_palette_to_srgb(&oklab_palette);

    // Initialize temporal dithering
    let mut temporal_dither = TemporalDither::new();

    // Process frames with temporal dithering and blue noise
    let mut indexed_frames = Vec::new();
    for (frame_idx, frame_data) in frames.iter().enumerate() {
        // Convert frame to OKLab
        let frame_oklab = srgb_to_oklab_batch(frame_data);

        // Apply temporal dithering for smooth animation
        let indices = temporal_dither.apply(
            &frame_oklab,
            &oklab_palette,
            width as usize,
            height as usize,
        );

        // Alternative: Use temporal blue noise (can switch based on content)
        // let indices = temporal_blue_noise(
        //     frame_data,
        //     width as usize,
        //     height as usize,
        //     &srgb_palette,
        //     0.85,
        //     frame_idx,
        // );

        indexed_frames.push(indices);
    }

    // Create GIF with enhanced palette
    let mut gif_buffer = Vec::new();
    {
        use gif::{Encoder, Frame, Repeat};

        // Convert palette for GIF format
        let mut global_palette = Vec::with_capacity(srgb_palette.len() * 3);
        for color in &srgb_palette {
            global_palette.push(color[0]);
            global_palette.push(color[1]);
            global_palette.push(color[2]);
        }

        // Ensure palette is exactly 256 colors (pad with black if needed)
        while global_palette.len() < 768 { // 256 * 3
            global_palette.push(0);
        }

        let mut encoder = Encoder::new(
            &mut gif_buffer,
            gif_opts.width,
            gif_opts.height,
            &global_palette[0..768]
        ).map_err(|_| ProcessorError::EncodingError)?;

        encoder.set_repeat(Repeat::Infinite)
            .map_err(|_| ProcessorError::EncodingError)?;

        // Write frames
        for indices in indexed_frames {
            let frame = Frame {
                width: gif_opts.width,
                height: gif_opts.height,
                buffer: indices.into(),
                delay: 100 / gif_opts.fps,
                ..Default::default()
            };
            encoder.write_frame(&frame)
                .map_err(|_| ProcessorError::EncodingError)?;
        }
    }

    // Build tensor if requested
    let tensor_data = if gif_opts.include_tensor {
        Some(build_tensor_from_frames(&frames, width, height)?)
    } else {
        None
    };

    let file_size = gif_buffer.len() as u32;
    Ok(ProcessResult {
        gif_data: gif_buffer,
        tensor_data,
        final_file_size: file_size,
        processing_time_ms: start.elapsed().as_millis() as f32,
        actual_frame_count: frames.len() as u16,
        palette_size_used: srgb_palette.len() as u16,
    })
}

// Helper function imports from oklab_quantization module
use oklab_quantization::{
    srgb_to_oklab_batch, build_oklab_palette, oklab_palette_to_srgb,
    TemporalDither,
};

// Include UniFFI scaffolding
uniffi::include_scaffolding!("rgb2gif");
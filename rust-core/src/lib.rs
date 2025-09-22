// RGB2GIF2VOXEL Processor - High-Performance GIF89a Encoding with Tensor Generation
// Features OKLab color space quantization and advanced dithering for superior quality

#![allow(clippy::empty_line_after_doc_comments)]

use std::time::Instant;
use imagequant::RGBA;

// ============================================================================
// MODULE IMPORTS
// ============================================================================

mod quantization;
mod oklab_quantization;
mod blue_noise;

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

/// Result type alias for cleaner function signatures
pub type Result<T> = std::result::Result<T, ProcessorError>;

/// Error types for UniFFI interop
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

// ============================================================================
// CONFIGURATION STRUCTURES
// ============================================================================

/// Color quantization options
#[derive(Debug, Clone)]
pub struct QuantizeOpts {
    pub quality_min: u8,         // 0-100, lower = better compression
    pub quality_max: u8,         // 0-100, higher = better quality
    pub speed: i32,              // 1-10, 1=slowest/best quality
    pub palette_size: u16,       // Max colors (typically 255)
    pub dithering_level: f32,    // 0.0-1.0, dithering strength
    pub shared_palette: bool,    // Use same palette for all frames
}

/// GIF output options
#[derive(Debug, Clone)]
pub struct GifOpts {
    pub width: u16,              // Output width in pixels
    pub height: u16,             // Output height in pixels
    pub frame_count: u16,        // Number of frames
    pub fps: u16,                // Frames per second
    pub loop_count: u16,         // 0 = infinite loop
    pub optimize: bool,          // Apply additional optimizations
    pub include_tensor: bool,    // Generate 16×16×256 tensor data
}

/// Processing result with metrics
#[derive(Debug, Clone)]
pub struct ProcessResult {
    pub gif_data: Vec<u8>,           // Complete GIF89a file data
    pub tensor_data: Option<Vec<u8>>, // Optional tensor for voxel visualization
    pub final_file_size: u32,         // Size in bytes
    pub processing_time_ms: f32,      // Total processing time
    pub actual_frame_count: u16,      // Frames processed
    pub palette_size_used: u16,       // Colors in palette
}

// ============================================================================
// MAIN PROCESSING PIPELINE
// ============================================================================

/// Process all frames in a single FFI call for maximum performance
///
/// # Arguments
/// * `frames_rgba` - Flattened RGBA data for all frames
/// * `width` - Frame width in pixels
/// * `height` - Frame height in pixels
/// * `frame_count` - Number of frames to process
/// * `quantize_opts` - Color quantization settings
/// * `gif_opts` - GIF output settings
///
/// # Returns
/// * `ProcessResult` containing GIF data and optional tensor
pub fn process_all_frames(
    frames_rgba: Vec<u8>,
    width: u32,
    height: u32,
    frame_count: u32,
    quantize_opts: QuantizeOpts,
    gif_opts: GifOpts,
) -> Result<ProcessResult> {
    let start = Instant::now();

    // Validate input buffer size
    let expected_size = (width * height * 4 * frame_count) as usize;
    if frames_rgba.len() != expected_size {
        return Err(ProcessorError::InvalidInput);
    }

    // Split buffer into individual frames
    let frame_size = (width * height * 4) as usize;
    let frames: Vec<&[u8]> = frames_rgba.chunks_exact(frame_size).collect();

    // Use OKLab color space for superior quality
    process_with_oklab(frames, width, height, quantize_opts, gif_opts)
}

// ============================================================================
// OKLAB PROCESSING PIPELINE
// ============================================================================

/// Process frames using perceptually uniform OKLab color space
fn process_with_oklab(
    frames: Vec<&[u8]>,
    width: u32,
    height: u32,
    quantize_opts: QuantizeOpts,
    gif_opts: GifOpts,
) -> Result<ProcessResult> {
    use oklab_quantization::{
        srgb_to_oklab_batch,
        build_oklab_palette,
        oklab_palette_to_srgb,
        TemporalDither,
    };

    let start = Instant::now();

    // Convert all frames to OKLab color space
    let mut all_oklab_pixels = Vec::new();
    for frame in &frames {
        let oklab = srgb_to_oklab_batch(frame);
        all_oklab_pixels.extend(oklab);
    }

    // Build optimal palette in OKLab space
    let palette_size = quantize_opts.palette_size.min(255) as usize;
    let oklab_palette = build_oklab_palette(&all_oklab_pixels, palette_size);

    // Convert palette back to sRGB for GIF encoding
    let srgb_palette = oklab_palette_to_srgb(&oklab_palette);

    // Apply temporal dithering for smooth animation
    let mut temporal_dither = TemporalDither::new();
    let mut indexed_frames = Vec::new();

    for (_frame_idx, frame_data) in frames.iter().enumerate() {
        let frame_oklab = srgb_to_oklab_batch(frame_data);
        let indices = temporal_dither.apply(
            &frame_oklab,
            &oklab_palette,
            width as usize,
            height as usize,
        );
        indexed_frames.push(indices);
    }

    // Encode as GIF89a
    let gif_buffer = encode_gif(&indexed_frames, &srgb_palette, &gif_opts)?;

    // Generate tensor if requested (for voxel visualization)
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

// ============================================================================
// FALLBACK IMAGEQUANT PIPELINE
// ============================================================================

/// Fallback processing using imagequant library
#[allow(dead_code)]
fn process_with_imagequant(
    frames: Vec<&[u8]>,
    width: u32,
    height: u32,
    quantize_opts: QuantizeOpts,
    gif_opts: GifOpts,
) -> Result<ProcessResult> {
    let start = Instant::now();

    // Setup imagequant
    let mut attr = imagequant::new();
    attr.set_quality(quantize_opts.quality_min, quantize_opts.quality_max)
        .map_err(|_| ProcessorError::QuantizationError)?;
    attr.set_speed(quantize_opts.speed)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Convert frames to RGBA pixels
    let mut images = Vec::new();
    for frame_data in &frames {
        let pixels: Vec<RGBA> = frame_data
            .chunks_exact(4)
            .map(|chunk| RGBA::new(chunk[0], chunk[1], chunk[2], chunk[3]))
            .collect();

        let img = attr.new_image(&pixels[..], width as usize, height as usize, 0.0)
            .map_err(|_| ProcessorError::QuantizationError)?;
        images.push(img);
    }

    // Quantize with shared palette
    if images.is_empty() {
        return Err(ProcessorError::InvalidInput);
    }

    let mut quantization = attr.quantize(&mut images[0])
        .map_err(|_| ProcessorError::QuantizationError)?;
    quantization.set_dithering_level(quantize_opts.dithering_level)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Get palette
    let palette = quantization.palette();
    let palette_size = palette.len() as u16;

    // Remap frames to palette indices
    let mut indexed_frames = Vec::new();
    for image in &mut images {
        let (_, indices) = quantization.remapped(image)
            .map_err(|_| ProcessorError::QuantizationError)?;
        indexed_frames.push(indices);
    }

    // Convert palette for GIF
    let srgb_palette: Vec<[u8; 4]> = palette.iter()
        .map(|c| [c.r, c.g, c.b, c.a])
        .collect();

    // Encode GIF
    let gif_buffer = encode_gif(&indexed_frames, &srgb_palette, &gif_opts)?;

    // Generate tensor if requested
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
        palette_size_used,
    })
}

// ============================================================================
// GIF ENCODING
// ============================================================================

/// Encode indexed frames as GIF89a
fn encode_gif(
    indexed_frames: &[Vec<u8>],
    palette: &[[u8; 4]],
    opts: &GifOpts,
) -> Result<Vec<u8>> {
    use gif::{Encoder, Frame, Repeat};

    let mut gif_buffer = Vec::new();

    // Convert palette to GIF format (RGB, no alpha)
    let mut global_palette = Vec::with_capacity(768);
    for color in palette.iter().take(256) {
        global_palette.push(color[0]);
        global_palette.push(color[1]);
        global_palette.push(color[2]);
    }

    // Pad to 256 colors if needed
    while global_palette.len() < 768 {
        global_palette.push(0);
    }

    // Create encoder
    let mut encoder = Encoder::new(
        &mut gif_buffer,
        opts.width,
        opts.height,
        &global_palette[0..768],
    ).map_err(|_| ProcessorError::EncodingError)?;

    // Set infinite loop
    encoder.set_repeat(Repeat::Infinite)
        .map_err(|_| ProcessorError::EncodingError)?;

    // Write frames
    for indices in indexed_frames {
        let frame = Frame {
            width: opts.width,
            height: opts.height,
            buffer: indices.clone().into(),
            delay: 100 / opts.fps, // Convert FPS to centiseconds
            ..Default::default()
        };
        encoder.write_frame(&frame)
            .map_err(|_| ProcessorError::EncodingError)?;
    }

    Ok(gif_buffer)
}

// ============================================================================
// TENSOR GENERATION FOR VOXEL VISUALIZATION
// ============================================================================

/// Build 16×16×256 tensor from frames for voxel cube visualization
/// Each frame is downsampled to 16×16 for efficient 3D rendering
fn build_tensor_from_frames(frames: &[&[u8]], width: u32, height: u32) -> Result<Vec<u8>> {
    let tensor_size = 16 * 16 * frames.len() * 4;
    let mut tensor = Vec::with_capacity(tensor_size);

    // Downsample each frame to 16×16
    let scale = (width / 16) as usize;

    for frame in frames {
        for ty in 0..16 {
            for tx in 0..16 {
                // Box filter for downsampling
                let mut r = 0u32;
                let mut g = 0u32;
                let mut b = 0u32;
                let mut a = 0u32;

                for dy in 0..scale {
                    for dx in 0..scale {
                        let x = tx * scale + dx;
                        let y = ty * scale + dy;
                        let idx = (y * width as usize + x) * 4;

                        if idx + 3 < frame.len() {
                            r += frame[idx] as u32;
                            g += frame[idx + 1] as u32;
                            b += frame[idx + 2] as u32;
                            a += frame[idx + 3] as u32;
                        }
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

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Calculate required buffer size for frames
pub fn calculate_buffer_size(width: u32, height: u32, frame_count: u32) -> u32 {
    width * height * 4 * frame_count
}

/// Validate buffer has expected size
pub fn validate_buffer(buffer: Vec<u8>, expected_size: u32) -> bool {
    buffer.len() == expected_size as usize
}

// ============================================================================
// UNIFFI SCAFFOLDING
// ============================================================================

uniffi::include_scaffolding!("rgb2gif");
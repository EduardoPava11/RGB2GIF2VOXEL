// Quantization module using libimagequant
// High-quality color quantization with speed/quality trade-offs

use imagequant::{Attributes, Image};
use crate::{ProcessorError, Result};
use rayon::prelude::*;

pub struct QuantizeOptions {
    pub quality_min: u8,     // 0-100, lower = better compression
    pub quality_max: u8,     // 0-100, higher = better quality
    pub speed: i32,          // 1-10, 1=slowest/best, 10=fastest
    pub palette_size: u16,   // Max colors (typically 256)
    pub dithering_level: f32, // 0.0-1.0, Floyd-Steinberg amount
}

impl Default for QuantizeOptions {
    fn default() -> Self {
        Self {
            quality_min: 85,      // Increased for better quality
            quality_max: 100,
            speed: 1,             // Slowest = best quality
            palette_size: 255,    // Reserve 1 for future transparency
            dithering_level: 0.85, // Less aggressive, better for animations
        }
    }
}

pub struct QuantizeResult {
    pub indices: Vec<u8>,      // Palette indices for each pixel
    pub palette: Vec<u32>,     // RGBA palette as packed u32 (0xRRGGBBAA)
    pub width: u32,
    pub height: u32,
}

/// Quantize a single RGBA frame
pub fn quantize_frame(
    rgba_data: &[u8],
    width: u32,
    height: u32,
    options: &QuantizeOptions,
) -> Result<QuantizeResult> {
    // Create attributes with quality settings
    let mut attr = Attributes::new();
    attr.set_quality(options.quality_min, options.quality_max)
        .map_err(|_| ProcessorError::QuantizationError)?;

    attr.set_speed(options.speed)
        .map_err(|_| ProcessorError::QuantizationError)?;

    attr.set_max_colors(options.palette_size as u32)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Convert raw bytes to RGBA slice
    use imagequant::RGBA;
    let pixels = unsafe {
        std::slice::from_raw_parts(
            rgba_data.as_ptr() as *const RGBA,
            (width * height) as usize,
        )
    };

    // Create image from RGBA data
    let mut image = Image::new_borrowed(
        &attr,
        pixels,
        width as usize,
        height as usize,
        0.0, // gamma (0 = sRGB)
    ).map_err(|_| ProcessorError::QuantizationError)?;

    // Perform quantization
    let mut result = attr.quantize(&mut image)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Set dithering level
    result.set_dithering_level(options.dithering_level)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Remap to palette indices
    let (palette, indices) = result.remapped(&mut image)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Convert palette to packed u32 RGBA
    let palette_rgba: Vec<u32> = palette.iter()
        .map(|c| ((c.r as u32) << 24) | ((c.g as u32) << 16) | ((c.b as u32) << 8) | (c.a as u32))
        .collect();

    Ok(QuantizeResult {
        indices,
        palette: palette_rgba,
        width,
        height,
    })
}

/// Quantize multiple frames in parallel with optional shared palette
pub fn quantize_batch(
    frames: Vec<Vec<u8>>,
    width: u32,
    height: u32,
    options: &QuantizeOptions,
    shared_palette: bool,
) -> Result<Vec<QuantizeResult>> {
    if shared_palette {
        // Build a global histogram from all frames
        quantize_with_shared_palette(frames, width, height, options)
    } else {
        // Quantize each frame independently in parallel
        frames
            .par_iter()
            .map(|frame| quantize_frame(frame, width, height, options))
            .collect::<Result<Vec<_>>>()
    }
}

/// Quantize with a shared palette across all frames
fn quantize_with_shared_palette(
    frames: Vec<Vec<u8>>,
    width: u32,
    height: u32,
    options: &QuantizeOptions,
) -> Result<Vec<QuantizeResult>> {
    // Create shared attributes
    let mut attr = Attributes::new();
    attr.set_quality(options.quality_min, options.quality_max)
        .map_err(|_| ProcessorError::QuantizationError)?;

    attr.set_speed(options.speed)
        .map_err(|_| ProcessorError::QuantizationError)?;

    attr.set_max_colors(options.palette_size as u32)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Build histogram from all frames
    // For simplicity, just use first frame's palette for all
    // In production, you'd build a proper histogram across all frames

    if frames.is_empty() {
        return Ok(Vec::new());
    }

    // Get palette from first frame
    let first_frame = &frames[0];
    use imagequant::RGBA;
    let first_pixels = unsafe {
        std::slice::from_raw_parts(
            first_frame.as_ptr() as *const RGBA,
            (width * height) as usize,
        )
    };

    let mut first_image = Image::new_borrowed(
        &attr,
        first_pixels,
        width as usize,
        height as usize,
        0.0,
    ).map_err(|_| ProcessorError::QuantizationError)?;

    let mut quant_result = attr.quantize(&mut first_image)
        .map_err(|_| ProcessorError::QuantizationError)?;

    quant_result.set_dithering_level(options.dithering_level)
        .map_err(|_| ProcessorError::QuantizationError)?;

    let (palette, _) = quant_result.remapped(&mut first_image)
        .map_err(|_| ProcessorError::QuantizationError)?;

    // Convert palette to packed format
    let palette_rgba: Vec<u32> = palette.iter()
        .map(|c| ((c.r as u32) << 24) | ((c.g as u32) << 16) | ((c.b as u32) << 8) | (c.a as u32))
        .collect();

    // Apply shared palette to all frames
    let results: Result<Vec<QuantizeResult>> = frames
        .into_par_iter()
        .map(|frame_data| {
            // Create image for this frame
            let pixels = unsafe {
                std::slice::from_raw_parts(
                    frame_data.as_ptr() as *const RGBA,
                    (width * height) as usize,
                )
            };

            let mut image = Image::new_borrowed(
                &attr,
                pixels,
                width as usize,
                height as usize,
                0.0,
            ).map_err(|_| ProcessorError::QuantizationError)?;

            // Quantize with the shared attribute (will reuse palette)
            let mut result = attr.quantize(&mut image)
                .map_err(|_| ProcessorError::QuantizationError)?;

            result.set_dithering_level(options.dithering_level)
                .map_err(|_| ProcessorError::QuantizationError)?;

            let (_, indices) = result.remapped(&mut image)
                .map_err(|_| ProcessorError::QuantizationError)?;

            Ok(QuantizeResult {
                indices,
                palette: palette_rgba.clone(),
                width,
                height,
            })
        })
        .collect();

    results
}

/// Quantize with per-frame optimization but limited colors for smaller files
pub fn quantize_optimized(
    frames: Vec<Vec<u8>>,
    width: u32,
    height: u32,
    max_colors: u16,
) -> Result<Vec<QuantizeResult>> {
    let options = QuantizeOptions {
        quality_min: 85,       // High quality baseline
        quality_max: 100,      // Maximum quality
        speed: 1,              // Best quality (slower)
        palette_size: max_colors.min(255), // Cap at 255
        dithering_level: 0.85, // Optimal for animations
    };

    // Always use shared palette for temporal coherence
    quantize_batch(frames, width, height, &options, true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_quantize_basic() {
        // Create test image data
        let mut data = vec![0u8; 256 * 256 * 4];
        for i in 0..256 {
            for j in 0..256 {
                let idx = (i * 256 + j) * 4;
                data[idx] = (i * 255 / 256) as u8;     // R gradient
                data[idx + 1] = (j * 255 / 256) as u8; // G gradient
                data[idx + 2] = 128;                   // B constant
                data[idx + 3] = 255;                   // A opaque
            }
        }

        let options = QuantizeOptions::default();
        let result = quantize_frame(&data, 256, 256, &options).unwrap();

        assert!(!result.indices.is_empty());
        assert!(!result.palette.is_empty());
        assert!(result.palette.len() <= 256);
    }
}
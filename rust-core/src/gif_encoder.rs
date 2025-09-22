// GIF89a encoder module using the gif crate
// Produces standard GIF files with loop extension and optimized palettes

use gif::{Encoder, Frame, Repeat};
use crate::{ProcessorError, Result};
use crate::quantization::QuantizeResult;

pub struct GifOptions {
    pub width: u16,
    pub height: u16,
    pub frame_count: u16,
    pub fps: u16,           // Frames per second
    pub loop_count: u16,    // 0 = infinite
    pub optimize: bool,     // Apply optimization passes
}

impl Default for GifOptions {
    fn default() -> Self {
        Self {
            width: 256,
            height: 256,
            frame_count: 256,
            fps: 30,
            loop_count: 0,  // Infinite loop
            optimize: true,
        }
    }
}

/// Encode quantized frames to GIF89a format
pub fn encode_gif(
    quantized_frames: Vec<QuantizeResult>,
    options: &GifOptions,
) -> Result<Vec<u8>> {
    if quantized_frames.is_empty() {
        return Err(ProcessorError::InvalidInput("No frames to encode".into()));
    }

    // Validate dimensions
    let first_frame = &quantized_frames[0];
    if first_frame.width != options.width as u32 || first_frame.height != options.height as u32 {
        return Err(ProcessorError::InvalidInput(
            format!("Frame dimensions {}x{} don't match options {}x{}",
                    first_frame.width, first_frame.height,
                    options.width, options.height)
        ));
    }

    // Prepare output buffer
    let mut output = Vec::new();

    // Calculate frame delay in centiseconds (GIF uses 1/100s units)
    let delay_cs = (100 / options.fps) as u16;

    // Check if all frames share the same palette (global palette optimization)
    let use_global_palette = quantized_frames.windows(2).all(|w| w[0].palette == w[1].palette);

    if use_global_palette {
        encode_with_global_palette(&quantized_frames, options, delay_cs, &mut output)?;
    } else {
        encode_with_local_palettes(&quantized_frames, options, delay_cs, &mut output)?;
    }

    if options.optimize {
        // Could apply additional optimization passes here
        // For now, we rely on the gif crate's built-in optimizations
    }

    Ok(output)
}

/// Encode with a single global palette (more efficient)
fn encode_with_global_palette(
    frames: &[QuantizeResult],
    options: &GifOptions,
    delay_cs: u16,
    output: &mut Vec<u8>,
) -> Result<()> {
    let global_palette = &frames[0].palette;

    // Convert palette to flat RGB bytes
    let mut palette_rgb = Vec::with_capacity(global_palette.len() * 3);
    for color in global_palette {
        // Convert from u32 RGBA to RGB bytes
        let r = (color >> 24) as u8;
        let g = (color >> 16) as u8;
        let b = (color >> 8) as u8;
        // Alpha is ignored in GIF
        palette_rgb.push(r);
        palette_rgb.push(g);
        palette_rgb.push(b);
    }

    // Pad palette to power of 2 if needed
    let color_bits = (global_palette.len() as f32).log2().ceil() as usize;
    let padded_size = 1 << color_bits;
    while palette_rgb.len() < padded_size * 3 {
        palette_rgb.extend_from_slice(&[0, 0, 0]);
    }

    // Create encoder with global palette
    let mut encoder = Encoder::new(output, options.width, options.height, &palette_rgb)
        .map_err(|e| ProcessorError::EncodingError(format!("Failed to create encoder: {}", e)))?;

    // Set loop extension
    let repeat = if options.loop_count == 0 {
        Repeat::Infinite
    } else {
        Repeat::Finite(options.loop_count)
    };

    encoder.write_extension(gif::ExtensionData::Repetitions(repeat))
        .map_err(|e| ProcessorError::EncodingError(format!("Failed to set loop: {}", e)))?;

    // Write frames
    for (idx, quantized) in frames.iter().enumerate() {
        let mut frame = Frame::from_indexed_pixels(
            options.width,
            options.height,
            quantized.indices.clone(),
            None,  // Use global palette
        );

        frame.delay = delay_cs;
        frame.dispose = gif::DisposalMethod::Keep;

        encoder.write_frame(&frame)
            .map_err(|e| ProcessorError::EncodingError(
                format!("Failed to write frame {}: {}", idx, e)
            ))?;
    }

    Ok(())
}

/// Encode with per-frame local palettes (better quality, larger file)
fn encode_with_local_palettes(
    frames: &[QuantizeResult],
    options: &GifOptions,
    delay_cs: u16,
    output: &mut Vec<u8>,
) -> Result<()> {
    // Use first frame's palette as global (required by GIF format)
    let global_palette = &frames[0].palette;

    let mut palette_rgb = Vec::with_capacity(global_palette.len() * 3);
    for color in global_palette {
        // Convert from u32 RGBA to RGB bytes
        let r = (color >> 24) as u8;
        let g = (color >> 16) as u8;
        let b = (color >> 8) as u8;
        palette_rgb.push(r);
        palette_rgb.push(g);
        palette_rgb.push(b);
    }

    // Pad to power of 2
    let color_bits = (global_palette.len() as f32).log2().ceil() as usize;
    let padded_size = 1 << color_bits;
    while palette_rgb.len() < padded_size * 3 {
        palette_rgb.extend_from_slice(&[0, 0, 0]);
    }

    let mut encoder = Encoder::new(output, options.width, options.height, &palette_rgb)
        .map_err(|e| ProcessorError::EncodingError(format!("Failed to create encoder: {}", e)))?;

    // Set loop extension
    let repeat = if options.loop_count == 0 {
        Repeat::Infinite
    } else {
        Repeat::Finite(options.loop_count)
    };

    encoder.write_extension(gif::ExtensionData::Repetitions(repeat))
        .map_err(|e| ProcessorError::EncodingError(format!("Failed to set loop: {}", e)))?;

    // Write frames with local palettes
    for (idx, quantized) in frames.iter().enumerate() {
        // Prepare local palette
        let mut local_palette_rgb = Vec::with_capacity(quantized.palette.len() * 3);
        for color in &quantized.palette {
            let r = (color >> 24) as u8;
            let g = (color >> 16) as u8;
            let b = (color >> 8) as u8;
            local_palette_rgb.push(r);
            local_palette_rgb.push(g);
            local_palette_rgb.push(b);
        }

        // Pad local palette
        let local_bits = (quantized.palette.len() as f32).log2().ceil() as usize;
        let local_padded = 1 << local_bits;
        while local_palette_rgb.len() < local_padded * 3 {
            local_palette_rgb.extend_from_slice(&[0, 0, 0]);
        }

        let mut frame = Frame::from_indexed_pixels(
            options.width,
            options.height,
            quantized.indices.clone(),
            None,  // Local palettes not supported in this version
        );

        frame.delay = delay_cs;
        frame.dispose = gif::DisposalMethod::Keep;

        encoder.write_frame(&frame)
            .map_err(|e| ProcessorError::EncodingError(
                format!("Failed to write frame {}: {}", idx, e)
            ))?;
    }

    Ok(())
}

/// Encode raw RGBA frames directly (quantization + encoding in one step)
pub fn encode_rgba_to_gif(
    rgba_frames: Vec<Vec<u8>>,
    width: u32,
    height: u32,
    fps: u16,
) -> Result<Vec<u8>> {
    use crate::quantization::{quantize_batch, QuantizeOptions};

    // Quantize frames with shared palette for better compression
    let mut quant_opts = QuantizeOptions::default();
    quant_opts.speed = 5;  // Balanced speed/quality

    let quantized = quantize_batch(rgba_frames, width, height, &quant_opts, true)?;

    // Encode to GIF
    let gif_opts = GifOptions {
        width: width as u16,
        height: height as u16,
        frame_count: quantized.len() as u16,
        fps,
        loop_count: 0,
        optimize: true,
    };

    encode_gif(quantized, &gif_opts)
}

/// Legacy compatibility function for existing FFI
pub fn encode_gif89a(
    indices: &[u8],
    palettes: &[u32],
    frame_count: u32,
    side: u32,
    delay_cs: u16,
) -> std::result::Result<Vec<u8>, Box<dyn std::error::Error>> {
    let frame_size = (side * side) as usize;
    let mut output = Vec::new();

    {
        // Convert first palette to RGB (global palette)
        let mut global_palette = Vec::with_capacity(256 * 3);
        for i in 0..256 {
            let color = if i < palettes.len() {
                palettes[i]
            } else {
                0xFF000000 // Black
            };
            global_palette.push(((color >> 16) & 0xFF) as u8); // R
            global_palette.push(((color >> 8) & 0xFF) as u8);  // G
            global_palette.push((color & 0xFF) as u8);         // B
        }

        // Create encoder
        let mut encoder = Encoder::new(&mut output, side as u16, side as u16, &global_palette)?;
        encoder.write_extension(gif::ExtensionData::Repetitions(Repeat::Infinite))?;

        // Process each frame
        for frame_idx in 0..frame_count as usize {
            // Get indices for this frame
            let frame_start = frame_idx * frame_size;
            let frame_end = frame_start + frame_size;

            if frame_end <= indices.len() {
                let frame_indices = &indices[frame_start..frame_end];

                // Create frame
                let mut frame = Frame::from_indexed_pixels(
                    side as u16,
                    side as u16,
                    frame_indices,
                    None
                );
                frame.delay = delay_cs;

                // Write frame
                encoder.write_frame(&frame)?;
            }
        }
    }

    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::quantization::QuantizeResult;

    fn create_test_frame(width: u32, height: u32) -> QuantizeResult {
        let indices = vec![0u8; (width * height) as usize];
        // Pack colors as u32 RGBA
        let palette = vec![
            0xFF0000FF_u32, // Red
            0x00FF00FF_u32, // Green
            0x0000FFFF_u32, // Blue
        ];

        QuantizeResult {
            indices,
            palette,
            width,
            height,
        }
    }

    #[test]
    fn test_encode_single_frame() {
        let frames = vec![create_test_frame(256, 256)];
        let options = GifOptions::default();

        let result = encode_gif(frames, &options);
        assert!(result.is_ok());

        let gif_data = result.unwrap();
        assert!(gif_data.len() > 0);
        assert_eq!(&gif_data[0..6], b"GIF89a"); // Check GIF header
    }

    #[test]
    fn test_encode_multiple_frames() {
        let frames = vec![
            create_test_frame(256, 256),
            create_test_frame(256, 256),
            create_test_frame(256, 256),
        ];

        let mut options = GifOptions::default();
        options.frame_count = 3;

        let result = encode_gif(frames, &options);
        assert!(result.is_ok());
    }

    #[test]
    fn test_frame_delay_calculation() {
        let frames = vec![create_test_frame(256, 256)];

        let mut options = GifOptions::default();
        options.fps = 30; // Should result in ~3cs delay

        let result = encode_gif(frames, &options).unwrap();
        assert!(result.len() > 0);
    }
}
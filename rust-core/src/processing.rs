// processing.rs - Image processing functions
use image::{ImageBuffer, Rgba, imageops::FilterType};
use color_quant::NeuQuant;
use std::error::Error;

/// Downsample RGBA image using Lanczos3 filter
pub fn downsample_lanczos(
    rgba_data: &[u8],
    width: u32,
    height: u32,
    target_size: u32,
) -> Result<Vec<u8>, Box<dyn Error>> {
    // Create image from RGBA data
    let img = ImageBuffer::<Rgba<u8>, Vec<u8>>::from_raw(
        width,
        height,
        rgba_data.to_vec(),
    ).ok_or("Failed to create image buffer")?;

    // Resize using Lanczos3 (high quality)
    let resized = image::imageops::resize(
        &img,
        target_size,
        target_size,
        FilterType::Lanczos3,
    );

    // Convert back to raw RGBA bytes
    Ok(resized.into_raw())
}

/// Quantize RGBA image to indexed color with palette
pub fn quantize_neuquant(
    rgba_data: &[u8],
    side: u32,
    palette_size: usize,
) -> Result<(Vec<u8>, Vec<u32>), Box<dyn Error>> {
    // NeuQuant expects RGB data, so we need to strip alpha
    let mut rgb_data = Vec::with_capacity((side * side * 3) as usize);
    for chunk in rgba_data.chunks(4) {
        rgb_data.push(chunk[0]); // R
        rgb_data.push(chunk[1]); // G
        rgb_data.push(chunk[2]); // B
        // Skip alpha
    }

    // Create NeuQuant quantizer
    let nq = NeuQuant::new(10, palette_size, &rgb_data);

    // Build palette (RGB triples)
    let palette_rgb = nq.color_map_rgb();
    let mut palette = Vec::with_capacity(palette_size);

    for i in 0..palette_size {
        let idx = i * 3;
        if idx + 2 < palette_rgb.len() {
            let r = palette_rgb[idx] as u32;
            let g = palette_rgb[idx + 1] as u32;
            let b = palette_rgb[idx + 2] as u32;
            // Pack as 0xAARRGGBB with opaque alpha
            let color = 0xFF000000 | (r << 16) | (g << 8) | b;
            palette.push(color);
        } else {
            // Pad with black if palette is smaller
            palette.push(0xFF000000);
        }
    }

    // Map pixels to palette indices
    let mut indices = Vec::with_capacity((side * side) as usize);
    for chunk in rgb_data.chunks(3) {
        // index_of ALWAYS expects 4 bytes (RGBA) even when NeuQuant was created with RGB
        // We need to add a dummy alpha byte
        let rgba = [chunk[0], chunk[1], chunk[2], 255u8];
        let index = nq.index_of(&rgba) as u8;
        indices.push(index);
    }

    Ok((indices, palette))
}

/// Alternative simpler quantization using color_quant directly
pub fn quantize_simple(
    rgba_data: &[u8],
    side: u32,
    palette_size: usize,
) -> Result<(Vec<u8>, Vec<u32>), Box<dyn Error>> {
    let pixel_count = (side * side) as usize;

    // color_quant NeuQuant expects RGB data (3 bytes per pixel), not RGBA
    // So we need to strip alpha channel
    let mut rgb_data = Vec::with_capacity(pixel_count * 3);
    for chunk in rgba_data.chunks(4) {
        rgb_data.push(chunk[0]); // R
        rgb_data.push(chunk[1]); // G
        rgb_data.push(chunk[2]); // B
        // Skip alpha
    }

    let quant = color_quant::NeuQuant::new(10, palette_size.min(256), &rgb_data);

    // Build color map - use RGB version since we passed RGB data
    let color_map_rgb = quant.color_map_rgb();

    // Convert palette to our format
    // color_map_rgb returns RGB triplets (3 bytes per color)
    let mut palette = Vec::with_capacity(palette_size);
    for chunk in color_map_rgb.chunks(3) {
        if chunk.len() >= 3 {
            let r = chunk[0] as u32;
            let g = chunk[1] as u32;
            let b = chunk[2] as u32;
            // Add opaque alpha channel
            let color = 0xFF000000 | (r << 16) | (g << 8) | b;
            palette.push(color);
        }
    }

    // Pad palette to requested size
    while palette.len() < palette_size {
        palette.push(0xFF000000); // Opaque black
    }

    // Map pixels to indices
    let mut indices = Vec::with_capacity(pixel_count);
    for chunk in rgb_data.chunks(3) {
        if chunk.len() >= 3 {
            // index_of ALWAYS expects 4 bytes (RGBA) even when NeuQuant was created with RGB
            let rgba = [chunk[0], chunk[1], chunk[2], 255u8];
            let index = quant.index_of(&rgba) as u8;
            indices.push(index);
        }
    }

    Ok((indices, palette))
}
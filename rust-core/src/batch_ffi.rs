// batch_ffi.rs
// Minimal batch processing FFI for architecture v2

use std::slice;
use image::{imageops, RgbaImage};
use color_quant::NeuQuant;
use gif::{Encoder, Frame, Repeat};

/// Process batch of RGBA frames - architecture v2 minimal FFI
/// Returns 0 on success, negative on error
#[no_mangle]
pub extern "C" fn yx_proc_batch_rgba8(
    frames: *const *const u8,  // Array of frame pointers
    count: i32,                 // Number of frames
    width: i32,                 // Input width
    height: i32,                // Input height
    target: i32,                // Target size (132)
    palette_size: i32,          // Palette size (256)
    out_indices: *mut u8,       // Output indices (Z-major)
    out_palettes: *mut u32,     // Output palettes (RGB packed)
) -> i32 {
    // Safety checks
    if frames.is_null() || out_indices.is_null() || out_palettes.is_null() {
        return -1;
    }
    if count <= 0 || width <= 0 || height <= 0 || target <= 0 || palette_size <= 0 {
        return -2;
    }

    let frame_count = count as usize;
    let input_size = (width * height * 4) as usize;
    let target_size = target as u32;
    let palette_len = palette_size as usize;

    unsafe {
        // Get frame pointers
        let frame_ptrs = slice::from_raw_parts(frames, frame_count);

        // Process each frame
        for (frame_idx, &frame_ptr) in frame_ptrs.iter().enumerate() {
            if frame_ptr.is_null() {
                return -3;
            }

            // Get frame data
            let frame_data = slice::from_raw_parts(frame_ptr, input_size);

            // Convert to RgbaImage
            let img = match RgbaImage::from_raw(width as u32, height as u32, frame_data.to_vec()) {
                Some(img) => img,
                None => return -4,
            };

            // Resize to target size
            let resized = if width != target || height != target {
                imageops::resize(&img, target_size, target_size, imageops::FilterType::Lanczos3)
            } else {
                img
            };

            // Quantize with NeuQuant
            let raw_pixels = resized.into_raw();
            let quantizer = NeuQuant::new(10, palette_len, &raw_pixels);

            // Get palette
            let palette = quantizer.color_map_rgba();

            // Write palette to output (RGB packed as 0x00RRGGBB)
            let palette_offset = frame_idx * palette_len;
            let out_palette_slice = slice::from_raw_parts_mut(
                out_palettes.add(palette_offset),
                palette_len
            );

            for (i, chunk) in palette.chunks(4).enumerate() {
                if i >= palette_len { break; }
                let r = chunk[0] as u32;
                let g = chunk[1] as u32;
                let b = chunk[2] as u32;
                out_palette_slice[i] = (r << 16) | (g << 8) | b;
            }

            // Quantize pixels to indices
            let indices_offset = frame_idx * (target_size * target_size) as usize;
            let out_indices_slice = slice::from_raw_parts_mut(
                out_indices.add(indices_offset),
                (target_size * target_size) as usize
            );

            for (i, chunk) in raw_pixels.chunks(4).enumerate() {
                if i >= out_indices_slice.len() { break; }
                out_indices_slice[i] = quantizer.index_of(chunk) as u8;
            }
        }
    }

    0 // Success
}

/// Encode GIF from quantized frames - architecture v2 minimal FFI
/// Returns 0 on success, negative on error
#[no_mangle]
pub extern "C" fn yx_gif_encode(
    indices: *const u8,         // Palette indices for all frames
    palettes: *const u32,       // RGB palettes for all frames
    frame_count: i32,           // Number of frames
    side: i32,                  // Cube side length (132)
    delay_cs: i32,              // Delay in centiseconds
    output: *mut u8,            // Output buffer
    output_len: *mut usize,     // In: buffer size, Out: actual size
) -> i32 {
    // Safety checks
    if indices.is_null() || palettes.is_null() || output.is_null() || output_len.is_null() {
        return -1;
    }
    if frame_count <= 0 || side <= 0 || delay_cs < 0 {
        return -2;
    }

    let n_frames = frame_count as usize;
    let size = side as usize;
    let frame_pixels = size * size;
    let palette_size = 256;

    unsafe {
        let max_size = *output_len;
        let mut buffer = Vec::with_capacity(max_size);

        // Create GIF encoder
        {
            let mut encoder = Encoder::new(&mut buffer, size as u16, size as u16, &[]).unwrap();
            encoder.set_repeat(Repeat::Infinite).unwrap();

            // Process each frame
            for frame_idx in 0..n_frames {
                // Get frame indices
                let indices_offset = frame_idx * frame_pixels;
                let frame_indices = slice::from_raw_parts(
                    indices.add(indices_offset),
                    frame_pixels
                );

                // Get frame palette
                let palette_offset = frame_idx * palette_size;
                let frame_palette = slice::from_raw_parts(
                    palettes.add(palette_offset),
                    palette_size
                );

                // Convert palette to GIF format (RGB bytes)
                let mut gif_palette = Vec::with_capacity(palette_size * 3);
                for &color in frame_palette {
                    gif_palette.push(((color >> 16) & 0xFF) as u8); // R
                    gif_palette.push(((color >> 8) & 0xFF) as u8);  // G
                    gif_palette.push((color & 0xFF) as u8);         // B
                }

                // Create GIF frame
                let mut frame = Frame::from_palette_pixels(
                    size as u16,
                    size as u16,
                    frame_indices,
                    &gif_palette,
                    None
                );
                frame.delay = delay_cs as u16;

                // Write frame
                if encoder.write_frame(&frame).is_err() {
                    return -3;
                }
            }
        }

        // Copy to output buffer
        let actual_size = buffer.len();
        if actual_size > max_size {
            return -4; // Buffer too small
        }

        std::ptr::copy_nonoverlapping(buffer.as_ptr(), output, actual_size);
        *output_len = actual_size;
    }

    0 // Success
}
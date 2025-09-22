//! iOS FFI for RGB2GIF2VOXEL
//! Provides C API matching Swift expectations

use std::collections::HashMap;
use std::ptr;
use std::slice;
use std::sync::Mutex;
use color_quant::NeuQuant;
use image::{ImageBuffer, Rgba, DynamicImage};
use gif::{Encoder, Frame, Repeat};
use std::io::Write;

// Processor state for accumulating frames
pub struct YinGifProcessor {
    frames: Vec<Vec<u8>>,  // Accumulated frames
    target_size: usize,     // Target dimension (e.g., 132)
    palette_size: usize,    // Palette size (e.g., 256)
}

// Global processor storage (for simplicity)
static mut PROCESSORS: Option<Mutex<HashMap<usize, YinGifProcessor>>> = None;
static mut NEXT_ID: usize = 1;

/// Initialize the processor system (called once)
fn ensure_initialized() {
    unsafe {
        if PROCESSORS.is_none() {
            PROCESSORS = Some(Mutex::new(HashMap::new()));
        }
    }
}

/// Create a new processor instance
#[no_mangle]
pub extern "C" fn yingif_processor_new() -> *mut libc::c_void {
    ensure_initialized();
    
    let processor = YinGifProcessor {
        frames: Vec::new(),
        target_size: 132,  // Default
        palette_size: 256, // Default
    };
    
    unsafe {
        let id = NEXT_ID;
        NEXT_ID += 1;
        
        if let Some(ref processors) = PROCESSORS {
            processors.lock().unwrap().insert(id, processor);
            return id as *mut libc::c_void;
        }
    }
    
    ptr::null_mut()
}

/// Free a processor instance
#[no_mangle]
pub extern "C" fn yingif_processor_free(processor: *mut libc::c_void) {
    if processor.is_null() {
        return;
    }
    
    unsafe {
        let id = processor as usize;
        if let Some(ref processors) = PROCESSORS {
            processors.lock().unwrap().remove(&id);
        }
    }
}

/// Process a single BGRA frame
#[no_mangle]
pub extern "C" fn yingif_process_frame(
    processor: *mut libc::c_void,
    bgra_data: *const u8,
    width: i32,
    height: i32,
    target_size: i32,
    palette_size: i32,
    out_indices: *mut u8,
    out_palette: *mut u32,
) -> i32 {
    if processor.is_null() || bgra_data.is_null() || out_indices.is_null() || out_palette.is_null() {
        return -1;
    }
    
    unsafe {
        let id = processor as usize;
        if let Some(ref processors) = PROCESSORS {
            if let Some(proc) = processors.lock().unwrap().get_mut(&id) {
                // Update settings
                proc.target_size = target_size as usize;
                proc.palette_size = palette_size as usize;
                
                // Convert BGRA to RGBA
                let pixel_count = (width * height) as usize;
                let bgra_slice = slice::from_raw_parts(bgra_data, pixel_count * 4);
                let mut rgba_data = vec![0u8; pixel_count * 4];
                
                for i in 0..pixel_count {
                    rgba_data[i * 4] = bgra_slice[i * 4 + 2];     // R
                    rgba_data[i * 4 + 1] = bgra_slice[i * 4 + 1]; // G
                    rgba_data[i * 4 + 2] = bgra_slice[i * 4];     // B
                    rgba_data[i * 4 + 3] = bgra_slice[i * 4 + 3]; // A
                }
                
                // Resize if needed
                let resized = if width != target_size || height != target_size {
                    resize_lanczos3(&rgba_data, width as u32, height as u32, target_size as u32)
                } else {
                    rgba_data
                };
                
                // Quantize
                let (palette, indices) = quantize_neuquant(&resized, target_size as u32, palette_size as usize);
                
                // Copy outputs
                let out_indices_slice = slice::from_raw_parts_mut(out_indices, (target_size * target_size) as usize);
                out_indices_slice.copy_from_slice(&indices);
                
                let out_palette_slice = slice::from_raw_parts_mut(out_palette, palette_size as usize);
                for (i, &color) in palette.iter().enumerate() {
                    out_palette_slice[i] = color;
                }
                
                // Store processed frame for later GIF creation
                proc.frames.push(indices);
                
                return 0;
            }
        }
    }
    
    -1
}

/// Create GIF from accumulated frames
#[no_mangle]
pub extern "C" fn yingif_create_gif89a(
    indices: *const u8,
    palette: *const u32,
    cube_size: i32,
    palette_size: i32,
    delay_ms: i32,
    out_data: *mut u8,
    out_capacity: i32,
    out_size: *mut i32,
) -> i32 {
    if indices.is_null() || palette.is_null() || out_data.is_null() || out_size.is_null() {
        return -1;
    }
    
    unsafe {
        let frame_count = cube_size as usize;
        let frame_pixels = (cube_size * cube_size) as usize;
        let total_pixels = frame_count * frame_pixels;
        
        // Read input data
        let indices_slice = slice::from_raw_parts(indices, total_pixels);
        let palette_slice = slice::from_raw_parts(palette, palette_size as usize);
        
        // Convert palette from u32 to RGB bytes
        let mut palette_rgb = vec![0u8; palette_size as usize * 3];
        for i in 0..palette_size as usize {
            let color = palette_slice[i];
            palette_rgb[i * 3] = ((color >> 16) & 0xFF) as u8; // R
            palette_rgb[i * 3 + 1] = ((color >> 8) & 0xFF) as u8; // G
            palette_rgb[i * 3 + 2] = (color & 0xFF) as u8; // B
        }
        
        // Create GIF
        let mut gif_data = Vec::new();
        {
            let mut encoder = Encoder::new(&mut gif_data, cube_size as u16, cube_size as u16, &palette_rgb).unwrap();
            encoder.set_repeat(Repeat::Infinite).unwrap();
            
            // Add frames
            for frame_idx in 0..frame_count {
                let start = frame_idx * frame_pixels;
                let end = start + frame_pixels;
                let frame_data = &indices_slice[start..end];
                
                let mut frame = Frame::from_indexed_pixels(cube_size as u16, cube_size as u16, frame_data, None);
                frame.delay = (delay_ms / 10) as u16; // Convert to centiseconds
                encoder.write_frame(&frame).unwrap();
            }
        }
        
        // Copy to output buffer
        let gif_size = gif_data.len() as i32;
        if gif_size > out_capacity {
            return -2; // Buffer too small
        }
        
        let out_slice = slice::from_raw_parts_mut(out_data, gif_size as usize);
        out_slice.copy_from_slice(&gif_data);
        *out_size = gif_size;
        
        0
    }
}

/// Estimate GIF size
#[no_mangle]
pub extern "C" fn yingif_estimate_gif_size(cube_size: i32, palette_size: i32) -> i32 {
    // Rough estimate: header + palette + compressed frames
    let header_size = 13; // GIF header
    let palette_bytes = palette_size * 3;
    let frame_pixels = cube_size * cube_size;
    let frames = cube_size;
    
    // Assume ~50% compression with LZW
    let compressed_frame_size = frame_pixels / 2;
    let total_frame_size = compressed_frame_size * frames;
    
    header_size + palette_bytes + total_frame_size + 1024 // Extra overhead
}

// Helper functions

fn resize_lanczos3(rgba: &[u8], width: u32, height: u32, target_size: u32) -> Vec<u8> {
    let img = ImageBuffer::<Rgba<u8>, _>::from_raw(width, height, rgba.to_vec()).unwrap();
    let resized = DynamicImage::ImageRgba8(img).resize_exact(
        target_size,
        target_size,
        image::imageops::FilterType::Lanczos3,
    );
    resized.to_rgba8().into_raw()
}

fn quantize_neuquant(rgba: &[u8], size: u32, colors: usize) -> (Vec<u32>, Vec<u8>) {
    let pixel_count = (size * size) as usize;
    
    // Extract RGB data (skip alpha)
    let mut rgb = vec![0u8; pixel_count * 3];
    for i in 0..pixel_count {
        rgb[i * 3] = rgba[i * 4];
        rgb[i * 3 + 1] = rgba[i * 4 + 1];
        rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    
    // Quantize
    let mut quantizer = NeuQuant::new(10, colors, &rgb);
    
    // Build palette
    let mut palette = vec![0u32; colors];
    for i in 0..colors {
        let [r, g, b, _] = quantizer.color(i);
        palette[i] = ((r as u32) << 16) | ((g as u32) << 8) | (b as u32);
    }
    
    // Map pixels to indices
    let mut indices = vec![0u8; pixel_count];
    for i in 0..pixel_count {
        let r = rgb[i * 3];
        let g = rgb[i * 3 + 1];
        let b = rgb[i * 3 + 2];
        indices[i] = quantizer.index_of(&[r, g, b, 255]) as u8;
    }
    
    (palette, indices)
}

// Add libc for C types
extern crate libc;
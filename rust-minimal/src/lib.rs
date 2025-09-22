// Minimal Rust FFI implementation - just enough to compile and benchmark

use std::slice;

/// Minimal frame processor - just downscale, no quantization yet
#[no_mangle]
pub extern "C" fn process_frame_minimal(
    bgra_ptr: *const u8,
    width: i32,
    height: i32,
    target_size: i32,
    output_ptr: *mut u8,
) -> i32 {
    // Safety check
    if bgra_ptr.is_null() || output_ptr.is_null() {
        return -1;
    }

    let width = width as usize;
    let height = height as usize;
    let target_size = target_size as usize;

    // Create slices from pointers
    let bgra = unsafe {
        slice::from_raw_parts(bgra_ptr, width * height * 4)
    };

    let output = unsafe {
        slice::from_raw_parts_mut(output_ptr, target_size * target_size)
    };

    // Simple nearest-neighbor downsampling (fast, good enough for benchmarking)
    let scale_x = width / target_size;
    let scale_y = height / target_size;

    for y in 0..target_size {
        for x in 0..target_size {
            let src_x = x * scale_x;
            let src_y = y * scale_y;
            let src_idx = (src_y * width + src_x) * 4;

            // Convert BGRA to grayscale for now
            let b = bgra[src_idx] as u32;
            let g = bgra[src_idx + 1] as u32;
            let r = bgra[src_idx + 2] as u32;

            // Simple grayscale conversion
            let gray = ((r * 299 + g * 587 + b * 114) / 1000) as u8;

            output[y * target_size + x] = gray;
        }
    }

    0 // Success
}
// Tensor module for 128×128×128 cube operations (N=128 optimal)
// Handles frame-major layout and efficient memory access

use crate::{ProcessorError, Result};
use rayon::prelude::*;

/// Tensor shape for 3D cube data
#[derive(Debug, Clone, Copy)]
pub struct TensorShape {
    pub width: u32,
    pub height: u32,
    pub frames: u32,
}

impl TensorShape {
    pub fn new(width: u32, height: u32, frames: u32) -> Self {
        Self { width, height, frames }
    }

    pub fn cube(size: u32) -> Self {
        Self {
            width: size,
            height: size,
            frames: size,
        }
    }

    pub fn total_elements(&self) -> usize {
        (self.width * self.height * self.frames) as usize
    }

    pub fn frame_size(&self) -> usize {
        (self.width * self.height) as usize
    }
}

/// Build tensor from RGBA frames (frame-major layout: [frame][y][x][channel])
pub fn build_tensor(
    frames_rgba: &[u8],
    shape: TensorShape,
) -> Result<Vec<u8>> {
    let expected_size = shape.total_elements() * 4; // RGBA
    if frames_rgba.len() != expected_size {
        return Err(ProcessorError::InvalidInput(
            format!("Expected {} bytes, got {}", expected_size, frames_rgba.len())
        ));
    }

    // For frame-major layout, data is already in the correct order
    // Just validate and return a copy
    Ok(frames_rgba.to_vec())
}

/// Extract a single frame from tensor
pub fn extract_frame(
    tensor: &[u8],
    shape: TensorShape,
    frame_index: u32,
) -> Result<Vec<u8>> {
    if frame_index >= shape.frames {
        return Err(ProcessorError::InvalidInput(
            format!("Frame index {} out of range (0..{})", frame_index, shape.frames)
        ));
    }

    let frame_size = shape.frame_size() * 4; // RGBA
    let start = (frame_index as usize) * frame_size;
    let end = start + frame_size;

    if end > tensor.len() {
        return Err(ProcessorError::TensorError("Tensor data too small".into()));
    }

    Ok(tensor[start..end].to_vec())
}

/// Convert voxel coordinates to linear index
#[inline]
pub fn voxel_to_index(x: u32, y: u32, z: u32, shape: TensorShape) -> usize {
    let frame_offset = z as usize * shape.frame_size();
    let row_offset = y as usize * shape.width as usize;
    let col_offset = x as usize;
    (frame_offset + row_offset + col_offset) * 4 // RGBA
}

/// Parallel tensor processing with Rayon
pub fn process_tensor_parallel<F>(
    tensor: &mut [u8],
    shape: TensorShape,
    processor: F,
) where
    F: Fn(&mut [u8]) + Sync + Send,
{
    let frame_size = shape.frame_size() * 4;

    tensor
        .par_chunks_mut(frame_size)
        .for_each(|frame| processor(frame));
}

/// Apply 3D convolution kernel (for future voxel operations)
pub fn convolve_3d(
    tensor: &[u8],
    shape: TensorShape,
    kernel: &[f32],
    kernel_size: u32,
) -> Result<Vec<u8>> {
    if kernel_size % 2 == 0 {
        return Err(ProcessorError::InvalidInput("Kernel size must be odd".into()));
    }

    let half_kernel = (kernel_size / 2) as i32;
    let mut output = vec![0u8; tensor.len()];

    // Parallel processing per frame
    output
        .par_chunks_mut(shape.frame_size() * 4)
        .enumerate()
        .for_each(|(z, out_frame)| {
            for y in 0..shape.height {
                for x in 0..shape.width {
                    let mut accum = [0.0f32; 4]; // RGBA accumulator

                    // Apply kernel
                    for kz in -half_kernel..=half_kernel {
                        for ky in -half_kernel..=half_kernel {
                            for kx in -half_kernel..=half_kernel {
                                let sz = (z as i32 + kz).clamp(0, shape.frames as i32 - 1) as u32;
                                let sy = (y as i32 + ky).clamp(0, shape.height as i32 - 1) as u32;
                                let sx = (x as i32 + kx).clamp(0, shape.width as i32 - 1) as u32;

                                let kernel_idx = ((kz + half_kernel) * kernel_size as i32 * kernel_size as i32 +
                                                 (ky + half_kernel) * kernel_size as i32 +
                                                 (kx + half_kernel)) as usize;

                                let pixel_idx = voxel_to_index(sx, sy, sz, shape);
                                let weight = kernel[kernel_idx];

                                for c in 0..4 {
                                    accum[c] += tensor[pixel_idx + c] as f32 * weight;
                                }
                            }
                        }
                    }

                    // Write result
                    let out_idx = (y * shape.width + x) as usize * 4;
                    for c in 0..4 {
                        out_frame[out_idx + c] = accum[c].clamp(0.0, 255.0) as u8;
                    }
                }
            }
        });

    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tensor_shape() {
        let shape = TensorShape::cube(128);
        assert_eq!(shape.width, 128);
        assert_eq!(shape.height, 128);
        assert_eq!(shape.frames, 128);
        assert_eq!(shape.total_elements(), 128 * 128 * 128);
        assert_eq!(shape.frame_size(), 128 * 128);
    }

    #[test]
    fn test_voxel_indexing() {
        let shape = TensorShape::cube(128);

        // Test corner cases
        assert_eq!(voxel_to_index(0, 0, 0, shape), 0);
        assert_eq!(voxel_to_index(1, 0, 0, shape), 4); // Next pixel (RGBA)
        assert_eq!(voxel_to_index(0, 1, 0, shape), 128 * 4); // Next row
        assert_eq!(voxel_to_index(0, 0, 1, shape), 128 * 128 * 4); // Next frame
    }

    #[test]
    fn test_frame_extraction() {
        let shape = TensorShape { width: 2, height: 2, frames: 2 };
        let tensor = vec![0u8; shape.total_elements() * 4];

        let frame = extract_frame(&tensor, shape, 0).unwrap();
        assert_eq!(frame.len(), 2 * 2 * 4);

        let frame = extract_frame(&tensor, shape, 1).unwrap();
        assert_eq!(frame.len(), 2 * 2 * 4);

        // Out of bounds
        assert!(extract_frame(&tensor, shape, 2).is_err());
    }
}
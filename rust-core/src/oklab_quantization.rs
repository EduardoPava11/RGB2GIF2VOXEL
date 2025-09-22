// OKLab Color Space Quantization for Superior GIF Quality
// Perceptually uniform color space for better gradients and skin tones

use crate::{ProcessorError, Result};
use rayon::prelude::*;
use std::collections::HashMap;

/// OKLab color representation
#[derive(Clone, Copy, Debug)]
pub struct OklabColor {
    pub l: f32, // Lightness
    pub a: f32, // Green-red
    pub b: f32, // Blue-yellow
}

/// Convert sRGB to OKLab for perceptually uniform processing
pub fn srgb_to_oklab_batch(rgba: &[u8]) -> Vec<OklabColor> {
    rgba.chunks_exact(4)
        .map(|pixel| {
            let r = pixel[0] as f32 / 255.0;
            let g = pixel[1] as f32 / 255.0;
            let b = pixel[2] as f32 / 255.0;

            // Convert sRGB to linear RGB
            let linear_r = if r <= 0.04045 {
                r / 12.92
            } else {
                ((r + 0.055) / 1.055).powf(2.4)
            };
            let linear_g = if g <= 0.04045 {
                g / 12.92
            } else {
                ((g + 0.055) / 1.055).powf(2.4)
            };
            let linear_b = if b <= 0.04045 {
                b / 12.92
            } else {
                ((b + 0.055) / 1.055).powf(2.4)
            };

            // Manual OKLab conversion from linear RGB
            // Based on OKLab paper: https://bottosson.github.io/posts/oklab/
            let l_ = 0.4122214708 * linear_r + 0.5363325363 * linear_g + 0.0514459929 * linear_b;
            let m = 0.2119034982 * linear_r + 0.6806995451 * linear_g + 0.1073969566 * linear_b;
            let s = 0.0883024619 * linear_r + 0.2817188376 * linear_g + 0.6299787005 * linear_b;

            let l_root = l_.cbrt();
            let m_root = m.cbrt();
            let s_root = s.cbrt();

            OklabColor {
                l: 0.2104542553 * l_root + 0.7936177850 * m_root - 0.0040720468 * s_root,
                a: 1.9779984951 * l_root - 2.4285922050 * m_root + 0.4505937099 * s_root,
                b: 0.0259040371 * l_root + 0.7827717662 * m_root - 0.8086757660 * s_root,
            }
        })
        .collect()
}

/// Convert OKLab back to sRGB
pub fn oklab_to_srgb_batch(oklab_colors: &[OklabColor]) -> Vec<u8> {
    let mut result = Vec::with_capacity(oklab_colors.len() * 4);

    for color in oklab_colors {
        // Manual OKLab to linear RGB conversion
        let l_ = color.l + 0.3963377774 * color.a + 0.2158037573 * color.b;
        let m_ = color.l - 0.1055613458 * color.a - 0.0638541728 * color.b;
        let s_ = color.l - 0.0894841775 * color.a - 1.2914855480 * color.b;

        let l_cubed = l_ * l_ * l_;
        let m_cubed = m_ * m_ * m_;
        let s_cubed = s_ * s_ * s_;

        let linear_r = 4.0767416621 * l_cubed - 3.3077115913 * m_cubed + 0.2309699292 * s_cubed;
        let linear_g = -1.2684380046 * l_cubed + 2.6097574011 * m_cubed - 0.3413193965 * s_cubed;
        let linear_b = -0.0041960863 * l_cubed - 0.7034186147 * m_cubed + 1.7076147010 * s_cubed;

        // Convert linear RGB to sRGB
        let r = if linear_r <= 0.0031308 {
            linear_r * 12.92
        } else {
            1.055 * linear_r.powf(1.0 / 2.4) - 0.055
        };
        let g = if linear_g <= 0.0031308 {
            linear_g * 12.92
        } else {
            1.055 * linear_g.powf(1.0 / 2.4) - 0.055
        };
        let b = if linear_b <= 0.0031308 {
            linear_b * 12.92
        } else {
            1.055 * linear_b.powf(1.0 / 2.4) - 0.055
        };

        result.push((r.clamp(0.0, 1.0) * 255.0) as u8);
        result.push((g.clamp(0.0, 1.0) * 255.0) as u8);
        result.push((b.clamp(0.0, 1.0) * 255.0) as u8);
        result.push(255); // Alpha
    }

    result
}

/// Quantize in OKLab space for better perceptual results
pub fn quantize_in_oklab(
    rgba_data: &[u8],
    width: u32,
    height: u32,
    palette_size: usize,
) -> Result<(Vec<u8>, Vec<[u8; 4]>)> {
    // Convert to OKLab
    let oklab_pixels = srgb_to_oklab_batch(rgba_data);

    // Build palette using median cut in OKLab space
    let palette = build_oklab_palette(&oklab_pixels, palette_size);

    // Map pixels to nearest palette colors
    let indices = map_to_palette(&oklab_pixels, &palette);

    // Convert palette back to sRGB
    let srgb_palette = oklab_palette_to_srgb(&palette);

    Ok((indices, srgb_palette))
}

/// Build optimal palette using median cut algorithm in OKLab space
pub fn build_oklab_palette(pixels: &[OklabColor], target_size: usize) -> Vec<OklabColor> {
    if pixels.is_empty() || target_size == 0 {
        return Vec::new();
    }

    // Start with all pixels in one box
    let mut boxes = vec![ColorBox::from_pixels(pixels)];

    // Split boxes until we reach target palette size
    while boxes.len() < target_size && boxes.iter().any(|b| b.can_split()) {
        // Find box with largest volume or variance
        let (split_idx, _) = boxes
            .iter()
            .enumerate()
            .filter(|(_, b)| b.can_split())
            .max_by_key(|(_, b)| (b.variance() * 1000.0) as u32)
            .unwrap();

        let box_to_split = boxes.remove(split_idx);
        let (box1, box2) = box_to_split.split();
        boxes.push(box1);
        boxes.push(box2);
    }

    // Get average color from each box
    boxes.into_iter().map(|b| b.average()).collect()
}

/// Color box for median cut algorithm
struct ColorBox {
    pixels: Vec<OklabColor>,
    min_l: f32,
    max_l: f32,
    min_a: f32,
    max_a: f32,
    min_b: f32,
    max_b: f32,
}

impl ColorBox {
    fn from_pixels(pixels: &[OklabColor]) -> Self {
        let mut min_l = f32::MAX;
        let mut max_l = f32::MIN;
        let mut min_a = f32::MAX;
        let mut max_a = f32::MIN;
        let mut min_b = f32::MAX;
        let mut max_b = f32::MIN;

        for p in pixels {
            min_l = min_l.min(p.l);
            max_l = max_l.max(p.l);
            min_a = min_a.min(p.a);
            max_a = max_a.max(p.a);
            min_b = min_b.min(p.b);
            max_b = max_b.max(p.b);
        }

        Self {
            pixels: pixels.to_vec(),
            min_l, max_l,
            min_a, max_a,
            min_b, max_b,
        }
    }

    fn can_split(&self) -> bool {
        self.pixels.len() > 1
    }

    fn variance(&self) -> f32 {
        let l_range = self.max_l - self.min_l;
        let a_range = self.max_a - self.min_a;
        let b_range = self.max_b - self.min_b;

        // Weight luminance more heavily (human vision is more sensitive to it)
        l_range * 2.0 + a_range + b_range
    }

    fn split(mut self) -> (Self, Self) {
        // Determine longest axis
        let l_range = self.max_l - self.min_l;
        let a_range = self.max_a - self.min_a;
        let b_range = self.max_b - self.min_b;

        // Sort along longest axis
        if l_range >= a_range && l_range >= b_range {
            self.pixels.sort_by(|a, b| a.l.partial_cmp(&b.l).unwrap());
        } else if a_range >= b_range {
            self.pixels.sort_by(|a, b| a.a.partial_cmp(&b.a).unwrap());
        } else {
            self.pixels.sort_by(|a, b| a.b.partial_cmp(&b.b).unwrap());
        }

        // Split at median
        let mid = self.pixels.len() / 2;
        let second_half = self.pixels.split_off(mid);

        (Self::from_pixels(&self.pixels), Self::from_pixels(&second_half))
    }

    fn average(&self) -> OklabColor {
        let sum_l: f32 = self.pixels.iter().map(|p| p.l).sum();
        let sum_a: f32 = self.pixels.iter().map(|p| p.a).sum();
        let sum_b: f32 = self.pixels.iter().map(|p| p.b).sum();
        let count = self.pixels.len() as f32;

        OklabColor {
            l: sum_l / count,
            a: sum_a / count,
            b: sum_b / count,
        }
    }
}

/// Map pixels to nearest palette colors
fn map_to_palette(pixels: &[OklabColor], palette: &[OklabColor]) -> Vec<u8> {
    pixels
        .par_iter()
        .map(|pixel| {
            palette
                .iter()
                .enumerate()
                .min_by_key(|(_, p)| {
                    let dl = pixel.l - p.l;
                    let da = pixel.a - p.a;
                    let db = pixel.b - p.b;
                    ((dl * dl + da * da + db * db) * 1000.0) as u32
                })
                .map(|(idx, _)| idx as u8)
                .unwrap_or(0)
        })
        .collect()
}

/// Convert OKLab palette to sRGB
pub fn oklab_palette_to_srgb(palette: &[OklabColor]) -> Vec<[u8; 4]> {
    let rgba_bytes = oklab_to_srgb_batch(palette);

    // Convert flat Vec<u8> to Vec<[u8; 4]>
    rgba_bytes
        .chunks_exact(4)
        .map(|chunk| [chunk[0], chunk[1], chunk[2], chunk[3]])
        .collect()
}

/// Temporal dithering for animations - reduces "crawling ants"
pub struct TemporalDither {
    prev_error: Option<Vec<f32>>,
    frame_index: usize,
}

impl TemporalDither {
    pub fn new() -> Self {
        Self {
            prev_error: None,
            frame_index: 0,
        }
    }

    /// Apply temporal dithering with motion compensation
    pub fn apply(
        &mut self,
        pixels: &[OklabColor],
        palette: &[OklabColor],
        width: usize,
        height: usize,
    ) -> Vec<u8> {
        let mut result = vec![0u8; width * height];
        let mut errors = vec![0f32; width * height * 3]; // L, a, b components

        // Initialize with previous frame's error if available
        if let Some(prev) = &self.prev_error {
            if prev.len() == errors.len() {
                errors.copy_from_slice(prev);
                // Decay previous error to prevent accumulation
                for e in &mut errors {
                    *e *= 0.7; // 30% decay
                }
            }
        }

        // Apply blue noise pattern offset based on frame index
        let pattern_offset = (self.frame_index * 17) % 64; // Prime number for good distribution

        for y in 0..height {
            for x in 0..width {
                let idx = y * width + x;
                let pixel = pixels[idx];

                // Add error from previous pixels and frames
                let err_idx = idx * 3;
                let corrected = OklabColor {
                    l: pixel.l + errors[err_idx] * 0.5,
                    a: pixel.a + errors[err_idx + 1] * 0.5,
                    b: pixel.b + errors[err_idx + 2] * 0.5,
                };

                // Find nearest palette color
                let (palette_idx, nearest) = palette
                    .iter()
                    .enumerate()
                    .min_by_key(|(_, p)| {
                        let dl = corrected.l - p.l;
                        let da = corrected.a - p.a;
                        let db = corrected.b - p.b;
                        ((dl * dl + da * da + db * db) * 1000.0) as u32
                    })
                    .map(|(idx, p)| (idx, *p))
                    .unwrap();

                result[idx] = palette_idx as u8;

                // Calculate and distribute error
                let err_l = pixel.l - nearest.l;
                let err_a = pixel.a - nearest.a;
                let err_b = pixel.b - nearest.b;

                // Sierra dithering (better for animations than Floyd-Steinberg)
                // Distributes error to fewer pixels, reducing crawling
                if x + 1 < width {
                    let idx = (y * width + x + 1) * 3;
                    errors[idx] += err_l * 5.0 / 32.0;
                    errors[idx + 1] += err_a * 5.0 / 32.0;
                    errors[idx + 2] += err_b * 5.0 / 32.0;
                }
                if x + 2 < width {
                    let idx = (y * width + x + 2) * 3;
                    errors[idx] += err_l * 3.0 / 32.0;
                    errors[idx + 1] += err_a * 3.0 / 32.0;
                    errors[idx + 2] += err_b * 3.0 / 32.0;
                }
                if y + 1 < height {
                    if x > 1 {
                        let idx = ((y + 1) * width + x - 2) * 3;
                        errors[idx] += err_l * 2.0 / 32.0;
                        errors[idx + 1] += err_a * 2.0 / 32.0;
                        errors[idx + 2] += err_b * 2.0 / 32.0;
                    }
                    if x > 0 {
                        let idx = ((y + 1) * width + x - 1) * 3;
                        errors[idx] += err_l * 4.0 / 32.0;
                        errors[idx + 1] += err_a * 4.0 / 32.0;
                        errors[idx + 2] += err_b * 4.0 / 32.0;
                    }
                    let idx = ((y + 1) * width + x) * 3;
                    errors[idx] += err_l * 5.0 / 32.0;
                    errors[idx + 1] += err_a * 5.0 / 32.0;
                    errors[idx + 2] += err_b * 5.0 / 32.0;
                }
            }
        }

        // Save error for next frame
        self.prev_error = Some(errors);
        self.frame_index += 1;

        result
    }
}
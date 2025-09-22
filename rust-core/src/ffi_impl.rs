// FFI implementation module
// Bridges between the public API types and internal implementation

use crate::{ProcessorOptions, QuantizeOpts, GifOpts, TensorShape, QuantizeResult, RGBAColor, ProcessorError};
use crate::quantization::{
    quantize_frame, quantize_batch,
    QuantizeOptions as InternalQuantizeOptions,
    QuantizeResult as InternalQuantizeResult
};
use crate::gif_encoder::{encode_gif as internal_encode_gif, GifOptions as InternalGifOptions};
use crate::tensor::{build_tensor, TensorShape as InternalTensorShape};

// Conversion helpers
impl From<QuantizeOpts> for InternalQuantizeOptions {
    fn from(opts: QuantizeOpts) -> Self {
        InternalQuantizeOptions {
            quality_min: opts.quality_min,
            quality_max: opts.quality_max,
            speed: opts.speed,
            palette_size: opts.palette_size,
            dithering_level: opts.dithering_level,
        }
    }
}

impl From<GifOpts> for InternalGifOptions {
    fn from(opts: GifOpts) -> Self {
        InternalGifOptions {
            width: opts.width,
            height: opts.height,
            frame_count: opts.frame_count,
            fps: opts.fps,
            loop_count: opts.loop_count,
            optimize: opts.optimize,
        }
    }
}

impl From<TensorShape> for InternalTensorShape {
    fn from(shape: TensorShape) -> Self {
        InternalTensorShape::new(shape.width, shape.height, shape.frames)
    }
}

impl From<InternalQuantizeResult> for QuantizeResult {
    fn from(result: InternalQuantizeResult) -> Self {
        QuantizeResult {
            indices: result.indices,
            palette: result.palette.into_iter().map(|c| RGBAColor {
                r: (c >> 24) as u8,
                g: (c >> 16) as u8,
                b: (c >> 8) as u8,
                a: c as u8,
            }).collect(),
            width: result.width,
            height: result.height,
            frame_count: 1,
        }
    }
}

// Implementation functions
pub fn process_frames_to_gif_impl(
    frames_rgba: Vec<u8>,
    width: u32,
    height: u32,
    frame_count: u32,
    options: ProcessorOptions,
) -> Result<Vec<u8>, ProcessorError> {
    // Validate input
    let expected_size = (width * height * 4 * frame_count) as usize;
    if frames_rgba.len() != expected_size {
        return Err(ProcessorError::InvalidInput("Size mismatch".into()));
    }

    // Split frames
    let frame_size = (width * height * 4) as usize;
    let frames: Vec<Vec<u8>> = frames_rgba
        .chunks(frame_size)
        .map(|chunk| chunk.to_vec())
        .collect();

    // Quantize
    let shared_palette = options.quantize.shared_palette;
    let internal_opts = options.quantize.into();
    let quantized = if options.parallel {
        quantize_batch(frames, width, height, &internal_opts, shared_palette)
            .map_err(|e| ProcessorError::QuantizationError(e.to_string()))?
    } else {
        let mut results = Vec::new();
        for frame in frames {
            let result = quantize_frame(&frame, width, height, &internal_opts)
                .map_err(|e| ProcessorError::QuantizationError(e.to_string()))?;
            results.push(result);
        }
        results
    };

    // Encode to GIF
    let gif_opts = options.gif.into();
    internal_encode_gif(quantized, &gif_opts)
        .map_err(|e| ProcessorError::EncodingError(e.to_string()))
}

pub fn quantize_frames_impl(
    frames_rgba: Vec<u8>,
    width: u32,
    height: u32,
    frame_count: u32,
    options: QuantizeOpts,
) -> Result<QuantizeResult, ProcessorError> {
    // For simplicity, quantize just the first frame for now
    let frame_size = (width * height * 4) as usize;
    if frames_rgba.len() < frame_size {
        return Err(ProcessorError::InvalidInput("Not enough data".into()));
    }

    let first_frame = &frames_rgba[0..frame_size];
    let internal_opts = options.into();

    let result = quantize_frame(first_frame, width, height, &internal_opts)
        .map_err(|e| ProcessorError::QuantizationError(e.to_string()))?;

    let mut q_result: QuantizeResult = result.into();
    q_result.frame_count = frame_count;
    Ok(q_result)
}

pub fn encode_quantized_gif_impl(
    quantized: QuantizeResult,
    options: GifOpts,
) -> Result<Vec<u8>, ProcessorError> {
    // Convert back to internal format
    let internal_results = vec![InternalQuantizeResult {
        indices: quantized.indices,
        palette: quantized.palette.into_iter().map(|c| {
            ((c.r as u32) << 24) | ((c.g as u32) << 16) | ((c.b as u32) << 8) | (c.a as u32)
        }).collect(),
        width: quantized.width,
        height: quantized.height,
    }];

    let gif_opts = options.into();
    internal_encode_gif(internal_results, &gif_opts)
        .map_err(|e| ProcessorError::EncodingError(e.to_string()))
}

pub fn build_cube_tensor_impl(
    frames_rgba: Vec<u8>,
    shape: TensorShape,
) -> Result<Vec<u8>, ProcessorError> {
    let internal_shape = shape.into();
    build_tensor(&frames_rgba, internal_shape)
        .map_err(|e| ProcessorError::TensorError(e.to_string()))
}

// Processor implementation for stateful operations
pub struct ProcessorImpl {
    quality_min: u8,
    quality_max: u8,
    speed: i32,
}

impl ProcessorImpl {
    pub fn new() -> Self {
        Self {
            quality_min: 70,
            quality_max: 100,
            speed: 5,
        }
    }

    pub fn set_quality(&mut self, min_quality: u8, max_quality: u8) -> Result<(), ProcessorError> {
        if min_quality > max_quality || max_quality > 100 {
            return Err(ProcessorError::InvalidInput("Invalid quality range".into()));
        }
        self.quality_min = min_quality;
        self.quality_max = max_quality;
        Ok(())
    }

    pub fn set_speed(&mut self, speed: i32) -> Result<(), ProcessorError> {
        if speed < 1 || speed > 10 {
            return Err(ProcessorError::InvalidInput("Speed must be 1-10".into()));
        }
        self.speed = speed;
        Ok(())
    }

    pub fn quantize_batch(
        &self,
        frames_rgba: Vec<u8>,
        width: u32,
        height: u32,
        frame_count: u32,
    ) -> Result<QuantizeResult, ProcessorError> {
        let options = QuantizeOpts {
            quality_min: self.quality_min,
            quality_max: self.quality_max,
            speed: self.speed,
            palette_size: 256,
            dithering_level: 1.0,
            shared_palette: true,
        };
        quantize_frames_impl(frames_rgba, width, height, frame_count, options)
    }

    pub fn encode_gif(&self, quantized: QuantizeResult, fps: u16) -> Result<Vec<u8>, ProcessorError> {
        let options = GifOpts {
            width: quantized.width as u16,
            height: quantized.height as u16,
            frame_count: quantized.frame_count as u16,
            fps,
            loop_count: 0,
            optimize: true,
        };
        encode_quantized_gif_impl(quantized, options)
    }

    pub fn process_complete(
        &self,
        frames_rgba: Vec<u8>,
        width: u32,
        height: u32,
        frame_count: u32,
        fps: u16,
    ) -> Result<Vec<u8>, ProcessorError> {
        let options = ProcessorOptions {
            quantize: QuantizeOpts {
                quality_min: self.quality_min,
                quality_max: self.quality_max,
                speed: self.speed,
                palette_size: 256,
                dithering_level: 1.0,
                shared_palette: true,
            },
            gif: GifOpts {
                width: width as u16,
                height: height as u16,
                frame_count: frame_count as u16,
                fps,
                loop_count: 0,
                optimize: true,
            },
            parallel: true,
        };
        process_frames_to_gif_impl(frames_rgba, width, height, frame_count, options)
    }
}
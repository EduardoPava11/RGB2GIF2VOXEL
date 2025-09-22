// Parallel processing utilities using Rayon
// Provides work-stealing parallelism for frame and row processing

use rayon::prelude::*;

/// Process frames in parallel with configurable chunk size
pub fn process_frames_parallel<T, F, R>(
    frames: Vec<T>,
    processor: F,
) -> Vec<R>
where
    T: Send + Sync,
    F: Fn(&T) -> R + Send + Sync,
    R: Send,
{
    frames.par_iter().map(processor).collect()
}

/// Process frames in parallel with mutable access
pub fn process_frames_parallel_mut<T, F>(
    frames: &mut [T],
    processor: F,
)
where
    T: Send + Sync,
    F: Fn(&mut T) + Send + Sync,
{
    frames.par_iter_mut().for_each(processor);
}

/// Process with chunking for cache locality
pub fn process_chunks_parallel<T, F, R>(
    data: &[T],
    chunk_size: usize,
    processor: F,
) -> Vec<R>
where
    T: Sync,
    F: Fn(&[T]) -> R + Send + Sync,
    R: Send,
{
    data.par_chunks(chunk_size)
        .map(processor)
        .collect()
}

/// Process rows of an image in parallel
pub fn process_rows_parallel<F>(
    image_data: &mut [u8],
    width: usize,
    height: usize,
    channels: usize,
    processor: F,
)
where
    F: Fn(&mut [u8], usize) + Send + Sync, // row_data, row_index
{
    let row_stride = width * channels;

    image_data
        .par_chunks_mut(row_stride)
        .enumerate()
        .for_each(|(row_idx, row_data)| {
            if row_idx < height {
                processor(row_data, row_idx);
            }
        });
}

/// Parallel map with index
pub fn parallel_map_indexed<T, F, R>(
    items: Vec<T>,
    processor: F,
) -> Vec<R>
where
    T: Send + Sync,
    F: Fn(usize, T) -> R + Send + Sync,
    R: Send,
{
    items
        .into_par_iter()
        .enumerate()
        .map(|(idx, item)| processor(idx, item))
        .collect()
}

/// Parallel reduction with custom combiner
pub fn parallel_reduce<T, F, R>(
    items: Vec<T>,
    identity: R,
    mapper: F,
    reducer: fn(R, R) -> R,
) -> R
where
    T: Send + Sync,
    F: Fn(T) -> R + Send + Sync,
    R: Send + Clone + Sync,
{
    items
        .into_par_iter()
        .map(mapper)
        .reduce(|| identity.clone(), reducer)
}

/// Process with thread pool size control
pub fn process_with_threads<T, F, R>(
    items: Vec<T>,
    num_threads: usize,
    processor: F,
) -> Vec<R>
where
    T: Send + Sync,
    F: Fn(&T) -> R + Send + Sync,
    R: Send,
{
    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(num_threads)
        .build()
        .unwrap();

    pool.install(|| {
        items.par_iter().map(processor).collect()
    })
}

/// Parallel pipeline with multiple stages
pub fn parallel_pipeline<T1, T2, T3, F1, F2>(
    input: Vec<T1>,
    stage1: F1,
    stage2: F2,
) -> Vec<T3>
where
    T1: Send + Sync,
    T2: Send + Sync,
    T3: Send,
    F1: Fn(T1) -> T2 + Send + Sync,
    F2: Fn(T2) -> T3 + Send + Sync,
{
    input
        .into_par_iter()
        .map(stage1)
        .map(stage2)
        .collect()
}

/// Batch processing with size control
pub struct BatchProcessor {
    batch_size: usize,
    max_parallel: usize,
}

impl BatchProcessor {
    pub fn new(batch_size: usize, max_parallel: usize) -> Self {
        Self {
            batch_size,
            max_parallel,
        }
    }

    pub fn process<T, F, R>(&self, items: Vec<T>, processor: F) -> Vec<R>
    where
        T: Send + Sync,
        F: Fn(&[T]) -> Vec<R> + Send + Sync,
        R: Send,
    {
        items
            .chunks(self.batch_size)
            .collect::<Vec<_>>()
            .into_par_iter()
            .with_max_len(self.max_parallel)
            .flat_map(|batch| processor(batch))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parallel_map() {
        let items = vec![1, 2, 3, 4, 5];
        let results = process_frames_parallel(items, |&x| x * 2);
        assert_eq!(results, vec![2, 4, 6, 8, 10]);
    }

    #[test]
    fn test_parallel_chunks() {
        let data = vec![1, 2, 3, 4, 5, 6, 7, 8];
        let results = process_chunks_parallel(&data, 2, |chunk| chunk.iter().sum::<i32>());
        assert_eq!(results, vec![3, 7, 11, 15]);
    }

    #[test]
    fn test_parallel_rows() {
        let mut image = vec![0u8; 4 * 4 * 4]; // 4x4 RGBA image
        process_rows_parallel(&mut image, 4, 4, 4, |row, idx| {
            for pixel in row.chunks_mut(4) {
                pixel[0] = idx as u8; // Set red to row index
            }
        });

        // Check that each row has correct red value
        for y in 0..4 {
            let row_start = y * 4 * 4;
            assert_eq!(image[row_start], y as u8);
        }
    }

    #[test]
    fn test_batch_processor() {
        let processor = BatchProcessor::new(3, 2);
        let items: Vec<i32> = (0..10).collect();

        let results = processor.process(items, |batch| {
            batch.iter().map(|x| x * 2).collect()
        });

        let expected: Vec<i32> = (0..10).map(|x| x * 2).collect();
        assert_eq!(results, expected);
    }
}
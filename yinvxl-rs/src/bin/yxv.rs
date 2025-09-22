// YXV CLI Tool
// Command-line utility for working with YinVoxel files

use clap::{Parser, Subcommand};
use anyhow::Result;
use yinvxl::{YxvContainer, Compression};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "yxv")]
#[command(about = "YinVoxel (YXV) format tool", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Pack raw voxel data into YXV format
    Pack {
        /// Input file (raw voxel data)
        #[arg(short, long)]
        input: PathBuf,

        /// Output YXV file
        #[arg(short, long)]
        output: PathBuf,

        /// Width dimension
        #[arg(short = 'W', long)]
        width: u32,

        /// Height dimension
        #[arg(short = 'H', long)]
        height: u32,

        /// Depth dimension (number of frames)
        #[arg(short = 'D', long)]
        depth: u32,

        /// Compression type (none, lz4, lzfse, zstd)
        #[arg(short, long, default_value = "lz4")]
        compression: String,

        /// Palette file (768 bytes RGB)
        #[arg(short, long)]
        palette: Option<PathBuf>,
    },

    /// Unpack YXV file to raw voxel data
    Unpack {
        /// Input YXV file
        #[arg(short, long)]
        input: PathBuf,

        /// Output directory for frames
        #[arg(short, long)]
        output: PathBuf,
    },

    /// Display information about YXV file
    Info {
        /// Input YXV file
        input: PathBuf,
    },

    /// Validate YXV file integrity
    Validate {
        /// Input YXV file
        input: PathBuf,

        /// Verify checksums
        #[arg(short, long)]
        verify: bool,
    },

    /// Extract a single frame from YXV
    Extract {
        /// Input YXV file
        #[arg(short, long)]
        input: PathBuf,

        /// Frame index to extract
        #[arg(short, long)]
        frame: usize,

        /// Output file
        #[arg(short, long)]
        output: PathBuf,
    },

    /// Convert YXV to animated GIF
    #[cfg(feature = "gif")]
    ToGif {
        /// Input YXV file
        #[arg(short, long)]
        input: PathBuf,

        /// Output GIF file
        #[arg(short, long)]
        output: PathBuf,

        /// Frame delay in milliseconds
        #[arg(short, long, default_value = "40")]
        delay: u16,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Pack {
            input,
            output,
            width,
            height,
            depth,
            compression,
            palette,
        } => {
            println!("Packing voxel data to YXV...");

            // Read raw voxel data
            let voxel_data = std::fs::read(&input)?;

            // Parse compression type
            let comp = match compression.as_str() {
                "none" => Compression::None,
                "lz4" => Compression::Lz4,
                "lzfse" => Compression::Lzfse,
                "zstd" => Compression::Zstd,
                _ => {
                    eprintln!("Invalid compression type: {}", compression);
                    std::process::exit(1);
                }
            };

            // Create container
            let mut container = YxvContainer::new((width, height, depth));
            container.compression = comp;

            // Load palette if provided
            if let Some(palette_path) = palette {
                let palette_data = std::fs::read(&palette_path)?;
                for chunk in palette_data.chunks_exact(3) {
                    container.palette.push([chunk[0], chunk[1], chunk[2]]);
                }
            }

            // Split voxel data into frames
            let frame_size = (width * height) as usize;
            for chunk in voxel_data.chunks_exact(frame_size) {
                container.frames.push(chunk.to_vec());
            }

            // Write to file
            container.write_to_file(&output)?;

            println!("✅ Created YXV file: {}", output.display());
            println!("   Dimensions: {}×{}×{}", width, height, depth);
            println!("   Compression: {}", compression);
            println!("   Palette colors: {}", container.palette.len());
            println!("   Frames: {}", container.frames.len());
        }

        Commands::Unpack { input, output } => {
            println!("Unpacking YXV file...");

            let container = YxvContainer::read_from_file(&input)?;

            // Create output directory
            std::fs::create_dir_all(&output)?;

            // Write palette
            if !container.palette.is_empty() {
                let palette_path = output.join("palette.rgb");
                let mut palette_data = Vec::new();
                for color in &container.palette {
                    palette_data.extend_from_slice(color);
                }
                std::fs::write(&palette_path, &palette_data)?;
                println!("   Palette saved to: {}", palette_path.display());
            }

            // Write frames
            for (i, frame) in container.frames.iter().enumerate() {
                let frame_path = output.join(format!("frame_{:03}.raw", i));
                std::fs::write(&frame_path, frame)?;
            }

            println!("✅ Unpacked {} frames to: {}", container.frames.len(), output.display());
        }

        Commands::Info { input } => {
            println!("YXV File Information:");
            println!("   Path: {}", input.display());

            let metadata = std::fs::metadata(&input)?;
            println!("   File size: {} bytes", metadata.len());

            let container = YxvContainer::read_from_file(&input)?;
            println!("   Dimensions: {}×{}×{}",
                container.dimensions.0,
                container.dimensions.1,
                container.dimensions.2
            );
            println!("   Compression: {:?}", container.compression);
            println!("   Palette colors: {}", container.palette.len());
            println!("   Frames: {}", container.frames.len());

            let voxel_count = container.dimensions.0 *
                              container.dimensions.1 *
                              container.dimensions.2;
            println!("   Total voxels: {}", voxel_count);
        }

        Commands::Validate { input, verify } => {
            println!("Validating YXV file...");

            match YxvContainer::read_from_file(&input) {
                Ok(container) => {
                    println!("✅ File structure is valid");

                    if verify {
                        // TODO: Verify chunk checksums
                        println!("   Checksum verification: TODO");
                    }

                    println!("   Frames: {}", container.frames.len());
                    println!("   Expected: {}", container.dimensions.2);

                    if container.frames.len() == container.dimensions.2 as usize {
                        println!("✅ Frame count matches dimensions");
                    } else {
                        println!("⚠️  Frame count mismatch!");
                    }
                }
                Err(e) => {
                    println!("❌ Validation failed: {}", e);
                    std::process::exit(1);
                }
            }
        }

        Commands::Extract { input, frame, output } => {
            println!("Extracting frame {} from YXV...", frame);

            let container = YxvContainer::read_from_file(&input)?;

            if frame >= container.frames.len() {
                eprintln!("Frame index {} out of range (0-{})",
                    frame, container.frames.len() - 1);
                std::process::exit(1);
            }

            std::fs::write(&output, &container.frames[frame])?;
            println!("✅ Frame saved to: {}", output.display());
        }

        #[cfg(feature = "gif")]
        Commands::ToGif { input, output, delay } => {
            println!("Converting YXV to GIF...");
            // TODO: Implement GIF conversion
            println!("GIF conversion not yet implemented");
        }
    }

    Ok(())
}
# RGB2GIF2VOXEL

## The Spiritual Successor to Our Android App

This iOS application represents the evolution of our original Android RGB-to-GIF converter. By transitioning to Apple's stable hardware ecosystem, we've achieved significantly improved stability, performance consistency, and user experience.

### Why iOS: The Power of Stable Hardware

Unlike the fragmented Android ecosystem with thousands of device configurations, iOS development benefits from:
- **Consistent Camera APIs**: Uniform AVFoundation implementation across all devices
- **Predictable Performance**: Known hardware profiles enable optimal optimization
- **Unified Memory Management**: ARC and consistent memory limits simplify resource handling
- **Stable Color Pipeline**: Consistent BGRA format across all iOS devices

This hardware stability translates directly into app stability - fewer edge cases, more predictable behavior, and a smoother user experience.

## Features

- **256-Frame Capture**: Records exactly 256 frames at 1080x1080 resolution
- **Dual Processing Paths**: Choose between Swift (ImageIO) or Rust (NeuQuant) GIF encoding
- **Real-time Preview**: Live square preview showing exact capture area
- **Hardware Acceleration**: vImage framework for efficient downsampling
- **Professional Logging**: os.Logger and OSSignposter integration for Instruments profiling

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   iOS App (Swift)                   │
├─────────────────────────────────────────────────────┤
│  Camera Layer   │  Processing     │  UI Layer       │
│  ├ AVFoundation │  ├ Swift/ImageIO│  ├ SwiftUI      │
│  └ Preview      │  └ Rust/FFI     │  └ Combine      │
├─────────────────────────────────────────────────────┤
│                 Rust Core (via UniFFI)              │
│  NeuQuant quantization | GIF89a encoding            │
└─────────────────────────────────────────────────────┘
```

## Quick Start

1. Open `RGB2GIF2VOXEL.xcodeproj` in Xcode
2. Select your iOS device or simulator
3. Build and run (⌘R)
4. Grant camera and photo library permissions
5. Tap capture to record 256 frames
6. Choose Swift or Rust processing
7. GIF saves automatically to Photos

## Technical Highlights

### Camera Pipeline
- AVCaptureVideoDataOutput with BGRA pixel format
- Real-time square cropping to 1080x1080
- Efficient frame extraction using memcpy
- 87% capture optimization preventing stalls

### Processing Options
- **Swift Path**: Native ImageIO with CGImageDestination
- **Rust Path**: High-performance NeuQuant color quantization
- Both paths properly handle BGRA→RGBA conversion

### Robust Saving
- PHAssetCreationRequest with proper GIF metadata
- UTType.gif.identifier preservation
- Automatic Photos app integration

## Requirements

- iOS 17.0+
- Xcode 16.0+
- iPhone with camera
- 100MB free storage for processing

## License

MIT License - See LICENSE file for details

## Acknowledgments

Built on the lessons learned from our Android implementation, this iOS version demonstrates how stable hardware platforms enable more reliable software experiences.
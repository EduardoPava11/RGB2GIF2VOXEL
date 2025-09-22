# RGB2GIF2VOXEL Documentation

## Build Instructions

### Prerequisites
- Xcode 16.0+
- iOS 17.0+ SDK
- Rust toolchain (for rebuilding FFI)
- Swift 5.9+

### Building the App

1. **Open Project**
   ```bash
   open RGB2GIF2VOXEL.xcodeproj
   ```

2. **Select Target**
   - Choose your iOS device or simulator
   - Ensure "RGB2GIF2VOXEL" scheme is selected

3. **Build and Run**
   - Press ⌘B to build
   - Press ⌘R to run

### Rust FFI Rebuild (Optional)

```bash
cd rust-core
cargo build --release
./build-xcframework.sh
```

## Architecture

### Module Structure

#### Camera Module
- `ImprovedCameraManager.swift`: AVFoundation session management
- `CameraPreviewView.swift`: UIKit preview layer with square cropping
- Frame extraction optimized with memcpy for performance

#### Processing Module
- `SingleFFIPipelineImproved.swift`: Main pipeline orchestrator
- `VImageProcessor.swift`: Hardware-accelerated downsampling
- `CBORFrameEncoder.swift`: Frame serialization

#### UI Module
- `SimplifiedCameraView.swift`: Main capture interface
- `ContentView.swift`: App entry point
- Real-time progress indicators and user feedback

#### Services Module
- `PhotosGIFSaver.swift`: Robust Photos app integration
- `SwiftGIF89aEncoder.swift`: Native Swift GIF encoding
- Rust FFI bridge for NeuQuant processing

### Data Flow

1. **Capture**: Camera → BGRA frames (1080x1080)
2. **Downsample**: vImage → 256x256 frames
3. **Process**: Swift/Rust → GIF data
4. **Save**: PHPhotoLibrary → Photos app

## Performance Optimizations

### Memory Management
- Pre-allocated buffers for frame data
- Concurrent processing with TaskGroup
- Automatic memory pressure handling

### Frame Capture
- Optimized from O(n²) to O(n) with memcpy
- Fixed 87% stall with timeout mechanism
- Efficient BGRA→RGBA conversion

### GIF Encoding
- ImageIO for quality (Swift path)
- NeuQuant for speed (Rust path)
- Proper color channel handling

## Logging and Debugging

### os.Logger Categories
- `Log.app`: Application lifecycle
- `Log.camera`: Camera operations
- `Log.pipeline`: Processing pipeline
- `Log.ffi`: Rust FFI calls
- `Log.photos`: Photos saving

### Instruments Integration
OSSignposter points of interest:
- `fullPipeline`: End-to-end timing
- `capture`: Frame capture duration
- `downsample`: Image processing time
- `rustFFI`: Native processing time
- `savePhotos`: Photos integration time

## Troubleshooting

### Common Issues

#### Black Preview
- Ensure camera permissions granted
- Check AVCaptureSession is running
- Verify preview layer frame updates

#### Capture Stalls at 87%
- Fixed in current version
- Timeout mechanism prevents infinite wait
- Fallback to 200+ frames if needed

#### GIF Color Issues
- BGRA→RGBA conversion implemented
- Proper pixel format handling
- Orientation set to portrait

#### GIF Not Appearing in Photos
- Check photo library permissions
- Verify PHAssetCreationRequest success
- Ensure UTType.gif metadata preserved

## Testing

### Unit Tests
- Frame processing accuracy
- Color conversion correctness
- Memory leak detection

### Integration Tests
- End-to-end pipeline validation
- Photos app integration
- Permission handling

### Performance Tests
- Frame capture timing
- Processing benchmarks
- Memory usage profiling

## API Reference

### Key Classes

#### ImprovedCameraManager
```swift
@MainActor
class ImprovedCameraManager: NSObject, ObservableObject {
    func setupSession() async throws
    func startCapture() async throws -> [Data]
}
```

#### SingleFFIPipelineImproved
```swift
@MainActor
class SingleFFIPipelineImproved: ObservableObject {
    func runPipeline() async
    func selectSwiftPath() async throws -> Data
    func selectRustPath() async throws -> Data
}
```

#### PhotosGIFSaver
```swift
class PhotosGIFSaver {
    static func saveGIF(_ gifData: Data) async throws -> PHAsset
}
```
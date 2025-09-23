# 🏗️ RGB2GIF2VOXEL Architecture Plan

## Executive Summary

Transform the app into a **Metal-accelerated, N=128 optimized GIF-to-voxel renderer** with:
- **Metal 3D textures** for GPU-accelerated voxel rendering
- **N=128 spatiotemporal blue-noise (STBN) dithering** with Van Gogh style
- **Ray-marching and point cloud dual renderers**
- **Wu quantization** with perceptual metrics (ΔE2000, SSIM)

## 🎯 Core Architecture Components

### 1. Metal Shader Pipeline (Phase 1)

#### 1.1 Volume Representation
```swift
// GifVolumeLoader.swift
struct Volume3D {
    let texture: MTLTexture       // type3D, 256×256×256 RGBA8
    let size: SIMD3<UInt32>      // (256, 256, 256)
    let frameDurations: [Float]   // Per-frame timing
}
```

**Specifications:**
- **3D Texture**: `MTLTextureType.type3D`, 256×256×256×4 = 67,108,864 bytes
- **Pixel Format**: `.rgba8Unorm` for direct sampling
- **Fallback**: `.type2DArray` with 256 layers if memory constrained

#### 1.2 Ray-Marching Renderer
```metal
// VolumeRenderer.metal
fragment float4 rayMarchFragment(RasterizerData in [[stage_in]],
                                 texture3d<float> volume [[texture(0)]],
                                 constant Uniforms &uniforms [[buffer(0)]]) {
    float3 ro = uniforms.cameraOrigin;
    float3 rd = normalize(rayDirectionFromScreen(in.uv));

    float4 acc = float4(0);
    for (float t = t0; t < t1 && acc.a < 0.98; t += uniforms.stepSize) {
        float3 p = ro + t * rd;
        float4 c = volume.sample(samplerLinear, p);

        // Van Gogh style: enhance complementary colors
        float density = mixMax(c.rgb) * uniforms.styleWeight;
        float a = density * uniforms.alphaGain;

        acc.rgb += (1 - acc.a) * c.rgb * a;
        acc.a   += (1 - acc.a) * a;
    }
    return acc;
}
```

#### 1.3 Point Cloud Renderer (SceneKit)
```swift
// VoxelPointRenderer.swift
func createPointCloud(from volume: Volume3D) -> SCNGeometry {
    let element = SCNGeometryElement(...)
    element.primitiveType = .point
    element.pointSize = 6.0
    element.minimumPointScreenSpaceRadius = 2.0
    element.maximumPointScreenSpaceRadius = 10.0
    // Apply N=128 stride for performance
}
```

### 2. N=128 Optimization System (Phase 2)

#### 2.1 Mathematical Foundation
Based on your Haskell verification:
```haskell
-- N=128 is OPTIMAL:
-- • Perfect 2^7 binary alignment
-- • Total loss J = 0.335 (excellent)
-- • 483-650 effective colors (1.9-2.5x multiplier)
-- • 40% perceptual error reduction
-- • 60-80% temporal flicker reduction
```

#### 2.2 STBN Dithering Service
```swift
// DitherService.swift
protocol DitherService {
    func renderSTBN(
        rgb: inout RGBImage,
        lab: LabImage,
        palette: PaletteRGB8,
        paletteLab: PaletteLab,
        frameIndex t: Int,
        styleWeight γ: Float  // Van Gogh weight: 0.2 optimal
    )
}

// Implementation using precomputed 128×128×8 STBN mask
class STBNDitherer: DitherService {
    private let mask: Data  // 128×128×8 = 131,072 bytes

    func applyMask(x: Int, y: Int, t: Int) -> Float {
        let idx = (x & 127) + ((y & 127) << 7) + ((t & 7) << 14)
        return Float(mask[idx]) / 255.0 - 0.5
    }
}
```

#### 2.3 Wu Palette Quantization
```swift
// PaletteService.swift
protocol PaletteService {
    func makeGlobal(from labs: [LabImage]) -> PaletteRGB8
    func makeLocal(from lab: LabImage) -> PaletteRGB8
    func makeSliding(all: [LabImage], at t: Int, k: Int) -> PaletteRGB8
}

class WuQuantizer: PaletteService {
    // Wu's variance-minimization for K≤256
    // O(K²N) complexity, produces optimal palette
}
```

#### 2.4 Quality Metrics
```swift
// QualityMeter.swift
class PerceptualMetrics {
    // Combined objective function:
    // J = α·ΔE₀₀ + (1-α)·(1-SSIM) + β·Φ_temporal - γ·Ψ_style

    func deltaE2000(orig: LabColor, rendered: LabColor) -> Float
    func ssim(orig: RGBImage, rendered: RGBImage) -> Float
    func temporalFlicker(prev: RGBImage?, curr: RGBImage, next: RGBImage?) -> Float
    func vanGoghStyle(image: RGBImage) -> Float  // Complementary adjacency score
}
```

### 3. Integration Points

#### 3.1 Data Flow
```
Camera → Capture (256 frames) → Downsample to N=128
    ↓
Wu Quantization → Palette (256 colors)
    ↓
STBN Dithering → Indexed frames
    ↓
GIF Encode → GIF89a file
    ↓
Tensor Build → 256×256×256×4 RGBA
    ↓
Metal Upload → MTLTexture type3D
    ↓
Shader Render → Ray-march or Point Cloud
```

#### 3.2 File Structure
```
RGB2GIF2VOXEL/
├── Metal/
│   ├── VolumeRenderer.metal          # Ray-marching shaders
│   ├── VolumeRendererView.swift      # MTKView integration
│   └── GifVolumeLoader.swift         # GIF→3D texture
├── Optimization/
│   ├── STBNDitherer.swift            # N=128 STBN dithering
│   ├── WuQuantizer.swift             # Palette optimization
│   ├── PerceptualMetrics.swift       # ΔE2000, SSIM
│   └── VanGoghStyler.swift           # Complementary colors
├── Assets/
│   └── stbn_mask_128x128x8.bin       # Precomputed STBN mask
└── UI/
    └── QualityControls.swift          # Sliders for γ, step size, etc.
```

### 4. Performance Targets

#### 4.1 N=128 Configuration
```swift
struct OptimalConfig {
    let resolution = 128           // Verified optimal
    let paletteSize = 256          // GIF89a max
    let stbnFrames = 8             // Temporal period
    let spatialSigma = 2.0         // Spatial blur
    let temporalSigma = 1.5        // Temporal blur
    let vanGoghGamma = 0.2         // Style weight
}
```

#### 4.2 Expected Results
- **File Size**: ~2MB for typical sequences
- **Effective Colors**: 550-650 (2.5x perceived)
- **Quality Loss J**: 0.335 (excellent)
- **Frame Rate**: 60 FPS ray-march, 120 FPS point cloud
- **Memory**: ~70MB for 3D texture + ~200MB working

### 5. Implementation Phases

#### Phase 1: Metal Foundation (Week 1)
- [ ] Create `GifVolumeLoader` with ImageIO
- [ ] Implement `VolumeRenderer.metal` ray-marcher
- [ ] Build `MTKView` integration
- [ ] Add point cloud fallback

#### Phase 2: N=128 Optimization (Week 2)
- [ ] Port STBN mask generator or use precomputed
- [ ] Implement Wu quantizer in Swift/Metal
- [ ] Add Van Gogh style enhancement
- [ ] Create quality metrics

#### Phase 3: Integration (Week 3)
- [ ] Wire into existing camera pipeline
- [ ] Add UI controls for parameters
- [ ] Implement OSSignposter instrumentation
- [ ] Run ablation studies

#### Phase 4: Polish (Week 4)
- [ ] Optimize Metal shaders
- [ ] Add WebView MP4 fallback
- [ ] Document tensor format
- [ ] Performance profiling

### 6. Ablation Test Matrix

| N    | Palette Mode | Dithering | γ    | Expected J | Size  |
|------|-------------|-----------|------|------------|-------|
| 96   | Global      | BN        | 0.0  | 0.52       | 1.2MB |
| 96   | Sliding±2   | STBN-8    | 0.2  | 0.45       | 1.4MB |
| 128  | Global      | BN        | 0.0  | 0.42       | 1.8MB |
| **128** | **Sliding±2** | **STBN-8** | **0.2** | **0.335** | **2.0MB** |
| 128  | Local       | STBN-16   | 0.5  | 0.28       | 2.5MB |
| 144  | Sliding±2   | STBN-16   | 0.2  | 0.31       | 2.8MB |

### 7. Key Algorithms

#### 7.1 STBN Mask Application
```swift
let m = stbnMask[(x & 127) + ((y & 127) << 7) + ((t & 7) << 14)]
let jitter = (m - 0.5) * ditherAmplitude  // 1-2 L* units
let adjusted = rgbToLab(pixel) + jitterAlongLightness
let idx = nearestPaletteIndex(adjustedLab, paletteLab)
out[x,y] = palette[idx]
```

#### 7.2 Van Gogh Style (Complementary Adjacency)
```swift
// Find nearest color c1 and complement c2
// Score: -α*ΔE00 + γ*localComplementGain + η*phaseTerm(m,c)
if shouldUseComplement(c1, c2, localContext) {
    return c2  // Vibrant complement
} else {
    return c1  // Standard nearest
}
```

### 8. Quality Presets

```swift
enum QualityPreset {
    case quick     // N=96,  Global, BN,      γ=0.0
    case balanced  // N=128, Sliding, STBN-8,  γ=0.2 ← RECOMMENDED
    case high      // N=144, Sliding, STBN-16, γ=0.5
}
```

### 9. Success Metrics

✅ **Visual Quality**
- ΔE2000 < 5.0 average (imperceptible)
- SSIM > 0.85 (excellent structure)
- Temporal flicker < 0.1 (smooth)

✅ **Performance**
- 60+ FPS ray-marching
- < 100ms GIF encode
- < 50ms texture upload

✅ **File Size**
- 2MB ± 20% for 256 frames
- 550+ effective colors
- Smooth gradients

### 10. References

- **Metal 3D Textures**: [Apple Developer](https://developer.apple.com/documentation/metal/mtltexturetype/type3d)
- **STBN Theory**: NVIDIA/UCSD papers on spatiotemporal blue-noise
- **Wu Quantization**: Xiaolin Wu's color quantization algorithm
- **ΔE2000**: CIE Delta E 2000 color difference formula
- **Van Gogh Style**: Based on complementary color theory

---

## Next Steps

1. **Immediate**: Build `GifVolumeLoader` and basic Metal ray-marcher
2. **This Week**: Integrate N=128 STBN dithering
3. **Next Week**: Run ablation studies to verify J=0.335
4. **Ship**: Production presets with balanced N=128 default

The architecture is designed to slot directly into your existing pipeline while adding GPU-accelerated rendering and mathematically optimal N=128 processing.
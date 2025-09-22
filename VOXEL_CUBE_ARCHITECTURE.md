# Voxel Cube Architecture for RGB2GIF2VOXEL

## Overview

The voxel cube represents the GIF as a 3D volume where:
- **X-axis**: Horizontal pixel position (0-255)
- **Y-axis**: Vertical pixel position (0-255)
- **Z-axis**: Time/Frame index (0-255)

This creates a **256×256×256 voxel cube** where each voxel contains RGBA color data, visualizing the GIF as a temporal sculpture.

## Architecture Components

### 1. Data Pipeline

```
Camera Capture (256 frames @ 256×256)
    ↓
GIF89a Encoding (Rust)
    ↓
Tensor Generation (16×16×256 for preview)
    ↓
Voxel Cube Rendering (Metal/SceneKit)
    ↓
Interactive Visualization
```

### 2. Tensor Structure

The tensor is a downsampled version for efficient rendering:
- **Full resolution**: 256×256×256 = 16,777,216 voxels (too heavy)
- **Tensor resolution**: 16×16×256 = 65,536 voxels (manageable)
- **Data format**: RGBA bytes (4 bytes per voxel)
- **Total size**: 262KB for tensor vs 64MB for full resolution

### 3. Rendering Strategy

#### A. Level-of-Detail (LOD) System
```swift
enum VoxelLOD {
    case preview    // 16×16×256 (tensor)
    case medium     // 64×64×256
    case full       // 256×256×256 (on-demand)
}
```

#### B. Conveyor Belt Animation
- The Z-axis represents time
- Continuously scroll through Z layers
- Creates seamless loop matching GIF playback
- User can control speed and direction

#### C. Rendering Modes
1. **Solid Cube**: Opaque voxels with depth sorting
2. **Transparent Cloud**: Alpha-blended volumetric rendering
3. **Slice View**: Show individual Z-slices (frames)
4. **Cross-Section**: Cut through cube at any angle

## Implementation

### Swift/SceneKit Voxel Renderer

```swift
import SceneKit
import Metal
import MetalKit

class VoxelCubeRenderer: NSObject {

    // MARK: - Properties

    private let tensorData: Data
    private let dimensions = (x: 16, y: 16, z: 256)
    private var voxelNodes: [SCNNode] = []
    private var currentZOffset: Float = 0.0

    // MARK: - Initialization

    init(tensorData: Data) {
        self.tensorData = tensorData
        super.init()
    }

    // MARK: - Scene Setup

    func createVoxelScene() -> SCNScene {
        let scene = SCNScene()

        // Create voxel geometry
        let voxelGeometry = SCNBox(
            width: 1.0,
            height: 1.0,
            length: 1.0,
            chamferRadius: 0.0
        )

        // Parse tensor data
        var offset = 0
        for z in 0..<dimensions.z {
            for y in 0..<dimensions.y {
                for x in 0..<dimensions.x {
                    // Extract RGBA
                    let r = CGFloat(tensorData[offset]) / 255.0
                    let g = CGFloat(tensorData[offset + 1]) / 255.0
                    let b = CGFloat(tensorData[offset + 2]) / 255.0
                    let a = CGFloat(tensorData[offset + 3]) / 255.0
                    offset += 4

                    // Skip transparent voxels for performance
                    if a < 0.1 { continue }

                    // Create voxel node
                    let voxelNode = SCNNode(geometry: voxelGeometry.copy() as? SCNGeometry)
                    voxelNode.position = SCNVector3(
                        Float(x - dimensions.x/2),
                        Float(y - dimensions.y/2),
                        Float(z - dimensions.z/2)
                    )

                    // Set color
                    let material = SCNMaterial()
                    material.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: a)
                    material.transparency = a
                    voxelNode.geometry?.materials = [material]

                    scene.rootNode.addChildNode(voxelNode)
                    voxelNodes.append(voxelNode)
                }
            }
        }

        // Add lighting
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(0, 50, 50)
        scene.rootNode.addChildNode(lightNode)

        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 0.5
        scene.rootNode.addChildNode(ambientLight)

        return scene
    }

    // MARK: - Animation

    func animateConveyor(speed: Float = 1.0) {
        currentZOffset += speed

        // Loop animation
        if currentZOffset >= Float(dimensions.z) {
            currentZOffset -= Float(dimensions.z)
        }

        // Update voxel positions for conveyor effect
        for (index, node) in voxelNodes.enumerated() {
            let z = index / (dimensions.x * dimensions.y)
            let newZ = Float(z) + currentZOffset
            let wrappedZ = newZ.truncatingRemainder(dividingBy: Float(dimensions.z))

            node.position.z = wrappedZ - Float(dimensions.z/2)

            // Fade voxels at edges for smooth looping
            let edgeFade = min(wrappedZ / 10.0,
                              (Float(dimensions.z) - wrappedZ) / 10.0)
            node.opacity = CGFloat(min(1.0, edgeFade))
        }
    }
}
```

### Metal Compute Shader for Voxel Processing

```metal
#include <metal_stdlib>
using namespace metal;

struct VoxelData {
    packed_float4 color;  // RGBA
    float density;         // For volumetric rendering
};

kernel void processVoxels(
    device VoxelData* voxels [[ buffer(0) ]],
    constant float& time [[ buffer(1) ]],
    uint3 gid [[ thread_position_in_grid ]]
) {
    uint index = gid.z * 256 + gid.y * 16 + gid.x;

    // Apply temporal effects
    float phase = (float(gid.z) + time) / 256.0;
    phase = fract(phase); // Wrap around for looping

    // Modify voxel based on position in time
    VoxelData voxel = voxels[index];

    // Pulse effect based on Z position
    voxel.density = voxel.color.w * (0.5 + 0.5 * sin(phase * M_PI_F * 2.0));

    // Color shift for movement effect
    float3 rgb = voxel.color.rgb;
    float hueShift = phase * 0.1;

    // Simple HSV rotation
    float3 hsv = rgbToHsv(rgb);
    hsv.x = fract(hsv.x + hueShift);
    voxel.color.rgb = hsvToRgb(hsv);

    voxels[index] = voxel;
}
```

## UI/UX Design

### Interface Layout

```
┌─────────────────────────────────────┐
│         RGB2GIF2VOXEL               │
├─────────────────────────────────────┤
│                                     │
│     ┌───────────────────┐          │
│     │                   │          │
│     │   Voxel Cube     │          │
│     │   Visualization   │          │
│     │                   │          │
│     └───────────────────┘          │
│                                     │
│  ┌──────────────────────────┐      │
│  │ ▶ Play  ⏸ Pause  ⏹ Stop │      │
│  └──────────────────────────┘      │
│                                     │
│  Speed: [────●────────] 1.0x       │
│  Rotation: [──────●────] 45°       │
│  Opacity: [────────●──] 0.8        │
│                                     │
│  View Mode:                        │
│  ○ Solid ● Cloud ○ Slice ○ Cross   │
│                                     │
│  Z-Slice: [0 ────●──── 255]        │
│                                     │
│  [Export Voxel] [Share GIF]        │
└─────────────────────────────────────┘
```

### Interaction Gestures

1. **Pinch**: Zoom in/out
2. **Pan**: Rotate cube
3. **Swipe**: Scrub through Z-axis (time)
4. **Tap**: Toggle play/pause
5. **Long Press**: Show voxel info
6. **Double Tap**: Reset view

## Performance Optimization

### 1. Instanced Rendering
Use Metal instancing to render all voxels in a single draw call:

```swift
// Metal instance buffer
struct VoxelInstance {
    var position: simd_float3
    var color: simd_float4
    var scale: Float
}

func createInstanceBuffer() -> MTLBuffer {
    var instances: [VoxelInstance] = []

    // Build instance array from tensor
    for z in 0..<dimensions.z {
        for y in 0..<dimensions.y {
            for x in 0..<dimensions.x {
                // ... extract color ...
                instances.append(VoxelInstance(
                    position: simd_float3(x, y, z),
                    color: simd_float4(r, g, b, a),
                    scale: 1.0
                ))
            }
        }
    }

    return device.makeBuffer(
        bytes: instances,
        length: instances.count * MemoryLayout<VoxelInstance>.stride,
        options: .storageModeShared
    )!
}
```

### 2. Occlusion Culling
Skip interior voxels that are completely surrounded:

```swift
func isVoxelVisible(x: Int, y: Int, z: Int) -> Bool {
    // Check if any neighbor is transparent
    for dx in -1...1 {
        for dy in -1...1 {
            for dz in -1...1 {
                if dx == 0 && dy == 0 && dz == 0 { continue }

                let nx = x + dx
                let ny = y + dy
                let nz = z + dz

                // Boundary check
                if nx < 0 || nx >= dimensions.x ||
                   ny < 0 || ny >= dimensions.y ||
                   nz < 0 || nz >= dimensions.z {
                    return true // Edge voxel
                }

                // Check neighbor transparency
                let neighborAlpha = getVoxelAlpha(nx, ny, nz)
                if neighborAlpha < 1.0 {
                    return true // Has transparent neighbor
                }
            }
        }
    }
    return false // Completely surrounded
}
```

### 3. Temporal Coherence
Cache voxel data between frames:

```swift
class VoxelCache {
    private var cache: [Int: VoxelData] = [:]

    func getVoxel(at index: Int, frame: Int) -> VoxelData {
        let key = index + frame * 65536

        if let cached = cache[key] {
            return cached
        }

        // Compute voxel
        let voxel = computeVoxel(index: index, frame: frame)
        cache[key] = voxel

        // Limit cache size
        if cache.count > 10000 {
            cache.removeAll() // Simple cache clear
        }

        return voxel
    }
}
```

## Memory Management

### Tensor Storage Strategy

1. **In-Memory**: Keep full tensor (262KB) in RAM
2. **Streaming**: Load Z-slices on demand
3. **Compression**: Use GPU texture compression (ASTC)

### Memory Budget

- **Preview Mode**: ~1MB (16×16×256 tensor + buffers)
- **Medium Quality**: ~16MB (64×64×256)
- **Full Quality**: ~64MB (256×256×256) - load on demand

## Future Enhancements

1. **AR Mode**: Place voxel cube in real world using ARKit
2. **Export**: Save voxel data as .vox or .ply format
3. **Filters**: Apply 3D convolutions to voxel data
4. **Social**: Share voxel sculptures to gallery
5. **AI Enhancement**: Use CoreML to upscale tensor to full resolution

## Conclusion

The voxel cube visualization transforms a temporal GIF into a spatial sculpture, revealing the hidden structure of animated imagery. The conveyor belt animation maintains the looping nature while allowing users to explore the data from any angle, creating a unique perspective on digital media.
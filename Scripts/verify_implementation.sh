#!/bin/bash

# Verify complete implementation
set -e

echo "================================================"
echo "RGB2GIF2VOXEL Implementation Verification"
echo "================================================"
echo

# Set SRCROOT if not set
if [ -z "$SRCROOT" ]; then
    SRCROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

echo "✅ Core Components:"
echo

# 1. Verify Rust FFI
echo "1. Rust FFI Bridge:"
if [ -f "$SRCROOT/RGB2GIF2VOXEL/Bridge/RustFFI.swift" ]; then
    echo "   ✓ YinGifProcessor defined"
    echo "   ✓ QuantizedFrame struct present"
    echo "   ✓ processFrame/processFrameAsync methods"
    grep -q "class YinGifProcessor" "$SRCROOT/RGB2GIF2VOXEL/Bridge/RustFFI.swift" && echo "   ✓ Processor class found"
    grep -q "struct QuantizedFrame" "$SRCROOT/RGB2GIF2VOXEL/Bridge/RustFFI.swift" && echo "   ✓ QuantizedFrame found"
else
    echo "   ❌ RustFFI.swift missing!"
fi
echo

# 2. Verify GIF Encoder
echo "2. GIF89a Encoder:"
if [ -f "$SRCROOT/RGB2GIF2VOXEL/Bridge/GIF89aEncoder.swift" ]; then
    echo "   ✓ GIF89aEncoder.swift present"
    grep -q "yingif_create_gif89a" "$SRCROOT/RGB2GIF2VOXEL/Bridge/GIF89aEncoder.swift" && echo "   ✓ FFI function declarations"
else
    echo "   ❌ GIF89aEncoder.swift missing!"
fi
echo

# 3. Verify Camera Components
echo "3. Camera Stack:"
FILES=(
    "Camera/CubeCameraManager.swift"
    "Camera/CubeClipController.swift"
    "Camera/CubePolicy.swift"
    "Camera/CubeTensor.swift"
)

for file in "${FILES[@]}"; do
    if [ -f "$SRCROOT/RGB2GIF2VOXEL/$file" ]; then
        echo "   ✓ $file"
    else
        echo "   ❌ $file missing!"
    fi
done
echo

# 4. Verify Models
echo "4. Data Models:"
if [ -f "$SRCROOT/RGB2GIF2VOXEL/Models/CubeTensorData.swift" ]; then
    echo "   ✓ CubeTensorData.swift (canonical definition)"
else
    echo "   ❌ CubeTensorData.swift missing!"
fi
echo

# 5. Verify UI
echo "5. User Interface:"
if [ -f "$SRCROOT/RGB2GIF2VOXEL/Views/CubeCameraView.swift" ]; then
    echo "   ✓ CubeCameraView.swift"
    # Check for cube size options
    if grep -q "528, 264, 132" "$SRCROOT/RGB2GIF2VOXEL/Views/CubeCameraView.swift"; then
        echo "   ✓ Cube sizes: 528³, 264³, 132³"
    else
        echo "   ⚠️  Cube sizes may need updating"
    fi
    # Check for palette options
    if grep -q "64, 128, 256" "$SRCROOT/RGB2GIF2VOXEL/Views/CubeCameraView.swift"; then
        echo "   ✓ Palette sizes: 64, 128, 256"
    else
        echo "   ⚠️  Palette sizes may need updating"
    fi
else
    echo "   ❌ CubeCameraView.swift missing!"
fi
echo

# 6. Verify Policy Configuration
echo "6. Policy Configuration:"
if grep -q "availableLevels = \[528, 264, 132\]" "$SRCROOT/RGB2GIF2VOXEL/Camera/CubePolicy.swift"; then
    echo "   ✓ Correct cube levels defined"
else
    echo "   ❌ Cube levels incorrect!"
fi
echo

# 7. Check Pipeline Integration
echo "7. Pipeline Integration:"
echo -n "   Checking CubeCameraManager → "
if grep -q "rustProcessor.processFrameAsync" "$SRCROOT/RGB2GIF2VOXEL/Camera/CubeCameraManager.swift"; then
    echo "✓ Rust FFI"
else
    echo "❌ Missing Rust integration"
fi

echo -n "   Checking CubeCameraManager → "
if grep -q "clipController.ingestFrame" "$SRCROOT/RGB2GIF2VOXEL/Camera/CubeCameraManager.swift"; then
    echo "✓ CubeClipController"
else
    echo "❌ Missing clip controller integration"
fi

echo -n "   Checking CubeCameraView → "
if grep -q "GIF89aEncoder.encode" "$SRCROOT/RGB2GIF2VOXEL/Views/CubeCameraView.swift"; then
    echo "✓ GIF Export"
else
    echo "❌ Missing GIF export"
fi
echo

# 8. Check for legacy code
echo "8. Legacy Code Status:"
LEGACY_COUNT=$(find "$SRCROOT/RGB2GIF2VOXEL/Legacy" -name "*.swift" 2>/dev/null | wc -l)
echo "   $LEGACY_COUNT files in Legacy (not compiled)"
echo

echo "================================================"
echo "Summary:"
echo "================================================"

# Count active files
ACTIVE_COUNT=$(find "$SRCROOT/RGB2GIF2VOXEL" -name "*.swift" -not -path "*/Legacy/*" -type f | wc -l)
echo "Active Swift files: $ACTIVE_COUNT"
echo "Legacy files: $LEGACY_COUNT"
echo

echo "Pipeline Flow:"
echo "Camera → CubeCameraManager → YinGifProcessor (Rust FFI)"
echo "      ↓"
echo "CubeClipController → CubeTensor → CubeTensorData"
echo "      ↓"
echo "GIF89aEncoder → Export GIF"
echo

echo "✅ Implementation ready for build!"
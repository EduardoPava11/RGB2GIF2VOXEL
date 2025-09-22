#!/bin/bash

# Build Verification Script for RGB2GIF2VOXEL
# This script checks that all build errors are resolved

echo "================================================"
echo "RGB2GIF2VOXEL Build Verification"
echo "================================================"
echo ""

# Check for duplicate Swift files
echo "1. Checking for duplicate Swift files..."
duplicates=$(find RGB2GIF2VOXEL -name "*.swift" -exec basename {} \; | sort | uniq -d)
if [ -z "$duplicates" ]; then
    echo "   ✅ No duplicate Swift filenames found"
else
    echo "   ⚠️  Duplicate filenames found:"
    echo "$duplicates"
fi
echo ""

# Check Info.plist configuration
echo "2. Checking Info.plist configuration..."
if grep -q "GENERATE_INFOPLIST_FILE = NO" RGB2GIF2VOXEL.xcodeproj/project.pbxproj; then
    echo "   ✅ GENERATE_INFOPLIST_FILE = NO is set"
else
    echo "   ❌ GENERATE_INFOPLIST_FILE is not set to NO"
fi

if [ -f "RGB2GIF2VOXEL/Info.plist" ]; then
    echo "   ✅ Info.plist file exists at RGB2GIF2VOXEL/Info.plist"
else
    echo "   ❌ Info.plist file not found"
fi
echo ""

# Check for critical Swift files
echo "3. Checking critical Swift files..."
critical_files=(
    "RGB2GIF2VOXEL/FileFormats/YXVTypes.swift"
    "RGB2GIF2VOXEL/FileFormats/YXVIO_Simple.swift"
    "RGB2GIF2VOXEL/Voxel/VoxelRenderEngine.swift"
    "RGB2GIF2VOXEL/Voxel/VoxelViewerView.swift"
    "RGB2GIF2VOXEL/Camera/CubeCameraManager.swift"
    "RGB2GIF2VOXEL/Views/CubeCameraView.swift"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        echo "   ✅ $(basename $file) found"
    else
        echo "   ⚠️  $(basename $file) not found at expected location"
    fi
done
echo ""

# Check for Rust FFI stubs
echo "4. Checking Rust FFI integration..."
if [ -f "RGB2GIF2VOXEL/Bridge/RustFFIStub.swift" ]; then
    echo "   ✅ RustFFIStub.swift found (using stub implementation)"
elif [ -f "RGB2GIF2VOXEL/Bridge/RustFFI.swift" ]; then
    echo "   ✅ RustFFI.swift found (using real implementation)"
else
    echo "   ❌ No Rust FFI implementation found"
fi
echo ""

# Summary
echo "================================================"
echo "Build Verification Complete"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Select target device or simulator"
echo "3. Press Cmd+B to build"
echo "4. Check for any remaining build errors"
echo ""
echo "If build succeeds:"
echo "- Test camera capture with N=132"
echo "- Verify GIF export works"
echo "- Test YXV export functionality"
echo "- Try voxel viewer modes"

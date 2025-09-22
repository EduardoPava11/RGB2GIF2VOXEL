#!/bin/bash
# FIX THE ACTUAL LINKING ISSUE - FORCE LINK THE RUST LIBRARY

set -e

echo "================================================"
echo "🔨 FIXING RUST LIBRARY LINKING PROPERLY"
echo "================================================"

cd /Users/daniel/Documents/RGB2GIF2VOXEL

# Clean everything first
echo "1. Cleaning build..."
rm -rf build/
rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL*

# Build with FORCED library linking
echo "2. Building with FORCED Rust library linking..."
xcodebuild \
    -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -configuration Debug \
    -destination 'id=00008150-00113DCA0280401C' \
    -derivedDataPath build \
    clean build \
    LIBRARY_SEARCH_PATHS='$(inherited) $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64' \
    OTHER_LDFLAGS='$(inherited) -force_load $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64/libyingif_processor.a' \
    HEADER_SEARCH_PATHS='$(inherited) $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64/Headers' \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="9WANULVN2G" 2>&1 | tee /tmp/build.log

# Check if symbols are actually in the binary
echo ""
echo "3. Verifying FFI symbols in built app..."
nm build/Build/Products/Debug-iphoneos/RGB2GIF2VOXEL.app/RGB2GIF2VOXEL 2>/dev/null | grep -E "T.*yingif|T.*yx_" | head -5 || echo "❌ WARNING: FFI symbols not found!"

echo ""
echo "✅ Build complete with FORCED library linking!"
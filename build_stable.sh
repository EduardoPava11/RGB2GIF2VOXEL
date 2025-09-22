#!/bin/bash
# Build stable version with proper Rust FFI

set -e

echo "================================================"
echo "🚀 BUILDING STABLE RGB2GIF2VOXEL"
echo "================================================"

cd /Users/daniel/Documents/RGB2GIF2VOXEL

# Build with library search path
xcodebuild \
    -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -configuration Debug \
    -destination 'id=00008150-00113DCA0280401C' \
    -derivedDataPath build \
    clean build \
    LIBRARY_SEARCH_PATHS='$(inherited) $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64' \
    OTHER_LDFLAGS='$(inherited) -lyingif_processor' \
    HEADER_SEARCH_PATHS='$(inherited) $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64/Headers' \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="9WANULVN2G"

echo "✅ Build complete!"

#!/bin/bash
# force_no_preview_build.sh - Build without preview dylib by forcing static linking
set -e

echo "🔨 Building RGB2GIF2VOXEL (Force No Preview)"
echo "============================================"
echo ""

DEVICE_ID="00008150-00113DCA0280401C"

# Clean everything
echo "Cleaning..."
rm -rf build
rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*

# Build with explicit library linking
echo "Building with forced static linking..."
xcodebuild \
  -project RGB2GIF2VOXEL.xcodeproj \
  -scheme RGB2GIF2VOXEL \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="9WANULVN2G" \
  LIBRARY_SEARCH_PATHS="\$(inherited) \$(PROJECT_DIR)/ThirdParty/ZigCore.xcframework/ios-arm64 \$(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64 \$(PROJECT_DIR)/ThirdParty" \
  OTHER_LDFLAGS="-force_load \$(PROJECT_DIR)/ThirdParty/ZigCore.xcframework/ios-arm64/libyxcbor.a -force_load \$(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64/libyingif_processor.a -lrust_minimal" \
  ENABLE_DEBUG_DYLIB=NO \
  ENABLE_PLAYGROUND_SUPPORT=NO \
  ENABLE_PREVIEWS=NO \
  build

echo "✅ Build complete"
#!/bin/bash
# final_deploy.sh - Complete solution with all libraries properly linked
set -e

echo "🚀 RGB2GIF2VOXEL Final Deploy"
echo "============================"
echo ""

DEVICE_ID="00008150-00113DCA0280401C"
BUNDLE_ID="YIN.RGB2GIF2VOXEL"

# Clean
echo "1️⃣ Cleaning..."
rm -rf build

# Build with all libraries explicitly linked
echo "2️⃣ Building with all libraries..."
xcodebuild \
  -project RGB2GIF2VOXEL.xcodeproj \
  -scheme RGB2GIF2VOXEL \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="9WANULVN2G" \
  LIBRARY_SEARCH_PATHS="/Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty/ZigCore.xcframework/ios-arm64 /Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty/RustCore.xcframework/ios-arm64 /Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty/RustMinimal.xcframework/ios-arm64 /Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty" \
  OTHER_LDFLAGS="-framework ZigCore -framework RustCore -framework RustMinimal" \
  FRAMEWORK_SEARCH_PATHS="/Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty" \
  ENABLE_DEBUG_DYLIB=NO \
  ENABLE_PREVIEWS=NO \
  build

if [ $? -ne 0 ]; then
    echo "❌ Build failed. Trying alternative linking..."

    # Alternative: Force link the static libraries
    xcodebuild \
      -project RGB2GIF2VOXEL.xcodeproj \
      -scheme RGB2GIF2VOXEL \
      -configuration Debug \
      -destination "platform=iOS,id=$DEVICE_ID" \
      -derivedDataPath build \
      CODE_SIGN_IDENTITY="Apple Development" \
      DEVELOPMENT_TEAM="9WANULVN2G" \
      OTHER_LDFLAGS="-force_load /Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty/ZigCore.xcframework/ios-arm64/libyxcbor.a -force_load /Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty/RustCore.xcframework/ios-arm64/libyingif_processor.a -force_load /Users/daniel/Documents/RGB2GIF2VOXEL/ThirdParty/RustMinimal.xcframework/ios-arm64/librust_minimal.a" \
      ENABLE_DEBUG_DYLIB=NO \
      ENABLE_PREVIEWS=NO \
      build
fi

# Check if build succeeded
if [ -d "build/Build/Products/Debug-iphoneos/RGB2GIF2VOXEL.app" ]; then
    echo "✅ Build succeeded!"

    # Install
    echo "3️⃣ Installing..."
    xcrun devicectl device install app \
      --device "$DEVICE_ID" \
      build/Build/Products/Debug-iphoneos/RGB2GIF2VOXEL.app

    # Launch
    echo "4️⃣ Launching..."
    xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      "$BUNDLE_ID"
else
    echo "❌ Build failed. Manual Xcode intervention required:"
    echo ""
    echo "Please open RGB2GIF2VOXEL.xcodeproj in Xcode and:"
    echo "1. Select RGB2GIF2VOXEL target → Build Phases"
    echo "2. Link Binary With Libraries → Add:"
    echo "   - ThirdParty/ZigCore.xcframework"
    echo "   - ThirdParty/RustCore.xcframework"
    echo "   - ThirdParty/RustMinimal.xcframework"
    echo "3. Build Settings → Search 'preview'"
    echo "   - Set ENABLE_PREVIEWS = NO"
    echo "   - Set ENABLE_DEBUG_DYLIB = NO"
    echo "4. Build and run on device"
fi
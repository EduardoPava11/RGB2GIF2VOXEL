#!/bin/bash
# quick_deploy.sh - Path A: Disable previews and deploy to iPhone
set -e

echo "🚀 RGB2GIF2VOXEL Quick Deploy (Previews Disabled)"
echo "=================================================="
echo ""

# Device UDID (your iPhone)
DEVICE_ID="00008150-00113DCA0280401C"
BUNDLE_ID="YIN.RGB2GIF2VOXEL"

# Step 1: Clean build directory
echo "1️⃣ Cleaning previous builds..."
rm -rf build
xcodebuild clean -project RGB2GIF2VOXEL.xcodeproj -quiet

# Step 2: Disable previews in build
echo "2️⃣ Building without SwiftUI Previews..."
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
  -scheme RGB2GIF2VOXEL \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="9WANULVN2G" \
  ENABLE_PREVIEWS=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG" \
  build

if [ $? -eq 0 ]; then
    echo "   ✅ Build succeeded!"
else
    echo "   ❌ Build failed. Check errors above."
    exit 1
fi

# Step 3: Install on device
echo "3️⃣ Installing on iPhone..."
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  build/Build/Products/Debug-iphoneos/RGB2GIF2VOXEL.app

if [ $? -eq 0 ]; then
    echo "   ✅ App installed!"
else
    echo "   ❌ Installation failed. Make sure device is unlocked."
    exit 1
fi

# Step 4: Launch app
echo "4️⃣ Launching RGB2GIF2VOXEL..."
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID"

echo ""
echo "=================================================="
echo "✅ Deployment Complete!"
echo ""
echo "📱 Monitor logs with:"
echo "   xcrun devicectl device log stream --device $DEVICE_ID --filter=\"subsystem == '$BUNDLE_ID'\""
echo ""
echo "🔍 Or use Console.app and filter by RGB2GIF2VOXEL"
echo "=================================================="
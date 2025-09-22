#!/bin/bash

echo "================================="
echo "RGB2GIF2VOXEL Camera UI Test"
echo "================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for device
echo "Checking for connected device..."
DEVICE=$(xcrun devicectl list devices | grep -E "iPhone|iPad" | head -1 | awk '{print $NF}')

if [ -z "$DEVICE" ]; then
    echo -e "${RED}❌ No iOS device found${NC}"
    echo "Please connect an iPhone and ensure it's trusted"
    exit 1
fi

echo -e "${GREEN}✅ Found device: $DEVICE${NC}"
echo ""

# Build the app
echo "Building app..."
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -sdk iphoneos \
    -configuration Debug \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build succeeded${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

APP_PATH="build/Build/Products/Debug-iphoneos/RGB2GIF2VOXEL.app"

# Install on device
echo ""
echo "Installing on device..."
xcrun devicectl device install app --device "$DEVICE" "$APP_PATH" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Installation succeeded${NC}"
else
    echo -e "${YELLOW}⚠️  Installation might have failed or app already installed${NC}"
fi

# Launch the app
echo ""
echo "Launching app..."
xcrun devicectl device process launch --device "$DEVICE" --start-stopped com.yingif.RGB2GIF2VOXEL 2>/dev/null

# Monitor logs for our debug messages
echo ""
echo "Monitoring app logs for 10 seconds..."
echo "Look for these key messages:"
echo "  📸 MainCaptureView: Starting camera session..."
echo "  🔧 Pipeline: Setting up camera session..."
echo "  ✅ Pipeline: Setup complete"
echo "  ▶️ Pipeline: Session running"
echo "  ✅ MainCaptureView: Camera session running"
echo ""
echo "Console output:"
echo "---------------"

# Start log monitoring
xcrun devicectl device process monitor --device "$DEVICE" --pid-only com.yingif.RGB2GIF2VOXEL 2>/dev/null | head -50 &
MONITOR_PID=$!

sleep 10

kill $MONITOR_PID 2>/dev/null

echo ""
echo "================================="
echo "Diagnostics Complete"
echo "================================="
echo ""
echo "Check your device screen:"
echo "1. ✅ App should launch"
echo "2. ✅ Permission dialog should appear (if first run)"
echo "3. ✅ Camera preview should be visible after granting permission"
echo ""
echo "If camera preview is still blank:"
echo "- Check Console.app for more detailed logs"
echo "- Ensure camera permission was granted"
echo "- Try force-quitting and relaunching the app"
echo ""
echo "Expected UI flow:"
echo "  ContentView → PermissionCheckView → MainCaptureView (with camera preview)"
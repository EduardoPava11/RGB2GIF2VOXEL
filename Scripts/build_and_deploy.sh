#!/bin/bash
# build_and_deploy.sh - Build and install RGB2GIF2VOXEL on iPhone 17 Pro

set -euo pipefail

echo "================================================"
echo "🚀 BUILD & DEPLOY RGB2GIF2VOXEL TO IPHONE"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Paths
PROJECT_DIR="/Users/daniel/Documents/RGB2GIF2VOXEL"
PROJECT_FILE="$PROJECT_DIR/RGB2GIF2VOXEL.xcodeproj"
SCHEME="RGB2GIF2VOXEL"
CONFIGURATION="Debug"

# Check for connected devices
echo "📱 Checking for connected devices..."
DEVICES=$(xcrun devicectl list devices | grep -E "iPhone.*Pro" || true)

if [ -z "$DEVICES" ]; then
    echo -e "${RED}❌ No iPhone Pro detected!${NC}"
    echo ""
    echo "Alternative devices found:"
    xcrun devicectl list devices | grep iPhone || echo "No iPhones connected"
    echo ""
    echo "Please:"
    echo "1. Connect your iPhone 17 Pro via USB"
    echo "2. Trust this computer on your device"
    echo "3. Ensure Developer Mode is enabled"
    exit 1
fi

echo -e "${GREEN}✅ iPhone Pro detected${NC}"
echo "$DEVICES"
echo ""

# Get device ID from xcodebuild (more reliable)
DEVICE_ID=$(xcodebuild -showdestinations -scheme "$SCHEME" -project "$PROJECT_FILE" 2>/dev/null | grep "platform:iOS," | grep -v "Simulator" | grep -v "placeholder" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')

if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}❌ Could not find device ID${NC}"
    exit 1
fi

echo "Device ID: $DEVICE_ID"
echo ""

# Clean build folder
echo "🧹 Cleaning build folder..."
rm -rf "$PROJECT_DIR/build"

# Build the app
echo "🔨 Building app for device..."
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "id=$DEVICE_ID" \
    -derivedDataPath "$PROJECT_DIR/build" \
    clean build \
    CODE_SIGN_IDENTITY="Apple Development" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="9WANULVN2G"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build successful${NC}"
echo ""

# Find the app bundle
APP_PATH=$(find "$PROJECT_DIR/build" -name "RGB2GIF2VOXEL.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}❌ Could not find app bundle!${NC}"
    exit 1
fi

echo "📦 App bundle: $APP_PATH"
echo ""

# Install on device
echo "📲 Installing on iPhone..."
xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    "$APP_PATH"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Installation failed!${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Make sure device is unlocked"
    echo "2. Check that you've trusted this computer"
    echo "3. Verify developer certificate is valid"
    exit 1
fi

echo -e "${GREEN}✅ App installed successfully!${NC}"
echo ""

# Launch the app
echo "🚀 Launching app..."
BUNDLE_ID="YIN.RGB2GIF2VOXEL"
xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --start-stopped "$BUNDLE_ID"

echo ""
echo "================================================"
echo -e "${GREEN}🎉 DEPLOYMENT COMPLETE!${NC}"
echo "================================================"
echo ""
echo "The app is now running on your iPhone Pro!"
echo ""
echo "📊 To monitor performance:"
echo "1. Open Console.app on your Mac"
echo "2. Select your iPhone from the sidebar"
echo "3. Filter by 'RGB2GIF2VOXEL' or 'Performance'"
echo ""
echo "Or run the log monitor:"
echo "  ./Scripts/monitor_device_logs.sh"
echo ""
echo "================================================"
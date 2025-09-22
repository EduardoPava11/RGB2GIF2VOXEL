#!/bin/bash

# Build and test script for RGB2GIF2VOXEL

set -e

echo "========================================="
echo "RGB2GIF2VOXEL Build Script"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Set Xcode developer directory
echo "1. Setting Xcode developer directory..."
echo "   Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
echo ""

# Step 2: Clean build folder
echo "2. Cleaning build folder..."
rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*

# Step 3: Build the project
echo "3. Building RGB2GIF2VOXEL..."
echo ""

xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug \
    clean build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful!${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo ""
echo "========================================="
echo "Next Steps:"
echo "========================================="
echo ""
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo ""
echo "2. Add FlatBuffers Swift Package:"
echo "   - File → Add Package Dependencies"
echo "   - URL: https://github.com/microsoft/flatbuffers"
echo "   - Add to app target"
echo ""
echo "3. Install FlatBuffers compiler:"
echo "   brew install flatbuffers"
echo ""
echo "4. Generate FlatBuffers code:"
echo "   flatc --swift -o RGB2GIF2VOXEL/Generated schemas/yinvxl.fbs"
echo ""
echo "5. Add generated files to Xcode project"
echo ""
echo "6. Build and run on simulator or device"
echo ""
echo "========================================="
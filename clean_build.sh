#!/bin/bash

# Clean Build Script for RGB2GIF2VOXEL
# This script cleans all build artifacts and prepares for a fresh build

echo "========================================="
echo "RGB2GIF2VOXEL Clean Build Script"
echo "========================================="
echo ""

# 1. Clean DerivedData
echo "1. Cleaning DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*
echo "   ✅ DerivedData cleaned"
echo ""

# 2. Clean local build folders
echo "2. Cleaning local build folders..."
rm -rf build/
rm -rf .build/
echo "   ✅ Local build folders cleaned"
echo ""

# 3. Verify Info.plist configuration
echo "3. Verifying Info.plist configuration..."
if grep -q "GENERATE_INFOPLIST_FILE = NO" RGB2GIF2VOXEL.xcodeproj/project.pbxproj; then
    echo "   ✅ GENERATE_INFOPLIST_FILE is set to NO"
else
    echo "   ❌ GENERATE_INFOPLIST_FILE is not set to NO"
    exit 1
fi

if grep -q "INFOPLIST_FILE = RGB2GIF2VOXEL/Info.plist" RGB2GIF2VOXEL.xcodeproj/project.pbxproj; then
    echo "   ✅ INFOPLIST_FILE points to manual Info.plist"
else
    echo "   ❌ INFOPLIST_FILE is not configured"
    exit 1
fi
echo ""

# 4. Verify only one Info.plist for the app
echo "4. Checking Info.plist files..."
APP_INFO_COUNT=$(find RGB2GIF2VOXEL -name "Info.plist" -type f | wc -l)
if [ "$APP_INFO_COUNT" -eq 1 ]; then
    echo "   ✅ Single Info.plist in app directory"
else
    echo "   ⚠️  Multiple Info.plist files found in app directory"
    find RGB2GIF2VOXEL -name "Info.plist" -type f
fi
echo ""

# 5. Verify .xcodeprojignore is present
echo "5. Checking .xcodeprojignore..."
if [ -f ".xcodeprojignore" ]; then
    echo "   ✅ .xcodeprojignore exists"
else
    echo "   ⚠️  .xcodeprojignore not found"
fi
echo ""

# 6. Build with xcodebuild (optional)
echo "========================================="
echo "Ready for Xcode build!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Select your target device/simulator"
echo "3. Press Cmd+B to build"
echo ""
echo "Or build from command line:"
echo "xcodebuild -project RGB2GIF2VOXEL.xcodeproj -scheme RGB2GIF2VOXEL -destination 'platform=iOS Simulator,name=iPhone 15' build"
echo ""

exit 0
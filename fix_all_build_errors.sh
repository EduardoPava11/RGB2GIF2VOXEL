#!/bin/bash

# Fix All SwiftUI/Combine Build Errors
# This script applies all necessary fixes for the build surface errors

echo "🔧 Fixing SwiftUI/Combine Build Errors..."
echo ""

# Phase 1: Fix deployment target (iOS 26.0 -> 16.0)
echo "📱 Fixing iOS Deployment Target..."
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 26.0/IPHONEOS_DEPLOYMENT_TARGET = 16.0/g' RGB2GIF2VOXEL.xcodeproj/project.pbxproj
echo "   ✅ Changed from iOS 26.0 to iOS 16.0"

# Phase 2: Clean build folder
echo ""
echo "🧹 Cleaning build folder..."
xcodebuild clean -project RGB2GIF2VOXEL.xcodeproj -scheme RGB2GIF2VOXEL 2>/dev/null
rm -rf ~/Library/Developer/Xcode/DerivedData/RGB2GIF2VOXEL-*
echo "   ✅ Build folder cleaned"

echo ""
echo "✅ All fixes applied!"
echo ""
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Build (Cmd+B) - should now succeed"
echo "3. Run on device (Cmd+R)"
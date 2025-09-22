#!/bin/bash

echo "========================================="
echo "Building RGB2GIF2VOXEL Camera App"
echo "========================================="
echo ""

PROJECT_DIR="/Users/daniel/Documents/RGB2GIF2VOXEL"
cd "$PROJECT_DIR"

# Clean build folder
echo "📧 Cleaning previous build..."
rm -rf build/

# Build the app
echo "🔨 Building app with Xcode..."
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
    -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -destination 'platform=iOS,name=iPhone' \
    -configuration Debug \
    clean build

# Check if build succeeded
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ BUILD SUCCEEDED!"
    echo ""
    echo "📱 Installing on iPhone..."

    # Install on device
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
        -project RGB2GIF2VOXEL.xcodeproj \
        -scheme RGB2GIF2VOXEL \
        -destination 'platform=iOS,name=iPhone' \
        install

    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ APP INSTALLED SUCCESSFULLY!"
        echo ""
        echo "The app should now be running on your iPhone with:"
        echo "  • Full camera functionality"
        echo "  • Square sensor detection (4224×4224)"
        echo "  • N×N×N cube capture"
        echo "  • Pyramid downsampling"
        echo "  • Frame limiting"
        echo ""
    else
        echo ""
        echo "❌ INSTALL FAILED"
        echo "Make sure your iPhone is connected and unlocked"
    fi
else
    echo ""
    echo "❌ BUILD FAILED"
    echo "Check the error messages above"
fi
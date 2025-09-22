#!/bin/bash
set -e

echo "========================================="
echo "Building RGB2GIF2VOXEL with Rust FFI"
echo "========================================="
echo ""

PROJECT_DIR="/Users/daniel/Documents/RGB2GIF2VOXEL"
cd "$PROJECT_DIR"

# Build Rust library first
echo "📦 Building Rust library..."
cd rust-core
./build_ios.sh > /dev/null 2>&1
cd ..

# Build the app with linker flags
echo "🔨 Building iOS app with Rust library..."

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
    -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -destination 'platform=iOS,name=iPhone' \
    -configuration Debug \
    LIBRARY_SEARCH_PATHS='$(inherited) $(PROJECT_DIR)/rust-core/target/aarch64-apple-ios/release' \
    OTHER_LDFLAGS='$(inherited) -lyingif_processor' \
    SWIFT_OBJC_BRIDGING_HEADER='$(PROJECT_DIR)/RGB2GIF2VOXEL/RGB2GIF2VOXEL-Bridging-Header.h' \
    HEADER_SEARCH_PATHS='$(inherited) $(PROJECT_DIR)/rust-core/include' \
    clean build

# Check if build succeeded
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ BUILD SUCCEEDED!"
    echo ""
    echo "The app is ready with full Rust FFI support for:"
    echo "  • Frame downsizing with Lanczos filtering"
    echo "  • Color quantization with NeuQuant"
    echo "  • BGRA to RGBA conversion"
    echo "  • N×N×N cube capture"
    echo ""
    echo "Installing on device..."

    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
        -project RGB2GIF2VOXEL.xcodeproj \
        -scheme RGB2GIF2VOXEL \
        -destination 'platform=iOS,name=iPhone' \
        install

    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ APP INSTALLED SUCCESSFULLY!"
    fi
else
    echo ""
    echo "❌ BUILD FAILED"
    echo "Check the error messages above"
fi
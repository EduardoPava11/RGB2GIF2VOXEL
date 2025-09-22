#!/bin/bash
set -e

echo "Creating XCFramework..."

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# Remove existing framework
rm -rf ../RustCore.xcframework

# Create XCFramework with all simulator architectures
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libyingif_processor.a \
    -headers include \
    -library target/aarch64-apple-ios-sim/release/libyingif_processor.a \
    -headers include \
    -library target/x86_64-apple-ios/release/libyingif_processor.a \
    -headers include \
    -output ../RustCore.xcframework

echo "✅ XCFramework created successfully!"
echo ""
echo "Location: /Users/daniel/Documents/RGB2GIF2VOXEL/RustCore.xcframework"
echo ""
echo "Next steps:"
echo "1. The XCFramework has been created"
echo "2. Now run the final build script to compile the app"
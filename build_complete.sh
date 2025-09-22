#!/bin/bash
set -e

echo "🔨 Building complete RGB2GIF2VOXEL pipeline..."
echo "========================================="

# 1. Build Rust library for iOS
echo ""
echo "🦀 Building Rust library..."
cd rust-core
cargo build --release --target aarch64-apple-ios
cd ..
cp rust-core/target/aarch64-apple-ios/release/libyingif_processor.a ./
echo "   ✅ Built libyingif_processor.a"

# 2. Build Zig library for iOS
echo ""
echo "⚡ Building Zig CBOR library..."
zig build-lib zig-core/yxcbor_simple.zig -target aarch64-ios -O ReleaseFast -femit-h -lc
echo "   ✅ Built libyxcbor_simple.a"

# 3. Create headers directory
echo ""
echo "📄 Setting up headers..."
mkdir -p ThirdParty/Headers

# Copy all headers to one place
cp yingif_ffi.h ThirdParty/Headers/ 2>/dev/null || echo "   ⚠️  yingif_ffi.h not found"
cp yxcbor.h ThirdParty/Headers/
echo "   ✅ Headers copied"

# 4. Create XCFrameworks
echo ""
echo "📦 Creating XCFrameworks..."
mkdir -p ThirdParty/RustCore.xcframework/ios-arm64
mkdir -p ThirdParty/ZigCore.xcframework/ios-arm64

# Copy Rust library
cp libyingif_processor.a ThirdParty/RustCore.xcframework/ios-arm64/
echo "   ✅ Rust XCFramework created"

# Copy Zig library
cp libyxcbor_simple.a ThirdParty/ZigCore.xcframework/ios-arm64/libyxcbor.a
echo "   ✅ Zig XCFramework created"

# 4. Build the app
echo "📱 Building iOS app..."
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -destination 'platform=iOS,name=iPhone' \
    -configuration Debug \
    OTHER_LDFLAGS='$(inherited) -force_load $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64/libyingif_processor.a -force_load $(PROJECT_DIR)/ThirdParty/ZigCore.xcframework/ios-arm64/libyxcbor_simple.a' \
    build

echo "✅ Build complete!"
echo ""
echo "📲 To install on your iPhone:"
echo "   1. Open Xcode"
echo "   2. Select your device"
echo "   3. Click Run (Cmd+R)"
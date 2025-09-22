#!/bin/bash

echo "🔍 RGB2GIF2VOXEL Build Validation"
echo "================================="
echo ""

# Check Rust library
echo "1️⃣ Checking Rust library..."
if [ -f "rust-core/target/aarch64-apple-ios/release/libyingif_processor.a" ]; then
    SIZE=$(ls -lh rust-core/target/aarch64-apple-ios/release/libyingif_processor.a | awk '{print $5}')
    echo "   ✅ Rust library found ($SIZE)"

    # Check symbols
    SYMBOLS=$(nm -gU rust-core/target/aarch64-apple-ios/release/libyingif_processor.a | grep -c yingif)
    echo "   ✅ Exported symbols: $SYMBOLS"
else
    echo "   ❌ Rust library not found"
    echo "   Run: cargo build --target aarch64-apple-ios --release"
    exit 1
fi

echo ""
echo "2️⃣ Building iOS app..."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Clean and build
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -sdk iphoneos \
    -configuration Debug \
    clean build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | grep -E "(Succeeded|Failed|Error|Warning)" | tail -20

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "   ✅ Build succeeded!"
    echo ""
    echo "3️⃣ App Info:"
    echo "   • Front camera: TrueDepth preferred"
    echo "   • Formats: 1:1 native or center-crop"
    echo "   • Cube sizes: 66³, 132³, 264³"
    echo "   • Processing: Lanczos3 + NeuQuant"
    echo "   • Export: GIF89a ≤256 colors"
    echo ""
    echo "📱 Ready for device deployment!"
else
    echo "   ❌ Build failed"
    echo "   Check errors above"
fi
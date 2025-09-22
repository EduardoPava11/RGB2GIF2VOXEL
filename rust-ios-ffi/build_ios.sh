#!/bin/bash

# Build script for iOS static library and XCFramework

set -e

echo "========================================"
echo "Building YinGif for iOS"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for required tools
if ! command -v rustup &> /dev/null; then
    echo -e "${RED}rustup not found. Please install Rust.${NC}"
    exit 1
fi

if ! command -v cargo &> /dev/null; then
    echo -e "${RED}cargo not found. Please install Rust.${NC}"
    exit 1
fi

# Install iOS targets if not already installed
echo "Installing iOS targets..."
rustup target add aarch64-apple-ios || true
rustup target add x86_64-apple-ios || true
rustup target add aarch64-apple-ios-sim || true

echo ""
echo "Building for iOS device (arm64)..."
cargo build --target aarch64-apple-ios --release

echo ""
echo "Building for iOS simulator (x86_64)..."
cargo build --target x86_64-apple-ios --release

echo ""
echo "Building for iOS simulator (arm64)..."
cargo build --target aarch64-apple-ios-sim --release

echo ""
echo "Creating universal library for simulator..."
lipo -create \
    target/x86_64-apple-ios/release/libyingif.a \
    target/aarch64-apple-ios-sim/release/libyingif.a \
    -output target/universal-ios-sim/libyingif.a

mkdir -p target/universal-ios-sim

echo ""
echo "Generating C header..."
cargo build --release  # Build for host to generate header

echo ""
echo "Creating XCFramework..."
rm -rf ../YinGif.xcframework

xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libyingif.a \
    -headers include \
    -library target/universal-ios-sim/libyingif.a \
    -headers include \
    -output ../YinGif.xcframework

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "XCFramework created at: ../YinGif.xcframework"
echo ""
echo "To integrate into Xcode:"
echo "1. Drag YinGif.xcframework into your Xcode project"
echo "2. Ensure it's added to your target's 'Frameworks, Libraries, and Embedded Content'"
echo "3. Set 'Embed' to 'Do Not Embed' (for static library)"
echo "4. Remove or comment out RustFFIStub.swift"
echo "5. Build and run!"
echo ""

# Verify the output
echo "Library info:"
file ../YinGif.xcframework/ios-arm64/libyingif.a | head -1
lipo -info ../YinGif.xcframework/ios-arm64-simulator/libyingif.a

echo ""
echo "Exported symbols (first 10):"
nm -gU ../YinGif.xcframework/ios-arm64/libyingif.a | grep "yingif_" | head -10
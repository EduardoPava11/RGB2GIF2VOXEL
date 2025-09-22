#!/bin/bash
set -e

echo "Building Rust library for iOS..."

# Set correct SDK paths
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"

# Build for iOS device (arm64)
echo "Building for iOS device (arm64)..."
cargo build --release --target aarch64-apple-ios

# Build for iOS Simulator (arm64)
echo "Building for iOS Simulator (arm64)..."
SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk" \
cargo build --release --target aarch64-apple-ios-sim

echo "✅ Rust library built successfully!"

# Verify symbols
echo ""
echo "Verifying exported symbols..."
nm -gU target/aarch64-apple-ios/release/libyingif_processor.a | grep -E "yingif_"

echo ""
echo "Build complete! Files:"
echo "  Device: target/aarch64-apple-ios/release/libyingif_processor.a"
echo "  Simulator: target/aarch64-apple-ios-sim/release/libyingif_processor.a"
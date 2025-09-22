#!/bin/bash

# Build Rust library for iOS
# This script is called from Xcode Build Phases

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_DIR/rust-core"

echo "Building Rust library for iOS..."

cd "$RUST_DIR"

# Determine architecture based on SDK
if [ "$PLATFORM_NAME" == "iphonesimulator" ]; then
    if [ "$ARCHS" == "arm64" ]; then
        TARGET="aarch64-apple-ios-sim"
    else
        TARGET="x86_64-apple-ios"
    fi
else
    TARGET="aarch64-apple-ios"
fi

echo "Building for target: $TARGET"

# Build the Rust library
cargo build --target "$TARGET" --release

# Copy the library to a known location
BUILT_LIB="$RUST_DIR/target/$TARGET/release/librgb2gif_processor.a"
OUTPUT_DIR="$PROJECT_DIR/ThirdParty/RustCore.xcframework/ios-arm64"

if [ "$PLATFORM_NAME" == "iphonesimulator" ]; then
    OUTPUT_DIR="$PROJECT_DIR/ThirdParty/RustCore.xcframework/ios-arm64-simulator"
fi

mkdir -p "$OUTPUT_DIR"
cp "$BUILT_LIB" "$OUTPUT_DIR/librgb2gif_processor.a"

echo "Rust library built successfully"
#!/bin/bash
# Build Rust library for iOS and generate Swift bindings

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
RUST_DIR="$PROJECT_ROOT/rust-core"
SWIFT_DIR="$PROJECT_ROOT/RGB2GIF2VOXEL/Bridge/Generated"

echo "🦀 Building Rust library for iOS..."

cd "$RUST_DIR"

# Build for iOS simulator (x86_64)
echo "Building for iOS Simulator (x86_64)..."
cargo build --target x86_64-apple-ios --release

# Build for iOS simulator (arm64)
echo "Building for iOS Simulator (arm64)..."
cargo build --target aarch64-apple-ios-sim --release

# Build for iOS device (arm64)
echo "Building for iOS Device (arm64)..."
cargo build --target aarch64-apple-ios --release

# Create universal library
echo "Creating universal library..."
mkdir -p "$PROJECT_ROOT/ThirdParty/RustCore.xcframework"

# Create simulator universal binary
lipo -create \
    target/x86_64-apple-ios/release/librgb2gif_processor.a \
    target/aarch64-apple-ios-sim/release/librgb2gif_processor.a \
    -output "$PROJECT_ROOT/ThirdParty/librgb2gif_processor_sim.a"

# Copy device binary
cp target/aarch64-apple-ios/release/librgb2gif_processor.a \
   "$PROJECT_ROOT/ThirdParty/librgb2gif_processor_device.a"

# Generate Swift bindings
echo "Generating Swift bindings..."
cargo run --bin uniffi-bindgen generate \
    src/rgb2gif.udl \
    --language swift \
    --out-dir "$SWIFT_DIR"

echo "✅ Rust library built and Swift bindings generated!"
echo "   Simulator library: $PROJECT_ROOT/ThirdParty/librgb2gif_processor_sim.a"
echo "   Device library: $PROJECT_ROOT/ThirdParty/librgb2gif_processor_device.a"
echo "   Swift bindings: $SWIFT_DIR/"
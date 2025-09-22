#!/bin/bash
# build-ios.sh - Build Rust library for iOS device and simulator

set -euo pipefail

echo "🦀 Building Rust library for iOS..."

# Ensure we have the required targets
echo "📦 Adding iOS targets..."
rustup target add aarch64-apple-ios aarch64-apple-ios-sim 2>/dev/null || true

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf target/aarch64-apple-ios/release
rm -rf target/aarch64-apple-ios-sim/release
rm -rf include

# Build for iOS device (arm64)
echo "📱 Building for iOS device (arm64)..."
cargo build --release --target aarch64-apple-ios

# Build for iOS simulator (arm64)
echo "💻 Building for iOS simulator (arm64)..."
cargo build --release --target aarch64-apple-ios-sim

# Create include directory
echo "📝 Generating C headers..."
mkdir -p include

# Generate C header with cbindgen
if command -v cbindgen >/dev/null 2>&1; then
    cbindgen --config cbindgen.toml --crate yingif_processor --output include/yingif_ffi.h
else
    echo "⚠️ cbindgen not found. Install with: cargo install cbindgen"
    # Create a basic header as fallback
    cat > include/yingif_ffi.h << 'EOF'
#ifndef YINGIF_FFI_H
#define YINGIF_FFI_H

#include <stdint.h>
#include <stddef.h>

/* Process batch of RGBA frames */
int yx_proc_batch_rgba8(
    const uint8_t* const* frames,
    int n,
    int width,
    int height,
    int target_side,
    int palette_size,
    uint8_t* out_indices,
    uint32_t* out_palettes
);

/* Encode to GIF89a */
int yx_gif_encode(
    const uint8_t* indices,
    const uint32_t* palettes,
    int n,
    int side,
    int delay_cs,
    uint8_t* out_buf,
    size_t* out_len
);

/* Legacy functions */
void* yingif_processor_new(void);
void yingif_processor_free(void* processor);
int yingif_process_frame(
    void* processor,
    const uint8_t* bgra_data,
    int width,
    int height,
    int target_size,
    int palette_size,
    uint8_t* out_indices,
    uint32_t* out_palette
);

#endif /* YINGIF_FFI_H */
EOF
fi

# Create XCFramework
echo "📦 Creating XCFramework..."
DEVICE_LIB="target/aarch64-apple-ios/release/libyingif_processor.a"
SIM_LIB="target/aarch64-apple-ios-sim/release/libyingif_processor.a"
HEADERS="include"
OUTPUT="../ThirdParty/RustCore.xcframework"

# Remove old XCFramework
rm -rf "$OUTPUT"

# Create ThirdParty directory if needed
mkdir -p ../ThirdParty

# Build XCFramework
xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" -headers "$HEADERS" \
    -library "$SIM_LIB" -headers "$HEADERS" \
    -output "$OUTPUT"

echo "✅ XCFramework created at: $OUTPUT"

# Verify exported symbols
echo ""
echo "🔍 Verifying exported symbols..."
echo "Device library symbols:"
nm -gU "$DEVICE_LIB" | grep -E "yx_|yingif_" | head -10

echo ""
echo "✅ Build complete!"
echo ""
echo "Next steps:"
echo "1. Add $OUTPUT to your Xcode project"
echo "2. Link it in 'Link Binary With Libraries'"
echo "3. Import yingif_ffi.h in your bridging header"
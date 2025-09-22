#!/bin/bash
# build_xcframeworks.sh - Path B: Build proper XCFrameworks with device + simulator slices
set -e

echo "🔨 Building XCFrameworks for RGB2GIF2VOXEL"
echo "=========================================="
echo ""

# Step 1: Build Rust for both device and simulator
echo "1️⃣ Building Rust library..."
cd rust-core

# Device (iOS arm64)
echo "   Building for iOS device (arm64)..."
cargo build --release --target aarch64-apple-ios

# Simulator (Apple Silicon)
echo "   Building for iOS simulator (arm64)..."
cargo build --release --target aarch64-apple-ios-sim

cd ..

# Step 2: Build Zig for both device and simulator
echo "2️⃣ Building Zig library..."

# Create build directories
mkdir -p build/ios-arm64 build/ios-arm64-simulator

# Device (iOS arm64)
echo "   Building for iOS device (arm64)..."
zig build-lib zig-core/yxcbor_simple.zig \
  -target aarch64-ios \
  -O ReleaseFast \
  --name yxcbor \
  -femit-bin=build/ios-arm64/libyxcbor.a

# Simulator (Apple Silicon)
echo "   Building for iOS simulator (arm64)..."
zig build-lib zig-core/yxcbor_simple.zig \
  -target aarch64-ios-simulator \
  -O ReleaseFast \
  --name yxcbor \
  -femit-bin=build/ios-arm64-simulator/libyxcbor.a

# Step 3: Create directories for headers
echo "3️⃣ Preparing headers..."
mkdir -p ThirdParty/Headers
cp yxcbor.h ThirdParty/Headers/
cp rust-core/src/yingif_ffi.h ThirdParty/Headers/ 2>/dev/null || true

# Step 4: Create XCFramework for Rust
echo "4️⃣ Creating RustCore.xcframework..."
rm -rf ThirdParty/RustCore.xcframework

xcodebuild -create-xcframework \
  -library rust-core/target/aarch64-apple-ios/release/libyingif_processor.a \
  -headers ThirdParty/Headers \
  -library rust-core/target/aarch64-apple-ios-sim/release/libyingif_processor.a \
  -headers ThirdParty/Headers \
  -output ThirdParty/RustCore.xcframework

# Step 5: Create XCFramework for Zig
echo "5️⃣ Creating ZigCore.xcframework..."
rm -rf ThirdParty/ZigCore.xcframework

xcodebuild -create-xcframework \
  -library build/ios-arm64/libyxcbor.a \
  -headers ThirdParty/Headers \
  -library build/ios-arm64-simulator/libyxcbor.a \
  -headers ThirdParty/Headers \
  -output ThirdParty/ZigCore.xcframework

# Step 6: Also copy rust_minimal if needed
if [ -f "rust-minimal/target/aarch64-apple-ios/release/librust_minimal.a" ]; then
    echo "6️⃣ Building rust_minimal for simulator..."
    cd rust-minimal
    cargo build --release --target aarch64-apple-ios-sim
    cd ..

    rm -rf ThirdParty/RustMinimal.xcframework
    xcodebuild -create-xcframework \
      -library rust-minimal/target/aarch64-apple-ios/release/librust_minimal.a \
      -library rust-minimal/target/aarch64-apple-ios-sim/release/librust_minimal.a \
      -output ThirdParty/RustMinimal.xcframework
fi

echo ""
echo "=========================================="
echo "✅ XCFrameworks Created!"
echo ""
echo "Contents:"
ls -la ThirdParty/*.xcframework/
echo ""
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Remove old library references"
echo "3. Add the new XCFrameworks to 'Frameworks, Libraries, and Embedded Content'"
echo "4. Build and run"
echo "=========================================="
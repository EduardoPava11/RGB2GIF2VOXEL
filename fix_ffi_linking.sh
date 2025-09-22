#!/bin/bash
# Fix FFI linking for RGB2GIF2VOXEL

echo "================================================"
echo "🔧 FIXING RUST FFI LINKING"
echo "================================================"

cd /Users/daniel/Documents/RGB2GIF2VOXEL

# 1. Rebuild the Rust library for iOS
echo "1. Building Rust library for iOS..."
cd rust-core
cargo build --release --target aarch64-apple-ios
cd ..

# 2. Create proper XCFramework structure
echo "2. Creating proper XCFramework..."
rm -rf ThirdParty/RustCore.xcframework
mkdir -p ThirdParty/RustCore.xcframework/ios-arm64
cp rust-core/target/aarch64-apple-ios/release/libyingif_processor.a ThirdParty/RustCore.xcframework/ios-arm64/
cp -r rust-core/include ThirdParty/RustCore.xcframework/ios-arm64/Headers

# 3. Create Info.plist for XCFramework
cat > ThirdParty/RustCore.xcframework/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>LibraryIdentifier</key>
            <string>ios-arm64</string>
            <key>LibraryPath</key>
            <string>libyingif_processor.a</string>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>ios</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

echo "✅ XCFramework structure created"
echo ""
echo "3. Verifying library symbols..."
nm -gU ThirdParty/RustCore.xcframework/ios-arm64/libyingif_processor.a | grep yingif | head -5

echo ""
echo "================================================"
echo "✅ RUST FFI FIXED!"
echo "================================================"

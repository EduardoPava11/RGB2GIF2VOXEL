#!/bin/bash
# fix_and_deploy.sh - Complete fix and deployment script

set -e

echo "🔧 Fixing RGB2GIF2VOXEL for iOS..."
echo ""

# 1. Clean
echo "1. Cleaning build..."
xcodebuild clean -project RGB2GIF2VOXEL.xcodeproj -quiet

# 2. Rebuild native libraries if needed
echo "2. Checking native libraries..."

if [ ! -f "ThirdParty/RustCore.xcframework/ios-arm64/libyingif_processor.a" ]; then
    echo "   Building Rust library..."
    cd rust-core
    cargo build --release --target aarch64-apple-ios
    cd ..
    mkdir -p ThirdParty/RustCore.xcframework/ios-arm64
    cp rust-core/target/aarch64-apple-ios/release/libyingif_processor.a \
       ThirdParty/RustCore.xcframework/ios-arm64/
fi

if [ ! -f "ThirdParty/ZigCore.xcframework/ios-arm64/libyxcbor.a" ]; then
    echo "   Building Zig library..."
    zig build-lib zig-core/yxcbor_simple.zig \
      -target aarch64-ios -O ReleaseFast -femit-h -lc
    mkdir -p ThirdParty/ZigCore.xcframework/ios-arm64
    mv libyxcbor_simple.a ThirdParty/ZigCore.xcframework/ios-arm64/libyxcbor.a
    mv yxcbor_simple.h ThirdParty/Headers/yxcbor.h 2>/dev/null || true
fi

echo "   ✅ Libraries ready"

# 3. Create proper XCFramework structure
echo "3. Setting up XCFrameworks..."

# Create Info.plist for RustCore
cat > ThirdParty/RustCore.xcframework/Info.plist << 'EOF'
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
EOF

# Create Info.plist for ZigCore
cat > ThirdParty/ZigCore.xcframework/Info.plist << 'EOF'
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
            <string>libyxcbor.a</string>
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
EOF

echo "   ✅ XCFrameworks configured"

# 4. Build for device
echo "4. Building for iPhone..."
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
  -scheme RGB2GIF2VOXEL \
  -configuration Debug \
  -destination "platform=iOS,id=1144544E-B1D8-5406-B5C1-25EDFBE26941" \
  -derivedDataPath build \
  EMBEDDED_CONTENT_CONTAINS_SWIFT=YES \
  ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="9WANULVN2G" \
  build

if [ $? -eq 0 ]; then
    echo "   ✅ Build succeeded"
else
    echo "   ❌ Build failed"
    exit 1
fi

# 5. Install
echo "5. Installing on iPhone..."
xcrun devicectl device install app \
  --device 1144544E-B1D8-5406-B5C1-25EDFBE26941 \
  build/Build/Products/Debug-iphoneos/RGB2GIF2VOXEL.app

if [ $? -eq 0 ]; then
    echo "   ✅ App installed"
else
    echo "   ❌ Installation failed"
    exit 1
fi

# 6. Launch
echo "6. Launching app..."
xcrun devicectl device process launch \
  --device 1144544E-B1D8-5406-B5C1-25EDFBE26941 \
  YIN.RGB2GIF2VOXEL

echo ""
echo "==============================="
echo "✅ Deployment Complete!"
echo ""
echo "Monitor logs with:"
echo "log stream --device --predicate 'subsystem == \"YIN.RGB2GIF2VOXEL\"'"
echo "==============================="
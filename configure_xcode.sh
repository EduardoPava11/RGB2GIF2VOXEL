#!/bin/bash
# Configure Xcode project with native libraries and bridging header

set -e

echo "📱 Configuring Xcode project..."

# Use xcodebuild to set build settings
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -configuration Debug \
    -showBuildSettings \
    > /dev/null 2>&1 || true

# Create xcconfig file for build settings
cat > RGB2GIF2VOXEL.xcconfig << 'EOF'
// Build settings for RGB2GIF2VOXEL

// Bridging Header
SWIFT_OBJC_BRIDGING_HEADER = RGB2GIF2VOXEL/RGB2GIF2VOXEL-Bridging-Header.h

// Header Search Paths
HEADER_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/ThirdParty/Headers

// Library Search Paths
LIBRARY_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64 $(PROJECT_DIR)/ThirdParty/ZigCore.xcframework/ios-arm64

// Other Linker Flags
OTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/ThirdParty/RustCore.xcframework/ios-arm64/libyingif_processor.a -force_load $(PROJECT_DIR)/ThirdParty/ZigCore.xcframework/ios-arm64/libyxcbor.a

// Framework Search Paths
FRAMEWORK_SEARCH_PATHS = $(inherited) $(PROJECT_DIR)/ThirdParty

// Enable Modules
CLANG_ENABLE_MODULES = YES

// Target iOS 17+
IPHONEOS_DEPLOYMENT_TARGET = 17.0

// Valid Architectures
VALID_ARCHS = arm64
EOF

echo "✅ Created xcconfig file"

# Try to build
echo "🔨 Testing build configuration..."
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -configuration Debug \
    -xcconfig RGB2GIF2VOXEL.xcconfig \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build \
    build 2>&1 | tail -20

echo "✅ Configuration complete!"
echo ""
echo "📲 Next steps:"
echo "   1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "   2. In Project Settings, set 'Based on Configuration File' to RGB2GIF2VOXEL.xcconfig"
echo "   3. Build and run on your iPhone"
#!/bin/bash
# add_xcframework.sh - Add RustCore.xcframework to Xcode project

set -euo pipefail

PROJECT_DIR="/Users/daniel/Documents/RGB2GIF2VOXEL"
XCFRAMEWORK_PATH="$PROJECT_DIR/ThirdParty/RustCore.xcframework"
PROJECT_FILE="$PROJECT_DIR/RGB2GIF2VOXEL.xcodeproj/project.pbxproj"

echo "📦 Adding RustCore.xcframework to Xcode project..."

# Check if XCFramework exists
if [ ! -d "$XCFRAMEWORK_PATH" ]; then
    echo "❌ XCFramework not found at: $XCFRAMEWORK_PATH"
    echo "   Please run rust-core/build-ios.sh first"
    exit 1
fi

# Check if already added (avoid duplicates)
if grep -q "RustCore.xcframework" "$PROJECT_FILE"; then
    echo "✅ RustCore.xcframework is already in the project"
else
    echo "⚠️  Manual step required:"
    echo ""
    echo "Please manually add the XCFramework to your Xcode project:"
    echo ""
    echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
    echo "2. Select the RGB2GIF2VOXEL target"
    echo "3. Go to 'General' tab"
    echo "4. Under 'Frameworks, Libraries, and Embedded Content', click '+'"
    echo "5. Click 'Add Other...' -> 'Add Files...'"
    echo "6. Navigate to: $XCFRAMEWORK_PATH"
    echo "7. Select 'RustCore.xcframework' and click 'Add'"
    echo "8. Ensure 'Embed & Sign' is selected"
    echo ""
    echo "The framework header is already imported in the bridging header."
fi

echo ""
echo "🔍 Verifying setup..."

# Check bridging header
if grep -q "RustCore/yingif_ffi.h" "$PROJECT_DIR/RGB2GIF2VOXEL/RGB2GIF2VOXEL-Bridging-Header.h"; then
    echo "✅ Bridging header correctly imports RustCore"
else
    echo "⚠️  Bridging header may need updating"
fi

# Check for FFI declarations
if [ -f "$PROJECT_DIR/RGB2GIF2VOXEL/Bridge/RustFFI.swift" ]; then
    echo "✅ RustFFI.swift with real function declarations exists"
else
    echo "⚠️  RustFFI.swift not found"
fi

echo ""
echo "✅ Setup verification complete!"
echo ""
echo "Next steps:"
echo "1. Add XCFramework to project if not already done (see instructions above)"
echo "2. Build and run the app"
echo "3. The app should now use real Rust implementations instead of stubs"
#!/bin/bash

# Build Configuration Verification Script
# Ensures the project is ready for Xcode build

echo "================================================"
echo "RGB2GIF2VOXEL Build Configuration Verification"
echo "================================================"
echo ""

ERRORS=0
WARNINGS=0

# Check for duplicate Info.plist files
echo "1. Checking for duplicate Info.plist files..."
INFO_COUNT=$(find . -name "Info.plist" -not -path "./DerivedData/*" -not -path "./build/*" -not -path "./.build/*" -not -path "./target/*" | wc -l)
if [ "$INFO_COUNT" -eq 1 ]; then
    echo "   ✅ Single Info.plist found at correct location"
else
    echo "   ❌ Found $INFO_COUNT Info.plist files (should be 1)"
    find . -name "Info.plist" -not -path "./DerivedData/*" -not -path "./build/*" -not -path "./.build/*" -not -path "./target/*"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check for README.md files in app directories
echo "2. Checking for README.md files in app directories..."
README_IN_APP=$(find ./RGB2GIF2VOXEL -name "*.md" -type f 2>/dev/null | wc -l)
if [ "$README_IN_APP" -eq 0 ]; then
    echo "   ✅ No .md files in RGB2GIF2VOXEL directory"
else
    echo "   ❌ Found $README_IN_APP .md files in RGB2GIF2VOXEL directory"
    find ./RGB2GIF2VOXEL -name "*.md" -type f
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check if .xcodeprojignore exists
echo "3. Checking .xcodeprojignore configuration..."
if [ -f ".xcodeprojignore" ]; then
    echo "   ✅ .xcodeprojignore exists"
    if grep -q "*.md" .xcodeprojignore; then
        echo "   ✅ .xcodeprojignore excludes .md files"
    else
        echo "   ⚠️  .xcodeprojignore may not exclude .md files"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo "   ❌ .xcodeprojignore not found"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check Rust library
echo "4. Checking Rust library build..."
RUST_LIB="rust-core/target/aarch64-apple-ios/release/librgb2gif_processor.a"
if [ -f "$RUST_LIB" ]; then
    echo "   ✅ Rust library found: librgb2gif_processor.a"
    SIZE=$(ls -lh "$RUST_LIB" | awk '{print $5}')
    echo "   📦 Size: $SIZE"
else
    echo "   ⚠️  Rust library not built for iOS"
    echo "   Run: cd rust-core && cargo build --target aarch64-apple-ios --release"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# Check UniFFI bindings
echo "5. Checking UniFFI generated files..."
UNIFFI_SWIFT="RGB2GIF2VOXEL/Bridge/Generated/rgb2gif.swift"
UNIFFI_HEADER="RGB2GIF2VOXEL/Bridge/Generated/rgb2gifFFI.h"
if [ -f "$UNIFFI_SWIFT" ] && [ -f "$UNIFFI_HEADER" ]; then
    echo "   ✅ UniFFI bindings found"
else
    echo "   ❌ UniFFI bindings missing"
    [ ! -f "$UNIFFI_SWIFT" ] && echo "   Missing: $UNIFFI_SWIFT"
    [ ! -f "$UNIFFI_HEADER" ] && echo "   Missing: $UNIFFI_HEADER"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check bridging header
echo "6. Checking bridging header..."
BRIDGING_HEADER="RGB2GIF2VOXEL/RGB2GIF2VOXEL-Bridging-Header.h"
if [ -f "$BRIDGING_HEADER" ]; then
    echo "   ✅ Bridging header found"
    if grep -q "rgb2gifFFI.h" "$BRIDGING_HEADER"; then
        echo "   ✅ Bridging header imports UniFFI"
    else
        echo "   ❌ Bridging header doesn't import rgb2gifFFI.h"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "   ❌ Bridging header not found"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Summary
echo "================================================"
echo "Summary:"
echo "================================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ Build configuration looks good!"
    echo ""
    echo "Next steps:"
    echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
    echo "2. Clean build folder (Shift+Cmd+K)"
    echo "3. Build (Cmd+B)"
elif [ $ERRORS -eq 0 ]; then
    echo "⚠️  Configuration has $WARNINGS warning(s) but should build"
    echo ""
    echo "Recommended actions:"
    [ ! -f "$RUST_LIB" ] && echo "• Build Rust library: cd rust-core && cargo build --target aarch64-apple-ios --release"
else
    echo "❌ Found $ERRORS error(s) that will prevent building"
    echo "   Please fix the errors above before building in Xcode"
fi
echo ""

exit $ERRORS
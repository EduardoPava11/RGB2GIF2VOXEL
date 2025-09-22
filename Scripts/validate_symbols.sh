#!/bin/bash

# Symbol validation script
# Ensures no duplicate definitions and correct linking

set -e

echo "🔍 Validating symbol definitions..."

# Function to check for duplicates
check_duplicates() {
    local pattern="$1"
    local name="$2"
    local count=$(grep -r "$pattern" RGB2GIF2VOXEL/ --include="*.swift" 2>/dev/null | wc -l)

    if [ $count -eq 0 ]; then
        echo "❌ $name not found!"
        return 1
    elif [ $count -gt 1 ]; then
        echo "❌ $name has $count definitions (should be 1)"
        grep -r "$pattern" RGB2GIF2VOXEL/ --include="*.swift" | head -5
        return 1
    else
        echo "✅ $name has exactly 1 definition"
        return 0
    fi
}

# Check each critical type
check_duplicates "class RustProcessor" "RustProcessor"
check_duplicates "struct QuantizedFrame" "QuantizedFrame"
check_duplicates "enum ProcessingError" "ProcessingError"

# Check deployment target
DEPLOY=$(grep "IPHONEOS_DEPLOYMENT_TARGET" RGB2GIF2VOXEL.xcodeproj/project.pbxproj | head -1)
if [[ "$DEPLOY" == *"17.0"* ]]; then
    echo "✅ iOS deployment target is correct (17.0)"
else
    echo "❌ Invalid deployment target: $DEPLOY"
    exit 1
fi

# Check Rust library exists
if [ -f "rust-core/target/aarch64-apple-ios/release/librust_core.a" ]; then
    echo "✅ Rust library found"

    # Check FFI symbols
    SYMBOLS=$(nm -g rust-core/target/aarch64-apple-ios/release/librust_core.a | grep -E "yx_proc_batch_rgba8|yx_gif_encode" | wc -l)
    if [ $SYMBOLS -eq 2 ]; then
        echo "✅ FFI symbols present"
    else
        echo "⚠️  Expected 2 FFI symbols, found $SYMBOLS"
    fi
else
    echo "⚠️  Rust library not built yet"
fi

echo ""
echo "✅ Symbol validation complete!"

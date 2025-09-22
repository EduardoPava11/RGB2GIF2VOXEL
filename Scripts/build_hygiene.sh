#!/bin/bash

# Enhanced Build Hygiene Check
# Add as Run Script Build Phase in Xcode

set -e  # Exit on first error

# Set SRCROOT if not set (for command line testing)
if [ -z "$SRCROOT" ]; then
    SRCROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

echo "🔍 Running comprehensive build hygiene check..."

# 1. Check for backup files
echo "Checking for backup files..."
BACKUP_FILES=$(find "${SRCROOT}/RGB2GIF2VOXEL" \
    -name "*.backup" -o \
    -name "*.bak" -o \
    -name "*.old" -o \
    -name "*~" \
    2>/dev/null | grep -v "/Legacy/" || true)

if [ ! -z "$BACKUP_FILES" ]; then
    echo "❌ Build failed: Backup files detected!"
    echo "$BACKUP_FILES"
    exit 1
fi

# 2. Check for duplicate type definitions
echo "Checking for duplicate types..."
check_duplicates() {
    local type_name=$1
    local files=$(find "${SRCROOT}/RGB2GIF2VOXEL" \
        -name "*.swift" \
        -not -path "*/Legacy/*" \
        -exec grep -l "^public struct ${type_name}[[:space:]]*{\|^struct ${type_name}[[:space:]]*{\|^public class ${type_name}[[:space:]]*{\|^class ${type_name}[[:space:]]*{\|^public enum ${type_name}[[:space:]]*{\|^enum ${type_name}[[:space:]]*{" {} \; 2>/dev/null)

    local count=$(echo "$files" | grep -v "^$" | wc -l)

    if [ "$count" -gt 1 ]; then
        echo "❌ Multiple definitions of $type_name found:"
        echo "$files"
        return 1
    fi
    return 0
}

# Check critical types
check_duplicates "CubeTensorData" || exit 1
check_duplicates "CubeTensor" || exit 1
check_duplicates "QuantizedFrame" || exit 1

# 3. Check for legacy type references in active code
echo "Checking for legacy type usage..."
LEGACY_REFS=$(find "${SRCROOT}/RGB2GIF2VOXEL" \
    -name "*.swift" \
    -not -path "*/Legacy/*" \
    -exec grep -l "DownsizeOption\|PaletteOption\|FrontCameraManager\|SquareCameraView" {} \; 2>/dev/null || true)

if [ ! -z "$LEGACY_REFS" ]; then
    echo "❌ Active code references legacy types:"
    echo "$LEGACY_REFS"
    exit 1
fi

# 4. Verify required files exist
echo "Verifying core files..."
REQUIRED_FILES=(
    "RGB2GIF2VOXEL/Models/CubeTensorData.swift"
    "RGB2GIF2VOXEL/Camera/CubeCameraManager.swift"
    "RGB2GIF2VOXEL/Camera/CubeClipController.swift"
    "RGB2GIF2VOXEL/Camera/CubePolicy.swift"
    "RGB2GIF2VOXEL/Camera/CubeTensor.swift"
    "RGB2GIF2VOXEL/Bridge/RustFFI.swift"
    "RGB2GIF2VOXEL/Bridge/GIF89aEncoder.swift"
    "RGB2GIF2VOXEL/Views/CubeCameraView.swift"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${SRCROOT}/$file" ]; then
        echo "❌ Required file missing: $file"
        exit 1
    fi
done

# 5. Count active vs legacy files
ACTIVE_COUNT=$(find "${SRCROOT}/RGB2GIF2VOXEL" \
    -name "*.swift" \
    -not -path "*/Legacy/*" \
    -type f | wc -l)

LEGACY_COUNT=$(find "${SRCROOT}/RGB2GIF2VOXEL/Legacy" \
    -name "*.swift" \
    -type f 2>/dev/null | wc -l)

echo "📊 File counts:"
echo "  Active Swift files: $ACTIVE_COUNT"
echo "  Legacy files (excluded): $LEGACY_COUNT"

# 6. Warning for common mistakes
if [ -f "${SRCROOT}/RGB2GIF2VOXEL/Camera/FrameProcessor.swift" ]; then
    echo "⚠️  Warning: FrameProcessor.swift should be in Legacy folder"
fi

echo "✅ Build hygiene check passed!"
echo "   - No backup files"
echo "   - No duplicate types"
echo "   - No legacy references"
echo "   - All core files present"
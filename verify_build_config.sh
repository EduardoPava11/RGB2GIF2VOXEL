#!/bin/bash
#
# Build Configuration Verification Script
# Ensures no duplicate types or conflicting files
#

echo "========================================="
echo "RGB2GIF2VOXEL Build Configuration Check"
echo "========================================="
echo

# Check 1: Ensure Log.swift.disabled doesn't exist
echo "✓ Checking for disabled files..."
if [ -f "RGB2GIF2VOXEL/Utils/Log.swift.disabled" ]; then
    echo "  ❌ ERROR: Log.swift.disabled still exists!"
    echo "     Remove it from the project and file system"
    exit 1
else
    echo "  ✅ No disabled files found"
fi
echo

# Check 2: Ensure only one VImageDownsampler exists
echo "✓ Checking VImageDownsampler..."
VIMAGE_COUNT=$(find RGB2GIF2VOXEL -name "VImageDownsampler*.swift" -type f | wc -l)
if [ $VIMAGE_COUNT -gt 1 ]; then
    echo "  ❌ ERROR: Multiple VImageDownsampler files found:"
    find RGB2GIF2VOXEL -name "VImageDownsampler*.swift" -type f
    exit 1
else
    echo "  ✅ Single VImageDownsampler: RGB2GIF2VOXEL/Pipeline/VImageDownsampler.swift"
fi
echo

# Check 3: Ensure only Logging.swift exists (no Log.swift)
echo "✓ Checking Log types..."
if [ -f "RGB2GIF2VOXEL/Utils/Log.swift" ]; then
    echo "  ❌ ERROR: Log.swift still exists!"
    echo "     Remove it from the project"
    exit 1
fi

if [ ! -f "RGB2GIF2VOXEL/Core/Logging.swift" ]; then
    echo "  ❌ ERROR: Logging.swift not found!"
    exit 1
else
    echo "  ✅ Only Logging.swift exists (enum Log)"
fi
echo

# Check 4: Verify consistent subsystem
echo "✓ Checking subsystem consistency..."
WRONG_SUBSYSTEM=$(grep -r "com\.rgb2gif2voxel" --include="*.swift" RGB2GIF2VOXEL | wc -l)
if [ $WRONG_SUBSYSTEM -gt 0 ]; then
    echo "  ❌ ERROR: Found files with wrong subsystem:"
    grep -l "com\.rgb2gif2voxel" --include="*.swift" -r RGB2GIF2VOXEL
    echo "     Should be: com.yingif.rgb2gif2voxel"
    exit 1
else
    echo "  ✅ All files use correct subsystem: com.yingif.rgb2gif2voxel"
fi
echo

# Check 5: Look for duplicate Swift filenames
echo "✓ Checking for duplicate filenames..."
DUPLICATES=$(find RGB2GIF2VOXEL -name "*.swift" -type f | sed 's/.*\///' | sort | uniq -d)
if [ ! -z "$DUPLICATES" ]; then
    echo "  ❌ ERROR: Duplicate filenames found:"
    echo "$DUPLICATES"
    exit 1
else
    echo "  ✅ No duplicate Swift filenames"
fi
echo

# Check 6: Verify key imports
echo "✓ Checking imports..."
FILES_USING_LOG=$(grep -l "Log\.\(app\|camera\|pipeline\|gif\|ffi\|ui\|processing\)" --include="*.swift" -r RGB2GIF2VOXEL)
for file in $FILES_USING_LOG; do
    if ! grep -q "^import os" "$file"; then
        echo "  ⚠️  WARNING: $file uses Log but doesn't import os"
    fi
done
echo "  ✅ Import check complete"
echo

echo "========================================="
echo "✅ BUILD CONFIGURATION VERIFIED"
echo "========================================="
echo
echo "Next steps:"
echo "1. Open RGB2GIF2VOXEL.xcodeproj in Xcode"
echo "2. Clean Build Folder (Shift+Cmd+K)"
echo "3. Build (Cmd+B)"
echo
echo "The project is configured for:"
echo "• N=128 optimal frame capture"
echo "• 128×128 downsampling"
echo "• GIF89a generation"
echo "• 128³ voxel visualization"
#!/bin/bash

# Build hygiene check script
# Add this as a Run Script Build Phase in Xcode to prevent backup files from being compiled

echo "🔍 Checking build hygiene..."

# Check for backup files
BACKUP_FILES=$(find "${SRCROOT}/RGB2GIF2VOXEL" -name "*.backup" -o -name "*.bak" -o -name "*.old" 2>/dev/null)

if [ ! -z "$BACKUP_FILES" ]; then
    echo "❌ Build failed: Backup files detected in project!"
    echo "Please remove the following files:"
    echo "$BACKUP_FILES"
    exit 1
fi

# Check for files in Legacy directory being compiled
if [ -d "${SRCROOT}/RGB2GIF2VOXEL/Legacy" ]; then
    echo "⚠️  Warning: Legacy directory exists. Ensure these files are not in the build target."
fi

# Verify single CubeTensorData definition
TENSOR_DEFS=$(find "${SRCROOT}/RGB2GIF2VOXEL" -name "*.swift" -path "*/Legacy/*" -prune -o -exec grep -l "struct CubeTensorData" {} \; | grep -v "/Legacy/")
DEF_COUNT=$(echo "$TENSOR_DEFS" | grep -v "^$" | wc -l)

if [ "$DEF_COUNT" -gt 1 ]; then
    echo "❌ Build failed: Multiple CubeTensorData definitions found!"
    echo "$TENSOR_DEFS"
    exit 1
fi

echo "✅ Build hygiene check passed"
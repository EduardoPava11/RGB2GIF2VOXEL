#!/bin/bash

# Script to clean up .excluded and .original backup files
# These are causing Xcode build errors with File System Synchronized Groups

echo "🧹 Cleaning up excluded and backup files..."

# Find and remove .excluded files
echo "Removing .excluded files:"
find /Users/daniel/Documents/RGB2GIF2VOXEL -name "*.excluded" -type f | while read -r file; do
    echo "  - $(basename "$file")"
    rm "$file"
done

# Find and remove .original files
echo "Removing .original files:"
find /Users/daniel/Documents/RGB2GIF2VOXEL -name "*.original" -type f | while read -r file; do
    echo "  - $(basename "$file")"
    rm "$file"
done

echo "✅ Cleanup complete!"
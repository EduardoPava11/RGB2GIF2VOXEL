#!/bin/bash
# Clean build without problematic device libraries

echo "Cleaning build..."
xcodebuild clean -project RGB2GIF2VOXEL.xcodeproj -scheme RGB2GIF2VOXEL

echo "Moving device libraries out of the way..."
cd /Users/daniel/Documents/RGB2GIF2VOXEL/RGB2GIF2VOXEL/Frameworks
mv librgb2gif_processor.a.device librgb2gif_processor.a.device.bak 2>/dev/null || true

echo "Building for simulator..."
xcodebuild -project ../../RGB2GIF2VOXEL.xcodeproj \
    -scheme RGB2GIF2VOXEL \
    -sdk iphonesimulator \
    -configuration Debug \
    -arch arm64 \
    build \
    OTHER_LDFLAGS="-lyingif_processor -lrust_minimal -lrgb2gif_processor" \
    LIBRARY_SEARCH_PATHS="/Users/daniel/Documents/RGB2GIF2VOXEL/RGB2GIF2VOXEL/Frameworks"

echo "Build complete!"
#!/bin/bash

# Build validation script - ensures no duplicate symbols

echo "🔍 Validating build system..."

# Check for duplicate class definitions
echo "Checking for duplicate YinGifProcessor definitions..."
YINGIF_COUNT=$(grep -r "class YinGifProcessor" RGB2GIF2VOXEL/ --include="*.swift" | wc -l)
if [ $YINGIF_COUNT -gt 1 ]; then
    echo "❌ Found $YINGIF_COUNT YinGifProcessor definitions (should be 1)"
    grep -r "class YinGifProcessor" RGB2GIF2VOXEL/ --include="*.swift"
    exit 1
fi

echo "Checking for duplicate QuantizedFrame definitions..."
FRAME_COUNT=$(grep -r "struct QuantizedFrame" RGB2GIF2VOXEL/ --include="*.swift" | wc -l) 
if [ $FRAME_COUNT -gt 1 ]; then
    echo "❌ Found $FRAME_COUNT QuantizedFrame definitions (should be 1)"
    grep -r "struct QuantizedFrame" RGB2GIF2VOXEL/ --include="*.swift"
    exit 1
fi

# Check deployment target
echo "Checking iOS deployment target..."
DEPLOY_TARGET=$(grep "IPHONEOS_DEPLOYMENT_TARGET" RGB2GIF2VOXEL.xcodeproj/project.pbxproj | head -1)
if [[ $DEPLOY_TARGET == *"26.0"* ]]; then
    echo "❌ Invalid deployment target: $DEPLOY_TARGET"
    exit 1
fi

# Try to build
echo "Testing compilation..."
xcodebuild -project RGB2GIF2VOXEL.xcodeproj \
           -scheme RGB2GIF2VOXEL \
           -sdk iphonesimulator \
           -configuration Debug \
           build > /tmp/build_test.log 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Build validation passed"
else
    echo "❌ Build failed - check /tmp/build_test.log"
    tail -20 /tmp/build_test.log
    exit 1
fi

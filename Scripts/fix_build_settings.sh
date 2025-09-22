#!/bin/bash

echo "Fixing build settings for RGB2GIF2VOXEL..."

# Disable preview builds
xcodebuild -project RGB2GIF2VOXEL.xcodeproj -target RGB2GIF2VOXEL -configuration Debug -showBuildSettings | grep -E "ENABLE_PREVIEWS|ENABLE_DEBUG_DYLIB"

# Set the build settings
xcodebuild -project RGB2GIF2VOXEL.xcodeproj -target RGB2GIF2VOXEL -configuration Debug \
  ENABLE_PREVIEWS=NO \
  ENABLE_DEBUG_DYLIB=NO \
  -allowProvisioningUpdates

echo "Build settings updated"

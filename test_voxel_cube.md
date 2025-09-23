# Voxel Cube Testing Guide

## Test Steps

1. **Build and Run the App**
   - Open `RGB2GIF2VOXEL.xcodeproj` in Xcode
   - Select your iPhone as the target device
   - Press Cmd+R to build and run

2. **Capture a GIF**
   - Tap the capture button to start recording
   - Move the camera around to capture frames
   - Tap the capture button again to stop
   - Wait for GIF processing to complete

3. **Look for Debug Output**
   Check the Xcode console for these key messages:

   **From Rust (during GIF creation):**
   ```
   [RUST] Building tensor for voxel visualization...
   [RUST]   Frame count: [number]
   [RUST]   Frame dimensions: 256x256
   [RUST]   Tensor size: [bytes]
   [RUST]   Contains non-zero data: true
   ```

   **From Swift (when GIF is ready):**
   ```
   ✅ VOXEL TENSOR DATA READY FOR VISUALIZATION!
      Size: 67108864 bytes
      Expected: 67108864 bytes
      Match: YES ✅
   ```

   **When pressing "View 256³ Voxel Cube" button:**
   ```
   🔮 VOXEL CUBE BUTTON PRESSED!
      Tensor data available: YES
      Raw tensor size: 67108864 bytes
      Contains non-zero data: YES ✅
   ```

   **In the Voxel Visualization Screen:**
   ```
   🎯 VoxelVisualizationScreen INITIALIZED!
   🔨 Creating voxel cloud from tensor data...
      Has non-zero data: YES ✅
   ✅ Created voxel cloud with [number] visible points!
   ```

4. **What You Should See**

   - **IF WORKING:** A 3D point cloud of colored voxels representing your captured frames
   - **IF DEBUG CUBE:** A rotating purple cube (means SceneKit works but tensor data is empty)
   - **IF BLACK SCREEN:** Check that tensor data is being generated

## Troubleshooting

### Problem: No voxel cube appears
**Solution:** Check console for "Contains non-zero data: NO" messages. This means:
- The frames might be all black
- The tensor generation might be failing
- The alpha channel might be 0

### Problem: Debug purple cube appears instead
**Solution:** This means SceneKit is working but your tensor has no visible voxels:
- Check that you're capturing actual camera frames (not blank frames)
- Verify the frames have color data
- Check the alpha threshold in `createVoxelCloud()`

### Problem: Very few points visible
**Solution:** The sampling stride might be too large:
- In `VoxelVisualizationScreen.swift`, line ~391
- Change `sampleStride` from 4 to 2 for more points
- Or from 4 to 8 for fewer but faster rendering

### Problem: Points too small to see
**Solution:** Adjust point size in `createPointCloud()`:
- Line ~472: `element.pointSize = 5.0` (increase to 10.0)
- Line ~473: `element.minimumPointScreenSpaceRadius = 2.0` (increase to 5.0)

## Key Files Modified

1. **rust-core/src/lib.rs**
   - Added comprehensive debug logging
   - Ensured tensor generation for 256×256×256 cube
   - Verified tensor contains actual data

2. **RGB2GIF2VOXEL/Voxel/VoxelVisualizationScreen.swift**
   - Added debug logging throughout
   - Created debug cube for verification
   - Improved point visibility settings
   - Better camera positioning

3. **RGB2GIF2VOXEL/Views/CubeCameraView.swift**
   - Enhanced voxel button with debug output
   - Verified tensor data before showing voxel viewer
   - Added data validation checks

## Expected Tensor Size
- 256 × 256 × 256 × 4 (RGBA) = 67,108,864 bytes
- This represents 16,777,216 voxels in a 256³ cube
- Each voxel has RGBA color (4 bytes)

## Visual Enhancements Applied
- Dynamic color palette extraction from GIF
- Liquid Glass UI with translucent materials
- Animated gradient backgrounds
- Multiple visualization modes (point cloud, volumetric, etc.)
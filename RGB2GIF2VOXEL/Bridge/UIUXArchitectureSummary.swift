//
//  UIUXArchitectureSummary.swift
//  RGB2GIF2VOXEL
//
//  Documentation-only file summarizing the Swift UI/UX architecture.
//  This describes how the user interface, rendering, capture pipeline,
//  and export flows are structured and connected.
//

/*
 UI/UX Architecture Summary (Swift Layer)

 1) High-Level UI Modules

 - VoxelViewerView (SwiftUI)
   • Primary user-facing screen for viewing voxel content and exporting files.
   • Responsibilities:
     - Present view mode selector (Isometric, Orthographic Front/Top/Side, Perspective, Animated).
     - Host SceneKit content via VoxelSceneView (UIViewRepresentable).
     - Show basic HUD (e.g., frame counter in animated mode).
     - Provide export actions (USDZ, OBJ, YXV) with a share sheet.
   • State:
     - @StateObject voxelEngine (VoxelRenderEngine) – source of truth for voxel data and rendering state.
     - UI flags for export menus, share sheet, and error messaging.

 - VoxelSceneView (UIViewRepresentable)
   • Bridges SwiftUI to SceneKit (SCNView).
   • Responsibilities:
     - Create and configure SCNView + SCNScene.
     - Add a camera and a placeholder voxel node.
     - On updates, apply transforms supplied by VoxelRenderEngine for the selected view mode.
     - In animated mode, reflect current frame index in any future per-frame visualization.

 - ShareSheet (UIViewControllerRepresentable)
   • Presents UIActivityViewController for quick file sharing (USDZ/OBJ/YXV exports).

 2) Rendering and View-State Management

 - VoxelRenderEngine (@MainActor, ObservableObject)
   • Acts as the rendering view model/controller.
   • Responsibilities:
     - Hold current voxel dataset (VoxelData: dimensions, indices, palette).
     - Publish UI state: currentViewMode, rotation (for perspective), isAnimating, currentFrame.
     - Compute transforms for each view mode:
       · Isometric (45° Y, 35.264° X)
       · Orthographic (front/top/side)
       · Perspective (applies user drag-based rotations)
       · Animated (identity; frame index drives visual change)
     - Basic animation loop using Timer ~30 FPS, advancing currentFrame within [0, depth).
     - Export helpers:
       · exportUSDZ(): Builds an MDLAsset (placeholder cube mesh for now) and writes .usdz to Documents.
       · exportOBJ(): Writes a minimal .obj file to Documents.
     - Data loading:
       · loadVoxelData(from: CubeTensorData) converts canonical tensor to VoxelData.
       · (Future) loadVoxelData(from: URL) to support YXVReader.

   • Data model (internal):
     - VoxelData: dimensions (width, height, depth), indices (Data of palette indices), palette ([UInt32]).
     - Provides slice extraction helpers for future visualization (XY/XZ/YZ planes).

 3) Capture Orchestration and Export Integration

 - CaptureCoordinator (@MainActor, ObservableObject)
   • Orchestrates camera capture and downstream processing; exposes UI-friendly state.
   • Responsibilities:
     - Owns CubeCameraManager and binds its state (isCapturing, currentFPS, captureProgress).
     - Publishes generatedGIF data for sharing.
     - Provides:
       · setupCamera(), startCapture(), stopCapture() – lifecycle control.
       · generateGIF(): Converts a built CubeTensorData into a GIF via GIF89aEncoder.
       · exportYXV(tensor: CubeTensorData) – writes a YXV file (via YXVWriter in YXVIO_Simple).

   • UI usage:
     - VoxelViewerView calls exportYXV() when the user chooses YXV in the export dialog.
     - Other screens (not shown) could trigger capture or GIF generation and observe published state.

 - CubeCameraManager (ObservableObject) [see CubeCameraManager_Updated.swift]
   • Encapsulates AVFoundation setup and frame capture with focus on square formats.
   • Responsibilities:
     - Discover the best front camera (TrueDepth preferred).
     - Select the best native 1:1 format; otherwise configure for center-crop to square.
     - Configure BGRA output, frame rate, and connection parameters (portrait, mirrored, no stabilization).
     - Stream frames to YinGifProcessor (Rust FFI) for downsize + quantization.
     - Ingest results into a clip controller to assemble the N×N×N voxel tensor.
     - Publish FPS and capture progress for UI.

 4) User Interactions and Data Flow

 - Viewing:
   • VoxelViewerView initializes VoxelRenderEngine and calls loadVoxelData(from: CubeTensorData) when a tensor is available.
   • The user selects a view mode; VoxelRenderEngine updates transforms accordingly.
   • In Perspective mode, drag gestures update VoxelRenderEngine.rotation for real-time rotation.
   • In Animated mode, a Timer advances currentFrame and UI displays a frame counter overlay.

 - Exporting:
   • USDZ: VoxelRenderEngine.exportUSDZ() → creates MDLAsset with placeholder mesh → writes to Documents → ShareSheet.
   • OBJ: VoxelRenderEngine.exportOBJ() → writes simple OBJ text → ShareSheet.
   • YXV: CaptureCoordinator.exportYXV(tensor:) → YXVWriter (YXVIO_Simple) → writes YXV to Documents → ShareSheet.
   • ShareSheet wraps UIActivityViewController for user to save/share.

 - Capturing (UI perspective):
   • A capture UI (not shown here) would instruct CaptureCoordinator to setup/start capture.
   • CubeCameraManager streams frames; optionally crops to square.
   • Frames are processed via Rust FFI (YinGifProcessor) and ingested to build the voxel tensor.
   • Once N frames are collected, CaptureCoordinator can generate GIFs or export YXV.

 5) External Boundaries (as seen from the UI)

 - Rust FFI (YinGifProcessor, RustFFI.swift, RustFFIStub.swift)
   • From the UI’s standpoint, Rust provides:
     - processFrameAsync(...) to convert BGRA frames into quantized frames (indices + palette).
     - GIF encoding via GIF89aEncoder (thin Swift wrapper around FFI).
   • RustFFIStub.swift provides fallback stub implementations when the Rust library isn’t linked, enabling UI development without Rust.

 - YXV I/O
   • YXVIO_Simple.swift provides a FlatBuffers-free YXV writer for now, used by CaptureCoordinator.
   • A FlatBuffers-based YXVIO.swift exists but currently requires adding the FlatBuffers package. Until then, the simple path keeps UI exports working.

 6) State, Concurrency, and Performance

 - State Management:
   • SwiftUI + Combine: Views observe @Published properties in VoxelRenderEngine and CaptureCoordinator.
   • CaptureCoordinator binds to CubeCameraManager publishers for FPS and progress indicators.

 - Concurrency:
   • Camera session and video data are handled on dedicated queues (sessionQueue, videoDataQueue).
   • Frame processing uses async/await via YinGifProcessor.processFrameAsync and Task.detached; UI updates are marshaled back to the main actor.
   • Exports run asynchronously and return URLs for sharing.

 - Performance Considerations (UI layer):
   • Minimal work on the main thread; heavy lifting is offloaded to background queues/Rust.
   • SceneKit updates are lightweight (transform changes); mesh generation is a future optimization target (Rust-backed).
   • Animated mode uses a fixed Timer; can be adapted to display link or SceneKit timing if needed.

 7) Extensibility and Future Enhancements

 - Rendering:
   • Replace placeholder cube with real voxel geometry (instancing or merged mesh).
   • Colorize geometry from the palette and index data; support per-frame visualization.

 - File I/O:
   • Implement YXVReader for loading voxel files back into the UI.
   • Migrate to FlatBuffers-based headers when package/schema are integrated.

 - Capture UI:
   • Build a dedicated capture screen with live preview, progress, FPS, error reporting.
   • Provide controls for cube size, palette size, and export preferences.

 - Testing:
   • Add Swift Testing suites for transforms, export flows, and capture orchestration.
   • Provide UI previews for VoxelViewerView in various states and modes.

 Summary:
 The UI/UX layer centers on VoxelViewerView (SwiftUI) for presentation and VoxelRenderEngine for rendering state and exports. CaptureCoordinator orchestrates the camera pipeline and integrates exports (GIF/YXV). SceneKit is bridged via UIViewRepresentable for flexible rendering. Rust and (future) Zig services appear as clearly defined boundaries from the UI’s perspective, allowing Swift to remain focused on user interaction, rendering orchestration, and platform integration.
*/

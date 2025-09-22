// Bridge Module - Central import point for Rust FFI
// This file ensures all Rust bindings are properly accessible

import Foundation

// MARK: - Module Setup Instructions
/*
 To use the Rust processor in your Swift code:

 1. Ensure the generated files are added to your Xcode target:
    - Bridge/Generated/rgb2gif.swift
    - Bridge/Generated/rgb2gifFFI.h

 2. Add the module map to your build settings:
    - Build Settings → Swift Compiler - Search Paths
    - Import Paths: $(PROJECT_DIR)/RGB2GIF2VOXEL/Bridge/Generated

 3. For the C header, ensure the bridging header includes:
    #import "rgb2gifFFI.h"

 4. Import this module in files that need Rust functionality:
    import Foundation
    // The types will be available in the same module
 */

// MARK: - Type Verification
// These extensions verify that the UniFFI types are available
#if DEBUG
extension ProcessorOptions {
    static func makeDefault() -> ProcessorOptions {
        return ProcessorOptions(
            quantize: QuantizeOpts(
                qualityMin: 70,
                qualityMax: 100,
                speed: 5,
                paletteSize: 256,
                ditheringLevel: 1.0,
                sharedPalette: true
            ),
            gif: GifOpts(
                width: 256,
                height: 256,
                frameCount: 256,
                fps: 30,
                loopCount: 0,
                optimize: true,
                includeTensor: false
            ),
            parallel: true
        )
    }
}
#endif
//
//  CompilationTest.swift  
//  RGB2GIF2VOXEL
//
//  Test to verify type visibility
//

import Foundation

// Simple test to verify our types are visible
class CompilationTest {
    
    func testTypeVisibility() {
        // Test CaptureMetrics
        let metrics = CaptureMetrics()
        
        // Test YinGifProcessor  
        let processor = YinGifProcessor()
        
        // Test PipelineError
        let error = PipelineError.processingFailed("Invalid input")
        
        // Test QuantizedFrame
        let frame = QuantizedFrame(index: 0, data: Data(repeating: 0xFF, count: 256 * 256 * 4), width: 256, height: 256)
        
        print("All types visible: \(metrics), \(processor), \(error), \(frame)")
    }
}
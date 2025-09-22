//
//  FrameSaver.swift
//  RGB2GIF2VOXEL
//
//  Wrapper that delegates to SwiftCBORFrameSaver for native Swift CBOR implementation
//

import Foundation
import CoreVideo
import Combine

/// Frame saver using native Swift CBOR implementation
@MainActor
public class FrameSaver: ObservableObject {

    // Delegate to Swift implementation
    private let swiftImplementation = SwiftCBORFrameSaver()

    // MARK: - Published Properties

    @Published public var isWriterOpen: Bool = false
    @Published public var framesSaved: Int = 0

    // Forward state from implementation
    private func syncState() {
        isWriterOpen = swiftImplementation.isWriterOpen
        framesSaved = swiftImplementation.framesSaved
    }

    // MARK: - Public API

    public init() {}

    public func openWriter(sessionId: String, frameCount: Int, width: Int, height: Int) throws {
        try swiftImplementation.openWriter(
            sessionId: sessionId,
            frameCount: frameCount,
            width: width,
            height: height
        )
        syncState()
    }

    public func saveFrame(pixelBuffer: CVPixelBuffer, frameIndex: Int) throws {
        try swiftImplementation.saveFrame(pixelBuffer: pixelBuffer, frameIndex: frameIndex)
        syncState()
    }

    public func closeWriter() {
        swiftImplementation.closeWriter()
        syncState()
    }
}
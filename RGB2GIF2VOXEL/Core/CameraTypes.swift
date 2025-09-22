//
//  CameraTypes.swift
//  RGB2GIF2VOXEL
//
//  Camera-related type definitions
//

import Foundation
import AVFoundation
import Combine

/// Information about a camera format
public struct CameraFormatInfo {
    public let width: Int
    public let height: Int
    public let cleanApertureWidth: Int
    public let cleanApertureHeight: Int
    public let isNativeSquare: Bool
    public let needsCrop: Bool
    public let fps: Double
    public let maxFPS: Int
    public let minISO: Float
    public let maxISO: Float
    public let activeColorSpace: AVCaptureColorSpace

    public init(width: Int, height: Int, cleanApertureWidth: Int, cleanApertureHeight: Int, isNativeSquare: Bool, needsCrop: Bool, fps: Double, maxFPS: Int = 30, minISO: Float = 0, maxISO: Float = 0, activeColorSpace: AVCaptureColorSpace = .sRGB) {
        self.width = width
        self.height = height
        self.cleanApertureWidth = cleanApertureWidth
        self.cleanApertureHeight = cleanApertureHeight
        self.isNativeSquare = isNativeSquare
        self.needsCrop = needsCrop
        self.fps = fps
        self.maxFPS = maxFPS
        self.minISO = minISO
        self.maxISO = maxISO
        self.activeColorSpace = activeColorSpace
    }
}

/// Capture metrics tracking
@MainActor
public class CaptureMetrics: ObservableObject {
    @Published public var frameProcessingTime: [TimeInterval] = []
    @Published public var framesProcessed: Int = 0
    @Published public var droppedFrames: Int = 0
    @Published public var lastFrameTime: TimeInterval = 0
    @Published public var averageFPS: Double = 0
    @Published public var thermalState: ProcessInfo.ThermalState = .nominal
    @Published public var memoryPressure: Float = 0.0

    private let maxSamples = 100

    public init() {}

    public func recordFrameTime(_ time: TimeInterval) {
        frameProcessingTime.append(time)
        if frameProcessingTime.count > maxSamples {
            frameProcessingTime.removeFirst()
        }
        
        // Update average FPS
        let recentTimes = Array(frameProcessingTime.suffix(10))
        if !recentTimes.isEmpty {
            let avgTime = recentTimes.reduce(0, +) / Double(recentTimes.count)
            averageFPS = avgTime > 0 ? 1.0 / avgTime : 0.0
        }
    }
    
    public func incrementDroppedFrames() {
        droppedFrames += 1
    }
}

/// Capture progress information
public struct CaptureProgress {
    public let currentFrame: Int
    public let totalFrames: Int
    public let stage: String

    public init(currentFrame: Int, totalFrames: Int, stage: String) {
        self.currentFrame = currentFrame
        self.totalFrames = totalFrames
        self.stage = stage
    }
}
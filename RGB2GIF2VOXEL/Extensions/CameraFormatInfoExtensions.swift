//
//  CameraFormatInfoExtensions.swift
//  RGB2GIF2VOXEL
//
//  Extensions for CameraFormatInfo
//

import Foundation
import AVFoundation

extension CameraFormatInfo {
    /// Display text for the format
    var displayText: String {
        return "\(width)×\(height) @\(maxFPS)fps"
    }
}
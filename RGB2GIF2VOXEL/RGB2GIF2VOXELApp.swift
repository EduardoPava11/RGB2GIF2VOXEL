//
//  RGB2GIF2VOXELApp.swift
//  RGB2GIF2VOXEL
//
//  Created by Daniel on 2025-09-20.
//

import SwiftUI
import AVFoundation

@main
struct RGB2GIF2VOXELApp: App {
    init() {
        // Configure AVAudioSession for camera
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                            options: [.defaultToSpeaker, .mixWithOthers])
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

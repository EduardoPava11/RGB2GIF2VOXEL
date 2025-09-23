//
//  ContentView.swift
//  RGB2GIF2VOXEL
//
//  Simple entry point with clean UI/UX
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        // Use unified capture with proper frame handling
        UnifiedCaptureView()
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}

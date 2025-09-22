//
//  ContentView.swift
//  RGB2GIF2VOXEL
//
//  Created by Daniel on 2025-09-20.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        // Use simplified camera with clear user flow
        SimplifiedCameraView()
            .preferredColorScheme(.dark)
    }
}

struct DemoOptionCard: View {
    let title: String
    let subtitle: String
    let gradient: LinearGradient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(gradient)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}

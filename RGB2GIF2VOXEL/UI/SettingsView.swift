//
//  SettingsView.swift
//  RGB2GIF2VOXEL
//
//  Settings for capture quality and processing options
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("frameRate") private var frameRate = 30
    @AppStorage("colorPalette") private var colorPalette = 256
    @AppStorage("useHDR") private var useHDR = false
    @AppStorage("autoSave") private var autoSave = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Capture Settings") {
                    Picker("Frame Rate", selection: $frameRate) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }

                    Picker("Color Palette", selection: $colorPalette) {
                        Text("64 colors").tag(64)
                        Text("128 colors").tag(128)
                        Text("256 colors").tag(256)
                    }

                    Toggle("Use HDR", isOn: $useHDR)
                }

                Section("Processing") {
                    Toggle("Auto-save to Photos", isOn: $autoSave)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Tensor Size")
                        Spacer()
                        Text("256³ voxels")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
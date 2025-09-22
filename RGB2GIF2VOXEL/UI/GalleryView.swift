//
//  GalleryView.swift
//  RGB2GIF2VOXEL
//
//  Gallery view for created GIFs
//

import SwiftUI

struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var gifURLs: [URL] = []

    var body: some View {
        NavigationView {
            ScrollView {
                if gifURLs.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("No GIFs Yet")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        Text("Capture 256 frames to create your first GIF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                        ForEach(gifURLs, id: \.self) { url in
                            GIFThumbnail(url: url)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadGIFs()
        }
    }

    private func loadGIFs() {
        // Load GIFs from app's documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                    in: .userDomainMask).first!
        let gifPath = documentsPath.appendingPathComponent("GIFs")

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: gifPath,
                includingPropertiesForKeys: nil
            )
            gifURLs = files.filter { $0.pathExtension == "gif" }
                          .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            print("Failed to load GIFs: \(error)")
        }
    }
}

struct GIFThumbnail: View {
    let url: URL

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.8))
            )
    }
}

#Preview {
    GalleryView()
}
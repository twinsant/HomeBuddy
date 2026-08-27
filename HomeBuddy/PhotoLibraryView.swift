//
//  PhotoLibraryView.swift
//  HomeBuddy
//

import AppKit
import Photos
import SwiftUI

struct PhotoLibraryView: View {
    let album: PhotoAlbum
    let assets: [PHAsset]

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    var body: some View {
        Group {
            if assets.isEmpty {
                ContentUnavailableView(
                    "“\(album.title)”中还没有照片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("这个相册中暂时没有可显示的图片。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            PhotoThumbnailView(asset: asset)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(album.title)
        .frame(minWidth: 420, minHeight: 300)
    }
}

private struct PhotoThumbnailView: View {
    let asset: PHAsset
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 140, maxWidth: .infinity, minHeight: 140, maxHeight: 220)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: asset.localIdentifier) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            let targetSize = CGSize(width: 500, height: 500)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { nsImage, _ in
                guard let nsImage else { return }
                Task { @MainActor in
                    image = Image(nsImage: nsImage)
                }
            }
        }
    }
}

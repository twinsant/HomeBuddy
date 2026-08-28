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
    @State private var selectedIndex: Int?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    var body: some View {
        Group {
            if let selectedIndex {
                PhotoViewerView(
                    assets: assets,
                    initialIndex: selectedIndex,
                    onBack: { self.selectedIndex = nil }
                )
            } else if assets.isEmpty {
                ContentUnavailableView(
                    "“\(album.title)”中还没有照片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("这个相册中暂时没有可显示的图片。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            Button {
                                selectedIndex = index
                            } label: {
                                PhotoThumbnailView(asset: asset)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .accessibilityLabel("查看照片")
                            .help("点击查看大图")
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

private struct PhotoViewerView: View {
    let assets: [PHAsset]
    let initialIndex: Int
    let onBack: () -> Void

    @State private var currentIndex: Int
    @State private var image: NSImage?

    init(assets: [PHAsset], initialIndex: Int, onBack: @escaping () -> Void) {
        self.assets = assets
        self.initialIndex = initialIndex
        self.onBack = onBack
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentAsset: PHAsset {
        assets[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("返回相册", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Text("照片 \(currentIndex + 1) / \(assets.count)")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()

            ZStack {
                Color.black

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(24)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 20) {
                Button {
                    showPrevious()
                } label: {
                    Label("上一张", systemImage: "chevron.left")
                }
                .disabled(currentIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button {
                    showNext()
                } label: {
                    Label("下一张", systemImage: "chevron.right")
                }
                .disabled(currentIndex == assets.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .task(id: currentAsset.localIdentifier) {
            loadCurrentImage()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: showPrevious()
            case .right: showNext()
            default: break
            }
        }
        .onExitCommand(perform: onBack)
    }

    private func showPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func showNext() {
        guard currentIndex + 1 < assets.count else { return }
        currentIndex += 1
    }

    private func loadCurrentImage() {
        image = nil

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: currentAsset,
            targetSize: CGSize(width: 2400, height: 2400),
            contentMode: .aspectFit,
            options: options
        ) { nsImage, _ in
            guard let nsImage else { return }
            Task { @MainActor in
                image = nsImage
            }
        }
    }
}

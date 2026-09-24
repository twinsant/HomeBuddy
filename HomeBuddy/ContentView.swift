//
//  ContentView.swift
//  HomeBuddy
//
//  Created by Atman An on 2026/8/26.
//

import AppKit
import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var photoLibrary = PhotoLibraryStore()
    @StateObject private var batchRecognitionModels = BatchRecognitionModelStore()
    @StateObject private var batchFaceRecognitionModels = BatchFaceRecognitionModelStore()
    @State private var selectedAlbumID: String?
    @State private var isShowingBatchRecognition = false
    @State private var batchRecognitionModel: BatchRecognitionModel?
    @State private var isShowingBatchFaceRecognition = false
    @State private var batchFaceRecognitionModel: BatchFaceRecognitionModel?

    var body: some View {
        NavigationSplitView {
            Group {
                if hasPhotoAccess {
                    PhotoSidebarView(albums: photoLibrary.albums, selectedAlbumID: $selectedAlbumID)
                } else {
                    PhotoPermissionView(openSettings: openPhotoSettings)
                }
            }
            .navigationTitle("照片相册")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            if let selectedAlbum {
                PhotoLibraryView(
                    album: selectedAlbum,
                    assets: photoLibrary.assets(for: selectedAlbum)
                )
                    .id(selectedAlbum.id)
            } else {
                ContentUnavailableView("选择一个相册", systemImage: "rectangle.stack", description: Text("从左侧选择相册以查看其中的照片。"))
            }
        }
        .toolbar {
            ToolbarItem {
                if let selectedAlbum {
                    Text(selectedAlbum.title)
                        .font(.headline)
                        .lineLimit(1)
                        .help(selectedAlbum.title)
                }
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    photoLibrary.refresh()
                } label: {
                    Label("刷新图库", systemImage: "arrow.clockwise")
                }
                .help("重新读取系统照片图库")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    showBatchRecognition()
                } label: {
                    Label {
                        Text("Ollama 批量识图")
                    } icon: {
                        BatchRecognitionToolbarIcon(
                            isAnimating: batchRecognitionModels.activeModel?.phase == .running
                        )
                    }
                }
                .disabled(selectedAlbum == nil && batchRecognitionModels.activeModel == nil)
                .help("打开 Ollama 批量识图任务")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    showBatchFaceRecognition()
                } label: {
                    Label {
                        Text("批量人脸识别")
                    } icon: {
                        BatchFaceRecognitionToolbarIcon(
                            isAnimating: batchFaceRecognitionModels.activeModel?.phase == .running
                        )
                    }
                }
                .disabled(selectedAlbum == nil && batchFaceRecognitionModels.activeModel == nil)
                .help("打开批量人脸识别任务")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .popover(isPresented: $isShowingBatchRecognition) {
            if let batchRecognitionModel {
                BatchRecognitionView(
                    model: batchRecognitionModel,
                    isPresented: $isShowingBatchRecognition
                )
            } else {
                Text("没有可用的批量识图任务")
                    .padding()
            }
        }
        .popover(isPresented: $isShowingBatchFaceRecognition) {
            if let batchFaceRecognitionModel {
                BatchFaceRecognitionView(
                    model: batchFaceRecognitionModel,
                    isPresented: $isShowingBatchFaceRecognition
                )
            } else {
                Text("没有可用的批量人脸识别任务")
                    .padding()
            }
        }
        .task {
            photoLibrary.requestAccessAndLoad()
        }
        .onChange(of: photoLibrary.albums) { _, albums in
            if selectedAlbumID == nil || !albums.contains(where: { $0.id == selectedAlbumID }) {
                selectedAlbumID = albums.first(where: \.isRecents)?.id ?? albums.first?.id
            }
        }
    }

    private var selectedAlbum: PhotoAlbum? {
        photoLibrary.albums.first { $0.id == selectedAlbumID }
    }

    private var hasPhotoAccess: Bool {
        let status = photoLibrary.authorizationStatus
        return status == .authorized || status == .limited
    }

    private func showBatchRecognition() {
        let model: BatchRecognitionModel?
        if let activeModel = batchRecognitionModels.activeModel {
            model = activeModel
        } else if let selectedAlbum {
            model = batchRecognitionModels.model(
                for: selectedAlbum.id,
                assets: photoLibrary.assets(for: selectedAlbum)
            )
        } else {
            model = nil
        }

        guard let model else { return }
        batchRecognitionModel = model
        model.startOrResume()
        isShowingBatchRecognition = true
    }

    private func showBatchFaceRecognition() {
        guard let selectedAlbum else { return }
        let model = batchFaceRecognitionModels.model(
            for: selectedAlbum.id,
            assets: photoLibrary.assets(for: selectedAlbum)
        )
        batchFaceRecognitionModel = model
        model.startOrResume()
        isShowingBatchFaceRecognition = true
    }

    private func openPhotoSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct BatchRecognitionToolbarIcon: View {
    let isAnimating: Bool

    var body: some View {
        Image(systemName: "photo.stack")
            .foregroundStyle(isAnimating ? Color.blue : Color.primary)
            .scaleEffect(isAnimating ? 1.14 : 1)
            .opacity(isAnimating ? 0.68 : 1)
            .animation(
                isAnimating
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
    }
}

private struct BatchFaceRecognitionToolbarIcon: View {
    let isAnimating: Bool

    var body: some View {
        Image(systemName: "person.2.crop.square.stack")
            .foregroundStyle(isAnimating ? Color.blue : Color.primary)
            .scaleEffect(isAnimating ? 1.14 : 1)
            .opacity(isAnimating ? 0.68 : 1)
            .animation(
                isAnimating
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
    }
}

private struct PhotoAlbumRow: View {
    let album: PhotoAlbum
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: album.icon)
            Text(album.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
    }
}

private struct PhotoPermissionView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("无法访问照片图库")
                .font(.title2.weight(.semibold))
            Text("请在系统设置中允许 HomeBuddy 访问照片。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("打开照片设置", action: openSettings)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PhotoSidebarView: View {
    let albums: [PhotoAlbum]
    @Binding var selectedAlbumID: String?

    var body: some View {
        List {
            ForEach(albums) { album in
                Button {
                    selectedAlbumID = album.id
                } label: {
                    PhotoAlbumRow(album: album, isSelected: selectedAlbumID == album.id)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    ContentView()
}

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
    @State private var selectedAlbumID: String?

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
                PhotoLibraryView(album: selectedAlbum, assets: photoLibrary.assets(for: selectedAlbum))
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
        }
        .task {
            photoLibrary.requestAccessAndLoad()
        }
        .onChange(of: photoLibrary.albums) { _, albums in
            if selectedAlbumID == nil || !albums.contains(where: { $0.id == selectedAlbumID }) {
                selectedAlbumID = albums.first?.id
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

    private func openPhotoSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else {
            return
        }
        NSWorkspace.shared.open(url)
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

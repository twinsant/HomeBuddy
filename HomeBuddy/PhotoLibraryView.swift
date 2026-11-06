//
//  PhotoLibraryView.swift
//  HomeBuddy
//

import AppKit
import AVKit
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Vision

struct PhotoLibraryView: View {
    let album: PhotoAlbum
    let assets: [LibraryAsset]
    let assetsRevision: String
    let minimumImageLongEdge: Int
    @ObservedObject private var hiddenMedia = HiddenMediaStore.shared
    @State private var selectedIndex: Int?
    @State private var selectedVideoIndex: Int?
    @State private var viewerAssets: [LibraryAsset] = []
    @State private var searchText = ""
    @State private var searchResultIDs: Set<String>?
    @State private var personSummaries: [PersonAlbumSummary] = []
    @State private var selectedPersonID: String?
    @State private var personSummaryRequestID = UUID()

    init(album: PhotoAlbum, assets: [LibraryAsset], assetsRevision: String, minimumImageLongEdge: Int = 0) {
        self.album = album
        self.assets = assets
        self.assetsRevision = assetsRevision
        self.minimumImageLongEdge = minimumImageLongEdge
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    private var searchKeywords: [String] {
        searchText
            .components(separatedBy: [" ", "\t", "\n", ",", "，"])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var displayedAssets: [LibraryAsset] {
        let keywords = searchKeywords
        guard minimumImageLongEdge > 0 || selectedPersonID != nil || !keywords.isEmpty else { return assets }

        let personAssetIDs: Set<String>? = selectedPersonID.map { id in
            personSummaries.first(where: { $0.person.id == id })?.assetIDs ?? []
        }
        return assets.filter { asset in
            (minimumImageLongEdge == 0 || max(asset.pixelWidth, asset.pixelHeight) >= minimumImageLongEdge)
                && (personAssetIDs?.contains(asset.localIdentifier) ?? true)
                && (keywords.isEmpty || (searchResultIDs?.contains(asset.localIdentifier) ?? true))
        }
    }

    private var searchTaskID: String {
        let keywords = searchKeywords.joined(separator: "\u{1F}" )
        return "\(assetsRevision)|\(keywords)"
    }

    private var personSummaryTaskID: String {
        "\(album.id):\(assetsRevision)"
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if (album.isFaceAlbum || album.isVideoAlbum) && !personSummaries.isEmpty {
                            PersonFilterBar(
                                summaries: personSummaries,
                                assetsByID: Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }),
                                isVideoAlbum: album.isVideoAlbum,
                                selectedPersonID: $selectedPersonID
                            )
                        }

                        if displayedAssets.isEmpty {
                            ContentUnavailableView(
                                album.isVideoAlbum
                                    ? (minimumImageLongEdge > 0 || selectedPersonID != nil || !searchKeywords.isEmpty ? "没有匹配的视频" : "“\(album.title)”中还没有视频")
                                    : (minimumImageLongEdge > 0 || selectedPersonID != nil || !searchKeywords.isEmpty
                                        ? "没有匹配的照片"
                                        : "“\(album.title)”中还没有照片"),
                                systemImage: album.isVideoAlbum ? "video" : "photo.on.rectangle.angled",
                                description: Text(
                                    album.isVideoAlbum
                                        ? (selectedPersonID != nil || !searchKeywords.isEmpty ? "尝试调整搜索关键词或关闭筛选条件。" : "这个分类暂时没有可显示的视频。")
                                        : (minimumImageLongEdge > 0 && selectedPersonID == nil && searchKeywords.isEmpty
                                        ? "没有符合最小尺寸的图片（最长边需达到 \(minimumImageLongEdge) 像素）。"
                                        : (minimumImageLongEdge > 0 || selectedPersonID != nil || !searchKeywords.isEmpty
                                            ? "尝试调整搜索关键词或关闭筛选条件。"
                                            : "这个相册暂时没有可显示的图片。"))
                                )
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            if !searchKeywords.isEmpty || minimumImageLongEdge > 0 {
                                Text(album.isVideoAlbum
                                    ? (searchKeywords.isEmpty ? "筛选后显示 \(displayedAssets.count) 个视频" : "找到 \(displayedAssets.count) 个视频（需同时包含全部关键词）")
                                    : (searchKeywords.isEmpty ? "筛选后显示 \(displayedAssets.count) 张图片" : "找到 \(displayedAssets.count) 张照片（需同时包含全部关键词）"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(Array(displayedAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                    Button {
                                        guard displayedAssets.indices.contains(index) else { return }
                                        if asset.isVideo {
                                            viewerAssets = displayedAssets.filter(\.isVideo)
                                            selectedVideoIndex = viewerAssets.firstIndex { $0.localIdentifier == asset.localIdentifier }
                                        } else {
                                            viewerAssets = displayedAssets
                                            selectedIndex = index
                                        }
                                    } label: {
                                        PhotoThumbnailView(asset: asset)
                                            .contentShape(Rectangle())
                                            .overlay(alignment: .topTrailing) {
                                                if hiddenMedia.isHidden(asset) {
                                                    Image(systemName: "eye.slash.fill")
                                                        .padding(6)
                                                        .foregroundStyle(.white)
                                                        .background(.black.opacity(0.7), in: Circle())
                                                        .padding(6)
                                                        .allowsHitTesting(false)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel(asset.isVideo ? "播放视频" : "查看照片")
                                    .accessibilityIdentifier("photoThumbnail-\(index)")
                                    .help(asset.isVideo ? "点击播放视频" : "点击查看大图")
                                    .id(asset.localIdentifier)
                                    .modifier(PhotoExportMenu(asset: asset))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                }
                .allowsHitTesting(selectedIndex == nil && selectedVideoIndex == nil)
                .accessibilityHidden(selectedIndex != nil || selectedVideoIndex != nil)

                if let selectedVideoIndex, viewerAssets.indices.contains(selectedVideoIndex) {
                    PhotoVideoPlayerView(assets: viewerAssets, initialIndex: selectedVideoIndex, albumTitle: album.title) { assetID in
                        self.selectedVideoIndex = nil
                        DispatchQueue.main.async {
                            guard self.selectedVideoIndex == nil,
                                  self.displayedAssets.contains(where: { $0.localIdentifier == assetID }) else { return }
                            withAnimation { scrollProxy.scrollTo(assetID, anchor: .center) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .zIndex(1)
                } else if let selectedIndex, viewerAssets.indices.contains(selectedIndex) {
                    PhotoViewerView(
                        assets: viewerAssets,
                        initialIndex: selectedIndex,
                        albumTitle: album.title,
                        onBack: { assetID in
                            self.selectedIndex = nil
                            // 关闭覆盖层后再滚动；列表可能已因搜索或刷新移除这张照片。
                            DispatchQueue.main.async {
                                guard self.selectedIndex == nil,
                                      self.displayedAssets.contains(where: { $0.localIdentifier == assetID }) else { return }
                                withAnimation {
                                    scrollProxy.scrollTo(assetID, anchor: .center)
                                }
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .zIndex(1)
                }
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .searchable(text: $searchText, prompt: "搜索 Ollama 识别文字")
        .onChange(of: searchText) { _, _ in
            // 搜索条件改变时关闭查看器，不再显示旧结果中的照片。
            selectedIndex = nil
            selectedVideoIndex = nil
        }
        .onChange(of: assetsRevision) { _, _ in
            // Recognition may reorder the people collection without changing any image.
            let available = Set(assets.map(\.localIdentifier))
            if !viewerAssets.allSatisfy({ available.contains($0.localIdentifier) }) { selectedIndex = nil }
            if selectedVideoIndex != nil && !viewerAssets.allSatisfy({ available.contains($0.localIdentifier) }) {
                selectedVideoIndex = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyRecognitionDidChange"))) { _ in
            if album.isFaceAlbum || album.isVideoAlbum { loadPersonSummaries() }
            let keywords = searchKeywords
            guard !keywords.isEmpty else { return }
            PhotoMetadataCache.shared.assetIDs(matchingOllamaKeywords: keywords) { result in
                guard searchKeywords == keywords else { return }
                searchResultIDs = result
            }
        }
        .task(id: searchTaskID) {
            let keywords = searchKeywords
            guard !keywords.isEmpty else {
                searchResultIDs = nil
                return
            }

            searchResultIDs = nil
            PhotoMetadataCache.shared.assetIDs(matchingOllamaKeywords: keywords) { result in
                guard searchKeywords == keywords else { return }
                searchResultIDs = result
            }
        }
        .task(id: personSummaryTaskID) {
            if album.isFaceAlbum || album.isVideoAlbum { loadPersonSummaries() }
            else { personSummaryRequestID = UUID(); personSummaries = []; selectedPersonID = nil }
        }
    }

    private func loadPersonSummaries() {
        let requestID = UUID()
        personSummaryRequestID = requestID
        PhotoMetadataCache.shared.personAlbumSummaries(assetIDs: Set(assets.map(\.localIdentifier))) { summaries in
            guard personSummaryRequestID == requestID else { return }
            personSummaries = summaries
            if let selectedPersonID, !summaries.contains(where: { $0.person.id == selectedPersonID }) {
                self.selectedPersonID = nil
            }
        }
    }
}

private struct PersonFilterBar: View {
    let summaries: [PersonAlbumSummary]
    let assetsByID: [String: LibraryAsset]
    let isVideoAlbum: Bool
    @Binding var selectedPersonID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按人物筛选")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        selectedPersonID = nil
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.title2)
                                .frame(width: 58, height: 58)
                                .background(.quaternary, in: Circle())
                            Text("全部")
                                .font(.caption.weight(.medium))
                            Text("人物")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 90)
                        .padding(8)
                        .background(selectedPersonID == nil ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isVideoAlbum ? "显示全部视频" : "显示全部人物照片")

                    ForEach(summaries) { summary in
                        Button {
                            selectedPersonID = selectedPersonID == summary.person.id ? nil : summary.person.id
                        } label: {
                            VStack(spacing: 6) {
                                PersonAlbumAvatar(
                                    asset: summary.avatarAssetID.flatMap { assetsByID[$0] },
                                    faceBox: summary.avatarFaceBox
                                )
                                Text(summary.person.displayName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                HStack(spacing: 6) {
                                    Label("\(summary.recognizedPhotoCount)", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Label("\(summary.potentialPhotoCount)", systemImage: "questionmark.circle.fill")
                                        .foregroundStyle(.purple)
                                }
                                .font(.caption2.monospacedDigit())
                                .help(isVideoAlbum
                                    ? "已识别 \(summary.recognizedPhotoCount) 个视频 · 潜在识别 \(summary.potentialPhotoCount) 个视频"
                                    : "已识别 \(summary.recognizedPhotoCount) 张 · 潜在识别 \(summary.potentialPhotoCount) 张")
                            }
                            .frame(width: 108)
                            .padding(8)
                            .background(selectedPersonID == summary.person.id ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isVideoAlbum
                            ? "\(summary.person.displayName)，已识别 \(summary.recognizedPhotoCount) 个视频，潜在识别 \(summary.potentialPhotoCount) 个视频"
                            : "\(summary.person.displayName)，已识别 \(summary.recognizedPhotoCount) 张，潜在识别 \(summary.potentialPhotoCount) 张")
                        .accessibilityAddTraits(selectedPersonID == summary.person.id ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PersonAlbumAvatar: View {
    let asset: LibraryAsset?
    let faceBox: CGRect?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: 58, height: 58)
        .background(.quaternary)
        .clipShape(Circle())
        .task(id: asset?.revisionID) {
            image = nil
            guard let asset else { return }
            if asset.isVideo, let url = try? VideoCoverStore.url(for: asset) {
                let cover = await Task.detached(priority: .userInitiated) {
                    VideoCoverStore.thumbnail(at: url, maximumSize: 600)
                }.value
                guard !Task.isCancelled else { return }
                if let cover {
                    setImage(from: cover)
                    return
                }
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            LibraryImageManager.shared.requestImage(
                for: asset,
                targetSize: CGSize(width: 360, height: 360),
                contentMode: .aspectFit,
                options: options
            ) { source, _ in
                guard let source else { return }
                guard let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                setImage(from: cgImage)
            }
        }
    }

    private func setImage(from cgImage: CGImage) {
        let sourceRect = faceBox.map { box in
            CGRect(
                x: box.minX * CGFloat(cgImage.width),
                y: (1 - box.maxY) * CGFloat(cgImage.height),
                width: box.width * CGFloat(cgImage.width),
                height: box.height * CGFloat(cgImage.height)
            ).insetBy(dx: -box.width * CGFloat(cgImage.width) * 0.18,
                      dy: -box.height * CGFloat(cgImage.height) * 0.18)
        }
        let cropped = sourceRect.flatMap { rect in
            cgImage.cropping(to: rect.integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)))
        } ?? cgImage
        image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}

private struct PhotoExportMenu: ViewModifier {
    let asset: LibraryAsset
    @ObservedObject private var hiddenMedia = HiddenMediaStore.shared
    @State private var isExporting = false
    @State private var exportError: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(hiddenMedia.isHidden(asset) ? "取消隐藏" : "隐藏", systemImage: hiddenMedia.isHidden(asset) ? "eye" : "eye.slash") {
                    hiddenMedia.toggleHidden(asset)
                }
                if !asset.isVideo {
                    Button("导出照片…", systemImage: "square.and.arrow.up") {
                        let snapshot = asset
                        Task { await export(snapshot) }
                    }
                    .disabled(isExporting)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isExporting {
                    ProgressView("正在导出…")
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .allowsHitTesting(false)
                }
            }
            .alert("照片导出失败", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("好", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "未知错误")
            }
    }

    @MainActor
    private func export(_ snapshot: LibraryAsset) async {
        guard !isExporting, hiddenMedia.isVisible(snapshot) else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let details = try PhotoExporter.fileDetails(for: snapshot)
            let panel = NSSavePanel()
            panel.title = "导出照片"
            panel.message = "保留原始格式和元数据；Live Photo 仅导出静态照片。"
            panel.prompt = "导出"
            panel.nameFieldStringValue = details.filename
            panel.canCreateDirectories = true
            if let type = details.type { panel.allowedContentTypes = [type] }
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            guard hiddenMedia.isVisible(snapshot) else { return }
            try await PhotoExporter.export(snapshot, to: destination)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// Exports file bytes, never a rendered thumbnail or a re-encoded image.
nonisolated enum PhotoExporter {
    static func originalResource(for photo: PHAsset) throws -> PHAssetResource {
        let resources = PHAssetResource.assetResources(for: photo)
        guard let resource = resources.first(where: { $0.type == .photo })
            ?? resources.first(where: { $0.type == .alternatePhoto }) else {
            throw DiskLibraryError.message("找不到可导出的原始照片资源。")
        }
        return resource
    }

    static func fileDetails(for asset: LibraryAsset) throws -> (filename: String, type: UTType?) {
        switch asset.source {
        case .disk(_, let image):
            let file = URL(fileURLWithPath: image.relativePath)
            return (file.lastPathComponent, UTType(filenameExtension: file.pathExtension))
        case .photos(let photo):
            let resource = try originalResource(for: photo)
            return (URL(fileURLWithPath: resource.originalFilename).lastPathComponent,
                    UTType(resource.uniformTypeIdentifier))
        }
    }

    static func export(_ asset: LibraryAsset, to destination: URL) async throws {
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        switch asset.source {
        case .disk(let directory, let image):
            try await Task.detached(priority: .userInitiated) {
                let root = try DiskImageLoader.resolvedDirectory(directory).url
                let accessed = root.startAccessingSecurityScopedResource()
                defer { if accessed { root.stopAccessingSecurityScopedResource() } }
                let source = root.appendingPathComponent(image.relativePath)
                let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL
                let targetPath = destination.resolvingSymlinksInPath().standardizedFileURL
                let sourceAttributes = try FileManager.default.attributesOfItem(atPath: sourcePath.path)
                let targetAttributes = try? FileManager.default.attributesOfItem(atPath: targetPath.path)
                let sameFile = targetAttributes != nil
                    && (sourceAttributes[.systemNumber] as? NSNumber) == (targetAttributes?[.systemNumber] as? NSNumber)
                    && (sourceAttributes[.systemFileNumber] as? NSNumber) == (targetAttributes?[.systemFileNumber] as? NSNumber)
                guard sourcePath != targetPath, !sameFile else {
                    throw DiskLibraryError.message("导出位置不能是原始照片，请选择其他文件路径。")
                }
                let original = try DiskImageLoader.originalData(directory: directory, image: image)
                try original.data.write(to: destination, options: .atomic)
            }.value
        case .photos(let photo):
            let resource = try originalResource(for: photo)
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: staging, options: options) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            // Download must succeed before replacing an existing destination.
            try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: staging).write(to: destination, options: .atomic)
            }.value
        }
    }
}

/// Keeps shared files available after the picker closes, including while another app imports them.
nonisolated enum MediaShareExporter {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HomeBuddySharedMedia", isDirectory: true)
    }

    static func prepare(_ asset: LibraryAsset) async throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for folder in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               date < cutoff {
                try? manager.removeItem(at: folder)
            }
        }

        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            if asset.isVideo {
                guard case .photos(let video) = asset.source else {
                    throw DiskLibraryError.message("找不到可分享的视频资源。")
                }
                let resources = PHAssetResource.assetResources(for: video)
                guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
                    ?? resources.first(where: { $0.type == .video }) else {
                    throw DiskLibraryError.message("找不到可分享的视频资源。")
                }
                let filename = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
                let destination = folder.appendingPathComponent(filename.isEmpty ? "Video.mov" : filename)
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                return destination
            }
            let filename = try PhotoExporter.fileDetails(for: asset).filename
            let destination = folder.appendingPathComponent(filename.isEmpty ? "Photo" : filename)
            try await PhotoExporter.export(asset, to: destination)
            return destination
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
    }
}

private struct SharePickerAnchor: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView()
        DispatchQueue.main.async { view = anchor }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct HiddenMediaButton: View {
    let asset: LibraryAsset
    @ObservedObject private var hiddenMedia = HiddenMediaStore.shared

    var body: some View {
        Button {
            hiddenMedia.toggleHidden(asset)
        } label: {
            Label(hiddenMedia.isHidden(asset) ? "取消隐藏" : "隐藏",
                  systemImage: hiddenMedia.isHidden(asset) ? "eye" : "eye.slash")
        }
        .accessibilityIdentifier("toggleHiddenMedia")
        .help(hiddenMedia.isHidden(asset) ? "取消隐藏此项目" : "隐藏此项目")
    }
}

private struct MediaShareButton: View {
    let asset: LibraryAsset
    @ObservedObject private var hiddenMedia = HiddenMediaStore.shared
    @State private var anchor: NSView?
    @State private var picker: NSSharingServicePicker?
    @State private var isPreparing = false
    @State private var generation = UUID()
    @State private var shareError: String?

    var body: some View {
        Button {
            let snapshot = asset
            guard hiddenMedia.isVisible(snapshot) else { return }
            let request = UUID()
            generation = request
            isPreparing = true
            Task { @MainActor in
                do {
                    let url = try await MediaShareExporter.prepare(snapshot)
                    guard generation == request, hiddenMedia.isVisible(snapshot), let anchor, anchor.window != nil else {
                        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                        if generation == request { isPreparing = false }
                        return
                    }
                    isPreparing = false
                    let picker = NSSharingServicePicker(items: [url])
                    self.picker = picker
                    picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
                } catch {
                    guard generation == request else { return }
                    isPreparing = false
                    shareError = error.localizedDescription
                }
            }
        } label: {
            Label(asset.isVideo ? "分享视频" : "分享图片", systemImage: "square.and.arrow.up")
        }
        .background(SharePickerAnchor(view: $anchor).allowsHitTesting(false))
        .disabled(isPreparing)
        .accessibilityIdentifier(asset.isVideo ? "shareVideo" : "sharePhoto")
        .help(asset.isLivePhoto ? "分享 Live Photo 的静态照片" : (asset.isVideo ? "分享当前视频" : "分享当前图片"))
        .alert("分享失败", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("好", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "未知错误")
        }
        .onChange(of: asset.revisionID) { _, _ in invalidate() }
        .onChange(of: hiddenMedia.revision) { _, _ in invalidate() }
        .onDisappear { invalidate() }
    }

    private func invalidate() {
        generation = UUID()
        isPreparing = false
        shareError = nil
    }
}

private struct PhotoThumbnailView: View {
    let asset: LibraryAsset
    @State private var image: Image?
    @State private var loadError: String?
    @State private var ollamaFailureCount = 0
    @State private var imageRequestID: PHImageRequestID?
    @State private var imageRequestGeneration = UUID()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if let loadError {
                    Image(systemName: "photo.badge.exclamationmark")
                        .help(loadError)
                } else {
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .task(id: asset.revisionID) {
            image = nil
            loadError = nil
            ollamaFailureCount = 0
            if !asset.isVideo {
                PhotoMetadataCache.shared.ollamaFailureCount(for: asset) { ollamaFailureCount = $0 }
            }
            await loadImage()
        }
        .overlay(alignment: .topTrailing) {
            if ollamaFailureCount > 3 {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .orange)
                    .padding(7)
                    .help("Ollama 识图失败 \(ollamaFailureCount) 次")
                    .accessibilityLabel("Ollama 识图失败 \(ollamaFailureCount) 次")
            }
        }
        .overlay {
            if asset.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
                    .accessibilityHidden(true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyRecognitionDidChange"))) { _ in
            guard !asset.isVideo else { return }
            PhotoMetadataCache.shared.ollamaFailureCount(for: asset) { ollamaFailureCount = $0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyVideoCoverDidChange"))) { notification in
            guard asset.isVideo, notification.object as? String == asset.revisionID else { return }
            Task { await loadImage() }
        }
        .onDisappear {
            imageRequestGeneration = UUID()
            if let imageRequestID {
                PHImageManager.default().cancelImageRequest(imageRequestID)
                self.imageRequestID = nil
            }
        }
    }

    private func loadImage() async {
        let generation = UUID()
        imageRequestGeneration = generation
        if let imageRequestID {
            PHImageManager.default().cancelImageRequest(imageRequestID)
            self.imageRequestID = nil
        }
        if asset.isVideo, let url = try? VideoCoverStore.url(for: asset) {
            let cover = await Task.detached(priority: .userInitiated) {
                VideoCoverStore.thumbnail(at: url, maximumSize: 500)
            }.value
            guard imageRequestGeneration == generation, !Task.isCancelled else { return }
            if let cover {
                image = Image(nsImage: NSImage(cgImage: cover, size: .zero))
                loadError = nil
                return
            }
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = asset.isVideo ? .fastFormat : .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        imageRequestID = LibraryImageManager.shared.requestImage(
            for: asset,
            targetSize: CGSize(width: 500, height: 500),
            contentMode: .aspectFill,
            options: options
        ) { nsImage, info in
            guard imageRequestGeneration == generation else { return }
            guard let nsImage else {
                loadError = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "图片无法读取"
                return
            }
            loadError = nil
            image = Image(nsImage: nsImage)
        }
    }
}

private struct PhotoVideoPlayerView: View {
    private struct FaceSelection: Identifiable {
        let id = UUID()
        let index: Int
        let box: CGRect
        let asset: LibraryAsset
        let session: UUID
        let navigationGeneration: UUID
    }

    let assets: [LibraryAsset]
    let initialIndex: Int
    let albumTitle: String
    let onBack: (String) -> Void
    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var requestID: PHImageRequestID?
    @State private var loadError: String?
    @State private var loadGeneration = UUID()
    @State private var coverDescription: String?
    @State private var coverFaces: FaceDetectionResult?
    @State private var coverImage: NSImage?
    @State private var people: [Person] = []
    @State private var mostLabeledPeople: [PersonFaceCount] = []
    @State private var selectedFace: FaceSelection?
    @State private var faceAssignmentError: String?
    @State private var isShowingInfo = true
    @State private var resultGeneration = UUID()
    @State private var coverGeneration = UUID()
    @State private var navigationGeneration = UUID()
    @State private var metadata: VideoMetadata?

    init(assets: [LibraryAsset], initialIndex: Int, albumTitle: String, onBack: @escaping (String) -> Void) {
        self.assets = assets
        self.initialIndex = initialIndex
        self.albumTitle = albumTitle
        self.onBack = onBack
        _currentIndex = State(initialValue: initialIndex)
    }

    private var asset: LibraryAsset { assets[currentIndex] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onBack(asset.localIdentifier) } label: {
                    Label("返回相册：\(albumTitle)", systemImage: "chevron.left")
                        .lineLimit(1)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("backToPhotoLibrary")
                Spacer()
                Text("视频 \(currentIndex + 1) / \(assets.count)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("videoPosition")
                    .accessibilityLabel("视频 \(currentIndex + 1) / \(assets.count)")
            }
            .padding()

            HStack(spacing: 0) {
                Group {
                    if let player {
                        VideoPlayer(player: player)
                            .padding(24)
                    } else if let loadError {
                        ContentUnavailableView("视频无法播放", systemImage: "video.slash", description: Text(loadError))
                    } else {
                        ProgressView("正在加载视频…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.85))

                if isShowingInfo {
                    VideoRecognitionInfoSidebar(
                        metadata: metadata,
                        coverImage: coverImage,
                        ollamaText: coverDescription,
                        faceResult: coverFaces,
                        people: people,
                        onFaceTap: selectFace
                    )
                    .frame(width: 300)
                }
            }

            HStack(spacing: 20) {
                Button { navigate(to: currentIndex - 1) } label: {
                    Label("上一个视频", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("previousVideo")
                .disabled(currentIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button { navigate(to: currentIndex + 1) } label: {
                    Label("下一个视频", systemImage: "chevron.right")
                }
                .accessibilityIdentifier("nextVideo")
                .disabled(currentIndex + 1 >= assets.count)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .task(id: asset.revisionID) {
            let currentAsset = asset
            loadVideo()
            loadCoverResults()
            await loadVideoMetadata(for: currentAsset)
            guard !Task.isCancelled, asset.revisionID == currentAsset.revisionID else { return }
            await loadCoverImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyRecognitionDidChange"))) { _ in
            loadCoverResults()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyVideoCoverDidChange"))) { notification in
            guard notification.object as? String == asset.revisionID else { return }
            Task { await loadCoverImage() }
        }
        .onDisappear {
            resetVideo()
        }
        .sheet(item: $selectedFace) { selection in
            PersonAssignmentSheet(
                people: people,
                mostLabeledPeople: $mostLabeledPeople,
                faces: .constant(coverFaces?.faces ?? []),
                faceIndex: selection.index,
                isRecognizingFaces: .constant(false),
                onAssign: { assignPerson($0, selection: selection) },
                onCreate: { assignNewPerson(named: $0, selection: selection) }
            )
        }
        .alert("人物标注失败", isPresented: Binding(
            get: { faceAssignmentError != nil },
            set: { if !$0 { faceAssignmentError = nil } }
        )) {
            Button("确定", role: .cancel) { faceAssignmentError = nil }
        } message: {
            Text(faceAssignmentError ?? "")
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: navigate(to: currentIndex - 1)
            case .right: navigate(to: currentIndex + 1)
            default: break
            }
        }
        .onExitCommand { onBack(asset.localIdentifier) }
        .toolbar {
            ToolbarItem {
                HiddenMediaButton(asset: asset)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                MediaShareButton(asset: asset)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    isShowingInfo.toggle()
                } label: {
                    Label("识别信息", systemImage: "info.circle")
                }
                .accessibilityIdentifier("videoRecognitionInfo")
                .help("显示或隐藏视频信息和封面识别结果")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func navigate(to index: Int) {
        guard assets.indices.contains(index), index != currentIndex else { return }
        resetVideo()
        currentIndex = index
    }

    private func resetVideo() {
        loadGeneration = UUID()
        resultGeneration = UUID()
        coverGeneration = UUID()
        navigationGeneration = UUID()
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil
        player?.pause()
        player = nil
        loadError = nil
        metadata = nil
        coverDescription = nil
        coverFaces = nil
        coverImage = nil
        people = []
        mostLabeledPeople = []
        selectedFace = nil
        faceAssignmentError = nil
    }

    private func loadVideoMetadata(for currentAsset: LibraryAsset) async {
        let cache = PhotoMetadataCache.shared
        let session = cache.databaseSession
        let cached = await cache.videoMetadata(for: currentAsset, session: session)
        guard !Task.isCancelled, asset.revisionID == currentAsset.revisionID,
              cache.databaseSession == session else { return }
        guard let record = cached ?? VideoMetadataRecord.extract(from: currentAsset) else { return }
        metadata = VideoMetadata(asset: currentAsset, record: record)

        if cached == nil,
           let latest = PHAsset.fetchAssets(withLocalIdentifiers: [currentAsset.localIdentifier], options: nil).firstObject,
           latest.mediaType == .video,
           VideoMetadataRevision(LibraryAsset(latest, databaseURL: currentAsset.databaseURL)) == VideoMetadataRevision(currentAsset),
           !Task.isCancelled {
            _ = await cache.saveVideoMetadata(record, for: currentAsset, session: session)
        }
    }

    private func loadCoverResults() {
        let generation = UUID()
        resultGeneration = generation
        PhotoMetadataCache.shared.ollamaText(for: asset) {
            guard resultGeneration == generation else { return }
            coverDescription = $0
        }
        PhotoMetadataCache.shared.faceDetectionResult(for: asset) {
            guard resultGeneration == generation else { return }
            coverFaces = $0
        }
        PhotoMetadataCache.shared.people {
            guard resultGeneration == generation else { return }
            people = $0
        }
    }

    private func selectFace(_ index: Int) {
        guard let faces = coverFaces?.faces, faces.indices.contains(index) else { return }
        let currentAsset = asset
        let session = PhotoMetadataCache.shared.databaseSession
        let navigation = navigationGeneration
        selectedFace = FaceSelection(index: index, box: faces[index].box, asset: currentAsset,
                                     session: session, navigationGeneration: navigation)
        PhotoMetadataCache.shared.mostLabeledPeople { rankedPeople in
            guard asset.revisionID == currentAsset.revisionID,
                  PhotoMetadataCache.shared.databaseSession == session,
                  navigationGeneration == navigation else { return }
            mostLabeledPeople = rankedPeople
        }
    }

    private func selectionIsCurrent(_ selection: FaceSelection) -> Bool {
        guard asset.revisionID == selection.asset.revisionID,
              PhotoMetadataCache.shared.databaseSession == selection.session,
              navigationGeneration == selection.navigationGeneration,
              let faces = coverFaces?.faces, faces.indices.contains(selection.index) else { return false }
        return faces[selection.index].box == selection.box
    }

    private func assignPerson(_ personID: String?, selection: FaceSelection) {
        guard selectionIsCurrent(selection) else {
            faceAssignmentError = AppLocalization.localizedString("人脸结果已变化，请重新选择人脸。", comment: "")
            loadCoverResults()
            return
        }
        selectedFace = nil
        PhotoMetadataCache.shared.saveFacePersonID(
            personID, faceIndex: selection.index, for: selection.asset,
            expectedFaceBox: selection.box, expectedSession: selection.session
        ) { succeeded in
            guard asset.revisionID == selection.asset.revisionID,
                  PhotoMetadataCache.shared.databaseSession == selection.session,
                  navigationGeneration == selection.navigationGeneration else { return }
            if !succeeded {
                faceAssignmentError = AppLocalization.localizedString("人脸标注未能保存，识别结果可能已变化，请重试。", comment: "")
                loadCoverResults()
            }
        }
    }

    private func assignNewPerson(named name: String, selection: FaceSelection) {
        guard selectionIsCurrent(selection) else {
            faceAssignmentError = AppLocalization.localizedString("人脸结果已变化，请重新选择人脸。", comment: "")
            loadCoverResults()
            return
        }
        selectedFace = nil
        PhotoMetadataCache.shared.savePerson(named: name, expectedSession: selection.session) { person in
            guard asset.revisionID == selection.asset.revisionID,
                  PhotoMetadataCache.shared.databaseSession == selection.session,
                  navigationGeneration == selection.navigationGeneration else { return }
            guard let person else {
                faceAssignmentError = AppLocalization.localizedString("人物未能保存，请重试。", comment: "")
                return
            }
            if !people.contains(where: { $0.id == person.id }) { people.append(person) }
            assignPerson(person.id, selection: selection)
        }
    }

    private func loadCoverImage() async {
        let generation = UUID()
        coverGeneration = generation
        guard let url = try? VideoCoverStore.url(for: asset) else {
            coverImage = nil
            return
        }
        let cover = await Task.detached(priority: .userInitiated) {
            VideoCoverStore.thumbnail(at: url, maximumSize: 600)
        }.value
        guard coverGeneration == generation, !Task.isCancelled else { return }
        coverImage = cover.map { NSImage(cgImage: $0, size: .zero) }
    }

    private func loadVideo() {
        guard case .photos(let photo) = asset.source else {
            loadError = "仅支持播放照片图库中的视频。"
            return
        }
        let generation = UUID()
        loadGeneration = generation
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestPlayerItem(forVideo: photo, options: options) { item, info in
            Task { @MainActor in
                guard loadGeneration == generation else { return }
                guard let item else {
                    loadError = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "无法读取视频资源。"
                    return
                }
                let player = AVPlayer(playerItem: item)
                self.player = player
                player.play()
            }
        }
    }
}

extension VideoMetadataRecord {
    static func extract(from asset: LibraryAsset) -> VideoMetadataRecord? {
        guard case .photos(let video) = asset.source, asset.isVideo else { return nil }
        let resources = PHAssetResource.assetResources(for: video)
        let resource = resources.first { $0.type == .fullSizeVideo }
            ?? resources.first { $0.type == .video }
        let location = video.location.flatMap { $0.horizontalAccuracy >= 0 ? $0 : nil }
        let duration = video.duration
        return VideoMetadataRecord(
            filename: resource?.originalFilename,
            typeIdentifier: resource?.uniformTypeIdentifier,
            duration: duration.isFinite && duration >= 0 ? duration : nil,
            creationTime: asset.creationDate?.timeIntervalSince1970,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            updatedAt: Date().timeIntervalSince1970
        )
    }
}

struct VideoMetadata {
    let rows: [(String, String)]

    init(asset: LibraryAsset, record: VideoMetadataRecord) {
        var values: [(String, String)] = []
        if let filename = record.filename {
            values.append(("文件名", filename))
        }
        if let identifier = record.typeIdentifier {
            let type = UTType(identifier)?.localizedDescription ?? identifier
            values.append(("文件类型", type))
        }
        if asset.pixelWidth > 0 && asset.pixelHeight > 0 {
            values.append(("分辨率", "\(asset.pixelWidth) × \(asset.pixelHeight)"))
        }
        if let duration = record.duration, let formatted = Self.formattedDuration(duration) {
            values.append(("时长", formatted))
        }
        if let creationTime = record.creationTime {
            let date = Date(timeIntervalSince1970: creationTime)
            values.append(("拍摄时间", date.formatted(date: .abbreviated, time: .shortened)))
        }
        if let date = asset.modificationDate {
            values.append(("修改时间", date.formatted(date: .abbreviated, time: .shortened)))
        }
        if let latitude = record.latitude, let longitude = record.longitude {
            values.append(("位置", String(format: "%.5f, %.5f", latitude, longitude)))
        }
        values.append(("元数据更新时间", Date(timeIntervalSince1970: record.updatedAt).formatted(date: .abbreviated, time: .shortened)))
        values.append(("状态", asset.isFavorite
            ? AppLocalization.localizedString("已收藏", comment: "")
            : AppLocalization.localizedString("未收藏", comment: "")))
        rows = values
    }

    static func formattedDuration(_ duration: TimeInterval) -> String? {
        guard duration.isFinite, duration >= 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration)
    }
}

private struct VideoRecognitionInfoSidebar: View {
    let metadata: VideoMetadata?
    let coverImage: NSImage?
    let ollamaText: String?
    let faceResult: FaceDetectionResult?
    let people: [Person]
    let onFaceTap: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("识别信息")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("videoRecognitionInfoTitle")

                if let metadata {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("视频信息").font(.headline)
                            .accessibilityIdentifier("videoMetadataTitle")
                        ForEach(Array(metadata.rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.0).foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(row.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                            }
                            Divider()
                        }
                    }
                }
                Text("以下结果仅针对提取的封面，不代表整个视频。")
                    .font(.caption).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("视频封面").font(.headline)
                    if let coverImage {
                        Image(nsImage: coverImage)
                            .resizable().aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                FaceBoundingBoxOverlay(
                                    imageSize: coverImage.size,
                                    faces: faceResult?.faces ?? [],
                                    personNames: Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.displayName) }),
                                    imagePadding: 0,
                                    minimumBoxSize: 0,
                                    onFaceTap: onFaceTap
                                )
                            }
                            .accessibilityIdentifier("videoCoverImage")
                    } else {
                        Text("尚未提取封面，请返回视频分类后选择“提取封面”。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ollama 识别文字").font(.headline)
                    if let ollamaText, !ollamaText.isEmpty {
                        MarkdownTextView(markdown: ollamaText)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("暂无识别结果，请在视频分类中批量识别封面。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("封面人脸").font(.headline)
                    if let faceResult {
                        Text(faceResult.faceCount == 0 ? "未检测到人脸" : "检测到 \(faceResult.faceCount) 张人脸")
                        ForEach(Array(faceResult.faces.enumerated()), id: \.offset) { index, face in
                            Button {
                                onFaceTap(index)
                            } label: {
                                if let personID = face.personID {
                                    let name = people.first(where: { $0.id == personID })?.displayName
                                        ?? AppLocalization.localizedString("未知人物", comment: "")
                                    Text("人脸 \(index + 1)：\(name)")
                                } else if let candidate = face.candidate {
                                    Text("人脸 \(index + 1)：可能是 \(candidate.displayName)（待确认）")
                                } else {
                                    Text("人脸 \(index + 1)：未标注")
                                }
                            }
                            .buttonStyle(.link)
                            .disabled(coverImage == nil)
                            .accessibilityIdentifier("videoCoverFaceRow-\(index)")
                        }
                        .font(.caption)
                    } else {
                        Text("暂无人脸识别结果，请在视频分类中批量识别封面人脸。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(.regularMaterial)
        .accessibilityIdentifier("videoRecognitionInfoSidebar")
    }
}

private struct LivePhotoPlayer: NSViewRepresentable {
    let photo: PHLivePhoto
    let playbackID: UUID?
    let onPlaybackChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .aspectFit
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PHLivePhotoView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPlaybackChanged = onPlaybackChanged
        if view.livePhoto !== photo { view.livePhoto = photo }
        guard coordinator.playbackID != playbackID else { return }
        coordinator.playbackID = playbackID
        // Playback starts after SwiftUI finishes updating and the view has its size.
        coordinator.eventGeneration = UUID()
        let generation = coordinator.eventGeneration
        Task { @MainActor [weak view, weak coordinator] in
            guard let view, let coordinator, coordinator.eventGeneration == generation else { return }
            if playbackID != nil { view.startPlayback(with: .full) }
            else { view.stopPlayback() }
        }
    }

    static func dismantleNSView(_ view: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.eventGeneration = UUID()
        coordinator.onPlaybackChanged = nil
        view.delegate = nil
        view.stopPlayback()
        view.livePhoto = nil
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var playbackID: UUID?
        var eventGeneration = UUID()
        var onPlaybackChanged: ((Bool) -> Void)?

        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            notify(true)
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            notify(false)
        }

        private func notify(_ playing: Bool) {
            let generation = eventGeneration
            Task { @MainActor [weak self] in
                guard let self, eventGeneration == generation else { return }
                onPlaybackChanged?(playing)
            }
        }
    }
}

private struct PhotoViewerView: View {
    private struct FaceSelection: Identifiable {
        let id = UUID()
        let index: Int
        let asset: LibraryAsset
    }

    let assets: [LibraryAsset]
    let initialIndex: Int
    let albumTitle: String
    let onBack: (String) -> Void

    @State private var currentIndex: Int
    @State private var image: NSImage?
    @State private var imageLoadError: String?
    @State private var livePhoto: PHLivePhoto?
    @State private var livePhotoRequestID: PHImageRequestID?
    @State private var livePhotoGeneration = UUID()
    @State private var livePhotoLoadError: String?
    @State private var isLoadingLivePhoto = false
    @State private var isPlayingLivePhoto = false
    @State private var livePhotoPlaybackID: UUID?
    @State private var metadata: PhotoMetadata?
    @State private var ollamaText: String?
    @State private var isShowingInfo = true
    @State private var isShowingFaceBoxes = true
    @State private var isAnalyzing = false
    @State private var analysisResult: VisionAnalysisResult?
    @State private var detectedFaceCount: Int?
    @State private var detectedFaceBoxes: [CGRect] = []
    @State private var detectedFaces: [DetectedFace] = []
    @State private var faceEmbeddings: [FaceEmbedding] = []
    @State private var faceRecognitionStatus = ""
    @State private var isRecognizingFaces = false
    @State private var hasLoadedFaceData = false
    @State private var hasLoadedPeople = false
    @State private var recognitionAttemptedAssetID: String?
    @State private var photoGeneration = UUID()
    @State private var automaticRecognitionTask: Task<Void, Never>?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var isFindingCandidates = false
    @State private var recognitionFailed = false
    @State private var people: [Person] = []
    @State private var mostLabeledPeople: [PersonFaceCount] = []
    @State private var selectedFace: FaceSelection?
    @State private var isOllamaAnalyzing = false
    @State private var zoomScale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1
    @State private var imageOffset: CGSize = .zero
    @State private var viewportSize: CGSize = .zero

    private var displayedZoomScale: CGFloat {
        min(max(zoomScale * gestureScale, 1), 5)
    }

    init(
        assets: [LibraryAsset],
        initialIndex: Int,
        albumTitle: String,
        onBack: @escaping (String) -> Void
    ) {
        self.assets = assets
        let boundedIndex = assets.isEmpty ? 0 : min(max(initialIndex, 0), assets.count - 1)
        self.initialIndex = boundedIndex
        self.albumTitle = albumTitle
        self.onBack = onBack
        _currentIndex = State(initialValue: boundedIndex)
    }

    private var currentAsset: LibraryAsset {
        assets[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    exitViewer()
                } label: {
                    Label("返回相册：\(albumTitle)", systemImage: "chevron.left")
                        .lineLimit(1)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("backToPhotoLibrary")
                .help("返回相册：\(albumTitle)")

                Text("照片 \(currentIndex + 1) / \(assets.count)")
                    .foregroundStyle(.secondary)
                if currentAsset.isLivePhoto {
                    Label("LIVE", systemImage: "livephoto")
                        .accessibilityIdentifier("livePhotoBadge")
                    if isLoadingLivePhoto {
                        ProgressView().controlSize(.small)
                        Text("正在加载 Live Photo…").font(.caption)
                    } else if livePhoto != nil {
                        Button {
                            isPlayingLivePhoto.toggle()
                            livePhotoPlaybackID = isPlayingLivePhoto ? UUID() : nil
                        } label: {
                            Label(isPlayingLivePhoto ? "停止" : "播放 Live Photo",
                                  systemImage: isPlayingLivePhoto ? "stop.fill" : "play.fill")
                        }
                        .accessibilityIdentifier("playLivePhoto")
                    } else if let livePhotoLoadError {
                        Text("动态内容加载失败，显示静态照片")
                            .font(.caption)
                            .help(livePhotoLoadError)
                        Button("重试") { loadLivePhoto() }
                    }
                }
                Spacer()
            }
            .padding()

            HStack(spacing: 0) {
                ZStack {
                    Color.black.opacity(0.7)

                    if let image {
                        ZStack {
                            if let livePhoto {
                                let generation = livePhotoGeneration
                                LivePhotoPlayer(photo: livePhoto, playbackID: livePhotoPlaybackID) { playing in
                                    guard livePhotoGeneration == generation else { return }
                                    isPlayingLivePhoto = playing
                                }
                                .id(generation)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(24)
                            } else {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(24)
                            }

                            TrackpadScrollView(
                                isZoomed: displayedZoomScale > 1,
                                onHorizontalScroll: { handleTrackpadScroll($0) },
                                onPan: { delta in
                                    guard displayedZoomScale > 1 else { return }
                                    imageOffset = boundedOffset(CGSize(
                                        width: imageOffset.width + delta.width,
                                        height: imageOffset.height + delta.height
                                    ))
                                },
                                onMagnification: { magnification in
                                    zoomScale = min(max(zoomScale * (1 + magnification), 1), 5)
                                },
                                onDoubleClick: { location in
                                    toggleDoubleClickZoom(at: location)
                                }
                            )

                            if isShowingFaceBoxes && !isPlayingLivePhoto {
                                FaceBoundingBoxOverlay(
                                    imageSize: image.size,
                                    faces: detectedFaces,
                                    personNames: Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.displayName) })
                                ) { index in
                                    selectedFace = FaceSelection(index: index, asset: currentAsset)
                                    refreshMostLabeledPeople()
                                }
                            }
                        }
                        .scaleEffect(displayedZoomScale)
                        .offset(boundedOffset(imageOffset))
                        .gesture(
                            MagnificationGesture()
                                .updating($gestureScale) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    zoomScale = min(max(zoomScale * value, 1), 5)
                                }
                        )
                    } else if let imageLoadError {
                        ContentUnavailableView("图片无法读取", systemImage: "photo.badge.exclamationmark", description: Text(imageLoadError))
                    } else {
                        ProgressView()
                    }

                    if let detectedFaceCount {
                        Text(detectedFaceCount == 0 ? "未检测到人脸" : "检测到 \(detectedFaceCount) 张人脸")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.7), in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(16)
                    }

                    if isRecognizingFaces || !faceRecognitionStatus.isEmpty {
                        HStack(spacing: 8) {
                            if isRecognizingFaces { ProgressView().controlSize(.small).tint(.white) }
                            Text(isRecognizingFaces
                                 ? (isFindingCandidates ? "正在查询可能人物…"
                                    : recognitionAttemptedAssetID == nil ? "准备识别人脸…" : "正在识别人脸…")
                                 : faceRecognitionStatus)
                                .font(.caption)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            if recognitionFailed {
                                Button("重试") { startFaceRecognition(force: true) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(10)
                        .background(.black.opacity(0.75), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // clipped 只裁剪画面；交互区域也必须限制在未缩放的视口内。
                .contentShape(.interaction, Rectangle())
                .clipped()
                .modifier(PhotoExportMenu(asset: currentAsset))
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    viewportSize = size
                    imageOffset = boundedOffset(imageOffset)
                }
                .onChange(of: displayedZoomScale) { _, _ in
                    imageOffset = boundedOffset(imageOffset)
                }
                if isShowingInfo {
                    PhotoInfoSidebar(asset: currentAsset, metadata: metadata, ollamaText: ollamaText)
                        .frame(width: 300)
                }
            }

            HStack(spacing: 20) {
                Button {
                    showPrevious()
                } label: {
                    Label("上一张", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("previousPhoto")
                .disabled(currentIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button {
                    showNext()
                } label: {
                    Label("下一张", systemImage: "chevron.right")
                }
                .accessibilityIdentifier("nextPhoto")
                .disabled(currentIndex == assets.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .task(id: currentAsset.revisionID) {
            loadCurrentImage()
            loadMetadata()
            loadOllamaText()
            loadFaceDetectionResult()
        }
        .onDisappear {
            invalidateRecognition()
            resetLivePhoto()
        }
        .sheet(item: $selectedFace) { selection in
            PersonAssignmentSheet(
                people: people,
                mostLabeledPeople: $mostLabeledPeople,
                faces: $detectedFaces,
                faceIndex: selection.index,
                isRecognizingFaces: $isRecognizingFaces,
                onAssign: { personID in
                    assignPerson(personID, faceIndex: selection.index, asset: selection.asset)
                },
                onCreate: { name in
                    assignNewPerson(named: name, faceIndex: selection.index, asset: selection.asset)
                }
            )
        }
        .toolbar {
            ToolbarItem {
                HiddenMediaButton(asset: currentAsset)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                MediaShareButton(asset: currentAsset)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    isShowingInfo.toggle()
                } label: {
                    Label("照片信息", systemImage: "info.circle")
                }
                .accessibilityIdentifier("photoInfo")
                .help("显示或隐藏照片信息")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    copyCurrentImage()
                } label: {
                    Label("复制图片", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("copyImage")
                .disabled(image == nil)
                .keyboardShortcut("c", modifiers: .command)
                .help("复制当前图片（⌘C）")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    analyzeCurrentImage(.text)
                } label: {
                    Label("识别文字", systemImage: "text.viewfinder")
                }
                .accessibilityIdentifier("recognizeText")
                .disabled(image == nil || isAnalyzing)
                .help("识别当前照片中的文字")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    analyzeCurrentImage(.barcode)
                } label: {
                    Label("识别二维码和条码", systemImage: "barcode.viewfinder")
                }
                .accessibilityIdentifier("recognizeBarcodes")
                .disabled(image == nil || isAnalyzing)
                .help("识别当前照片中的二维码和条码")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    analyzeCurrentImage(.faces)
                } label: {
                    Label("检测人脸", systemImage: "face.smiling")
                }
                .accessibilityIdentifier("detectFaces")
                .disabled(image == nil || isAnalyzing)
                .help("检测当前照片中的人脸")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    isShowingFaceBoxes.toggle()
                } label: {
                    Label(isShowingFaceBoxes ? "隐藏人脸方框" : "显示人脸方框", systemImage: "person.crop.rectangle")
                }
                .keyboardShortcut("f", modifiers: [])
                .help(isShowingFaceBoxes ? "隐藏人脸方框（F）" : "显示人脸方框（F）")
                .accessibilityIdentifier("toggleFaceBoxes")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    startFaceRecognition(force: true)
                } label: {
                    Label("识别人脸并匹配", systemImage: "person.crop.rectangle.stack")
                }
                .accessibilityIdentifier("recognizeAndMatchFaces")
                .disabled(image == nil || !hasLoadedFaceData || !hasLoadedPeople || recognitionTask != nil)
                .help("使用本地模型识别人脸，并从 Chroma 查询可能人物")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    analyzeCurrentImageWithOllama()
                } label: {
                    Label("Ollama 识图", systemImage: "brain")
                }
                .accessibilityIdentifier("ollamaImageRecognition")
                .disabled(image == nil || isAnalyzing || isOllamaAnalyzing)
                .help("使用本机 Ollama 视觉模型描述当前照片")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                if isAnalyzing || isOllamaAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .help(isOllamaAnalyzing ? "Ollama 正在分析照片" : "正在分析照片")
                }
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    zoomScale = min(zoomScale + 0.25, 5)
                } label: {
                    Label("放大", systemImage: "plus.magnifyingglass")
                }
                .accessibilityIdentifier("zoomIn")
                .disabled(image == nil || zoomScale >= 5)
                .help("放大照片")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    zoomScale = max(zoomScale - 0.25, 1)
                } label: {
                    Label("缩小", systemImage: "minus.magnifyingglass")
                }
                .accessibilityIdentifier("zoomOut")
                .disabled(image == nil || zoomScale <= 1)
                .help("缩小照片")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    zoomScale = 1
                    imageOffset = .zero
                } label: {
                    Text("\(Int(displayedZoomScale * 100))%")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("zoomPercentage")
                .disabled(image == nil)
                .help("还原为适合窗口的大小")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: showPrevious()
            case .right: showNext()
            default: break
            }
        }
        .onExitCommand(perform: exitViewer)
        .sheet(item: $analysisResult) { result in
            VisionAnalysisResultView(result: result)
        }
    }

    private func showPrevious() {
        guard currentIndex > 0 else { return }
        navigate(to: currentIndex - 1)
    }

    private func showNext() {
        guard currentIndex + 1 < assets.count else { return }
        navigate(to: currentIndex + 1)
    }

    private func navigate(to index: Int) {
        invalidateRecognition()
        resetLivePhoto()
        image = nil
        metadata = nil
        ollamaText = nil
        detectedFaceCount = nil
        detectedFaceBoxes = []
        detectedFaces = []
        faceEmbeddings = []
        currentIndex = index
    }

    private func exitViewer() {
        // 先清理查看器状态，避免在 500% 缩放或平移过程中退出时残留手势状态。
        invalidateRecognition()
        resetLivePhoto()
        zoomScale = 1
        imageOffset = .zero
        onBack(currentAsset.localIdentifier)
    }

    private func handleTrackpadScroll(_ horizontalDelta: CGFloat) {
        guard displayedZoomScale == 1 else { return }
        if horizontalDelta > 0 {
            showPrevious()
        } else {
            showNext()
        }
    }

    private func toggleDoubleClickZoom(at appKitLocation: CGPoint) {
        if displayedZoomScale <= 1 {
            let targetZoomScale: CGFloat = 5
            let focusPoint = CGSize(
                width: appKitLocation.x - viewportSize.width / 2,
                // AppKit 原点在左下角，SwiftUI 的 offset 以左上角方向为正。
                height: viewportSize.height / 2 - appKitLocation.y
            )
            let currentZoomScale = max(displayedZoomScale, 1)
            let focusedOffset = CGSize(
                width: focusPoint.width -
                    (focusPoint.width - imageOffset.width) * targetZoomScale / currentZoomScale,
                height: focusPoint.height -
                    (focusPoint.height - imageOffset.height) * targetZoomScale / currentZoomScale
            )
            zoomScale = targetZoomScale
            imageOffset = PhotoViewerGeometry.boundedOffset(
                focusedOffset,
                imageSize: image?.size ?? .zero,
                viewportSize: viewportSize,
                zoomScale: targetZoomScale
            )
        } else {
            zoomScale = 1
            imageOffset = .zero
        }
    }

    private func boundedOffset(_ offset: CGSize) -> CGSize {
        PhotoViewerGeometry.boundedOffset(
            offset,
            imageSize: image?.size ?? .zero,
            viewportSize: viewportSize,
            zoomScale: displayedZoomScale
        )
    }

    private func copyCurrentImage() {
        guard let image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func loadCurrentImage() {
        invalidateRecognition()
        loadLivePhoto()
        let asset = currentAsset
        let assetID = asset.localIdentifier
        let generation = photoGeneration
        image = nil
        imageLoadError = nil
        zoomScale = 1
        imageOffset = .zero
        analysisResult = nil
        detectedFaceCount = nil
        detectedFaceBoxes = []
        detectedFaces = []
        faceEmbeddings = []
        faceRecognitionStatus = ""
        hasLoadedFaceData = false
        hasLoadedPeople = false
        recognitionAttemptedAssetID = nil
        selectedFace = nil
        isAnalyzing = false
        isOllamaAnalyzing = false

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        LibraryImageManager.shared.requestImage(
            for: asset,
            targetSize: CGSize(width: 2400, height: 2400),
            contentMode: .aspectFit,
            options: options
        ) { nsImage, info in
            Task { @MainActor in
                guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
                guard let nsImage else {
                    imageLoadError = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "请刷新目录或重新授权。"
                    return
                }
                image = nsImage
                maybeStartFaceRecognition()
            }
        }
    }

    private func resetLivePhoto() {
        // Independent of recognition: relabeling a face must not invalidate playback.
        livePhotoGeneration = UUID()
        if let livePhotoRequestID {
            PHImageManager.default().cancelImageRequest(livePhotoRequestID)
        }
        livePhotoRequestID = nil
        livePhoto = nil
        livePhotoLoadError = nil
        isLoadingLivePhoto = false
        isPlayingLivePhoto = false
        livePhotoPlaybackID = nil
    }

    private func loadLivePhoto() {
        resetLivePhoto()
        let asset = currentAsset
        guard asset.isLivePhoto, case .photos(let photo) = asset.source else { return }
        let generation = livePhotoGeneration
        let revision = asset.revisionID
        isLoadingLivePhoto = true
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        livePhotoRequestID = PHImageManager.default().requestLivePhoto(
            for: photo,
            targetSize: CGSize(width: 2400, height: 2400),
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            let errorMessage = (info?[PHImageErrorKey] as? Error)?.localizedDescription
            Task { @MainActor in
                guard livePhotoGeneration == generation, currentAsset.revisionID == revision,
                      !cancelled, !degraded else { return }
                livePhotoRequestID = nil
                isLoadingLivePhoto = false
                guard let result else {
                    livePhotoLoadError = errorMessage ?? "无法加载 Live Photo 的动态内容。"
                    return
                }
                livePhoto = result
                isPlayingLivePhoto = true
                livePhotoPlaybackID = UUID()
            }
        }
    }

    private func loadMetadata() {
        let asset = currentAsset
        let assetID = asset.localIdentifier
        metadata = nil

        PhotoMetadataCache.shared.metadata(for: asset) { cachedMetadata in
            guard currentAsset.localIdentifier == assetID else { return }
            if let cachedMetadata, cachedMetadata.metadataUpdatedAt != nil {
                metadata = cachedMetadata
            } else {
                loadMetadataFromPhotos(asset: asset, assetID: assetID)
            }
        }
    }

    private func loadOllamaText() {
        let assetID = currentAsset.localIdentifier
        ollamaText = nil
        PhotoMetadataCache.shared.ollamaText(for: currentAsset) { text in
            guard currentAsset.localIdentifier == assetID else { return }
            ollamaText = text
        }
    }

    private func loadFaceDetectionResult() {
        let asset = currentAsset
        let assetID = asset.localIdentifier
        let generation = photoGeneration
        detectedFaceCount = nil
        detectedFaceBoxes = []
        detectedFaces = []
        mostLabeledPeople = []
        hasLoadedFaceData = false
        hasLoadedPeople = false

        PhotoMetadataCache.shared.faceDetectionResult(for: asset) { result in
            guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
            if let result {
                detectedFaceCount = result.faceCount
                detectedFaces = result.faces
                detectedFaceBoxes = result.faceBoxes
            }
            hasLoadedFaceData = true
            maybeStartFaceRecognition()
        }
        PhotoMetadataCache.shared.people { loadedPeople in
            guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
            people = loadedPeople
            hasLoadedPeople = true
            maybeStartFaceRecognition()
        }
        refreshMostLabeledPeople()
    }

    private func refreshMostLabeledPeople() {
        let assetID = currentAsset.localIdentifier
        let generation = photoGeneration
        PhotoMetadataCache.shared.mostLabeledPeople { rankedPeople in
            guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
            mostLabeledPeople = rankedPeople
        }
    }

    private func assignPerson(
        _ personID: String?,
        faceIndex: Int,
        asset: LibraryAsset
    ) {
        guard currentAsset.revisionID == asset.revisionID,
              detectedFaces.indices.contains(faceIndex)
        else { return }

        invalidateRecognition()
        let generation = photoGeneration
        let previous = detectedFaces[faceIndex].personID
        let assetID = asset.localIdentifier
        let face = detectedFaces[faceIndex]
        detectedFaces[faceIndex] = DetectedFace(box: face.box, personID: personID, candidate: nil)
        selectedFace = nil
        PhotoMetadataCache.shared.saveFacePersonID(personID, faceIndex: faceIndex, for: asset) { succeeded in
            guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
            if !succeeded, detectedFaces.indices.contains(faceIndex) {
                detectedFaces[faceIndex] = DetectedFace(box: face.box, personID: previous, candidate: face.candidate)
                faceRecognitionStatus = AppLocalization.localizedString("人物已保存，但人脸标注未写入 SQLite。请重新检测后再试。", comment: "")
            } else if succeeded {
                refreshMostLabeledPeople()
                guard let embedding = faceEmbeddings.first(where: { boxesMatch($0.box, face.box) }) else { return }
                Task {
                    do {
                        let configuration = ChromaConfiguration.current
                        let collectionID = try await ChromaService.shared.createCollectionIfNeeded(configuration: configuration)
                        let vectorID = "\(assetID)#\(faceIndex)"
                        if let personID,
                           let person = people.first(where: { $0.id == personID }) {
                            try await ChromaService.shared.upsert(
                                ids: [vectorID], embeddings: [embedding.vector],
                                metadatas: [[
                                    "asset_id": assetID,
                                    "person_id": person.id,
                                    "display_name": person.displayName,
                                    "model_id": FaceRecognitionService.modelIdentifier
                                ]],
                                collectionID: collectionID, configuration: configuration
                            )
                        } else {
                            try await ChromaService.shared.delete(ids: [vectorID], collectionID: collectionID, configuration: configuration)
                        }
                    } catch {
                        guard currentAsset.localIdentifier == assetID else { return }
                        faceRecognitionStatus = String.localizedStringWithFormat(
                            AppLocalization.localizedString("人物标注已保存在本地，但 Chroma 更新失败：%@", comment: ""),
                            error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    private func assignNewPerson(named name: String, faceIndex: Int, asset: LibraryAsset) {
        guard currentAsset.revisionID == asset.revisionID else { return }
        PhotoMetadataCache.shared.savePerson(named: name) { person in
            guard let person else { return }
            if !people.contains(where: { $0.id == person.id }) { people.append(person) }
            guard currentAsset.revisionID == asset.revisionID else { return }
            assignPerson(person.id, faceIndex: faceIndex, asset: asset)
        }
    }

    private func maybeStartFaceRecognition() {
        guard image != nil, hasLoadedFaceData, hasLoadedPeople,
              recognitionAttemptedAssetID != currentAsset.localIdentifier,
              !isRecognizingFaces, automaticRecognitionTask == nil
        else { return }
        guard FaceRecognitionConfiguration.modelURL() != nil else {
            faceRecognitionStatus = AppLocalization.localizedString("人脸框来自基础检测；请在设置中选择 GGUF 模型，再点击“识别人脸并匹配”生成候选。", comment: "")
            return
        }
        let generation = photoGeneration
        isRecognizingFaces = true
        automaticRecognitionTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, photoGeneration == generation else { return }
            automaticRecognitionTask = nil
            startFaceRecognition(force: false)
        }
    }

    private func invalidateRecognition() {
        photoGeneration = UUID()
        automaticRecognitionTask?.cancel()
        automaticRecognitionTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecognizingFaces = false
        isFindingCandidates = false
        recognitionFailed = false
        faceRecognitionStatus = ""
    }

    private func startFaceRecognition(force: Bool) {
        if force { invalidateRecognition() }
        let asset = currentAsset
        let assetID = asset.localIdentifier
        let generation = photoGeneration
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        if !force, recognitionAttemptedAssetID == assetID { return }
        recognitionAttemptedAssetID = assetID
        isRecognizingFaces = true
        isFindingCandidates = false
        recognitionFailed = false
        faceRecognitionStatus = ""

        recognitionTask = Task {
            do {
                let embeddings = try await FaceRecognitionService.shared.recognize(image: cgImage)
                guard !Task.isCancelled, photoGeneration == generation else { return }
                faceEmbeddings = embeddings
                var matchedFaces = embeddings.map { embedding in
                    let existing = detectedFaces
                        .filter { boxesMatch($0.box, embedding.box) }
                        .max { intersectionOverUnion($0.box, embedding.box) < intersectionOverUnion($1.box, embedding.box) }
                    return DetectedFace(box: embedding.box, personID: existing?.personID)
                }
                detectedFaces = matchedFaces
                detectedFaceBoxes = matchedFaces.map(\.box)
                detectedFaceCount = matchedFaces.count
                isFindingCandidates = true
                do {
                    matchedFaces = try await indexConfirmedFacesAndFindCandidates(
                        faces: matchedFaces,
                        embeddings: embeddings,
                        assetID: assetID,
                        generation: generation
                    )
                    guard !Task.isCancelled, photoGeneration == generation else { return }
                    detectedFaces = matchedFaces
                    faceRecognitionStatus = AppLocalization.localizedString(
                        matchedFaces.contains(where: { $0.candidate != nil })
                            ? "紫色提示是可能人物，请点击人脸确认或重新标注。"
                            : "识别完成，但 Chroma 没有阈值内候选。已标注照片需先运行“识别人脸并匹配”，将人脸向量写入索引。",
                        comment: ""
                    )
                } catch {
                    guard !Task.isCancelled, photoGeneration == generation else { return }
                    faceRecognitionStatus = String.localizedStringWithFormat(
                        AppLocalization.localizedString("本地检测完成，但 Chroma 查询失败：%@", comment: ""),
                        error.localizedDescription
                    )
                    recognitionFailed = true
                }
                guard !Task.isCancelled, photoGeneration == generation else { return }
                PhotoMetadataCache.shared.saveFaceDetectionResult(
                    FaceDetectionResult(faceCount: matchedFaces.count, faces: matchedFaces, detectorVersion: FaceDetectionResult.currentDetectorVersion),
                    for: asset
                )
            } catch {
                guard !Task.isCancelled, photoGeneration == generation else { return }
                faceRecognitionStatus = error.localizedDescription
                recognitionFailed = true
            }
            guard !Task.isCancelled, photoGeneration == generation else { return }
            isRecognizingFaces = false
            isFindingCandidates = false
            recognitionTask = nil
        }
    }

    private func indexConfirmedFacesAndFindCandidates(
        faces: [DetectedFace],
        embeddings: [FaceEmbedding],
        assetID: String,
        generation: UUID
    ) async throws -> [DetectedFace] {
        try Task.checkCancellation()
        guard photoGeneration == generation else { throw CancellationError() }
        let configuration = ChromaConfiguration.current
        let collectionID = try await ChromaService.shared.createCollectionIfNeeded(configuration: configuration)
        try Task.checkCancellation()
        guard photoGeneration == generation else { throw CancellationError() }

        // 浏览照片时不清空已有索引：取消查询不能让后续照片失去匹配来源。
        // 人工修改标注时由 assignPerson 单独更新或删除对应向量。
        let indexed = zip(faces, embeddings).enumerated().compactMap { index, pair -> (String, [Double], [String: String])? in
            let (face, embedding) = pair
            guard let personID = face.personID,
                  let person = people.first(where: { $0.id == personID })
            else { return nil }
            return (
                "\(assetID)#\(index)", embedding.vector,
                ["asset_id": assetID, "person_id": personID, "display_name": person.displayName,
                 "model_id": FaceRecognitionService.modelIdentifier]
            )
        }
        if !indexed.isEmpty {
            try Task.checkCancellation()
            guard photoGeneration == generation else { throw CancellationError() }
            try await ChromaService.shared.upsert(
                ids: indexed.map(\.0), embeddings: indexed.map(\.1), metadatas: indexed.map(\.2),
                collectionID: collectionID, configuration: configuration
            )
        }
        try Task.checkCancellation()
        guard photoGeneration == generation else { throw CancellationError() }

        var result = faces
        for index in result.indices where result[index].personID == nil {
            try Task.checkCancellation()
            guard photoGeneration == generation else { throw CancellationError() }
            let query = try await ChromaService.shared.query(
                embedding: embeddings[index].vector,
                results: 5,
                collectionID: collectionID,
                configuration: configuration
            )
            try Task.checkCancellation()
            guard photoGeneration == generation else { throw CancellationError() }
            let candidate = FaceCandidateRanking.topFive(from: query, people: people).first
            guard let candidate else { continue }
            result[index] = DetectedFace(
                box: result[index].box,
                personID: nil,
                candidate: candidate
            )
        }
        return result
    }

    private func boxesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        intersectionOverUnion(lhs, rhs) >= 0.5
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let area = lhs.width * lhs.height + rhs.width * rhs.height - intersection.width * intersection.height
        return area > 0 ? intersection.width * intersection.height / area : 0
    }

    private func loadMetadataFromPhotos(asset: LibraryAsset, assetID: String) {

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        LibraryImageManager.shared.requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { data, uti, _, _ in
            guard let data else { return }
            let parsedMetadata = PhotoMetadata(asset: asset, data: data, uti: uti)
            PhotoMetadataCache.shared.save(parsedMetadata, for: asset)
            Task { @MainActor in
                guard currentAsset.localIdentifier == assetID else { return }
                metadata = parsedMetadata
            }
        }
    }

    private func analyzeCurrentImage(_ type: VisionAnalysisType) {
        let asset = currentAsset
        let assetID = asset.localIdentifier
        let generation = photoGeneration
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            if type != .faces {
                analysisResult = VisionAnalysisResult(
                    title: AppLocalization.localizedString("无法分析照片", comment: ""),
                    message: AppLocalization.localizedString("当前照片还没有加载完成。", comment: "")
                )
            }
            return
        }

        isAnalyzing = true
        analysisResult = nil
        detectedFaceCount = nil
        detectedFaceBoxes = []
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.performAnalysis(type, on: cgImage)
            Task { @MainActor in
                guard currentAsset.localIdentifier == assetID else { return }
                guard photoGeneration == generation else { return }
                isAnalyzing = false
                detectedFaceCount = result.faceCount
                analysisResult = type == .faces ? nil : result
                if type == .faces, let faceCount = result.faceCount {
                    let faces = result.faceBoxes.map { box in
                        let existing = detectedFaces
                            .filter { boxesMatch($0.box, box) }
                            .max { intersectionOverUnion($0.box, box) < intersectionOverUnion($1.box, box) }
                        return DetectedFace(box: box, personID: existing?.personID, candidate: existing?.candidate)
                    }
                    detectedFaces = faces
                    detectedFaceBoxes = faces.map(\.box)
                    PhotoMetadataCache.shared.saveFaceDetectionResult(
                        FaceDetectionResult(
                            faceCount: faceCount,
                            faces: faces,
                            detectorVersion: FaceDetectionResult.legacyDetectorVersion
                        ),
                        for: asset
                    )
                    if FaceRecognitionConfiguration.modelURL() != nil, !isRecognizingFaces {
                        startFaceRecognition(force: true)
                    } else if FaceRecognitionConfiguration.modelURL() == nil {
                                faceRecognitionStatus = AppLocalization.localizedString("检测到人脸；要查询“可能是某某”，请先在设置中选择本地 GGUF 模型。", comment: "")
                    }
                } else {
                    detectedFaceBoxes = result.faceBoxes
                }
            }
        }
    }

    private func analyzeCurrentImageWithOllama() {
        guard let image,
              let imageData = Self.jpegData(from: image)
        else {
            analysisResult = VisionAnalysisResult(
                title: AppLocalization.localizedString("无法分析照片", comment: ""),
                message: AppLocalization.localizedString("当前照片还没有加载完成。", comment: "")
            )
            return
        }

        let asset = currentAsset
        let assetID = asset.localIdentifier
        let generation = photoGeneration
        let configuration = OllamaConfiguration.current
        isOllamaAnalyzing = true
        analysisResult = nil

        Task {
            do {
                let text = try await OllamaVisionService.shared.analyze(
                    imageData: imageData,
                    configuration: configuration
                )
                guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
                let saved: Bool = await withCheckedContinuation { continuation in
                    PhotoMetadataCache.shared.saveOllamaText(text, model: configuration.model, for: asset) { succeeded in
                        continuation.resume(returning: succeeded)
                    }
                }
                guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
                guard saved else { throw DiskLibraryError.message("图片或数据库已变化，识别结果未保存。请刷新后重试。") }
                isOllamaAnalyzing = false
                ollamaText = text
                analysisResult = VisionAnalysisResult(title: AppLocalization.localizedString("Ollama 图片识别结果", comment: ""), message: text)
            } catch {
                guard currentAsset.localIdentifier == assetID, photoGeneration == generation else { return }
                PhotoMetadataCache.shared.recordOllamaFailure(for: asset)
                isOllamaAnalyzing = false
                analysisResult = VisionAnalysisResult(
                    title: AppLocalization.localizedString("Ollama 识别失败", comment: ""),
                    message: String.localizedStringWithFormat(
                        AppLocalization.localizedString("%@\n\n请确认 Ollama 已启动，并且设置中的模型支持图片输入。", comment: ""),
                        error.localizedDescription
                    )
                )
            }
        }
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiffData as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1024
                  ] as CFDictionary
              )
        else { return nil }

        let bitmap = NSBitmapImageRep(cgImage: thumbnail)
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.8]
        )
    }

    private static func performAnalysis(_ type: VisionAnalysisType, on image: CGImage) -> VisionAnalysisResult {
        do {
            switch type {
            case .text:
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: image).perform([request])

                let text = (request.results ?? []).compactMap {
                    $0.topCandidates(1).first?.string
                }
                return VisionAnalysisResult(
                    title: AppLocalization.localizedString("文字识别结果", comment: ""),
                    message: text.isEmpty ? AppLocalization.localizedString("没有识别到文字。", comment: "") : text.joined(separator: "\n")
                )

            case .barcode:
                let request = VNDetectBarcodesRequest()
                try VNImageRequestHandler(cgImage: image).perform([request])

                let observations: [VNBarcodeObservation] = request.results ?? []
                let codes: [String] = observations.compactMap { observation in
                    guard let value = observation.payloadStringValue else { return nil }
                    let type = observation.symbology.rawValue
                    return "\(type): \(value)"
                }
                return VisionAnalysisResult(
                    title: AppLocalization.localizedString("二维码和条码结果", comment: ""),
                    message: codes.isEmpty ? AppLocalization.localizedString("没有识别到二维码或条码。", comment: "") : codes.joined(separator: "\n")
                )

            case .faces:
                let request = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(cgImage: image).perform([request])
                let observations: [VNFaceObservation] = request.results ?? []
                let count = observations.count
                return VisionAnalysisResult(
                    title: AppLocalization.localizedString("人脸检测结果", comment: ""),
                    message: count == 0
                        ? AppLocalization.localizedString("没有检测到人脸。", comment: "")
                        : String.localizedStringWithFormat(AppLocalization.localizedString("检测到 %lld 张人脸。", comment: ""), count),
                    faceCount: count,
                    faceBoxes: observations.map(\.boundingBox)
                )
            }
        } catch {
            return VisionAnalysisResult(title: AppLocalization.localizedString("分析失败", comment: ""), message: error.localizedDescription)
        }
    }
}

private enum VisionAnalysisType {
    case text
    case barcode
    case faces
}

private struct VisionAnalysisResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let faceCount: Int?
    let faceBoxes: [CGRect]

    init(title: String, message: String, faceCount: Int? = nil, faceBoxes: [CGRect] = []) {
        self.title = title
        self.message = message
        self.faceCount = faceCount
        self.faceBoxes = faceBoxes
    }
}

private struct TrackpadScrollView: NSViewRepresentable {
    let isZoomed: Bool
    let onHorizontalScroll: (CGFloat) -> Void
    let onPan: (CGSize) -> Void
    let onMagnification: (CGFloat) -> Void
    let onDoubleClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollCaptureView {
        let view = ScrollCaptureView()
        view.isZoomed = isZoomed
        view.onHorizontalScroll = onHorizontalScroll
        view.onPan = onPan
        view.onMagnification = onMagnification
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureView, context: Context) {
        nsView.isZoomed = isZoomed
        nsView.onHorizontalScroll = onHorizontalScroll
        nsView.onPan = onPan
        nsView.onMagnification = onMagnification
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class ScrollCaptureView: NSView {
    var isZoomed = false
    var onHorizontalScroll: ((CGFloat) -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onMagnification: ((CGFloat) -> Void)?
    var onDoubleClick: ((CGPoint) -> Void)?
    private var scrollState = PhotoViewerScrollState()

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(convert(event.locationInWindow, from: nil))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }

        let action = scrollState.handle(
            delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            isZoomed: isZoomed
        )
        switch action {
        case .navigate(let delta): onHorizontalScroll?(delta)
        case .pan(let delta): onPan?(delta)
        case .none: break
        }
    }

    override func magnify(with event: NSEvent) {
        onMagnification?(event.magnification)
    }
}

// 一次手势固定用途；切图忽略惯性，平移保留惯性。
struct PhotoViewerScrollState {
    enum Action: Equatable {
        case none
        case navigate(CGFloat)
        case pan(CGSize)
    }

    private var startedZoomed: Bool?
    private var accumulatedDelta: CGSize = .zero
    private var hasTriggered = false

    mutating func handle(
        delta: CGSize, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase,
        isZoomed: Bool
    ) -> Action {
        if phase.contains(.cancelled) {
            startedZoomed = nil
            return .none
        }
        if !momentumPhase.isEmpty {
            return startedZoomed == true && isZoomed ? .pan(delta) : .none
        }
        if phase.contains(.began) || startedZoomed == nil {
            startedZoomed = isZoomed
            accumulatedDelta = .zero
            hasTriggered = false
        }
        guard startedZoomed == isZoomed else { return .none }
        if isZoomed { return .pan(delta) }
        // 结束事件不能解除切图锁，下一次 began 才能再次切图。
        guard !phase.contains(.ended), !hasTriggered else { return .none }
        accumulatedDelta.width += delta.width
        accumulatedDelta.height += delta.height
        guard abs(accumulatedDelta.width) >= 40,
              abs(accumulatedDelta.width) > abs(accumulatedDelta.height)
        else { return .none }
        hasTriggered = true
        return .navigate(accumulatedDelta.width)
    }
}

enum PhotoViewerGeometry {
    static func boundedOffset(
        _ offset: CGSize, imageSize: CGSize, viewportSize: CGSize, zoomScale: CGFloat
    ) -> CGSize {
        guard zoomScale > 1, imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return .zero }
        let fitScale = min(
            max(viewportSize.width - 48, 0) / imageSize.width,
            max(viewportSize.height - 48, 0) / imageSize.height
        )
        let maxX = max((imageSize.width * fitScale * zoomScale - viewportSize.width) / 2, 0)
        let maxY = max((imageSize.height * fitScale * zoomScale - viewportSize.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}

enum FaceOverlayGeometry {
    static func imageRect(imageSize: CGSize, viewportSize: CGSize, padding: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let inset = max(padding, 0) * 2
        let scale = min(max(viewportSize.width - inset, 0) / imageSize.width,
                        max(viewportSize.height - inset, 0) / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (viewportSize.width - size.width) / 2,
                      y: (viewportSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func faceRect(_ box: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + box.minX * imageRect.width,
               y: imageRect.minY + (1 - box.maxY) * imageRect.height,
               width: box.width * imageRect.width, height: box.height * imageRect.height)
    }
}

private struct FaceBoundingBoxOverlay: View {
    let imageSize: CGSize
    let faces: [DetectedFace]
    let personNames: [String: String]
    var imagePadding: CGFloat = 24
    var minimumBoxSize: CGFloat = 28
    let onFaceTap: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let imageRect = FaceOverlayGeometry.imageRect(imageSize: imageSize, viewportSize: proxy.size, padding: imagePadding)

            ForEach(Array(faces.enumerated()), id: \.offset) { index, face in
                let box = FaceOverlayGeometry.faceRect(face.box, in: imageRect)
                Button {
                    onFaceTap(index)
                } label: {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(face.personID != nil ? .green : face.candidate != nil ? .purple : .yellow, lineWidth: 3)
                        if let personID = face.personID,
                           let personName = personNames[personID] {
                            faceNameLabel(personName, color: .green)
                                .offset(y: -24)
                        } else if let candidate = face.candidate {
                            faceNameLabel("可能是：\(candidate.displayName) · \(candidate.similarityPercent)%", color: .purple)
                                .offset(y: -24)
                        }
                    }
                    .frame(width: max(box.width, minimumBoxSize), height: max(box.height, minimumBoxSize))
                    .frame(width: max(box.width, 28), height: max(box.height, 28))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("faceBoundingBox-\(index)")
                .accessibilityLabel("标注人脸 \(index + 1)")
                .frame(
                    width: max(box.width, 28),
                    height: max(box.height, 28)
                )
                .position(
                    x: box.midX,
                    y: box.midY
                )
            }
        }
    }

    private func faceNameLabel(_ name: String, color: Color) -> some View {
        Text(name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
    }
}

enum FaceCandidateRanking {
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func topFive(from query: ChromaQueryResult, people: [Person]) -> [FacePersonCandidate] {
        guard let ids = query.ids.first,
              let distances = query.distances.first,
              let metadatas = query.metadatas.first else { return [] }

        let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        let ranked = zip(zip(ids, distances), metadatas).compactMap { pair, metadata -> FacePersonCandidate? in
            guard let metadata,
                  metadata["model_id"] == FaceRecognitionService.modelIdentifier,
                  let personID = metadata["person_id"],
                  let person = peopleByID[personID],
                  pair.1.isFinite,
                  pair.1 <= FaceRecognitionService.maximumCosineDistance
            else { return nil }
            return FacePersonCandidate(personID: personID, displayName: person.displayName, distance: pair.1)
        }.sorted { $0.distance < $1.distance }

        var seenNames = Set<String>()
        return Array(ranked.filter { seenNames.insert(normalizedName($0.displayName)).inserted }.prefix(5))
    }
}

private struct PersonAssignmentSheet: View {
    let people: [Person]
    @Binding var mostLabeledPeople: [PersonFaceCount]
    @Binding var faces: [DetectedFace]
    let faceIndex: Int
    @Binding var isRecognizingFaces: Bool
    let onAssign: (String?) -> Void
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPersonID: String?
    @State private var newPersonName = ""

    private var currentPersonID: String? {
        faces.indices.contains(faceIndex) ? faces[faceIndex].personID : nil
    }

    private var candidate: FacePersonCandidate? {
        faces.indices.contains(faceIndex) ? faces[faceIndex].candidate : nil
    }

    private var uniquePeople: [Person] {
        var seenNames = Set<String>()
        return people.filter { person in
            seenNames.insert(FaceCandidateRanking.normalizedName(person.displayName)).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("标注人物")
                .font(.title3.weight(.semibold))

            Picker("人物", selection: $selectedPersonID) {
                Text("未标注").tag(String?.none)
                ForEach(uniquePeople) { person in
                    Text(person.displayName).tag(Optional(person.id))
                }
            }

            if !mostLabeledPeople.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("标注最多的人物")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(mostLabeledPeople) { entry in
                            Button {
                                onAssign(entry.person.id)
                                dismiss()
                            } label: {
                                Text("\(entry.person.displayName) · \(entry.count) 张")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .help("\(entry.person.displayName)：已标注 \(entry.count) 张人脸，点击确定并保存")
                        }
                    }
                }
            }

            if let candidate {
                Button {
                    onAssign(candidate.personID)
                    dismiss()
                } label: {
                    Label("确认是 \(candidate.displayName)（相似度 \(candidate.similarityPercent)%）", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("confirmFaceCandidate")
            } else if isRecognizingFaces {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在查询可能人物…")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            TextField("新人物名称", text: $newPersonName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        onCreate(name)
                    } else {
                        onAssign(selectedPersonID)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            guard let currentPersonID,
                  let currentPerson = people.first(where: { $0.id == currentPersonID })
            else {
                selectedPersonID = nil
                return
            }
            selectedPersonID = uniquePeople.first(where: {
                FaceCandidateRanking.normalizedName($0.displayName) == FaceCandidateRanking.normalizedName(currentPerson.displayName)
            })?.id
        }
    }
}

private struct MarkdownTextView: View {
    let markdown: String

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VisionAnalysisResultView: View {
    let result: VisionAnalysisResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(result.title, systemImage: "wand.and.stars")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("analysisResultTitle")
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .accessibilityIdentifier("completeAnalysis")
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                MarkdownTextView(markdown: result.message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
    }
}

struct PhotoMetadata {
    let fileType: String?
    let fileSize: String
    let pixelSize: String
    let creationDate: String
    let metadataUpdatedAt: Date?
    let camera: String?
    let lens: String?
    let exposure: String?
    let iso: String?
    let focalLength: String?
    let location: String?

    init(
        fileType: String?, fileSize: String, pixelSize: String, creationDate: String,
        metadataUpdatedAt: Date?,
        camera: String?, lens: String?, exposure: String?, iso: String?,
        focalLength: String?, location: String?
    ) {
        self.fileType = fileType
        self.fileSize = fileSize
        self.pixelSize = pixelSize
        self.creationDate = creationDate
        self.metadataUpdatedAt = metadataUpdatedAt
        self.camera = camera
        self.lens = lens
        self.exposure = exposure
        self.iso = iso
        self.focalLength = focalLength
        self.location = location
    }

    init(asset: LibraryAsset, data: Data, uti: String?) {
        fileType = uti.flatMap { UTType($0)?.localizedDescription } ?? uti
        fileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        pixelSize = "\(asset.pixelWidth) × \(asset.pixelHeight)"
        metadataUpdatedAt = Date()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            creationDate = asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? AppLocalization.localizedString("未知", comment: "")
            camera = nil
            lens = nil
            exposure = nil
            iso = nil
            focalLength = nil
            location = nil
            return
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        creationDate = asset.creationDate?.formatted(date: .abbreviated, time: .shortened)
            ?? (exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String)
            ?? AppLocalization.localizedString("未知", comment: "")

        let make = tiff?[kCGImagePropertyTIFFMake as String] as? String
        let model = tiff?[kCGImagePropertyTIFFModel as String] as? String
        camera = [make, model].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        lens = exif?[kCGImagePropertyExifLensModel as String] as? String
        exposure = Self.exposureValue(exif?[kCGImagePropertyExifExposureTime as String])
        iso = Self.isoValue(exif?[kCGImagePropertyExifISOSpeedRatings as String])
        focalLength = Self.focalLengthValue(exif?[kCGImagePropertyExifFocalLength as String])
        location = gps == nil ? nil : "包含 GPS 信息"
    }

    private static func exposureValue(_ value: Any?) -> String? {
        guard let value = value as? Double else { return nil }
        return value >= 1
            ? AppLocalization.format("%.2f 秒", value)
            : AppLocalization.format("1/%.0f 秒", 1 / value)
    }

    private static func isoValue(_ value: Any?) -> String? {
        if let values = value as? [NSNumber], let first = values.first {
            return "ISO \(first.intValue)"
        }
        if let value = value as? NSNumber {
            return "ISO \(value.intValue)"
        }
        return nil
    }

    private static func focalLengthValue(_ value: Any?) -> String? {
        guard let value = value as? Double else { return nil }
        return String(format: "%.0f mm", value)
    }
}

private struct PhotoInfoSidebar: View {
    let asset: LibraryAsset
    let metadata: PhotoMetadata?
    let ollamaText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("照片信息")
                    .font(.title3.weight(.semibold))

                if let path = asset.relativePath {
                    Text(path).font(.caption).textSelection(.enabled)
                }

                if let databaseURL = PhotoMetadataCache.shared.databaseURL {
                    Text("SQLite 缓存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(databaseURL.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                if let metadata {
                    infoSection("基本信息", rows: [
                        ("分辨率", metadata.pixelSize),
                        ("文件类型", metadata.fileType ?? AppLocalization.localizedString("未知", comment: "")),
                        ("文件大小", metadata.fileSize),
                        ("拍摄时间", metadata.creationDate),
                        ("元数据更新时间", metadata.metadataUpdatedAt.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? AppLocalization.localizedString("未知", comment: "")),
                        ("状态", asset.relativePath == nil ? (asset.isFavorite ? "已收藏" : "未收藏") : "磁盘图片（只读）")
                    ])

                    let shootingRows = [
                        ("相机", metadata.camera),
                        ("镜头", metadata.lens),
                        ("曝光时间", metadata.exposure),
                        ("感光度", metadata.iso),
                        ("焦距", metadata.focalLength),
                        ("位置", metadata.location)
                    ].compactMap { row -> (String, String)? in
                        guard let value = row.1 else { return nil }
                        return (row.0, value)
                    }
                    if !shootingRows.isEmpty {
                        infoSection("拍摄信息", rows: shootingRows)
                    }

                    if let ollamaText, !ollamaText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ollama 识别文字")
                                .font(.headline)
                            MarkdownTextView(markdown: ollamaText)
                                .padding(10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    ProgressView("正在读取照片信息…")
                }
            }
            .padding(20)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func infoSection(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(row.1)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                Divider()
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

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
    @StateObject private var diskLibrary = DiskLibraryStore()
    @StateObject private var batchRecognitionModels = BatchRecognitionModelStore()
    @StateObject private var batchFaceRecognitionModels = BatchFaceRecognitionModelStore()
    @ObservedObject private var hiddenMedia = HiddenMediaStore.shared
    @State private var selectedAlbumID: String?
    @State private var minimumDiskImageLongEdge = 0
    @State private var isShowingBatchRecognition = false
    @State private var batchRecognitionModel: BatchRecognitionModel?
    @State private var isShowingBatchFaceRecognition = false
    @State private var batchFaceRecognitionModel: BatchFaceRecognitionModel?
    @State private var recognitionRevision = 0
    @State private var databaseRevision = 0
    @State private var faceModelReady = FaceRecognitionConfiguration.modelURL() != nil
    @State private var pendingOllamaCount: Int?
    @State private var pendingFaceCount: Int?
    @State private var pendingVideoCoverCount: Int?
    @State private var videoCoverRevision = 0
    @State private var videoCoverCountRequest = UUID()
    @State private var videoCoverModel: BatchVideoCoverModel?
    @State private var isShowingVideoCovers = false

    var body: some View {
        NavigationSplitView {
            PhotoSidebarView(
                albums: photoLibrary.albums,
                photoCounts: hiddenMedia.canShowUnfilteredCounts ? photoLibrary.photoCounts : [:],
                diskLibrary: diskLibrary,
                selectedAlbumID: $selectedAlbumID,
                hasPhotoAccess: hasPhotoAccess,
                showDiskCounts: hiddenMedia.canShowUnfilteredCounts,
                openSettings: openPhotoSettings,
                addDirectory: {
                    Task {
                        if let id = await diskLibrary.addDirectory() { selectedAlbumID = id }
                    }
                }
            )
            .navigationTitle("照片相册")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                SetupNotice(
                    needsPhotoAccess: !hasPhotoAccess,
                    needsFaceModel: !faceModelReady,
                    openPhotoSettings: openPhotoSettings
                )
                detailContent
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Text("HomeBuddy")
                    .font(.headline)

                Toggle(isOn: Binding(get: { hiddenMedia.isHiding }, set: { hiddenMedia.setHiding($0) })) {
                    Label("隐藏已标记内容", systemImage: hiddenMedia.isHiding ? "eye.slash" : "eye")
                }
                .toggleStyle(.button)
                .scaleEffect(0.5)
                .accessibilityIdentifier("hideMarkedMedia")
                .help(hiddenMedia.isHiding ? "已隐藏标记的照片和视频；关闭需输入密码" : "正在显示隐藏内容；点击立即隐藏")

                Button {
                    if let selectedDirectory {
                        Task { await diskLibrary.scan(selectedDirectory) }
                    } else {
                        photoLibrary.refresh()
                        Task { await diskLibrary.reload() }
                    }
                } label: {
                    Label("刷新图库", systemImage: "arrow.clockwise")
                }
                .disabled(selectedDirectory.map { diskLibrary.scanningIDs.contains($0.id) } ?? false)
                .help(selectedDirectory == nil ? "重新读取系统照片图库" : "递归重新扫描当前目录")

                if selectedDirectory != nil {
                    Picker("最小边长", selection: $minimumDiskImageLongEdge) {
                        Text("不筛选").tag(0)
                        Text("800 像素").tag(800)
                        Text("640 像素").tag(640)
                        Text("480 像素").tag(480)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("minimumDiskImageLongEdge")
                    .help("隐藏最长边短于所选像素的本地图片")
                }

                if selectedAlbum?.isVideoAlbum == true {
                    Button {
                        Task { await showVideoCovers() }
                    } label: {
                        Label {
                            Text("提取封面")
                        } icon: {
                            videoCoverToolbarIcon
                        }
                    }
                    .accessibilityIdentifier("batchVideoCovers")
                    .help("批量提取并保存视频封面")
                }

                Button {
                    Task { await showBatchRecognition() }
                } label: {
                    Label {
                        Text(selectedAlbum?.isVideoAlbum == true ? "批量识别封面" : "Ollama 批量识图")
                    } icon: {
                        ollamaToolbarIcon
                    }
                }
                .disabled((selectedDirectory == nil && selectedAlbum == nil && batchRecognitionModels.activeModel == nil)
                          || selectedDirectory.map { diskLibrary.scanningIDs.contains($0.id) } == true)
                .accessibilityIdentifier("batchOllamaRecognition")
                .help("打开 Ollama 批量识图任务")

                Button {
                    Task { await showBatchFaceRecognition() }
                } label: {
                    Label {
                        Text(selectedAlbum?.isVideoAlbum == true ? "批量识别封面人脸" : "批量人脸识别")
                    } icon: {
                        faceRecognitionToolbarIcon
                    }
                }
                .disabled(!faceModelReady
                          || (selectedDirectory == nil && selectedAlbum == nil && batchFaceRecognitionModels.activeModel == nil)
                          || selectedDirectory.map { diskLibrary.scanningIDs.contains($0.id) } == true)
                .accessibilityIdentifier("batchFaceRecognition")
                .help(faceModelReady ? "打开批量人脸识别任务" : "先在设置里选择人脸模型文件")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .popover(isPresented: $isShowingVideoCovers) {
            if let videoCoverModel {
                BatchVideoCoverView(model: videoCoverModel, isPresented: $isShowingVideoCovers)
                    .environment(\.locale, AppLocalization.locale)
            }
        }
        .popover(isPresented: $isShowingBatchRecognition) {
            Group {
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
            .environment(\.locale, AppLocalization.locale)
        }
        .popover(isPresented: $isShowingBatchFaceRecognition) {
            Group {
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
            .environment(\.locale, AppLocalization.locale)
        }
        .task {
            await diskLibrary.reload()
            photoLibrary.requestAccessAndLoad()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            faceModelReady = FaceRecognitionConfiguration.modelURL() != nil
        }
        .onChange(of: photoLibrary.albums) { _, _ in repairSelection() }
        .onChange(of: diskLibrary.directories) { _, _ in repairSelection() }
        .onChange(of: hiddenMedia.revision) { _, _ in
            batchRecognitionModels.reset()
            batchFaceRecognitionModels.reset()
            videoCoverModel?.pause()
            videoCoverModel = nil
            batchRecognitionModel = nil
            batchFaceRecognitionModel = nil
            isShowingVideoCovers = false
            isShowingBatchRecognition = false
            isShowingBatchFaceRecognition = false
        }
        .task(id: pendingCountTaskKey) {
            await refreshPendingRecognitionCounts()
        }
        .task(id: "\(pendingCountTaskKey)|\(videoCoverRevision)") {
            await refreshPendingVideoCoverCount()
        }
        .onChange(of: batchRecognitionModels.activeModel == nil) { wasIdle, isIdle in
            if !wasIdle && isIdle { Task { await refreshPendingRecognitionCounts() } }
        }
        .onChange(of: batchFaceRecognitionModels.activeModel == nil) { wasIdle, isIdle in
            if !wasIdle && isIdle { Task { await refreshPendingRecognitionCounts() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyDatabaseDidChange"))) { _ in
            batchRecognitionModels.activeModel?.stop()
            batchFaceRecognitionModels.activeModel?.pause()
            videoCoverModel?.pause()
            videoCoverModel = nil
            isShowingVideoCovers = false
            isShowingBatchRecognition = false
            isShowingBatchFaceRecognition = false
            batchRecognitionModel = nil
            batchFaceRecognitionModel = nil
            recognitionRevision += 1
            databaseRevision += 1
            Task { await diskLibrary.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyRecognitionDidChange"))) { _ in
            recognitionRevision += 1
            if batchRecognitionModels.activeModel?.phase != .running
                && batchFaceRecognitionModels.activeModel?.phase != .running {
                Task { await refreshPendingRecognitionCounts() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("HomeBuddyVideoCoverDidChange"))) { _ in
            if videoCoverModel?.phase != .running { videoCoverRevision += 1 }
        }
        .alert("目录操作失败", isPresented: Binding(
            get: { diskLibrary.errorMessage != nil },
            set: { if !$0 { diskLibrary.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { diskLibrary.errorMessage = nil }
        } message: {
            Text(diskLibrary.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selectedDirectory {
            DiskPhotoLibraryView(directory: selectedDirectory, revision: diskLibrary.revision,
                                 isScanning: diskLibrary.scanningIDs.contains(selectedDirectory.id),
                                 minimumImageLongEdge: minimumDiskImageLongEdge)
                .id("\(selectedDirectory.id):\(databaseRevision):\(hiddenMedia.revision)")
        } else if let selectedAlbum {
            PhotoLibraryView(
                album: selectedAlbum,
                assets: libraryAssets(for: selectedAlbum, revision: recognitionRevision),
                assetsRevision: libraryAssetCacheKey(revision: recognitionRevision)
            )
                .id("\(selectedAlbum.id):\(databaseRevision):\(hiddenMedia.revision)")
        } else if !hasPhotoAccess && diskLibrary.directories.isEmpty {
            PhotoPermissionView(openSettings: openPhotoSettings)
        } else {
            ContentUnavailableView("选择一个相册", systemImage: "rectangle.stack", description: Text("从左侧选择相册以查看其中的照片。"))
        }
    }

    @ViewBuilder
    private var videoCoverToolbarIcon: some View {
        if let model = videoCoverModel {
            VideoCoverToolbarIcon(model: model, fallbackCount: pendingVideoCoverCount) {
                Task { await refreshPendingVideoCoverCount() }
            }
        } else {
            Image(systemName: "film.stack")
                .overlay(alignment: .topTrailing) {
                    ToolbarPendingCountBadge(count: pendingVideoCoverCount ?? 0)
                        .offset(x: 8, y: -7)
                }
        }
    }

    private var ollamaToolbarIcon: some View {
        BatchRecognitionToolbarIcon(isAnimating: batchRecognitionModels.activeModel?.phase == .running)
            .overlay(alignment: .topTrailing) {
                ollamaPendingBadge
            }
    }

    @ViewBuilder
    private var ollamaPendingBadge: some View {
        if let model = batchRecognitionModels.activeModel {
            ModelPendingCountBadge(
                model: model,
                pendingCount: { $0.remainingCount },
                fallbackCount: pendingOllamaCount,
                refreshWhenIdle: { Task { await refreshPendingRecognitionCounts() } }
            )
            .offset(x: 8, y: -7)
        } else {
            ToolbarPendingCountBadge(count: pendingOllamaCount ?? 0)
                .offset(x: 8, y: -7)
        }
    }

    private var faceRecognitionToolbarIcon: some View {
        BatchFaceRecognitionToolbarIcon(isAnimating: batchFaceRecognitionModels.activeModel?.phase == .running)
            .overlay(alignment: .topTrailing) {
                faceRecognitionPendingBadge
            }
    }

    @ViewBuilder
    private var faceRecognitionPendingBadge: some View {
        if let model = batchFaceRecognitionModels.activeModel {
            ModelPendingCountBadge(
                model: model,
                pendingCount: { max($0.assets.count - $0.completed, 0) },
                fallbackCount: pendingFaceCount,
                refreshWhenIdle: { Task { await refreshPendingRecognitionCounts() } }
            )
            .offset(x: 8, y: -7)
        } else {
            ToolbarPendingCountBadge(count: pendingFaceCount ?? 0)
                .offset(x: 8, y: -7)
        }
    }

    private var selectedDirectory: DiskDirectory? {
        diskLibrary.directories.first { $0.id == selectedAlbumID }
    }

    private func repairSelection() {
        guard selectedDirectory == nil, selectedAlbum == nil else { return }
        selectedAlbumID = photoLibrary.albums.first(where: \.isRecents)?.id
            ?? diskLibrary.directories.first?.id ?? photoLibrary.albums.first?.id
    }

    private var selectedAlbum: PhotoAlbum? {
        photoLibrary.albums.first { $0.id == selectedAlbumID }
    }

    private var hasPhotoAccess: Bool {
        let status = photoLibrary.authorizationStatus
        return status == .authorized || status == .limited
    }

    private func libraryAssets(for album: PhotoAlbum, revision: Int) -> [LibraryAsset] {
        hiddenMedia.visibleAssets(photoLibrary.assets(for: album, cacheKey: libraryAssetCacheKey(revision: revision)))
    }

    private func libraryAssetCacheKey(revision: Int) -> String {
        "\(photoLibrary.revision):\(revision):\(databaseRevision):\(hiddenMedia.revision)"
    }

    private func selectedAssets() async throws -> (id: String, assets: [LibraryAsset])? {
        if let directory = selectedDirectory {
            let images = try await PhotoMetadataCache.shared.diskLibraryOperation { try $0.images(directoryID: directory.id) }
            return (directory.id, hiddenMedia.visibleAssets(images.map { LibraryAsset(directory: directory, image: $0) }))
        }
        if let album = selectedAlbum {
            return (album.id, libraryAssets(for: album, revision: recognitionRevision))
        }
        return nil
    }

    private var pendingCountTaskKey: String {
        "\(selectedAlbumID ?? "")|\(diskLibrary.revision)|\(photoLibrary.revision)|\(databaseRevision)|\(hiddenMedia.revision)"
    }

    private func refreshPendingRecognitionCounts() async {
        let requestKey = pendingCountTaskKey
        do {
            guard let selection = try await selectedAssets() else {
                pendingOllamaCount = 0
                pendingFaceCount = 0
                return
            }
            let counts = await PhotoMetadataCache.shared.pendingRecognitionCounts(for: selection.assets)
            guard !Task.isCancelled, requestKey == pendingCountTaskKey else { return }
            pendingOllamaCount = counts.ollama
            pendingFaceCount = counts.faces
        } catch {
            guard !Task.isCancelled, requestKey == pendingCountTaskKey else { return }
            pendingOllamaCount = nil
            pendingFaceCount = nil
        }
    }

    private func refreshPendingVideoCoverCount() async {
        let request = UUID()
        videoCoverCountRequest = request
        let requestKey = pendingCountTaskKey
        do {
            guard selectedAlbum?.isVideoAlbum == true, let selection = try await selectedAssets() else {
                pendingVideoCoverCount = 0
                return
            }
            let existing = await VideoCoverStore.existingCoverIDs(for: selection.assets)
            guard !Task.isCancelled, request == videoCoverCountRequest,
                  requestKey == pendingCountTaskKey else { return }
            pendingVideoCoverCount = max(selection.assets.count - existing.count, 0)
        } catch {
            guard !Task.isCancelled, request == videoCoverCountRequest,
                  requestKey == pendingCountTaskKey else { return }
            pendingVideoCoverCount = nil
        }
    }

    private func showBatchRecognition() async {
        let visibilityRevision = hiddenMedia.revision
        let model: BatchRecognitionModel?
        if let activeModel = batchRecognitionModels.activeModel,
           (activeModel.assets.first?.isVideo == true) == (selectedAlbum?.isVideoAlbum == true),
           await PhotoMetadataCache.shared.areCurrent(activeModel.assets) {
            model = activeModel
        } else {
            batchRecognitionModels.activeModel?.stop()
            do {
                guard let selection = try await selectedAssets() else { return }
                model = batchRecognitionModels.model(for: selection.id, assets: selection.assets)
            } catch { diskLibrary.errorMessage = error.localizedDescription; return }
        }

        guard let model, visibilityRevision == hiddenMedia.revision,
              model.assets.allSatisfy(hiddenMedia.isVisible) else { return }
        batchRecognitionModel = model
        model.startOrResume()
        isShowingBatchRecognition = true
    }

    private func showBatchFaceRecognition() async {
        let visibilityRevision = hiddenMedia.revision
        let model: BatchFaceRecognitionModel
        if let active = batchFaceRecognitionModels.activeModel,
           (active.assets.first?.isVideo == true) == (selectedAlbum?.isVideoAlbum == true),
           await PhotoMetadataCache.shared.areCurrent(active.assets) {
            model = active
        } else {
            batchFaceRecognitionModels.activeModel?.pause()
            do {
                guard let selection = try await selectedAssets() else { return }
                model = batchFaceRecognitionModels.model(for: selection.id, assets: selection.assets)
            } catch { diskLibrary.errorMessage = error.localizedDescription; return }
        }
        guard visibilityRevision == hiddenMedia.revision, model.assets.allSatisfy(hiddenMedia.isVisible) else { return }
        batchFaceRecognitionModel = model
        model.startOrResume()
        isShowingBatchFaceRecognition = true
    }

    private func showVideoCovers() async {
        let visibilityRevision = hiddenMedia.revision
        do {
            guard let selection = try await selectedAssets(), selectedAlbum?.isVideoAlbum == true else { return }
            guard visibilityRevision == hiddenMedia.revision, selection.assets.allSatisfy(hiddenMedia.isVisible) else { return }
            let revisions = selection.assets.map(\.revisionID)
            if videoCoverModel?.assets.map(\.revisionID) != revisions {
                videoCoverModel?.pause()
                videoCoverModel = BatchVideoCoverModel(assets: selection.assets)
            }
            videoCoverModel?.startOrResume()
            isShowingVideoCovers = true
        } catch {
            diskLibrary.errorMessage = error.localizedDescription
        }
    }

    private func openPhotoSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct VideoCoverToolbarIcon: View {
    @ObservedObject var model: BatchVideoCoverModel
    let fallbackCount: Int?
    let refreshWhenIdle: () -> Void

    var body: some View {
        let isRunning = model.phase == .running
        Image(systemName: "film.stack")
            .foregroundStyle(isRunning ? Color.blue : Color.primary)
            .scaleEffect(isRunning ? 1.14 : 1)
            .opacity(isRunning ? 0.68 : 1)
            .animation(isRunning ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                       value: isRunning)
            .overlay(alignment: .topTrailing) {
                ToolbarPendingCountBadge(count: isRunning && !model.isPreparing
                                         ? model.remainingCount : (fallbackCount ?? model.remainingCount))
                    .offset(x: 8, y: -7)
            }
            .onChange(of: isRunning) { _, running in
                if !running { refreshWhenIdle() }
            }
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

private struct ModelPendingCountBadge<Model: ObservableObject>: View {
    @ObservedObject var model: Model
    let pendingCount: (Model) -> Int
    let fallbackCount: Int?
    let refreshWhenIdle: () -> Void

    var body: some View {
        let isRunning = (model as? BatchRecognitionModel)?.phase == .running
            || (model as? BatchFaceRecognitionModel)?.phase == .running
        ToolbarPendingCountBadge(count: isRunning ? pendingCount(model) : (fallbackCount ?? pendingCount(model)))
            .onChange(of: isRunning) { _, running in
                if !running { refreshWhenIdle() }
            }
    }
}

private struct ToolbarPendingCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize()
                .frame(minWidth: count > 9 ? 24 : 18, minHeight: 18)
                .background(Color.red, in: Capsule())
                .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
                .accessibilityLabel("尚有 \(count) 项待处理")
                .fixedSize()
        }
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
    var photoCount: Int? = nil

    var body: some View {
        HStack {
            Image(systemName: album.icon)
            Text(album.title)
            Spacer(minLength: 4)
            if let photoCount {
                Text("\(photoCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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
    let photoCounts: [String: Int]
    @ObservedObject var diskLibrary: DiskLibraryStore
    @Binding var selectedAlbumID: String?
    let hasPhotoAccess: Bool
    let showDiskCounts: Bool
    let openSettings: () -> Void
    let addDirectory: () -> Void

    var body: some View {
        List {
            Section("磁盘目录") {
                Button(action: addDirectory) { Label("添加目录…", systemImage: "folder.badge.plus") }
                ForEach(diskLibrary.directories) { directory in
                    Button { selectedAlbumID = directory.id } label: {
                        HStack {
                            Image(systemName: "folder")
                            VStack(alignment: .leading) {
                                Text(directory.title).lineLimit(1)
                                if showDiskCounts {
                                    Text("\(directory.imageCount) 张图片").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if diskLibrary.scanningIDs.contains(directory.id) { ProgressView().controlSize(.mini) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .background(selectedAlbumID == directory.id ? Color.accentColor.opacity(0.2) : .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("diskDirectory-\(directory.id)")
                    .help(directory.path)
                    .contextMenu {
                        Button("重新扫描") { Task { await diskLibrary.scan(directory) } }
                            .disabled(diskLibrary.scanningIDs.contains(directory.id))
                        Button("从列表移除（保留原图）") { Task { await diskLibrary.remove(directory) } }
                            .disabled(diskLibrary.scanningIDs.contains(directory.id))
                    }
                }
            }
            Section("人物") {
                Button { selectedAlbumID = PhotoAlbum.faceAlbum.id } label: {
                    PhotoAlbumRow(album: .faceAlbum, isSelected: selectedAlbumID == PhotoAlbum.faceAlbum.id)
                }
                .buttonStyle(.plain)
            }
            Section("视频") {
                Button { selectedAlbumID = PhotoAlbum.videoAlbum.id } label: {
                    PhotoAlbumRow(
                        album: .videoAlbum,
                        isSelected: selectedAlbumID == PhotoAlbum.videoAlbum.id,
                        photoCount: photoCounts[PhotoAlbum.videoAlbum.id]
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("videoAlbum")
                .disabled(!hasPhotoAccess)
            }
            Section("系统相册") {
                if hasPhotoAccess {
                    ForEach(albums.filter { !$0.isFaceAlbum && !$0.isVideoAlbum }) { album in
                        Button { selectedAlbumID = album.id } label: {
                            PhotoAlbumRow(
                                album: album,
                                isSelected: selectedAlbumID == album.id,
                                photoCount: photoCounts[album.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("尚未允许访问照片图库").font(.caption).foregroundStyle(.secondary)
                    Button("打开照片设置", action: openSettings)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

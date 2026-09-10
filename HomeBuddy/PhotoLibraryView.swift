//
//  PhotoLibraryView.swift
//  HomeBuddy
//

import AppKit
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers
import Vision

struct PhotoLibraryView: View {
    let album: PhotoAlbum
    let assets: [PHAsset]
    @State private var selectedIndex: Int?
    @State private var isShowingBatchRecognition = false
    @State private var isBatchRecognitionMinimized = false
    @StateObject private var batchRecognitionModel: BatchRecognitionModel
    @State private var searchText = ""
    @State private var searchResultIDs: Set<String>?

    init(album: PhotoAlbum, assets: [PHAsset]) {
        self.album = album
        self.assets = assets
        _batchRecognitionModel = StateObject(wrappedValue: BatchRecognitionModel(assets: assets))
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

    private var displayedAssets: [PHAsset] {
        guard !searchKeywords.isEmpty, let searchResultIDs else { return assets }
        return assets.filter { searchResultIDs.contains($0.localIdentifier) }
    }

    private var searchTaskID: String {
        let keywords = searchKeywords.joined(separator: "\u{1F}" )
        let assetIDs = assets.map(\.localIdentifier).joined(separator: "\u{1F}")
        return "\(keywords)|\(assetIDs)"
    }

    var body: some View {
        Group {
            if let selectedIndex, displayedAssets.indices.contains(selectedIndex) {
                PhotoViewerView(
                    assets: displayedAssets,
                    initialIndex: selectedIndex,
                    onBack: { self.selectedIndex = nil }
                )
            } else if displayedAssets.isEmpty {
                ContentUnavailableView(
                    searchKeywords.isEmpty ? "“\(album.title)”中还没有照片" : "没有匹配的照片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(
                        searchKeywords.isEmpty
                            ? "这个相册中暂时没有可显示的图片。"
                            : "没有找到包含全部关键词的 Ollama 识别文字。"
                    )
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !searchKeywords.isEmpty {
                            Text("找到 \(displayedAssets.count) 张照片（需同时包含全部关键词）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array(displayedAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                                Button {
                                    guard displayedAssets.indices.contains(index) else { return }
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
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .searchable(text: $searchText, prompt: "搜索 Ollama 识别文字")
        .onChange(of: searchText) { _, _ in
            // 搜索结果数组会异步变化，旧的大图索引不再可靠。
            selectedIndex = nil
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
        .toolbar {
            ToolbarItem(id: "batchRecognition") {
                Button {
                    if isShowingBatchRecognition {
                        isBatchRecognitionMinimized = false
                    } else {
                        isShowingBatchRecognition = true
                        isBatchRecognitionMinimized = false
                    }
                } label: {
                    Label {
                        Text("Ollama 批量识图")
                    } icon: {
                        AnimatedBatchIcon(isAnimating: batchRecognitionModel.phase == .running)
                    }
                }
                .disabled(assets.isEmpty)
                .help("识别当前相册中的全部照片")
                .popover(isPresented: batchRecognitionPopoverBinding) {
                    BatchRecognitionView(
                        model: batchRecognitionModel,
                        isPresented: $isShowingBatchRecognition
                    )
                }
            }
            .sharedBackgroundVisibility(.hidden)

        }
        .onChange(of: isShowingBatchRecognition) { _, isShowing in
            if isShowing {
                isBatchRecognitionMinimized = false
                batchRecognitionModel.startOrResume()
            }
        }
    }

    private var batchRecognitionPopoverBinding: Binding<Bool> {
        Binding(
            get: { isShowingBatchRecognition && !isBatchRecognitionMinimized },
            set: { isPresented in
                if !isPresented {
                    isBatchRecognitionMinimized = true
                }
            }
        )
    }
}

private struct AnimatedBatchIcon: View {
    let isAnimating: Bool

    var body: some View {
        Image(systemName: "photo.stack")
            .foregroundStyle(Color.accentColor)
            .scaleEffect(isAnimating ? 1.14 : 1)
            .animation(
                isAnimating
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
            .help(isAnimating ? "Ollama 正在后台识别照片" : "打开 Ollama 批量识图")
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
    @State private var metadata: PhotoMetadata?
    @State private var ollamaText: String?
    @State private var isShowingInfo = true
    @State private var isAnalyzing = false
    @State private var analysisResult: VisionAnalysisResult?
    @State private var detectedFaceCount: Int?
    @State private var detectedFaceBoxes: [CGRect] = []
    @State private var isOllamaAnalyzing = false
    @State private var zoomScale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1

    private var displayedZoomScale: CGFloat {
        min(max(zoomScale * gestureScale, 1), 5)
    }

    init(
        assets: [PHAsset],
        initialIndex: Int,
        onBack: @escaping () -> Void
    ) {
        self.assets = assets
        let boundedIndex = assets.isEmpty ? 0 : min(max(initialIndex, 0), assets.count - 1)
        self.initialIndex = boundedIndex
        self.onBack = onBack
        _currentIndex = State(initialValue: boundedIndex)
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

            HStack(spacing: 0) {
                ZStack {
                    Color.black

                    if let image {
                        ZStack {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(24)

                            FaceBoundingBoxOverlay(imageSize: image.size, boxes: detectedFaceBoxes)
                        }
                        .scaleEffect(displayedZoomScale)
                        .gesture(
                            MagnificationGesture()
                                .updating($gestureScale) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    zoomScale = min(max(zoomScale * value, 1), 5)
                                }
                        )
                    } else {
                        ProgressView()
                            .tint(.white)
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

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
            loadMetadata()
            loadOllamaText()
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingInfo.toggle()
                } label: {
                    Label("照片信息", systemImage: "info.circle")
                }
                .help("显示或隐藏照片信息")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    copyCurrentImage()
                } label: {
                    Label("复制图片", systemImage: "doc.on.doc")
                }
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
                .disabled(image == nil || isAnalyzing)
                .help("检测当前照片中的人脸")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    analyzeCurrentImageWithOllama()
                } label: {
                    Label("Ollama 识图", systemImage: "brain")
                }
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
                .disabled(image == nil || zoomScale <= 1)
                .help("缩小照片")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem {
                Button {
                    zoomScale = 1
                } label: {
                    Text("\(Int(displayedZoomScale * 100))%")
                        .monospacedDigit()
                }
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
        .onExitCommand(perform: onBack)
        .sheet(item: $analysisResult) { result in
            VisionAnalysisResultView(result: result)
        }
    }

    private func showPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func showNext() {
        guard currentIndex + 1 < assets.count else { return }
        currentIndex += 1
    }

    private func copyCurrentImage() {
        guard let image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func loadCurrentImage() {
        let asset = currentAsset
        let assetID = asset.localIdentifier
        image = nil
        zoomScale = 1
        analysisResult = nil
        detectedFaceCount = nil
        detectedFaceBoxes = []
        isOllamaAnalyzing = false

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 2400, height: 2400),
            contentMode: .aspectFit,
            options: options
        ) { nsImage, _ in
            guard let nsImage else { return }
            Task { @MainActor in
                guard currentAsset.localIdentifier == assetID else { return }
                image = nsImage
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

    private func loadMetadataFromPhotos(asset: PHAsset, assetID: String) {

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImageDataAndOrientation(
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
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            if type != .faces {
                analysisResult = VisionAnalysisResult(
                    title: "无法分析照片",
                    message: "当前照片还没有加载完成。"
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
                isAnalyzing = false
                detectedFaceCount = result.faceCount
                detectedFaceBoxes = result.faceBoxes
                analysisResult = type == .faces ? nil : result
            }
        }
    }

    private func analyzeCurrentImageWithOllama() {
        guard let image,
              let imageData = Self.jpegData(from: image)
        else {
            analysisResult = VisionAnalysisResult(
                title: "无法分析照片",
                message: "当前照片还没有加载完成。"
            )
            return
        }

        let assetID = currentAsset.localIdentifier
        let configuration = OllamaConfiguration.current
        isOllamaAnalyzing = true
        analysisResult = nil

        Task {
            do {
                let text = try await OllamaVisionService.shared.analyze(
                    imageData: imageData,
                    configuration: configuration
                )
                guard currentAsset.localIdentifier == assetID else { return }
                isOllamaAnalyzing = false
                PhotoMetadataCache.shared.saveOllamaText(text, model: configuration.model, for: currentAsset)
                ollamaText = text
                analysisResult = VisionAnalysisResult(title: "Ollama 图片识别结果", message: text)
            } catch {
                guard currentAsset.localIdentifier == assetID else { return }
                isOllamaAnalyzing = false
                analysisResult = VisionAnalysisResult(
                    title: "Ollama 识别失败",
                    message: "\(error.localizedDescription)\n\n请确认 Ollama 已启动，并且设置中的模型支持图片输入。"
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
                    title: "文字识别结果",
                    message: text.isEmpty ? "没有识别到文字。" : text.joined(separator: "\n")
                )

            case .barcode:
                let request = VNDetectBarcodesRequest()
                try VNImageRequestHandler(cgImage: image).perform([request])

                let observations: [VNBarcodeObservation] = request.results ?? []
                let codes: [String] = observations.compactMap { observation in
                    guard let value = observation.payloadStringValue else { return nil }
                    let type = observation.symbology.rawValue
                    return "\(type)：\(value)"
                }
                return VisionAnalysisResult(
                    title: "二维码和条码结果",
                    message: codes.isEmpty ? "没有识别到二维码或条码。" : codes.joined(separator: "\n")
                )

            case .faces:
                let request = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(cgImage: image).perform([request])
                let observations: [VNFaceObservation] = request.results ?? []
                let count = observations.count
                return VisionAnalysisResult(
                    title: "人脸检测结果",
                    message: count == 0 ? "没有检测到人脸。" : "检测到 \(count) 张人脸。",
                    faceCount: count,
                    faceBoxes: observations.map(\.boundingBox)
                )
            }
        } catch {
            return VisionAnalysisResult(title: "分析失败", message: error.localizedDescription)
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

private struct FaceBoundingBoxOverlay: View {
    let imageSize: CGSize
    let boxes: [CGRect]

    var body: some View {
        GeometryReader { proxy in
            let contentSize = CGSize(
                width: max(proxy.size.width - 48, 0),
                height: max(proxy.size.height - 48, 0)
            )
            let scale = min(
                contentSize.width / max(imageSize.width, 1),
                contentSize.height / max(imageSize.height, 1)
            )
            let displayedSize = CGSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
            let origin = CGPoint(
                x: (proxy.size.width - displayedSize.width) / 2,
                y: (proxy.size.height - displayedSize.height) / 2
            )

            ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                Rectangle()
                    .stroke(.red, lineWidth: 3)
                    .frame(
                        width: box.width * displayedSize.width,
                        height: box.height * displayedSize.height
                    )
                    .position(
                        x: origin.x + box.midX * displayedSize.width,
                        y: origin.y + (1 - box.midY) * displayedSize.height
                    )
            }
        }
        .allowsHitTesting(false)
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
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(result.message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
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

    init(asset: PHAsset, data: Data, uti: String?) {
        fileType = uti.flatMap { UTType($0)?.localizedDescription } ?? uti
        fileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        pixelSize = "\(asset.pixelWidth) × \(asset.pixelHeight)"
        metadataUpdatedAt = Date()
        creationDate = asset.creationDate.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "未知"

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
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
        return value >= 1 ? String(format: "%.2f 秒", value) : String(format: "1/%.0f 秒", 1 / value)
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
    let asset: PHAsset
    let metadata: PhotoMetadata?
    let ollamaText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("照片信息")
                    .font(.title3.weight(.semibold))

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
                        ("文件类型", metadata.fileType ?? "未知"),
                        ("文件大小", metadata.fileSize),
                        ("拍摄时间", metadata.creationDate),
                        ("元数据更新时间", metadata.metadataUpdatedAt.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? "未知"),
                        ("状态", asset.isFavorite ? "已收藏" : "未收藏")
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
                            Text(ollamaText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
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

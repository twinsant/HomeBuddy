import AppKit
import Combine
import ImageIO
import Photos
import SwiftUI
import Vision

@MainActor
final class BatchRecognitionModelStore: ObservableObject {
    private var models: [String: BatchRecognitionModel] = [:]
    private var phaseSubscriptions: [String: AnyCancellable] = [:]
    @Published private(set) var activeModel: BatchRecognitionModel?

    func model(for albumID: String, assets: [PHAsset]) -> BatchRecognitionModel {
        if let model = models[albumID] {
            return model
        }

        let model = BatchRecognitionModel(assets: assets)
        models[albumID] = model
        phaseSubscriptions[albumID] = model.$phase.sink { [weak self, weak model] phase in
            guard let self, let model else { return }
            if phase == .running || (phase == .paused && self.activeModel === model) {
                self.activeModel = model
            } else if phase == .finished && self.activeModel === model {
                self.activeModel = nil
            }
        }
        return model
    }
}

@MainActor
final class BatchRecognitionModel: ObservableObject {
    enum Phase {
        case ready
        case running
        case paused
        case finished
    }

    let assets: [PHAsset]
    @Published private(set) var completed = 0
    @Published private(set) var currentName = ""
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var failures: [String] = []
    @Published private(set) var startedAt: Date?
    @Published private(set) var averageProcessingTime: TimeInterval?

    private var task: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var countedAssetIDs = Set<String>()
    private var totalProcessingTime: TimeInterval = 0
    private var processingCount = 0

    init(assets: [PHAsset]) {
        self.assets = assets
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
    }

    deinit {
        task?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    var progress: Double {
        assets.isEmpty ? 1 : Double(completed) / Double(assets.count)
    }

    var remainingCount: Int {
        max(assets.count - completed, 0)
    }

    var estimatedRemaining: TimeInterval? {
        guard let averageProcessingTime, remainingCount > 0 else { return nil }
        return averageProcessingTime * Double(remainingCount)
    }

    func startOrResume() {
        guard phase != .running, completed < assets.count else { return }
        phase = .running
        startedAt = startedAt ?? Date()
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func pause() {
        guard phase == .running else { return }
        task?.cancel()
        phase = .paused
    }

    func stop() {
        task?.cancel()
        task = nil
        if phase == .running {
            phase = .paused
        }
    }

    private func run() async {
        for asset in assets where !Task.isCancelled {
            var processingStartedAt: Date?
            do {
                if let cached = await cachedText(for: asset), !cached.isEmpty {
                    markCompleted(asset)
                    continue
                }

                currentName = asset.localIdentifier
                processingStartedAt = Date()
                let imageData = try await imageData(for: asset)
                try Task.checkCancellation()
                let configuration = OllamaConfiguration.current
                let text = try await OllamaVisionService.shared.analyze(
                    imageData: imageData,
                    configuration: configuration
                )
                try Task.checkCancellation()
                if let processingStartedAt {
                    recordProcessingTime(since: processingStartedAt)
                }
                PhotoMetadataCache.shared.saveOllamaText(text, model: configuration.model, for: asset)
                markCompleted(asset)
            } catch is CancellationError {
                break
            } catch {
                if let processingStartedAt {
                    recordProcessingTime(since: processingStartedAt)
                }
                failures.append("\(asset.localIdentifier)：\(error.localizedDescription)")
                markCompleted(asset)
            }
        }

        if Task.isCancelled {
            phase = .paused
        } else if completed >= assets.count {
            phase = .finished
            currentName = ""
        }
    }

    private func recordProcessingTime(since start: Date) {
        totalProcessingTime += Date().timeIntervalSince(start)
        processingCount += 1
        averageProcessingTime = totalProcessingTime / Double(processingCount)
    }

    private func markCompleted(_ asset: PHAsset) {
        guard countedAssetIDs.insert(asset.localIdentifier).inserted else { return }
        completed += 1
    }

    private func cachedText(for asset: PHAsset) async -> String? {
        await withCheckedContinuation { continuation in
            PhotoMetadataCache.shared.ollamaText(for: asset) { text in
                continuation.resume(returning: text)
            }
        }
    }

    private func imageData(for asset: PHAsset) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = true
                options.version = .current

                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else if let data {
                        continuation.resume(returning: Self.jpegData(from: data) ?? data)
                    } else {
                        continuation.resume(throwing: BatchRecognitionError.imageUnavailable)
                    }
                }
            }
        } onCancel: {
            // Photos does not expose a cancellation token for this request. The
            // surrounding task checks cancellation before sending data to Ollama.
        }
    }

    private static func jpegData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1024
                  ] as CFDictionary
              )
        else { return nil }

        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    private enum BatchRecognitionError: LocalizedError {
        case imageUnavailable

        var errorDescription: String? {
            "无法读取照片原始数据。"
        }
    }
}

struct BatchRecognitionView: View {
    @ObservedObject var model: BatchRecognitionModel
    @Binding var isPresented: Bool
    @State private var currentThumbnail: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Ollama 批量识图", systemImage: "brain")
                    .font(.title2.weight(.semibold))
                Spacer()
                if model.phase == .running {
                    Button("中断") { model.pause() }
                }
                Button("隐藏") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("已保存的照片会自动跳过。中断后重新打开此窗口即可从上次进度继续。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: model.progress)
                        HStack {
                            Text("进度：\(model.completed) / \(model.assets.count)")
                            Spacer(minLength: 16)
                            Text("剩余：\(model.remainingCount) 张")
                        }
                        .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let remaining = model.estimatedRemaining {
                            Text("预计剩余时间：\(remaining.formattedDuration)")
                        } else if model.phase == .running {
                            Text("正在计算预计剩余时间…")
                        }

                        if let average = model.averageProcessingTime {
                            Text("平均处理时间：\(average.formattedDuration)")
                        }
                    }
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Group {
                            if let currentThumbnail {
                                currentThumbnail
                                    .resizable()
                                    .scaledToFill()
                            } else if model.currentName.isEmpty {
                                Image(systemName: "photo")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前处理")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.currentName.isEmpty ? "等待下一张照片…" : model.currentName)
                                .font(.caption)
                                .foregroundStyle(model.currentName.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .task(id: model.currentName) {
                        if model.currentName.isEmpty {
                            currentThumbnail = nil
                        } else {
                            loadCurrentThumbnail()
                        }
                    }

                    if !model.failures.isEmpty {
                        Text("失败 \(model.failures.count) 张（恢复时会重试）")
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .padding(.top, 12)

            HStack {
                Group {
                    if model.phase == .finished {
                        Label("全部处理完成", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if model.phase != .running {
                        Button(model.phase == .ready ? "开始识别" : "恢复识别") {
                            model.startOrResume()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                Spacer()
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 520, idealWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary)
        }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onAppear {
            if model.phase == .ready { model.startOrResume() }
        }
    }

    private func loadCurrentThumbnail() {
        guard let asset = model.assets.first(where: { $0.localIdentifier == model.currentName }) else {
            currentThumbnail = nil
            return
        }

        currentThumbnail = nil
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 112, height: 112),
            contentMode: .aspectFill,
            options: options
        ) { nsImage, _ in
            guard let nsImage else { return }
            Task { @MainActor in
                guard model.currentName == asset.localIdentifier else { return }
                currentThumbnail = Image(nsImage: nsImage)
            }
        }
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        var seconds = max(Int(self.rounded()), 1)
        let days = seconds / 86_400
        seconds %= 86_400
        let hours = seconds / 3_600
        seconds %= 3_600
        let minutes = seconds / 60
        seconds %= 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days) 天") }
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分钟") }
        if seconds > 0 && parts.count < 2 { parts.append("\(seconds) 秒") }
        return "约 " + parts.joined(separator: " ")
    }
}

@MainActor
final class BatchFaceRecognitionModelStore: ObservableObject {
    private var models: [String: BatchFaceRecognitionModel] = [:]
    private var phaseSubscriptions: [String: AnyCancellable] = [:]
    @Published private(set) var activeModel: BatchFaceRecognitionModel?

    func model(for albumID: String, assets: [PHAsset]) -> BatchFaceRecognitionModel {
        if let model = models[albumID] {
            return model
        }

        let model = BatchFaceRecognitionModel(assets: assets)
        models[albumID] = model
        phaseSubscriptions[albumID] = model.$phase.sink { [weak self, weak model] phase in
            guard let self, let model else { return }
            if phase == .running || (phase == .paused && self.activeModel === model) {
                self.activeModel = model
            } else if phase == .finished && self.activeModel === model {
                self.activeModel = nil
            }
        }
        return model
    }
}

@MainActor
final class BatchFaceRecognitionModel: ObservableObject {
    enum Phase {
        case ready
        case running
        case paused
        case finished
    }

    let assets: [PHAsset]
    @Published private(set) var completed = 0
    @Published private(set) var currentName = ""
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var failures: [String] = []

    private var task: Task<Void, Never>?
    private var countedAssetIDs = Set<String>()

    init(assets: [PHAsset]) {
        self.assets = assets
    }

    deinit {
        task?.cancel()
    }

    var progress: Double {
        assets.isEmpty ? 1 : Double(completed) / Double(assets.count)
    }

    func startOrResume() {
        guard phase != .running, completed < assets.count else { return }
        phase = .running
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func pause() {
        guard phase == .running else { return }
        task?.cancel()
        phase = .paused
    }

    private func run() async {
        for asset in assets where !Task.isCancelled {
            currentName = asset.localIdentifier
            do {
                // Detection cache hits still need an embedding backfill for assigned faces.
                if let cached = await cachedResult(for: asset) {
                    try await indexMissingEmbeddings(in: cached, for: asset)
                    markCompleted(asset)
                    continue
                }

                let image = try await imageData(for: asset)
                try Task.checkCancellation()
                let result = try await Task.detached(priority: .userInitiated) {
                    try Self.detectFaces(in: image.data, orientation: image.orientation)
                }.value
                try Task.checkCancellation()
                await save(result, for: asset)
                guard let savedResult = await cachedResult(for: asset) else {
                    throw FaceRecognitionError.cacheUnavailable
                }
                try await indexMissingEmbeddings(in: savedResult, for: asset, photo: image)
                markCompleted(asset)
            } catch is CancellationError {
                break
            } catch {
                failures.append("\(asset.localIdentifier)：\(error.localizedDescription)")
            }
        }

        if Task.isCancelled {
            phase = .paused
        } else if completed >= assets.count {
            phase = .finished
            currentName = ""
        } else {
            phase = .paused
        }
    }

    private func markCompleted(_ asset: PHAsset) {
        guard countedAssetIDs.insert(asset.localIdentifier).inserted else { return }
        completed += 1
    }

    private func cachedResult(for asset: PHAsset) async -> FaceDetectionResult? {
        await withCheckedContinuation { continuation in
            PhotoMetadataCache.shared.faceDetectionResult(for: asset) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func save(_ result: FaceDetectionResult, for asset: PHAsset) async {
        await withCheckedContinuation { continuation in
            PhotoMetadataCache.shared.saveFaceDetectionResult(result, for: asset) {
                continuation.resume()
            }
        }
    }

    private func indexMissingEmbeddings(
        in result: FaceDetectionResult,
        for asset: PHAsset,
        photo suppliedPhoto: (data: Data, orientation: CGImagePropertyOrientation)? = nil
    ) async throws {
        let confirmedFaces = result.faces.enumerated().compactMap { index, face -> (Int, String)? in
            guard let personID = face.personID else { return nil }
            return (index, personID)
        }
        guard !confirmedFaces.isEmpty else { return }

        guard FaceRecognitionConfiguration.modelURL() != nil else {
            throw FaceRecognitionError.modelNotConfigured
        }

        let configuration = ChromaConfiguration.current
        let collectionID = try await ChromaService.shared.createCollectionIfNeeded(configuration: configuration)
        let personRecords = await people()
        let nameByID = Dictionary(uniqueKeysWithValues: personRecords.map { ($0.id, $0.displayName) })
        let photo: (data: Data, orientation: CGImagePropertyOrientation)
        if let suppliedPhoto {
            photo = suppliedPhoto
        } else {
            photo = try await imageData(for: asset)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(photo.data as CFData, nil),
              let uprightImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400
                ] as CFDictionary
              )
        else { throw FaceRecognitionError.imageUnavailable }

        let embeddings = try await FaceRecognitionService.shared.recognize(image: uprightImage)
        try Task.checkCancellation()

        var usedEmbeddingIndices = Set<Int>()
        var records: [(id: String, vector: [Double], metadata: [String: String])] = []
        for (faceIndex, personID) in confirmedFaces {
            guard let displayName = nameByID[personID],
                  result.faces.indices.contains(faceIndex)
            else { continue }
            let storedFace = result.faces[faceIndex]

            let match = embeddings.indices
                .filter { !usedEmbeddingIndices.contains($0) }
                .map { ($0, Self.intersectionOverUnion(storedFace.box, embeddings[$0].box)) }
                .max(by: { $0.1 < $1.1 })
            guard let (embeddingIndex, overlap) = match, overlap >= 0.25 else { continue }
            usedEmbeddingIndices.insert(embeddingIndex)
            let vector = embeddings[embeddingIndex].vector
            guard vector.count == 512, vector.allSatisfy(\.isFinite) else {
                throw FaceRecognitionError.invalidEmbedding
            }
            records.append((
                "\(asset.localIdentifier)#\(embeddingIndex)",
                vector,
                [
                    "asset_id": asset.localIdentifier,
                    "person_id": personID,
                    "display_name": displayName,
                    "model_id": FaceRecognitionService.modelIdentifier
                ]
            ))
        }

        guard !records.isEmpty else { return }
        let existing = try await ChromaService.shared.get(
            ids: records.map(\.id),
            collectionID: collectionID,
            configuration: configuration
        )
        let validExistingIDs = Set(existing.ids.enumerated().compactMap { index, id -> String? in
            guard index < existing.metadatas.count,
                  existing.metadatas[index]?["model_id"] == FaceRecognitionService.modelIdentifier,
                  existing.metadatas[index]?["person_id"] == records.first(where: { $0.id == id })?.metadata["person_id"]
            else { return nil }
            return id
        })
        let missingRecords = records.filter { !validExistingIDs.contains($0.id) }
        guard !missingRecords.isEmpty else { return }
        try await ChromaService.shared.upsert(
            ids: missingRecords.map(\.id),
            embeddings: missingRecords.map(\.vector),
            metadatas: missingRecords.map(\.metadata),
            collectionID: collectionID,
            configuration: configuration
        )
    }

    private func people() async -> [Person] {
        await withCheckedContinuation { continuation in
            PhotoMetadataCache.shared.people { records in
                continuation.resume(returning: records)
            }
        }
    }

    private nonisolated static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private func imageData(for asset: PHAsset) async throws -> (data: Data, orientation: CGImagePropertyOrientation) {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.version = .current

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
                data, _, orientation, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: (data, orientation))
                } else {
                    continuation.resume(throwing: FaceRecognitionError.imageUnavailable)
                }
            }
        }
    }

    private nonisolated static func detectFaces(in data: Data, orientation: CGImagePropertyOrientation) throws -> FaceDetectionResult {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw FaceRecognitionError.imageUnavailable
        }

        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
        let boxes = (request.results ?? []).map(\.boundingBox)
        return FaceDetectionResult(
            faceCount: boxes.count,
            faceBoxes: boxes,
            detectorVersion: FaceDetectionResult.legacyDetectorVersion
        )
    }

    private enum FaceRecognitionError: LocalizedError {
        case imageUnavailable
        case cacheUnavailable
        case modelNotConfigured
        case invalidEmbedding

        var errorDescription: String? {
            switch self {
            case .imageUnavailable:
                "无法读取照片或执行人脸检测。"
            case .cacheUnavailable:
                "人脸检测结果未能写入 SQLite。"
            case .modelNotConfigured:
                "检测到已标注人脸，但尚未在设置中选择 GGUF 模型，无法补齐 embedding。"
            case .invalidEmbedding:
                "人脸模型返回了无效的 512 维 embedding。"
            }
        }
    }
}

struct BatchFaceRecognitionView: View {
    @ObservedObject var model: BatchFaceRecognitionModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("批量人脸识别", systemImage: "person.2.crop.square.stack")
                    .font(.title2.weight(.semibold))
                Spacer()
                if model.phase == .running {
                    Button("中断") { model.pause() }
                }
                Button("隐藏") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            Text("已有检测结果仍会检查已标注人脸的 Chroma embedding；缺失时使用本地 GGUF 模型生成并保存。未标注人脸只检测方框。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: model.progress)
            HStack {
                Text("进度：\(model.completed) / \(model.assets.count)")
                Spacer()
                Text("剩余：\(max(model.assets.count - model.completed, 0)) 张")
            }
            .font(.headline)

            if !model.currentName.isEmpty {
                Text("当前处理：\(model.currentName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if !model.failures.isEmpty {
                Text("失败 \(model.failures.count) 张（恢复时会重试）")
                    .foregroundStyle(.orange)
            }

            HStack {
                if model.phase == .finished {
                    Label("全部处理完成", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if model.phase != .running {
                    Button(model.phase == .ready ? "开始识别" : "恢复识别") {
                        model.startOrResume()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
        .padding(18)
        .frame(minWidth: 520, idealWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary) }
        .onAppear {
            if model.phase == .ready { model.startOrResume() }
        }
    }
}

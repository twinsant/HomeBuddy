import AppKit
import Combine
import ImageIO
import Photos
import SwiftUI

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
    private var countedAssetIDs = Set<String>()
    private var totalProcessingTime: TimeInterval = 0
    private var processingCount = 0

    init(assets: [PHAsset]) {
        self.assets = assets
    }

    deinit {
        task?.cancel()
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
    @Binding var isMinimized: Bool
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
                Button {
                    isMinimized = true
                } label: {
                    Label("最小化", systemImage: "minus")
                }
                .help("最小化到相册界面，识别将在后台继续")
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                    if !model.currentName.isEmpty {
                        HStack(spacing: 12) {
                            Group {
                                if let currentThumbnail {
                                    currentThumbnail
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(width: 56, height: 56)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("当前处理")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(model.currentName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .task(id: model.currentName) {
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
                .padding(.top, 18)

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
            .padding(.top, 14)
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 640, minHeight: 460, idealHeight: 520)
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

struct BatchRecognitionToolbarView: View {
    @ObservedObject var model: BatchRecognitionModel
    @Binding var isMinimized: Bool
    @Binding var isPresented: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.phase == .finished ? "checkmark.circle.fill" : "brain")
                .foregroundStyle(model.phase == .finished ? .green : .accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.phase == .finished ? "批量识图完成" : "Ollama 批量识图")
                    .font(.subheadline.weight(.semibold))
                Text("\(model.completed) / \(model.assets.count) · 剩余 \(model.remainingCount) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: model.progress)
                .frame(width: 90)

            if model.phase == .running {
                Button("中断") { model.pause() }
            } else if model.phase == .paused {
                Button("恢复") { model.startOrResume() }
            }

            Button {
                isMinimized = false
            } label: {
                Label("展开", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .labelStyle(.iconOnly)
            .help("展开批量识图进度")

            Button {
                isPresented = false
            } label: {
                Label("关闭", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .help("隐藏批量识图面板，任务仍会继续")
        }
        .fixedSize(horizontal: true, vertical: false)
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

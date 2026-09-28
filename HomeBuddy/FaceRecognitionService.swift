import AppKit
import Foundation

struct FaceEmbedding: Equatable, Sendable {
    let box: CGRect
    let detectionScore: Double
    let vector: [Double]
}

struct FacePersonCandidate: Identifiable, Equatable, Sendable {
    let personID: String
    let displayName: String
    let distance: Double

    var id: String { personID }
    var similarityPercent: Int { Int(((1 - distance) * 100).rounded()) }
}

struct FaceRecognitionConfiguration {
    private static let bookmarkKey = "faceRecognition.modelBookmark"

    static var modelPath: String? {
        modelURL()?.path
    }

    static func saveModelURL(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    static func clearModelURL() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    static func modelURL() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale { try? saveModelURL(url) }
        return url
    }
}

actor FaceRecognitionService {
    static let shared = FaceRecognitionService()
    static let modelIdentifier = "antelopev2-arcface512-v1"
    static let maximumCosineDistance = 0.35

    enum ServiceError: LocalizedError {
        case modelNotConfigured
        case modelUnavailable(String)
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .modelNotConfigured:
                return "尚未选择 face-detect GGUF 模型。请到设置中选择 antelopev2.gguf。"
            case .modelUnavailable(let message):
                return message
            case .invalidImage:
                return "无法读取当前照片用于人脸识别。"
            }
        }
    }

    private var bridge: HBFaceRecognitionBridge?
    private var loadedModelURL: URL?
    private var scopedModelURL: URL?

    func recognize(image: CGImage) throws -> [FaceEmbedding] {
        try Task.checkCancellation()
        guard let modelURL = FaceRecognitionConfiguration.modelURL() else {
            throw ServiceError.modelNotConfigured
        }
        try loadModelIfNeeded(at: modelURL)
        guard let bridge else { throw ServiceError.modelNotConfigured }
        try Task.checkCancellation()

        let rawFaces: [[String: Any]]
        do {
            rawFaces = try bridge.recognizeImage(image)
        } catch {
            throw ServiceError.modelUnavailable(error.localizedDescription)
        }

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        return rawFaces.compactMap { raw in
            guard let x1 = (raw["x1"] as? NSNumber)?.doubleValue,
                  let y1 = (raw["y1"] as? NSNumber)?.doubleValue,
                  let x2 = (raw["x2"] as? NSNumber)?.doubleValue,
                  let y2 = (raw["y2"] as? NSNumber)?.doubleValue,
                  let score = (raw["score"] as? NSNumber)?.doubleValue,
                  let values = raw["embedding"] as? [NSNumber], !values.isEmpty
            else { return nil }

            let left = min(max(CGFloat(x1) / imageWidth, 0), 1)
            let right = min(max(CGFloat(x2) / imageWidth, left), 1)
            let bottom = min(max(1 - CGFloat(y2) / imageHeight, 0), 1)
            let top = min(max(1 - CGFloat(y1) / imageHeight, bottom), 1)
            return FaceEmbedding(
                box: CGRect(x: left, y: bottom, width: right - left, height: top - bottom),
                detectionScore: score,
                vector: values.map(\.doubleValue)
            )
        }
    }

    private func loadModelIfNeeded(at url: URL) throws {
        guard bridge == nil || loadedModelURL != url else { return }

        let hasAccess = url.startAccessingSecurityScopedResource()
        guard hasAccess else {
            throw ServiceError.modelUnavailable("无法访问模型文件。请在设置中重新选择模型文件。")
        }

        let loadedBridge: HBFaceRecognitionBridge
        do {
            loadedBridge = try HBFaceRecognitionBridge(modelPath: url.path)
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw ServiceError.modelUnavailable(error.localizedDescription)
        }
        let previousScopedModelURL = scopedModelURL
        bridge = loadedBridge
        loadedModelURL = url
        scopedModelURL = url
        previousScopedModelURL?.stopAccessingSecurityScopedResource()
    }
}

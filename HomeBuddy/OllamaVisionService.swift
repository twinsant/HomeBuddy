//
//  OllamaVisionService.swift
//  HomeBuddy
//

import Foundation

struct OllamaConfiguration {
    static let defaultBaseURL = "http://127.0.0.1:11434"
    static let defaultModel = "qwen3.8:27b-mlx"

    private static let baseURLKey = "ollama.baseURL"
    private static let modelKey = "ollama.model"

    var baseURL: String
    var model: String

    static var current: OllamaConfiguration {
        let defaults = UserDefaults.standard
        return OllamaConfiguration(
            baseURL: defaults.string(forKey: baseURLKey) ?? defaultBaseURL,
            model: defaults.string(forKey: modelKey) ?? defaultModel
        )
    }

    func save() {
        UserDefaults.standard.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.baseURLKey)
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.modelKey)
    }
}

struct OllamaVisionService {
    static let shared = OllamaVisionService()

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let images: [String]
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String?
        let error: String?
    }

    private struct TagsResponse: Decodable {
        let models: [ModelInfo]
    }

    private struct ModelInfo: Decodable {
        let name: String
    }

    enum ServiceError: LocalizedError {
        case invalidURL
        case invalidResponse
        case server(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return AppLocalization.localizedString("Ollama 地址无效，请在设置中检查地址。", comment: "")
            case .invalidResponse:
                return AppLocalization.localizedString("Ollama 返回了无法解析的响应。", comment: "")
            case .server(let message):
                return String.localizedStringWithFormat(AppLocalization.localizedString("Ollama：%@", comment: ""), message)
            case .emptyResponse:
                return AppLocalization.localizedString("Ollama 没有返回识别结果。", comment: "")
            }
        }
    }

    func analyze(imageData: Data, configuration: OllamaConfiguration) async throws -> String {
        let url = try endpoint("api/generate", baseURL: configuration.baseURL)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GenerateRequest(
            model: configuration.model,
            prompt: AppLocalization.localizedString(
                "请详细描述这张图片中的内容。如果有文字，请准确转录；如果有人物、物体或场景，请分别说明。请使用中文回答。",
                comment: "Prompt sent to the local vision model; respond in the app's language."
            ),
            images: [imageData.base64EncodedString()],
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data)
        if let error = decoded?.error, !error.isEmpty {
            throw ServiceError.server(error)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ServiceError.server("HTTP \(httpResponse.statusCode)")
        }
        guard let text = decoded?.response?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ServiceError.emptyResponse
        }
        return text
    }

    func availableModels(configuration: OllamaConfiguration) async throws -> [String] {
        let url = try endpoint("api/tags", baseURL: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GenerateResponse.self, from: data))?.error
            throw ServiceError.server(message ?? "HTTP \(httpResponse.statusCode)")
        }
        guard let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            throw ServiceError.invalidResponse
        }
        return decoded.models.map(\.name).sorted()
    }

    private func endpoint(_ path: String, baseURL: String) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw ServiceError.invalidURL
        }
        components.path = components.path.hasSuffix("/")
            ? components.path + path
            : components.path + "/" + path
        guard let url = components.url else {
            throw ServiceError.invalidURL
        }
        return url
    }
}

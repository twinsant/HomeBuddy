//
//  ChromaService.swift
//  HomeBuddy
//

import Foundation

struct ChromaConfiguration: Equatable {
    static let defaultBaseURL = "http://localhost:8000"
    private static let legacyIPv4BaseURL = "http://127.0.0.1:8000"
    static let defaultTenant = "default_tenant"
    static let defaultDatabase = "default_database"
    static let defaultCollection = "homebuddy_antelopev2_cosine_512"

    private static let baseURLKey = "chroma.baseURL"
    private static let tenantKey = "chroma.tenant"
    
    private static let databaseKey = "chroma.database"
    private static let collectionKey = "chroma.collection"

    var baseURL: String
    var tenant: String
    var database: String
    var collection: String

    static var current: ChromaConfiguration {
        let defaults = UserDefaults.standard
        let savedBaseURL = defaults.string(forKey: baseURLKey)
        let baseURL = savedBaseURL == legacyIPv4BaseURL ? defaultBaseURL : (savedBaseURL ?? defaultBaseURL)
        return ChromaConfiguration(
            baseURL: baseURL,
            tenant: defaults.string(forKey: tenantKey) ?? defaultTenant,
            database: defaults.string(forKey: databaseKey) ?? defaultDatabase,
            collection: defaults.string(forKey: collectionKey) ?? defaultCollection
        )
    }

    func save() {
        UserDefaults.standard.set(normalizedBaseURL, forKey: Self.baseURLKey)
        UserDefaults.standard.set(tenant.trimmedOrDefault(Self.defaultTenant), forKey: Self.tenantKey)
        UserDefaults.standard.set(database.trimmedOrDefault(Self.defaultDatabase), forKey: Self.databaseKey)
        UserDefaults.standard.set(collection.trimmedOrDefault(Self.defaultCollection), forKey: Self.collectionKey)
    }

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).replacingTrailingSlash()
    }

    var normalizedTenant: String { tenant.trimmedOrDefault(Self.defaultTenant) }
    var normalizedDatabase: String { database.trimmedOrDefault(Self.defaultDatabase) }
    var normalizedCollection: String { collection.trimmedOrDefault(Self.defaultCollection) }
}

private extension String {
    func replacingTrailingSlash() -> String {
        var value = self
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    func trimmedOrDefault(_ fallback: String) -> String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}

struct ChromaQueryResult: Equatable {
    let ids: [[String]]
    let distances: [[Double]]
    let metadatas: [[ [String: String]? ]]
}

struct ChromaGetResult: Equatable {
    let ids: [String]
    let metadatas: [[String: String]?]
}

struct ChromaService {
    static let shared = ChromaService()

    enum ServiceError: LocalizedError, Equatable {
        case invalidURL
        case invalidResponse
        case server(statusCode: Int, message: String)
        case invalidConfiguration(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Chroma 地址无效，请在设置中检查地址。"
            case .invalidResponse:
                return "Chroma 返回了无法解析的响应。"
            case .server(let statusCode, let message):
                return "Chroma（HTTP \(statusCode)）：\(message)"
            case .invalidConfiguration(let message):
                return "Chroma 配置无效：\(message)"
            }
        }
    }

    private struct CollectionResponse: Decodable {
        let id: String
        let name: String
    }

    private struct QueryResponse: Decodable {
        let ids: [[String]]
        let distances: [[Double]]?
        let metadatas: [[ [String: String]? ]]?
    }

    private struct GetResponse: Decodable {
        let ids: [String]
        let metadatas: [[String: String]?]?
    }

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkConnection(configuration: ChromaConfiguration) async throws {
        _ = try await requestData(path: "api/v2/heartbeat", method: "GET", body: Optional<Data>.none, configuration: configuration)
    }

    func collectionID(configuration: ChromaConfiguration) async throws -> String {
        let path = try apiPath("collections", configuration: configuration)
        let (data, response) = try await requestData(path: path, method: "GET", body: Optional<Data>.none, configuration: configuration)
        guard let collections = try? decoder.decode([CollectionResponse].self, from: data) else {
            throw ServiceError.invalidResponse
        }
        guard let collection = collections.first(where: { $0.name == configuration.normalizedCollection }) else {
            throw ServiceError.server(statusCode: response.statusCode, message: "找不到 collection：\(configuration.normalizedCollection)")
        }
        return collection.id
    }

    func createCollectionIfNeeded(configuration: ChromaConfiguration) async throws -> String {
        let path = try apiPath("collections", configuration: configuration)
        let body = try encoder.encode([
            "name": AnyEncodable(configuration.normalizedCollection),
            "get_or_create": AnyEncodable(true),
            "metadata": AnyEncodable(["hnsw:space": "cosine"])
        ])
        let (data, _) = try await requestData(path: path, method: "POST", body: body, configuration: configuration)
        guard let collection = try? decoder.decode(CollectionResponse.self, from: data) else {
            throw ServiceError.invalidResponse
        }
        return collection.id
    }

    func upsert(
        ids: [String],
        embeddings: [[Double]],
        metadatas: [[String: String]]? = nil,
        documents: [String]? = nil,
        collectionID: String,
        configuration: ChromaConfiguration
    ) async throws {
        guard !ids.isEmpty, ids.count == embeddings.count else {
            throw ServiceError.invalidConfiguration("ids 与 embeddings 数量必须一致且不能为空。")
        }
        if let metadatas, metadatas.count != ids.count {
            throw ServiceError.invalidConfiguration("metadatas 与 ids 数量必须一致。")
        }
        if let documents, documents.count != ids.count {
            throw ServiceError.invalidConfiguration("documents 与 ids 数量必须一致。")
        }

        var body: [String: AnyEncodable] = [
            "ids": AnyEncodable(ids),
            "embeddings": AnyEncodable(embeddings)
        ]
        if let metadatas { body["metadatas"] = AnyEncodable(metadatas) }
        if let documents { body["documents"] = AnyEncodable(documents) }
        let encoded = try encoder.encode(body)
        _ = try await requestData(path: try collectionPath(collectionID, operation: "upsert", configuration: configuration), method: "POST", body: encoded, configuration: configuration)
    }

    func get(
        ids: [String],
        collectionID: String,
        configuration: ChromaConfiguration
    ) async throws -> ChromaGetResult {
        guard !ids.isEmpty else { return ChromaGetResult(ids: [], metadatas: []) }
        let body = try encoder.encode([
            "ids": AnyEncodable(ids),
            "include": AnyEncodable(["metadatas"])
        ])
        let (data, _) = try await requestData(
            path: try collectionPath(collectionID, operation: "get", configuration: configuration),
            method: "POST",
            body: body,
            configuration: configuration
        )
        guard let decoded = try? decoder.decode(GetResponse.self, from: data) else {
            throw ServiceError.invalidResponse
        }
        return ChromaGetResult(ids: decoded.ids, metadatas: decoded.metadatas ?? [])
    }

    func delete(
        ids: [String],
        collectionID: String,
        configuration: ChromaConfiguration
    ) async throws {
        guard !ids.isEmpty else { return }
        let body = try encoder.encode(["ids": AnyEncodable(ids)])
        _ = try await requestData(path: try collectionPath(collectionID, operation: "delete", configuration: configuration), method: "POST", body: body, configuration: configuration)
    }

    func delete(
        where metadataFilters: [String: String],
        collectionID: String,
        configuration: ChromaConfiguration
    ) async throws {
        guard !metadataFilters.isEmpty else {
            throw ServiceError.invalidConfiguration("删除向量必须提供 metadata 条件。")
        }
        let body = try encoder.encode(["where": AnyEncodable(metadataFilters)])
        _ = try await requestData(path: try collectionPath(collectionID, operation: "delete", configuration: configuration), method: "POST", body: body, configuration: configuration)
    }

    func query(
        embedding: [Double],
        results: Int = 5,
        collectionID: String,
        configuration: ChromaConfiguration
    ) async throws -> ChromaQueryResult {
        guard !embedding.isEmpty, results > 0 else {
            throw ServiceError.invalidConfiguration("查询向量不能为空，结果数量必须大于零。")
        }
        let body: [String: AnyEncodable] = [
            "query_embeddings": AnyEncodable([embedding]),
            "n_results": AnyEncodable(results),
            "include": AnyEncodable(["metadatas", "distances"])
        ]
        let encoded = try encoder.encode(body)
        let (data, _) = try await requestData(path: try collectionPath(collectionID, operation: "query", configuration: configuration), method: "POST", body: encoded, configuration: configuration)
        guard let decoded = try? decoder.decode(QueryResponse.self, from: data) else {
            throw ServiceError.invalidResponse
        }
        return ChromaQueryResult(
            ids: decoded.ids,
            distances: decoded.distances ?? [],
            metadatas: decoded.metadatas ?? []
        )
    }

    private func apiPath(_ path: String, configuration: ChromaConfiguration) throws -> String {
        guard !configuration.normalizedTenant.isEmpty, !configuration.normalizedDatabase.isEmpty else {
            throw ServiceError.invalidConfiguration("tenant 和 database 不能为空。")
        }
        return "api/v2/tenants/\(configuration.normalizedTenant)/databases/\(configuration.normalizedDatabase)/\(path)"
    }

    private func collectionPath(_ id: String, operation: String, configuration: ChromaConfiguration) throws -> String {
        guard !id.isEmpty else { throw ServiceError.invalidConfiguration("collection ID 不能为空。") }
        return try apiPath("collections/\(id)/\(operation)", configuration: configuration)
    }

    private func requestData(path: String, method: String, body: Data?, configuration: ChromaConfiguration) async throws -> (Data, HTTPURLResponse) {
        guard let baseURL = URL(string: configuration.normalizedBaseURL), ["http", "https"].contains(baseURL.scheme?.lowercased()) else {
            throw ServiceError.invalidURL
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }
        components.path = components.path.replacingTrailingSlash() + "/" + path
        guard let url = components.url else { throw ServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "请求失败"
            throw ServiceError.server(statusCode: httpResponse.statusCode, message: message)
        }
        return (data, httpResponse)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

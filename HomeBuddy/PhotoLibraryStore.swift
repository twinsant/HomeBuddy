//
//  PhotoLibraryStore.swift
//  HomeBuddy
//

import Foundation
import Photos
import Combine
import SwiftUI
import SQLite3

struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let isAllPhotos: Bool

    var icon: String {
        isAllPhotos ? "photo.on.rectangle.angled" : "rectangle.stack"
    }

    init(collection: PHAssetCollection) {
        id = collection.localIdentifier
        title = collection.localizedTitle ?? "未命名相册"
        isAllPhotos = collection.assetCollectionSubtype == .smartAlbumUserLibrary
    }
}

@MainActor
final class PhotoLibraryStore: ObservableObject {
    @Published private(set) var albums: [PhotoAlbum] = []
    @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    func requestAccessAndLoad() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status

        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        self?.loadAlbums()
                    }
                }
            }
        } else if status == .authorized || status == .limited {
            loadAlbums()
        }
    }

    func refresh() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        loadAlbums()
    }

    func assets(for album: PhotoAlbum) -> [PHAsset] {
        guard let collection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [album.id],
            options: nil
        ).firstObject else {
            return []
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: collection, options: options)
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
            .filter { $0.mediaType == .image }
    }

    private func loadAlbums() {
        var collections: [PHAssetCollection] = []
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            collections.append(collection)
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            collections.append(collection)
        }

        var seen = Set<String>()
        albums = collections
            .map(PhotoAlbum.init)
            .filter { seen.insert($0.id).inserted }
            .sorted { left, right in
                if left.isAllPhotos != right.isAllPhotos {
                    return left.isAllPhotos
                }
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
    }
}

/// Persists photo metadata so opening a photo again does not require reading its original data.
final class PhotoMetadataCache {
    static let shared = PhotoMetadataCache()

    private static let directoryBookmarkKey = "photoMetadataStorageDirectoryBookmark"
    private static let directoryPathKey = "photoMetadataStorageDirectoryPath"
    private let queue = DispatchQueue(label: "com.twinsant.HomeBuddy.photo-metadata-cache")
    private var database: OpaquePointer?
    private var securityScopedDirectoryURL: URL?

    private init() {
        queue.sync {
            openDatabase()
        }
    }

    deinit {
        queue.sync { closeDatabase() }
    }

    var databaseURL: URL? {
        queue.sync { databaseURLValue }
    }

    var storageDirectoryURL: URL? {
        queue.sync { databaseURLValue?.deletingLastPathComponent() }
    }

    @discardableResult
    func setStorageDirectory(_ directory: URL) -> URL? {
        queue.sync {
            let directory = directory.standardizedFileURL
            guard directory.hasDirectoryPath else { return databaseURLValue }

            if let bookmark = try? directory.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmark, forKey: Self.directoryBookmarkKey)
            }
            UserDefaults.standard.set(directory.path, forKey: Self.directoryPathKey)

            closeDatabase()
            if directory.startAccessingSecurityScopedResource() {
                securityScopedDirectoryURL = directory
            }
            guard openDatabase(in: directory) else {
                openDefaultDatabase()
                return databaseURLValue
            }
            return databaseURLValue
        }
    }

    /// Copies the current cache database to a directory before switching to it.
    func copyDatabase(to directory: URL, overwriting: Bool) -> Bool {
        queue.sync {
            guard let sourceURL = databaseURLValue else { return false }
            let destinationDirectory = directory.standardizedFileURL
            let destinationURL = destinationDirectory.appendingPathComponent("photo-metadata.sqlite")
            let fileManager = FileManager.default
            let startedAccess = destinationDirectory.startAccessingSecurityScopedResource()
            defer {
                if startedAccess {
                    destinationDirectory.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else { return true }
                guard !fileManager.fileExists(atPath: destinationURL.path) || overwriting else { return false }

                // Flush a possible WAL before copying the database file.
                sqlite3_exec(database, "PRAGMA wal_checkpoint(FULL);", nil, nil, nil)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return true
            } catch {
                return false
            }
        }
    }

    func metadata(
        for asset: PHAsset,
        completion: @escaping (PhotoMetadata?) -> Void
    ) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            let result = self?.read(
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            )
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func save(_ metadata: PhotoMetadata, for asset: PHAsset) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            self?.write(
                metadata,
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            )
        }
    }

    func ollamaText(for asset: PHAsset, completion: @escaping (String?) -> Void) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            let result = self?.readOllamaText(
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            )
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func saveOllamaText(_ text: String, model: String, for asset: PHAsset) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            self?.writeOllamaText(
                text,
                model: model,
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            )
        }
    }

    private var databaseURLValue: URL?

    private func openDatabase() {
        if let path = UserDefaults.standard.string(forKey: Self.directoryPathKey) {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            if directory.startAccessingSecurityScopedResource() {
                securityScopedDirectoryURL = directory
            }
            if openDatabase(in: directory) {
                return
            }
            directory.stopAccessingSecurityScopedResource()
            securityScopedDirectoryURL = nil
        }

        if let bookmark = UserDefaults.standard.data(forKey: Self.directoryBookmarkKey) {
            var isStale = false
            if let directory = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), directory.startAccessingSecurityScopedResource() {
                securityScopedDirectoryURL = directory
                if !isStale, openDatabase(in: directory) {
                    return
                }
                directory.stopAccessingSecurityScopedResource()
                securityScopedDirectoryURL = nil
            }
        }
        openDefaultDatabase()
    }

    private func openDefaultDatabase() {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".homebuddy", isDirectory: true)
        let fallbackURL = (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? homeDirectoryURL)
            .appendingPathComponent("HomeBuddy", isDirectory: true)

        _ = openDatabase(in: homeDirectoryURL) || openDatabase(in: fallbackURL)
    }

    private func openDatabase(in directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("photo-metadata.sqlite")
            guard sqlite3_open(url.path, &database) == SQLITE_OK else {
                closeDatabase()
                return false
            }
            databaseURLValue = url
            createTable()
            return true
        } catch {
            return false
        }
    }

    private func closeDatabase() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
        databaseURLValue = nil
        if let securityScopedDirectoryURL {
            securityScopedDirectoryURL.stopAccessingSecurityScopedResource()
            self.securityScopedDirectoryURL = nil
        }
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS photo_metadata (
            asset_id TEXT PRIMARY KEY NOT NULL,
            modification_time REAL NOT NULL,
            pixel_width INTEGER NOT NULL,
            pixel_height INTEGER NOT NULL,
            file_type TEXT,
            file_size TEXT NOT NULL,
            pixel_size TEXT NOT NULL,
            creation_date TEXT NOT NULL,
            camera TEXT,
            lens TEXT,
            exposure TEXT,
            iso TEXT,
            focal_length TEXT,
            location TEXT,
            metadata_updated_at REAL,
            ollama_text TEXT,
            ollama_model TEXT,
            ollama_updated_at REAL
        );
        """
        sqlite3_exec(database, sql, nil, nil, nil)
        // 仅为在该字段加入前创建的缓存数据库执行迁移。
        if !columnExists("metadata_updated_at", in: "photo_metadata") {
            sqlite3_exec(database, "ALTER TABLE photo_metadata ADD COLUMN metadata_updated_at REAL;", nil, nil, nil)
        }
        if !columnExists("ollama_text", in: "photo_metadata") {
            sqlite3_exec(database, "ALTER TABLE photo_metadata ADD COLUMN ollama_text TEXT;", nil, nil, nil)
        }
        if !columnExists("ollama_model", in: "photo_metadata") {
            sqlite3_exec(database, "ALTER TABLE photo_metadata ADD COLUMN ollama_model TEXT;", nil, nil, nil)
        }
        if !columnExists("ollama_updated_at", in: "photo_metadata") {
            sqlite3_exec(database, "ALTER TABLE photo_metadata ADD COLUMN ollama_updated_at REAL;", nil, nil, nil)
        }
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        guard let database else { return false }
        let sql = "PRAGMA table_info(\(table));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if text(from: statement, at: 1) == column {
                return true
            }
        }
        return false
    }

    private func read(identifier: String, modificationTime: Double, width: Int, height: Int) -> PhotoMetadata? {
        guard let database else { return nil }
        let sql = "SELECT file_type, file_size, pixel_size, creation_date, metadata_updated_at, camera, lens, exposure, iso, focal_length, location FROM photo_metadata WHERE asset_id = ? AND modification_time = ? AND pixel_width = ? AND pixel_height = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        bindText(identifier, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, modificationTime)
        sqlite3_bind_int(statement, 3, Int32(width))
        sqlite3_bind_int(statement, 4, Int32(height))

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return PhotoMetadata(
            fileType: text(from: statement, at: 0),
            fileSize: text(from: statement, at: 1) ?? "未知",
            pixelSize: text(from: statement, at: 2) ?? "未知",
            creationDate: text(from: statement, at: 3) ?? "未知",
            metadataUpdatedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            camera: text(from: statement, at: 5),
            lens: text(from: statement, at: 6),
            exposure: text(from: statement, at: 7),
            iso: text(from: statement, at: 8),
            focalLength: text(from: statement, at: 9),
            location: text(from: statement, at: 10)
        )
    }

    private func write(_ metadata: PhotoMetadata, identifier: String, modificationTime: Double, width: Int, height: Int) {
        guard let database else { return }
        let sql = "INSERT INTO photo_metadata (asset_id, modification_time, pixel_width, pixel_height, file_type, file_size, pixel_size, creation_date, camera, lens, exposure, iso, focal_length, location, metadata_updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(asset_id) DO UPDATE SET modification_time = excluded.modification_time, pixel_width = excluded.pixel_width, pixel_height = excluded.pixel_height, file_type = excluded.file_type, file_size = excluded.file_size, pixel_size = excluded.pixel_size, creation_date = excluded.creation_date, camera = excluded.camera, lens = excluded.lens, exposure = excluded.exposure, iso = excluded.iso, focal_length = excluded.focal_length, location = excluded.location, metadata_updated_at = excluded.metadata_updated_at;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bindText(identifier, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, modificationTime)
        sqlite3_bind_int(statement, 3, Int32(width))
        sqlite3_bind_int(statement, 4, Int32(height))
        let values = [metadata.fileType, metadata.fileSize, metadata.pixelSize, metadata.creationDate, metadata.camera, metadata.lens, metadata.exposure, metadata.iso, metadata.focalLength, metadata.location]
        for (offset, value) in values.enumerated() {
            if let value {
                bindText(value, to: statement, at: Int32(offset + 5))
            } else {
                sqlite3_bind_null(statement, Int32(offset + 5))
            }
        }
        if let updatedAt = metadata.metadataUpdatedAt {
            sqlite3_bind_double(statement, 15, updatedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 15)
        }
        sqlite3_step(statement)
    }

    private func readOllamaText(identifier: String, modificationTime: Double, width: Int, height: Int) -> String? {
        guard let database else { return nil }
        let sql = "SELECT ollama_text FROM photo_metadata WHERE asset_id = ? AND modification_time = ? AND pixel_width = ? AND pixel_height = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        bindText(identifier, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, modificationTime)
        sqlite3_bind_int(statement, 3, Int32(width))
        sqlite3_bind_int(statement, 4, Int32(height))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(from: statement, at: 0)
    }

    private func writeOllamaText(_ text: String, model: String, identifier: String, modificationTime: Double, width: Int, height: Int) {
        guard let database else { return }
        let sql = "INSERT INTO photo_metadata (asset_id, modification_time, pixel_width, pixel_height, file_type, file_size, pixel_size, creation_date, ollama_text, ollama_model, ollama_updated_at) VALUES (?, ?, ?, ?, '', '', '', '', ?, ?, ?) ON CONFLICT(asset_id) DO UPDATE SET modification_time = excluded.modification_time, pixel_width = excluded.pixel_width, pixel_height = excluded.pixel_height, ollama_text = excluded.ollama_text, ollama_model = excluded.ollama_model, ollama_updated_at = excluded.ollama_updated_at;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(identifier, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, modificationTime)
        sqlite3_bind_int(statement, 3, Int32(width))
        sqlite3_bind_int(statement, 4, Int32(height))
        bindText(text, to: statement, at: 5)
        bindText(model, to: statement, at: 6)
        sqlite3_bind_double(statement, 7, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func bindText(_ value: String, to statement: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func text(from statement: OpaquePointer?, at index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}

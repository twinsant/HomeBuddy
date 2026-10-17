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
    let isFaceAlbum: Bool
    let isRecents: Bool

    var icon: String {
        if isFaceAlbum { return "person.2.crop.square.stack" }
        return isAllPhotos ? "photo.on.rectangle.angled" : "rectangle.stack"
    }

    init(collection: PHAssetCollection) {
        id = collection.localIdentifier
        title = collection.localizedTitle ?? "未命名相册"
        isAllPhotos = collection.assetCollectionSubtype == .smartAlbumUserLibrary
        isFaceAlbum = false
        isRecents = collection.assetCollectionSubtype == .smartAlbumRecentlyAdded
    }

    static var faceAlbum: PhotoAlbum {
        PhotoAlbum(
            id: "virtual:faces",
            title: "人物",
            isAllPhotos: false,
            isFaceAlbum: true,
            isRecents: false
        )
    }

    init(id: String, title: String, isAllPhotos: Bool, isFaceAlbum: Bool, isRecents: Bool) {
        self.id = id
        self.title = title
        self.isAllPhotos = isAllPhotos
        self.isFaceAlbum = isFaceAlbum
        self.isRecents = isRecents
    }
}

struct Person: Identifiable, Equatable {
    let id: String
    let displayName: String
}

struct PersonFaceCount: Identifiable, Equatable {
    let person: Person
    let count: Int

    var id: String { person.id }
}

struct DetectedFace: Equatable {
    let box: CGRect
    let personID: String?
    var candidate: FacePersonCandidate? = nil
}

struct FaceDetectionResult: Equatable {
    let faceCount: Int
    let faces: [DetectedFace]
    let detectorVersion: String

    var faceBoxes: [CGRect] { faces.map(\.box) }

    nonisolated init(faceCount: Int, faces: [DetectedFace], detectorVersion: String) {
        self.faceCount = faceCount
        self.faces = faces
        self.detectorVersion = detectorVersion
    }

    nonisolated init(faceCount: Int, faceBoxes: [CGRect], detectorVersion: String) {
        self.init(
            faceCount: faceCount,
            faces: faceBoxes.map { DetectedFace(box: $0, personID: nil) },
            detectorVersion: detectorVersion
        )
    }

    nonisolated static let currentDetectorVersion = "facedetect-antelopev2-1"
    nonisolated static let legacyDetectorVersion = "vision-face-1"
}

@MainActor
final class PhotoLibraryStore: ObservableObject {
    @Published private(set) var albums: [PhotoAlbum] = [.faceAlbum]
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

    func assets(for album: PhotoAlbum) -> [LibraryAsset] {
        if album.isFaceAlbum {
            let assetIDs = PhotoMetadataCache.shared.faceAssetIDs()
            guard !assetIDs.isEmpty else { return [] }

            let photoIDs = assetIDs.filter { !$0.hasPrefix("disk:") }
            let fetchedAssets = PHAsset.fetchAssets(withLocalIdentifiers: photoIDs, options: nil)
            let assetsByID = Dictionary(
                uniqueKeysWithValues: fetchedAssets.objects(at: IndexSet(integersIn: 0..<fetchedAssets.count))
                    .filter { $0.mediaType == .image }
                    .map { ($0.localIdentifier, $0) }
            )
            let diskAssets = PhotoMetadataCache.shared.faceDiskAssets()
            return assetIDs.compactMap { id in
                if let photo = assetsByID[id] { return LibraryAsset(photo) }
                return diskAssets[id]
            }
        }

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
            .map(LibraryAsset.init)
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
        let systemAlbums = collections
            .map(PhotoAlbum.init)
            .filter { seen.insert($0.id).inserted }
            .sorted { left, right in
                if left.isAllPhotos != right.isAllPhotos {
                    return left.isAllPhotos
                }
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
        albums = [PhotoAlbum.faceAlbum] + systemAlbums
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
        defer { NotificationCenter.default.post(name: .init("HomeBuddyDatabaseDidChange"), object: nil) }
        return queue.sync {
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
        for asset: LibraryAsset,
        completion: @escaping (PhotoMetadata?) -> Void
    ) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            let result = self?.accepts(asset) == true ? self?.read(
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            ) : nil
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func save(_ metadata: PhotoMetadata, for asset: LibraryAsset) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            guard self?.accepts(asset) == true else { return }
            self?.write(
                metadata,
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            )
        }
    }

    func ollamaText(for asset: LibraryAsset, completion: @escaping (String?) -> Void) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            let result = self?.accepts(asset) == true ? self?.readOllamaText(
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            ) : nil
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func assetIDs(matchingOllamaKeywords keywords: [String], completion: @escaping (Set<String>) -> Void) {
        let normalizedKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        queue.async { [weak self] in
            let result = self?.readAssetIDs(matchingOllamaKeywords: normalizedKeywords) ?? []
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Returns photo IDs with a cached positive face detection result.
    /// The synchronous snapshot is protected by the cache's serial SQLite queue.
    func faceAssetIDs() -> [String] {
        queue.sync { readFaceAssetIDs() }
    }

    func saveOllamaText(_ text: String, model: String, for asset: LibraryAsset, completion: ((Bool) -> Void)? = nil) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            guard self?.accepts(asset) == true else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            self?.writeOllamaText(
                text,
                model: model,
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            )
            let saved = self?.readOllamaText(identifier: identifier, modificationTime: modificationTime, width: width, height: height) == text
            DispatchQueue.main.async {
                if saved { NotificationCenter.default.post(name: .init("HomeBuddyRecognitionDidChange"), object: nil) }
                completion?(saved)
            }
        }
    }

    func faceDetectionResult(for asset: LibraryAsset, completion: @escaping (FaceDetectionResult?) -> Void) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            let result = self?.accepts(asset) == true ? self?.readFaceDetectionResult(
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height,
                detectorVersion: FaceDetectionResult.currentDetectorVersion
            ) : nil
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func saveFaceDetectionResult(
        _ result: FaceDetectionResult,
        for asset: LibraryAsset,
        completion: (() -> Void)? = nil
    ) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight

        queue.async { [weak self] in
            let accepted = self?.accepts(asset) == true
            if accepted { self?.writeFaceDetectionResult(
                result,
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height
            ) }
            DispatchQueue.main.async {
                if accepted { NotificationCenter.default.post(name: .init("HomeBuddyRecognitionDidChange"), object: nil) }
                completion?()
            }
        }
    }

    func people(completion: @escaping ([Person]) -> Void) {
        queue.async { [weak self] in
            let people = self?.readPeople() ?? []
            DispatchQueue.main.async { completion(people) }
        }
    }

    func mostLabeledPeople(completion: @escaping ([PersonFaceCount]) -> Void) {
        queue.async { [weak self] in
            let people = self?.readMostLabeledPeople() ?? []
            DispatchQueue.main.async { completion(people) }
        }
    }

    func savePerson(named displayName: String, completion: @escaping (Person?) -> Void) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let person = Person(id: UUID().uuidString, displayName: name)
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let normalizedName = Self.normalizedPersonName(name)
            let existingPerson = self.readPeople().first {
                Self.normalizedPersonName($0.displayName) == normalizedName
            }
            let savedPerson = existingPerson ?? (self.writePerson(person) ? person : nil)
            DispatchQueue.main.async { completion(savedPerson) }
        }
    }

    func saveFacePersonID(
        _ personID: String?,
        faceIndex: Int,
        for asset: LibraryAsset,
        completion: ((Bool) -> Void)? = nil
    ) {
        let identifier = asset.localIdentifier
        let modificationTime = asset.modificationDate?.timeIntervalSince1970 ?? 0
        let width = asset.pixelWidth
        let height = asset.pixelHeight
        queue.async { [weak self] in
            let succeeded = self?.accepts(asset) == true && (self?.writeFacePersonID(
                personID,
                faceIndex: faceIndex,
                identifier: identifier,
                modificationTime: modificationTime,
                width: width,
                height: height,
                detectorVersion: FaceDetectionResult.currentDetectorVersion
            ) ?? false)
            DispatchQueue.main.async {
                if succeeded { NotificationCenter.default.post(name: .init("HomeBuddyRecognitionDidChange"), object: nil) }
                completion?(succeeded)
            }
        }
    }

    /// Executed only on the serial database queue, before any cache read/write.
    func areCurrent(_ assets: [LibraryAsset]) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: assets.allSatisfy { accepts($0) }) }
        }
    }

    private func accepts(_ asset: LibraryAsset) -> Bool {
        guard databaseURLValue == asset.databaseURL else { return false }
        guard case .disk(let directory, let image) = asset.source else { return true }
        guard let database else { return false }
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM disk_images WHERE image_id = ? AND directory_id = ? AND modification_time = ? AND byte_size = ? AND pixel_width = ? AND pixel_height = ?;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(image.id, to: statement, at: 1)
        bindText(directory.id, to: statement, at: 2)
        sqlite3_bind_double(statement, 3, image.modificationTime)
        sqlite3_bind_int64(statement, 4, image.byteSize)
        sqlite3_bind_int64(statement, 5, Int64(image.width))
        sqlite3_bind_int64(statement, 6, Int64(image.height))
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func faceDiskAssets() -> [String: LibraryAsset] {
        let records: [(DiskDirectory, DiskImage)] = queue.sync {
            guard let database else { return [] }
            let index = DiskLibraryDatabase(database: database)
            let faceIDs = Set(readFaceAssetIDs())
            return ((try? index.directories()) ?? []).flatMap { directory in
                ((try? index.images(directoryID: directory.id)) ?? [])
                    .filter { faceIDs.contains($0.id) }
                    .map { (directory, $0) }
            }
        }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.1.id, LibraryAsset(directory: $0.0, image: $0.1)) })
    }

    private var databaseURLValue: URL?

    /// Runs directory index operations on the same connection as the Photos caches.
    func diskLibraryOperation<T: Sendable>(
        expectedURL: URL? = nil,
        _ operation: @escaping @Sendable (DiskLibraryDatabase) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard let database else { throw DiskLibraryError.message("数据库不可用。") }
                    if let expectedURL, expectedURL != databaseURLValue {
                        throw DiskLibraryError.message("数据库已切换，请重新扫描目录。")
                    }
                    let result = try operation(DiskLibraryDatabase(database: database))
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

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
            do {
                try DiskLibraryDatabase(database: database!).migrate()
            } catch {
                closeDatabase()
                return false
            }
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
        sqlite3_exec(database, "PRAGMA foreign_keys = ON;", nil, nil, nil)
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
        let faceTablesSQL = """
        CREATE TABLE IF NOT EXISTS face_detection_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id TEXT NOT NULL,
            modification_time REAL NOT NULL,
            pixel_width INTEGER NOT NULL,
            pixel_height INTEGER NOT NULL,
            detector_version TEXT NOT NULL,
            face_count INTEGER NOT NULL,
            detected_at REAL NOT NULL,
            UNIQUE (asset_id, modification_time, pixel_width, pixel_height, detector_version)
        );
        CREATE TABLE IF NOT EXISTS detected_faces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            result_id INTEGER NOT NULL,
            face_index INTEGER NOT NULL,
            x REAL NOT NULL,
            y REAL NOT NULL,
            width REAL NOT NULL,
            height REAL NOT NULL,
            person_id TEXT,
            FOREIGN KEY (result_id) REFERENCES face_detection_results(id) ON DELETE CASCADE,
            UNIQUE (result_id, face_index)
        );
        CREATE INDEX IF NOT EXISTS detected_faces_result_id_index
            ON detected_faces(result_id);
        CREATE INDEX IF NOT EXISTS face_detection_results_asset_revision_index
            ON face_detection_results(asset_id, modification_time DESC);
        """
        sqlite3_exec(database, faceTablesSQL, nil, nil, nil)
        sqlite3_exec(database, "CREATE TABLE IF NOT EXISTS people (person_id TEXT PRIMARY KEY NOT NULL, display_name TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL);", nil, nil, nil)
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
        if !columnExists("person_id", in: "detected_faces") {
            sqlite3_exec(database, "ALTER TABLE detected_faces ADD COLUMN person_id TEXT;", nil, nil, nil)
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

    private func readFaceDetectionResult(
        identifier: String,
        modificationTime: Double,
        width: Int,
        height: Int,
        detectorVersion: String
    ) -> FaceDetectionResult? {
        guard let database else { return nil }
        let resultSQL = """
        SELECT id, face_count, detector_version FROM face_detection_results
        WHERE asset_id = ? AND modification_time = ? AND pixel_width = ?
          AND pixel_height = ? AND detector_version IN (?, ?)
        ORDER BY CASE detector_version WHEN ? THEN 0 ELSE 1 END LIMIT 1;
        """
        var resultStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, resultSQL, -1, &resultStatement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(resultStatement) }
        bindText(identifier, to: resultStatement, at: 1)
        sqlite3_bind_double(resultStatement, 2, modificationTime)
        sqlite3_bind_int(resultStatement, 3, Int32(width))
        sqlite3_bind_int(resultStatement, 4, Int32(height))
        bindText(detectorVersion, to: resultStatement, at: 5)
        bindText(FaceDetectionResult.legacyDetectorVersion, to: resultStatement, at: 6)
        bindText(detectorVersion, to: resultStatement, at: 7)
        guard sqlite3_step(resultStatement) == SQLITE_ROW else { return nil }

        let resultID = sqlite3_column_int64(resultStatement, 0)
        let faceCount = Int(sqlite3_column_int(resultStatement, 1))
        let facesSQL = "SELECT x, y, width, height, person_id FROM detected_faces WHERE result_id = ? ORDER BY face_index;"
        var facesStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, facesSQL, -1, &facesStatement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(facesStatement) }
        sqlite3_bind_int64(facesStatement, 1, resultID)

        var faces: [DetectedFace] = []
        while sqlite3_step(facesStatement) == SQLITE_ROW {
            faces.append(DetectedFace(
                box: CGRect(
                    x: sqlite3_column_double(facesStatement, 0),
                    y: sqlite3_column_double(facesStatement, 1),
                    width: sqlite3_column_double(facesStatement, 2),
                    height: sqlite3_column_double(facesStatement, 3)
                ),
                personID: text(from: facesStatement, at: 4)
            ))
        }
        return FaceDetectionResult(
            faceCount: faceCount,
            faces: faces,
            detectorVersion: text(from: resultStatement, at: 2) ?? detectorVersion
        )
    }

    private func readPeople() -> [Person] {
        guard let database else { return [] }
        let sql = "SELECT person_id, display_name FROM people ORDER BY display_name COLLATE NOCASE;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var result: [Person] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(from: statement, at: 0), let name = text(from: statement, at: 1) else { continue }
            result.append(Person(id: id, displayName: name))
        }
        return result
    }

    // Each asset can have legacy and current detector results (or older photo revisions).
    // Count faces only from the newest photo revision and its preferred detector result.
    static let mostLabeledPeopleSQL = """
        SELECT p.person_id, p.display_name, COUNT(*) AS labeled_faces
        FROM detected_faces f
        JOIN face_detection_results r ON r.id = f.result_id
        JOIN people p ON p.person_id = f.person_id
        WHERE r.id = (
            SELECT latest.id FROM face_detection_results latest
            WHERE latest.asset_id = r.asset_id
            ORDER BY latest.modification_time DESC,
                CASE WHEN latest.detector_version = '\(FaceDetectionResult.currentDetectorVersion)' THEN 0 ELSE 1 END,
                latest.detected_at DESC, latest.id DESC
            LIMIT 1
        )
        GROUP BY p.person_id, p.display_name
        ORDER BY labeled_faces DESC, p.display_name COLLATE NOCASE, p.person_id
        LIMIT 5;
        """

    private func readMostLabeledPeople() -> [PersonFaceCount] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, Self.mostLabeledPeopleSQL, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var result: [PersonFaceCount] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(from: statement, at: 0),
                  let name = text(from: statement, at: 1) else { continue }
            result.append(PersonFaceCount(
                person: Person(id: id, displayName: name),
                count: Int(sqlite3_column_int(statement, 2))
            ))
        }
        return result
    }

    private static func normalizedPersonName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func writePerson(_ person: Person) -> Bool {
        guard let database else { return false }
        let sql = "INSERT INTO people (person_id, display_name, created_at, updated_at) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(person.id, to: statement, at: 1)
        bindText(person.displayName, to: statement, at: 2)
        let now = Date().timeIntervalSince1970
        sqlite3_bind_double(statement, 3, now)
        sqlite3_bind_double(statement, 4, now)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func writeFacePersonID(
        _ personID: String?,
        faceIndex: Int,
        identifier: String,
        modificationTime: Double,
        width: Int,
        height: Int,
        detectorVersion: String
    ) -> Bool {
        guard let database else { return false }
        let resultSQL = """
        SELECT id FROM face_detection_results
        WHERE asset_id = ? AND modification_time = ? AND pixel_width = ?
          AND pixel_height = ? AND detector_version IN (?, ?)
        ORDER BY CASE detector_version WHEN ? THEN 0 ELSE 1 END LIMIT 1;
        """
        var resultStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, resultSQL, -1, &resultStatement, nil) == SQLITE_OK else { return false }
        bindText(identifier, to: resultStatement, at: 1)
        sqlite3_bind_double(resultStatement, 2, modificationTime)
        sqlite3_bind_int(resultStatement, 3, Int32(width))
        sqlite3_bind_int(resultStatement, 4, Int32(height))
        bindText(detectorVersion, to: resultStatement, at: 5)
        bindText(FaceDetectionResult.legacyDetectorVersion, to: resultStatement, at: 6)
        bindText(detectorVersion, to: resultStatement, at: 7)
        guard sqlite3_step(resultStatement) == SQLITE_ROW else {
            sqlite3_finalize(resultStatement)
            return false
        }
        let resultID = sqlite3_column_int64(resultStatement, 0)
        sqlite3_finalize(resultStatement)

        let updateSQL = "UPDATE detected_faces SET person_id = ? WHERE result_id = ? AND face_index = ?;"
        var updateStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, updateSQL, -1, &updateStatement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(updateStatement) }
        if let personID {
            bindText(personID, to: updateStatement, at: 1)
        } else {
            sqlite3_bind_null(updateStatement, 1)
        }
        sqlite3_bind_int64(updateStatement, 2, resultID)
        sqlite3_bind_int(updateStatement, 3, Int32(faceIndex))
        guard sqlite3_step(updateStatement) == SQLITE_DONE else { return false }
        return sqlite3_changes(database) > 0
    }

    private func writeFaceDetectionResult(
        _ result: FaceDetectionResult,
        identifier: String,
        modificationTime: Double,
        width: Int,
        height: Int
    ) {
        guard let database else { return }
        var existingFaces: [(box: CGRect, personID: String)] = []
        let existingSQL = """
        SELECT f.face_index, f.person_id, f.x, f.y, f.width, f.height
        FROM detected_faces f
        JOIN face_detection_results r ON r.id = f.result_id
        WHERE r.asset_id = ? AND r.modification_time = ? AND r.pixel_width = ?
          AND r.pixel_height = ? AND f.person_id IS NOT NULL;
        """
        var existingStatement: OpaquePointer?
        if sqlite3_prepare_v2(database, existingSQL, -1, &existingStatement, nil) == SQLITE_OK {
            bindText(identifier, to: existingStatement, at: 1)
            sqlite3_bind_double(existingStatement, 2, modificationTime)
            sqlite3_bind_int(existingStatement, 3, Int32(width))
            sqlite3_bind_int(existingStatement, 4, Int32(height))
            // Preserve annotations across detector upgrades by matching face geometry,
            // rather than carrying a person ID over by array index.
            while sqlite3_step(existingStatement) == SQLITE_ROW {
                guard let personID = text(from: existingStatement, at: 1) else { continue }
                existingFaces.append((
                    CGRect(
                        x: sqlite3_column_double(existingStatement, 2),
                        y: sqlite3_column_double(existingStatement, 3),
                        width: sqlite3_column_double(existingStatement, 4),
                        height: sqlite3_column_double(existingStatement, 5)
                    ),
                    personID
                ))
            }
            sqlite3_finalize(existingStatement)
        }
        sqlite3_exec(database, "BEGIN TRANSACTION;", nil, nil, nil)
        var succeeded = false
        defer {
            sqlite3_exec(database, succeeded ? "COMMIT;" : "ROLLBACK;", nil, nil, nil)
        }

        let deleteSQL = """
        DELETE FROM face_detection_results
        WHERE asset_id = ? AND modification_time = ? AND pixel_width = ?
          AND pixel_height = ? AND detector_version = ?;
        """
        var deleteStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK else { return }
        bindText(identifier, to: deleteStatement, at: 1)
        sqlite3_bind_double(deleteStatement, 2, modificationTime)
        sqlite3_bind_int(deleteStatement, 3, Int32(width))
        sqlite3_bind_int(deleteStatement, 4, Int32(height))
        bindText(result.detectorVersion, to: deleteStatement, at: 5)
        guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
            sqlite3_finalize(deleteStatement)
            return
        }
        sqlite3_finalize(deleteStatement)

        let insertSQL = """
        INSERT INTO face_detection_results
        (asset_id, modification_time, pixel_width, pixel_height, detector_version, face_count, detected_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var insertStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, insertSQL, -1, &insertStatement, nil) == SQLITE_OK else { return }
        bindText(identifier, to: insertStatement, at: 1)
        sqlite3_bind_double(insertStatement, 2, modificationTime)
        sqlite3_bind_int(insertStatement, 3, Int32(width))
        sqlite3_bind_int(insertStatement, 4, Int32(height))
        bindText(result.detectorVersion, to: insertStatement, at: 5)
        sqlite3_bind_int(insertStatement, 6, Int32(result.faceCount))
        sqlite3_bind_double(insertStatement, 7, Date().timeIntervalSince1970)
        guard sqlite3_step(insertStatement) == SQLITE_DONE else {
            sqlite3_finalize(insertStatement)
            return
        }
        sqlite3_finalize(insertStatement)

        let resultID = sqlite3_last_insert_rowid(database)
        let faceSQL = "INSERT INTO detected_faces (result_id, face_index, x, y, width, height, person_id) VALUES (?, ?, ?, ?, ?, ?, ?);"
        for (index, face) in result.faces.enumerated() {
            var faceStatement: OpaquePointer?
            guard sqlite3_prepare_v2(database, faceSQL, -1, &faceStatement, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(faceStatement, 1, resultID)
            sqlite3_bind_int(faceStatement, 2, Int32(index))
            sqlite3_bind_double(faceStatement, 3, Double(face.box.origin.x))
            sqlite3_bind_double(faceStatement, 4, Double(face.box.origin.y))
            sqlite3_bind_double(faceStatement, 5, Double(face.box.size.width))
            sqlite3_bind_double(faceStatement, 6, Double(face.box.size.height))
            let inheritedPersonID = face.personID ?? existingFaces
                .map { ($0.personID, intersectionOverUnion(face.box, $0.box)) }
                .filter { $0.1 >= 0.5 }
                .max(by: { $0.1 < $1.1 })?.0
            if let personID = inheritedPersonID {
                bindText(personID, to: faceStatement, at: 7)
            } else {
                sqlite3_bind_null(faceStatement, 7)
            }
            let status = sqlite3_step(faceStatement)
            sqlite3_finalize(faceStatement)
            guard status == SQLITE_DONE else { return }
        }
        succeeded = true
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private func readAssetIDs(matchingOllamaKeywords keywords: [String]) -> Set<String> {
        guard let database, !keywords.isEmpty else { return [] }

        let conditions = Array(repeating: "ollama_text LIKE ? ESCAPE '\\'", count: keywords.count)
            .joined(separator: " AND ")
        let sql = "SELECT asset_id FROM photo_metadata WHERE ollama_text IS NOT NULL AND ollama_text <> '' AND \(conditions);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        for (offset, keyword) in keywords.enumerated() {
            let escapedKeyword = keyword
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            bindText("%\(escapedKeyword)%", to: statement, at: Int32(offset + 1))
        }

        var identifiers = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let identifier = text(from: statement, at: 0) {
                identifiers.insert(identifier)
            }
        }
        return identifiers
    }

    private func readFaceAssetIDs() -> [String] {
        guard let database else { return [] }
        let sql = """
        WITH latest AS (
            SELECT asset_id, MAX(detected_at) AS detected_at
            FROM face_detection_results
            WHERE detector_version IN (?, ?)
            GROUP BY asset_id
        )
        SELECT result.asset_id
        FROM latest
        JOIN face_detection_results AS result
          ON result.asset_id = latest.asset_id AND result.detected_at = latest.detected_at
        WHERE result.detector_version IN (?, ?) AND result.face_count > 0
        GROUP BY result.asset_id
        ORDER BY MAX(result.detected_at) DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bindText(FaceDetectionResult.currentDetectorVersion, to: statement, at: 1)
        bindText(FaceDetectionResult.legacyDetectorVersion, to: statement, at: 2)
        bindText(FaceDetectionResult.currentDetectorVersion, to: statement, at: 3)
        bindText(FaceDetectionResult.legacyDetectorVersion, to: statement, at: 4)

        var assetIDs: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let assetID = text(from: statement, at: 0) {
                assetIDs.append(assetID)
            }
        }
        return assetIDs
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

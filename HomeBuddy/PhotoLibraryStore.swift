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

    private let queue = DispatchQueue(label: "com.twinsant.HomeBuddy.photo-metadata-cache")
    private var database: OpaquePointer?

    private init() {
        queue.sync {
            openDatabase()
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    var databaseURL: URL? {
        queue.sync { databaseURLValue }
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

    private var databaseURLValue: URL?

    private func openDatabase() {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".homebuddy", isDirectory: true)
        let fallbackURL = (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? homeDirectoryURL)
            .appendingPathComponent("HomeBuddy", isDirectory: true)

        let candidates = [homeDirectoryURL, fallbackURL]
        for directory in candidates {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("photo-metadata.sqlite")
                guard sqlite3_open(url.path, &database) == SQLITE_OK else {
                    if let database {
                        sqlite3_close(database)
                        self.database = nil
                    }
                    continue
                }
                databaseURLValue = url
                createTable()
                return
            } catch {
                continue
            }
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
            location TEXT
        );
        """
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func read(identifier: String, modificationTime: Double, width: Int, height: Int) -> PhotoMetadata? {
        guard let database else { return nil }
        let sql = "SELECT file_type, file_size, pixel_size, creation_date, camera, lens, exposure, iso, focal_length, location FROM photo_metadata WHERE asset_id = ? AND modification_time = ? AND pixel_width = ? AND pixel_height = ? LIMIT 1;"
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
            camera: text(from: statement, at: 4),
            lens: text(from: statement, at: 5),
            exposure: text(from: statement, at: 6),
            iso: text(from: statement, at: 7),
            focalLength: text(from: statement, at: 8),
            location: text(from: statement, at: 9)
        )
    }

    private func write(_ metadata: PhotoMetadata, identifier: String, modificationTime: Double, width: Int, height: Int) {
        guard let database else { return }
        let sql = "INSERT OR REPLACE INTO photo_metadata (asset_id, modification_time, pixel_width, pixel_height, file_type, file_size, pixel_size, creation_date, camera, lens, exposure, iso, focal_length, location) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
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

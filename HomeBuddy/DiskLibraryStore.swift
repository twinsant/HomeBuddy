import AppKit
import Combine
import Foundation
import ImageIO
import Photos
import SQLite3
import UniformTypeIdentifiers

/// Both libraries use the same viewer, recognition models and cache identity.
nonisolated struct LibraryAsset: @unchecked Sendable {
    enum Source {
        case photos(PHAsset)
        case disk(DiskDirectory, DiskImage)
    }
    let source: Source
    let databaseURL: URL?

    @MainActor init(_ asset: PHAsset) {
        self.init(asset, databaseURL: PhotoMetadataCache.shared.databaseURL)
    }

    @MainActor init(_ asset: PHAsset, databaseURL: URL?) {
        source = .photos(asset)
        self.databaseURL = databaseURL
    }

    @MainActor init(directory: DiskDirectory, image: DiskImage) {
        self.init(directory: directory, image: image, databaseURL: PhotoMetadataCache.shared.databaseURL)
    }

    @MainActor init(directory: DiskDirectory, image: DiskImage, databaseURL: URL?) {
        source = .disk(directory, image)
        self.databaseURL = databaseURL
    }

    var localIdentifier: String {
        switch source { case .photos(let asset): return asset.localIdentifier; case .disk(_, let image): return image.id }
    }
    var modificationDate: Date? {
        switch source { case .photos(let asset): return asset.modificationDate; case .disk(_, let image): return Date(timeIntervalSince1970: image.modificationTime) }
    }
    var creationDate: Date? {
        switch source { case .photos(let asset): return asset.creationDate; case .disk: return nil }
    }
    var pixelWidth: Int {
        switch source { case .photos(let asset): return asset.pixelWidth; case .disk(_, let image): return image.width }
    }
    var pixelHeight: Int {
        switch source { case .photos(let asset): return asset.pixelHeight; case .disk(_, let image): return image.height }
    }
    var isFavorite: Bool {
        switch source { case .photos(let asset): return asset.isFavorite; case .disk: return false }
    }
    var isLivePhoto: Bool {
        guard case .photos(let asset) = source else { return false }
        return asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive)
    }
    var relativePath: String? {
        if case .disk(_, let image) = source { return image.relativePath }
        return nil
    }
    var revisionID: String {
        "\(databaseURL?.path ?? ""): \(localIdentifier):\(modificationDate?.timeIntervalSince1970 ?? 0):\(pixelWidth):\(pixelHeight):\(diskByteSize ?? 0)"
    }
    var diskByteSize: Int64? {
        if case .disk(_, let image) = source { return image.byteSize }
        return nil
    }
}

@MainActor
final class LibraryImageManager {
    static let shared = LibraryImageManager()

    func requestImage(for asset: LibraryAsset, targetSize: CGSize, contentMode: PHImageContentMode,
                      options: PHImageRequestOptions, resultHandler: @escaping @MainActor (NSImage?, [AnyHashable: Any]?) -> Void) {
        switch asset.source {
        case .photos(let photo):
            PHImageManager.default().requestImage(for: photo, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
                Task { @MainActor in resultHandler(image, info) }
            }
        case .disk(let directory, let image):
            let maximumSize = max(Int(max(targetSize.width, targetSize.height)), 1)
            Task {
                do {
                    let bitmap = try await Task.detached(priority: .utility) {
                        try DiskImageLoader.thumbnail(directory: directory, image: image, maximumSize: maximumSize)
                    }.value
                    resultHandler(NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height)), nil)
                } catch { resultHandler(nil, [PHImageErrorKey: error]) }
            }
        }
    }

    func requestImageDataAndOrientation(for asset: LibraryAsset, options: PHImageRequestOptions,
                                       resultHandler: @escaping @MainActor (Data?, String?, CGImagePropertyOrientation, [AnyHashable: Any]?) -> Void) {
        switch asset.source {
        case .photos(let photo):
            PHImageManager.default().requestImageDataAndOrientation(for: photo, options: options) { data, uti, orientation, info in
                Task { @MainActor in resultHandler(data, uti, orientation, info) }
            }
        case .disk(let directory, let image):
            Task {
                do {
                    let loaded = try await Task.detached(priority: .utility) {
                        try DiskImageLoader.originalData(directory: directory, image: image)
                    }.value
                    resultHandler(loaded.data, loaded.uti, loaded.orientation, nil)
                } catch { resultHandler(nil, nil, .up, [PHImageErrorKey: error]) }
            }
        }
    }
}

nonisolated struct DiskDirectory: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let path: String
    let bookmark: Data
    let lastScan: Double?
    let imageCount: Int
}

nonisolated struct DiskImage: Identifiable, Equatable, Sendable {
    let id: String
    let relativePath: String
    let modificationTime: Double
    let byteSize: Int64
    let width: Int
    let height: Int
}

nonisolated enum DiskLibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return AppLocalization.localizedString(text, comment: "") }
    }
}

/// All calls run on PhotoMetadataCache's existing serial SQLite queue.
nonisolated struct DiskLibraryDatabase {
    let database: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static let schema = """
    CREATE TABLE IF NOT EXISTS disk_directories (
        directory_id TEXT PRIMARY KEY NOT NULL,
        display_name TEXT NOT NULL,
        last_known_path TEXT NOT NULL UNIQUE,
        security_scoped_bookmark BLOB NOT NULL,
        last_scan_at REAL
    );
    CREATE TABLE IF NOT EXISTS disk_images (
        image_id TEXT PRIMARY KEY NOT NULL,
        directory_id TEXT NOT NULL REFERENCES disk_directories(directory_id) ON DELETE CASCADE,
        relative_path TEXT NOT NULL,
        modification_time REAL NOT NULL,
        byte_size INTEGER NOT NULL,
        pixel_width INTEGER NOT NULL,
        pixel_height INTEGER NOT NULL,
        scan_generation TEXT NOT NULL,
        UNIQUE(directory_id, relative_path)
    );
    CREATE INDEX IF NOT EXISTS disk_images_directory_index ON disk_images(directory_id);
    """

    func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    func migrate() throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute(Self.schema)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func failure() -> DiskLibraryError {
        .message("数据库操作失败：\(String(cString: sqlite3_errmsg(database)))")
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw failure()
        }
        return pointer
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func directories() throws -> [DiskDirectory] {
        let query = try statement("""
        SELECT d.directory_id, d.display_name, d.last_known_path, d.security_scoped_bookmark,
               d.last_scan_at, COUNT(i.image_id)
        FROM disk_directories d LEFT JOIN disk_images i ON i.directory_id = d.directory_id
        GROUP BY d.directory_id ORDER BY d.display_name COLLATE NOCASE, d.directory_id;
        """)
        defer { sqlite3_finalize(query) }
        var result: [DiskDirectory] = []
        var status = sqlite3_step(query)
        while status == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(query, 3) else { throw failure() }
            result.append(DiskDirectory(
                id: text(query, 0), title: text(query, 1), path: text(query, 2),
                bookmark: Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 3))),
                lastScan: sqlite3_column_type(query, 4) == SQLITE_NULL ? nil : sqlite3_column_double(query, 4),
                imageCount: Int(sqlite3_column_int(query, 5))
            ))
            status = sqlite3_step(query)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return result
    }

    func saveDirectory(id: String, url: URL, bookmark: Data) throws {
        let query = try statement("""
        INSERT INTO disk_directories(directory_id, display_name, last_known_path, security_scoped_bookmark)
        VALUES (?, ?, ?, ?) ON CONFLICT(directory_id) DO UPDATE SET
        display_name = excluded.display_name, last_known_path = excluded.last_known_path,
        security_scoped_bookmark = excluded.security_scoped_bookmark;
        """)
        defer { sqlite3_finalize(query) }
        bind(id, to: query, at: 1)
        bind(url.lastPathComponent, to: query, at: 2)
        bind(url.path, to: query, at: 3)
        _ = bookmark.withUnsafeBytes { sqlite3_bind_blob(query, 4, $0.baseAddress, Int32($0.count), transient) }
        try finish(query)
    }

    func removeDirectory(id: String) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try invalidateCaches(imageIDs: Set(images(directoryID: id).map(\.id)))
            let query = try statement("DELETE FROM disk_directories WHERE directory_id = ?;")
            defer { sqlite3_finalize(query) }
            bind(id, to: query, at: 1)
            try finish(query)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func images(directoryID: String) throws -> [DiskImage] {
        let query = try statement("""
        SELECT image_id, relative_path, modification_time, byte_size, pixel_width, pixel_height
        FROM disk_images WHERE directory_id = ? ORDER BY relative_path COLLATE NOCASE;
        """)
        defer { sqlite3_finalize(query) }
        bind(directoryID, to: query, at: 1)
        var result: [DiskImage] = []
        var status = sqlite3_step(query)
        while status == SQLITE_ROW {
            result.append(DiskImage(id: text(query, 0), relativePath: text(query, 1),
                                    modificationTime: sqlite3_column_double(query, 2),
                                    byteSize: sqlite3_column_int64(query, 3),
                                    width: Int(sqlite3_column_int(query, 4)), height: Int(sqlite3_column_int(query, 5))))
            status = sqlite3_step(query)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return result
    }

    /// The caller must supply a complete, successful scan. No partial scan may prune rows.
    func replaceImages(directoryID: String, images: [DiskImage]) throws {
        let previous = try self.images(directoryID: directoryID)
        let byPath = Dictionary(uniqueKeysWithValues: images.map { ($0.relativePath, $0) })
        let invalidated = Set(previous.filter { old in
            guard let new = byPath[old.relativePath] else { return true }
            return old.modificationTime != new.modificationTime || old.byteSize != new.byteSize || old.width != new.width || old.height != new.height
        }.map(\.id))
        let generation = UUID().uuidString
        try execute("BEGIN IMMEDIATE;")
        do {
            try invalidateCaches(imageIDs: invalidated)
            let insert = try statement("""
            INSERT INTO disk_images VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(directory_id, relative_path) DO UPDATE SET
            modification_time = excluded.modification_time, byte_size = excluded.byte_size,
            pixel_width = excluded.pixel_width, pixel_height = excluded.pixel_height,
            scan_generation = excluded.scan_generation;
            """)
            defer { sqlite3_finalize(insert) }
            for image in images {
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
                bind(image.id, to: insert, at: 1)
                bind(directoryID, to: insert, at: 2)
                bind(image.relativePath, to: insert, at: 3)
                sqlite3_bind_double(insert, 4, image.modificationTime)
                sqlite3_bind_int64(insert, 5, image.byteSize)
                sqlite3_bind_int64(insert, 6, Int64(image.width))
                sqlite3_bind_int64(insert, 7, Int64(image.height))
                bind(generation, to: insert, at: 8)
                try finish(insert)
            }
            let prune = try statement("DELETE FROM disk_images WHERE directory_id = ? AND scan_generation != ?;")
            defer { sqlite3_finalize(prune) }
            bind(directoryID, to: prune, at: 1)
            bind(generation, to: prune, at: 2)
            try finish(prune)
            let update = try statement("UPDATE disk_directories SET last_scan_at = ? WHERE directory_id = ?;")
            defer { sqlite3_finalize(update) }
            sqlite3_bind_double(update, 1, Date().timeIntervalSince1970)
            bind(directoryID, to: update, at: 2)
            try finish(update)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func invalidateCaches(imageIDs: Set<String>) throws {
        // Unit-test databases may only contain the directory index schema.
        for table in ["photo_metadata", "face_detection_results"] {
            let exists = try statement("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;")
            bind(table, to: exists, at: 1)
            let available = sqlite3_step(exists) == SQLITE_ROW
            sqlite3_finalize(exists)
            guard available else { continue }
            let deletion = try statement("DELETE FROM \(table) WHERE asset_id = ?;")
            defer { sqlite3_finalize(deletion) }
            for id in imageIDs {
                sqlite3_reset(deletion)
                sqlite3_clear_bindings(deletion)
                bind(id, to: deletion, at: 1)
                try finish(deletion)
            }
        }
    }
}

nonisolated enum DiskImageLoader {
    static func resolvedDirectory(_ directory: DiskDirectory) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: directory.bookmark, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    static func scan(root: URL) throws -> [DiskImage] {
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw DiskLibraryError.message("目录不可用，请重新选择目录。")
        }
        var enumerationError: Error?
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else { throw DiskLibraryError.message("无法读取目录。") }
        var images: [DiskImage] = []
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: Set(keys))
            // DirectoryEnumerator does not follow symlinks. Calling skipDescendants
            // on a link to a file can skip the next real directory instead.
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true, file.path.hasPrefix(prefix) else { continue }
            let image: DiskImage? = autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .image) == true,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { return nil }
                return DiskImage(id: "disk:" + UUID().uuidString, relativePath: String(file.path.dropFirst(prefix.count)),
                                 modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                                 byteSize: Int64(values.fileSize ?? 0), width: width, height: height)
            }
            if let image { images.append(image) }
        }
        if let enumerationError { throw enumerationError }
        try Task.checkCancellation()
        return images
    }

    static func thumbnail(directory: DiskDirectory, image: DiskImage, maximumSize: Int) throws -> CGImage {
        try Task.checkCancellation()
        let root = try resolvedDirectory(directory).url
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let file = root.appendingPathComponent(image.relativePath).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.resolvingSymlinksInPath().path.hasPrefix(prefix) else {
            throw DiskLibraryError.message("图片路径超出已授权目录。")
        }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard Int64(values.fileSize ?? 0) == image.byteSize,
              values.contentModificationDate?.timeIntervalSince1970 == image.modificationTime else {
            throw DiskLibraryError.message("图片已修改，请先刷新目录。")
        }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumSize
              ] as CFDictionary) else { throw DiskLibraryError.message("图片无法读取，请刷新目录或重新授权。") }
        return thumbnail
    }

    static func originalData(directory: DiskDirectory, image: DiskImage) throws -> (data: Data, uti: String?, orientation: CGImagePropertyOrientation) {
        try Task.checkCancellation()
        let root = try resolvedDirectory(directory).url
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let file = root.appendingPathComponent(image.relativePath).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.resolvingSymlinksInPath().path.hasPrefix(prefix) else {
            throw DiskLibraryError.message("图片路径超出已授权目录。")
        }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard Int64(values.fileSize ?? 0) == image.byteSize,
              values.contentModificationDate?.timeIntervalSince1970 == image.modificationTime else {
            throw DiskLibraryError.message("图片已修改，请先刷新目录。")
        }
        let data = try Data(contentsOf: file)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw DiskLibraryError.message("图片无法读取，请刷新目录或重新授权。")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        try Task.checkCancellation()
        return (data, CGImageSourceGetType(source).map { $0 as String }, orientation)
    }
}

@MainActor
final class DiskLibraryStore: ObservableObject {
    @Published private(set) var directories: [DiskDirectory] = []
    @Published private(set) var scanningIDs: Set<String> = []
    @Published private(set) var revision = 0
    @Published var errorMessage: String?
    private var isAdding = false

    func reload() async {
        do {
            directories = try await PhotoMetadataCache.shared.diskLibraryOperation { try $0.directories() }
            revision += 1
        }
        catch { errorMessage = error.localizedDescription }
    }

    func addDirectory() async -> String? {
        guard !isAdding else { return nil }
        isAdding = true
        defer { isAdding = false }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = AppLocalization.localizedString("选择图片目录，将递归扫描其中的图片（不会复制或修改原图）。", comment: "")
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        let url = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        do {
            await reload()
            let existing = directories.first { $0.path == url.path }
            let id = existing?.id ?? "directory:" + UUID().uuidString
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            try await PhotoMetadataCache.shared.diskLibraryOperation { try $0.saveDirectory(id: id, url: url, bookmark: bookmark) }
            await reload()
            if let directory = directories.first(where: { $0.id == id }) { await scan(directory) }
            return id
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func scan(_ directory: DiskDirectory) async {
        guard scanningIDs.insert(directory.id).inserted else { return }
        defer { scanningIDs.remove(directory.id) }
        let databaseURL = PhotoMetadataCache.shared.databaseURL
        do {
            let resolved = try DiskImageLoader.resolvedDirectory(directory)
            if resolved.stale || resolved.url.path != directory.path {
                let accessed = resolved.url.startAccessingSecurityScopedResource()
                defer { if accessed { resolved.url.stopAccessingSecurityScopedResource() } }
                let bookmark = try resolved.url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                             includingResourceValuesForKeys: nil, relativeTo: nil)
                try await PhotoMetadataCache.shared.diskLibraryOperation(expectedURL: databaseURL) {
                    try $0.saveDirectory(id: directory.id, url: resolved.url, bookmark: bookmark)
                }
            }
            let worker = Task.detached(priority: .utility) { try DiskImageLoader.scan(root: resolved.url) }
            let images = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            try await PhotoMetadataCache.shared.diskLibraryOperation(expectedURL: databaseURL) {
                try $0.replaceImages(directoryID: directory.id, images: images)
            }
            revision += 1
            await reload()
        } catch is CancellationError { }
        catch {
            errorMessage = String.localizedStringWithFormat(
                AppLocalization.localizedString("目录 %@ 扫描失败：%@\n旧索引已保留。可重新添加同一目录以恢复授权。", comment: ""),
                directory.title, error.localizedDescription
            )
        }
    }

    func remove(_ directory: DiskDirectory) async {
        guard !scanningIDs.contains(directory.id) else { return }
        do {
            try await PhotoMetadataCache.shared.diskLibraryOperation { try $0.removeDirectory(id: directory.id) }
            revision += 1
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
}

import AppKit
import ImageIO
import Photos
import SQLite3
import Testing
import UniformTypeIdentifiers
@testable import HomeBuddy

@MainActor
struct DiskLibraryTests {
    private func withDatabase(_ body: (DiskLibraryDatabase) throws -> Void) throws {
        var pointer: OpaquePointer?
        #expect(sqlite3_open(":memory:", &pointer) == SQLITE_OK)
        let database = try #require(pointer)
        defer { sqlite3_close(database) }
        let index = DiskLibraryDatabase(database: database)
        try index.execute("PRAGMA foreign_keys = ON;")
        try body(index)
    }

    private func image(id: String = "disk:one", path: String = "nested/photo.png", time: Double = 1) -> DiskImage {
        DiskImage(id: id, relativePath: path, modificationTime: time, byteSize: 123, width: 20, height: 10)
    }

    @Test func migrationPreservesExistingPhotosAndIsIdempotent() throws {
        try withDatabase { index in
            try index.execute("CREATE TABLE photo_metadata(asset_id TEXT PRIMARY KEY, ollama_text TEXT); INSERT INTO photo_metadata VALUES ('photos-original-id', 'cached description');")
            try index.migrate()
            try index.migrate()
            var query: OpaquePointer?
            #expect(sqlite3_prepare_v2(index.database, "SELECT asset_id, ollama_text FROM photo_metadata;", -1, &query, nil) == SQLITE_OK)
            defer { sqlite3_finalize(query) }
            #expect(sqlite3_step(query) == SQLITE_ROW)
            #expect(String(cString: try #require(sqlite3_column_text(query, 0))) == "photos-original-id")
            #expect(String(cString: try #require(sqlite3_column_text(query, 1))) == "cached description")
            #expect(try index.directories().isEmpty)
        }
    }

    @Test func rescanningPreservesIDsUpdatesRevisionAndPrunesMissingImages() throws {
        try withDatabase { index in
            try index.migrate()
            let bookmark = Data([1, 2, 3])
            try index.saveDirectory(id: "directory:one", url: URL(fileURLWithPath: "/tmp/photos", isDirectory: true), bookmark: bookmark)
            try index.replaceImages(directoryID: "directory:one", images: [image(), image(id: "disk:two", path: "other.png")])
            #expect(try index.directories().first?.imageCount == 2)
            try index.replaceImages(directoryID: "directory:one", images: [image(id: "disk:new-scan-id", time: 2)])
            let images = try index.images(directoryID: "directory:one")
            #expect(images.count == 1)
            #expect(images.first?.id == "disk:one")
            #expect(images.first?.modificationTime == 2)
            let directory = try #require(index.directories().first)
            #expect(directory.bookmark == bookmark)
            #expect(directory.lastScan != nil)
            try index.replaceImages(directoryID: directory.id, images: [])
            #expect(try index.images(directoryID: directory.id).isEmpty)
        }
    }

    @Test func failedIndexTransactionPreservesPreviousSnapshot() throws {
        try withDatabase { index in
            try index.migrate()
            try index.saveDirectory(id: "directory:one", url: URL(fileURLWithPath: "/tmp/photos", isDirectory: true), bookmark: Data([1]))
            try index.replaceImages(directoryID: "directory:one", images: [image()])
            let originalDirectory = try index.directories()
            #expect(throws: (any Error).self) {
                try index.replaceImages(directoryID: "directory:one", images: [
                    image(id: "disk:collision", path: "first.png"), image(id: "disk:collision", path: "second.png")
                ])
            }
            #expect(try index.images(directoryID: "directory:one") == [image()])
            #expect(try index.directories() == originalDirectory)
        }
    }

    @Test func removingDirectoryOnlyRemovesItsIndex() throws {
        try withDatabase { index in
            try index.migrate()
            try index.saveDirectory(id: "directory:one", url: URL(fileURLWithPath: "/tmp/photos", isDirectory: true), bookmark: Data([1]))
            try index.saveDirectory(id: "directory:two", url: URL(fileURLWithPath: "/tmp/other", isDirectory: true), bookmark: Data([2]))
            try index.replaceImages(directoryID: "directory:one", images: [image()])
            try index.replaceImages(directoryID: "directory:two", images: [image(id: "disk:two")])
            try index.removeDirectory(id: "directory:one")
            #expect(try index.images(directoryID: "directory:one").isEmpty)
            #expect(try index.images(directoryID: "directory:two").count == 1)
            #expect(try index.directories().map(\.id) == ["directory:two"])
        }
    }

    @Test func migrationFailureRollsBackNewTables() throws {
        try withDatabase { index in
            try index.execute("CREATE TABLE disk_images(incompatible_column TEXT);")
            #expect(throws: (any Error).self) { try index.migrate() }
            var query: OpaquePointer?
            #expect(sqlite3_prepare_v2(index.database, "SELECT COUNT(*) FROM sqlite_master WHERE name = 'disk_directories';", -1, &query, nil) == SQLITE_OK)
            defer { sqlite3_finalize(query) }
            #expect(sqlite3_step(query) == SQLITE_ROW)
            #expect(sqlite3_column_int(query, 0) == 0)
        }
    }

    @Test func bookmarkRestoresThumbnailAndRejectsPathTraversal() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("photo.png"))
        let bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
        let directory = DiskDirectory(id: "directory:test", title: "Test", path: root.path,
                                      bookmark: bookmark, lastScan: nil, imageCount: 1)
        #expect(try DiskImageLoader.resolvedDirectory(directory).url.standardizedFileURL == root.standardizedFileURL)
        let scanned = try #require(DiskImageLoader.scan(root: root).first)
        let thumbnail = try DiskImageLoader.thumbnail(directory: directory, image: scanned, maximumSize: 10)
        #expect(thumbnail.width == 10)
        #expect(thumbnail.height == 5)
        #expect(throws: (any Error).self) {
            try DiskImageLoader.thumbnail(directory: directory, image: image(path: "../outside.png"), maximumSize: 10)
        }
    }

    @Test func diskSourceLoadsOriginalDataAndSharedViewerImages() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: root.appendingPathComponent("photo.png"))
        let bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                             includingResourceValuesForKeys: nil, relativeTo: nil)
        let directory = DiskDirectory(id: "directory:fixture", title: "Fixture", path: root.path, bookmark: bookmark, lastScan: nil, imageCount: 1)
        let scanned = try #require(DiskImageLoader.scan(root: root).first)
        let asset = LibraryAsset(directory: directory, image: scanned)
        #expect(asset.localIdentifier == scanned.id)
        #expect(asset.pixelWidth == 20 && asset.pixelHeight == 10)
        #expect(asset.relativePath == "photo.png")
        #expect(asset.diskByteSize == Int64(png.count))
        #expect(!asset.isLivePhoto)

        let original = try DiskImageLoader.originalData(directory: directory, image: scanned)
        #expect(original.data == png)
        #expect(original.orientation == .up)
        #expect(original.uti == UTType.png.identifier)
        let parsed = PhotoMetadata(asset: asset, data: original.data, uti: original.uti)
        #expect(parsed.pixelSize == "20 × 10")
        #expect(parsed.metadataUpdatedAt != nil)

        let loaded: NSImage? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            LibraryImageManager.shared.requestImage(for: asset, targetSize: CGSize(width: 10, height: 10), contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        #expect(loaded?.size == NSSize(width: 10, height: 5))
        let adapted: Data? = await withCheckedContinuation { continuation in
            LibraryImageManager.shared.requestImageDataAndOrientation(for: asset, options: PHImageRequestOptions()) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        #expect(adapted == png)
        let details = try PhotoExporter.fileDetails(for: asset)
        #expect(details.filename == "photo.png")
        #expect(details.type == .png)
        let exported = root.appendingPathComponent("exported.png")
        try await PhotoExporter.export(asset, to: exported)
        #expect(try Data(contentsOf: exported) == png)
        try Data("previous destination".utf8).write(to: exported)
        try await PhotoExporter.export(asset, to: exported)
        #expect(try Data(contentsOf: exported) == png)
        let source = root.appendingPathComponent("photo.png")
        await #expect(throws: (any Error).self) {
            try await PhotoExporter.export(asset, to: source)
        }
        let alias = root.appendingPathComponent("alias.png")
        try manager.linkItem(at: source, to: alias)
        await #expect(throws: (any Error).self) {
            try await PhotoExporter.export(asset, to: alias)
        }
        #expect(try Data(contentsOf: source) == png)
        #expect(throws: (any Error).self) {
            try DiskImageLoader.originalData(directory: directory, image: image(path: "../outside.png"))
        }
        try Data("changed".utf8).write(to: root.appendingPathComponent("photo.png"))
        await #expect(throws: (any Error).self) {
            try await PhotoExporter.export(asset, to: exported)
        }
        #expect(try Data(contentsOf: exported) == png)
        #expect(throws: (any Error).self) { try DiskImageLoader.originalData(directory: directory, image: scanned) }
        #expect(throws: (any Error).self) { try DiskImageLoader.thumbnail(directory: directory, image: scanned, maximumSize: 10) }
    }

    @Test func originalDataPreservesOrientationAndExifForRecognition() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let file = root.appendingPathComponent("rotated.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(bitmap.cgImage), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:07 12:00:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Fixture Camera"]
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let bookmark = try root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        let directory = DiskDirectory(id: "directory:orientation", title: "Orientation", path: root.path, bookmark: bookmark, lastScan: nil, imageCount: 1)
        let scanned = try #require(DiskImageLoader.scan(root: root).first)
        let original = try DiskImageLoader.originalData(directory: directory, image: scanned)
        #expect(original.orientation == .right)
        let metadata = PhotoMetadata(asset: LibraryAsset(directory: directory, image: scanned), data: original.data, uti: original.uti)
        #expect(metadata.creationDate == "2026:10:07 12:00:00")
        #expect(metadata.camera == "Fixture Camera")
        let thumbnail = try DiskImageLoader.thumbnail(directory: directory, image: scanned, maximumSize: 20)
        #expect(thumbnail.width == 10 && thumbnail.height == 20)
    }

    @Test func rescanningInvalidatesRecognitionOnSizeChangeAndRemoval() throws {
        try withDatabase { index in
            try index.migrate()
            try index.execute("CREATE TABLE photo_metadata(asset_id TEXT PRIMARY KEY, ollama_text TEXT); CREATE TABLE face_detection_results(id INTEGER PRIMARY KEY, asset_id TEXT); CREATE TABLE detected_faces(result_id INTEGER REFERENCES face_detection_results(id) ON DELETE CASCADE);")
            try index.saveDirectory(id: "directory:one", url: URL(fileURLWithPath: "/tmp/photos"), bookmark: Data([1]))
            try index.replaceImages(directoryID: "directory:one", images: [image()])
            func seedCache() throws {
                try index.execute("INSERT INTO photo_metadata VALUES ('disk:one', 'cached'); INSERT INTO face_detection_results VALUES (1, 'disk:one'); INSERT INTO detected_faces VALUES (1);")
            }
            func count(_ table: String) throws -> Int {
                var query: OpaquePointer?
                #expect(sqlite3_prepare_v2(index.database, "SELECT COUNT(*) FROM \(table);", -1, &query, nil) == SQLITE_OK)
                defer { sqlite3_finalize(query) }
                #expect(sqlite3_step(query) == SQLITE_ROW)
                return Int(sqlite3_column_int(query, 0))
            }
            try seedCache()
            try index.replaceImages(directoryID: "directory:one", images: [image(id: "disk:rescan")])
            #expect(try count("photo_metadata") == 1)
            let changed = DiskImage(id: "disk:changed", relativePath: "nested/photo.png", modificationTime: 1, byteSize: 456, width: 20, height: 10)
            try index.replaceImages(directoryID: "directory:one", images: [changed])
            #expect(try count("photo_metadata") == 0)
            #expect(try count("face_detection_results") == 0)
            #expect(try count("detected_faces") == 0)
            #expect(try index.images(directoryID: "directory:one").first?.id == "disk:one")
            try seedCache()
            try index.replaceImages(directoryID: "directory:one", images: [])
            #expect(try count("photo_metadata") == 0)
            #expect(try count("face_detection_results") == 0)
            try index.replaceImages(directoryID: "directory:one", images: [image()])
            try seedCache()
            try index.removeDirectory(id: "directory:one")
            #expect(try count("photo_metadata") == 0)
            #expect(try count("detected_faces") == 0)
        }
    }

    private func unavailableAsset(size: Int64 = 123) -> LibraryAsset {
        let directory = DiskDirectory(id: "directory:unavailable-test", title: "Unavailable", path: "/unavailable-test", bookmark: Data(), lastScan: nil, imageCount: 1)
        let image = DiskImage(id: "disk:unavailable-test", relativePath: "missing.png", modificationTime: 1, byteSize: size, width: 20, height: 10)
        return LibraryAsset(directory: directory, image: image)
    }

    @Test func missingDiskSnapshotRejectsCacheWrites() async {
        let asset = unavailableAsset()
        #expect(await PhotoMetadataCache.shared.areCurrent([asset]) == false)
        let saved: Bool = await withCheckedContinuation { continuation in
            PhotoMetadataCache.shared.saveOllamaText("must not persist", model: "fixture", for: asset) { saved in
                continuation.resume(returning: saved)
            }
        }
        #expect(!saved)
        let cached: String? = await withCheckedContinuation { continuation in
            PhotoMetadataCache.shared.ollamaText(for: asset) { text in continuation.resume(returning: text) }
        }
        #expect(cached == nil)
    }

    @Test func batchFailureCanRetryAfterImmediatePauseAndResume() async throws {
        let model = BatchRecognitionModel(assets: [unavailableAsset()])
        model.startOrResume()
        model.pause()
        model.startOrResume()
        for _ in 0..<100 where model.phase == .running { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.phase == .paused)
        #expect(model.completed == 0)
        #expect(model.failures.count == 1)
        model.startOrResume()
        for _ in 0..<100 where model.phase == .running { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.phase == .paused)
        #expect(model.completed == 0)
        #expect(model.failures.count == 1)

        let faces = BatchFaceRecognitionModel(assets: [unavailableAsset()])
        faces.startOrResume()
        faces.pause()
        faces.startOrResume()
        for _ in 0..<100 where faces.phase == .running { try await Task.sleep(for: .milliseconds(20)) }
        #expect(faces.phase == .paused)
        #expect(faces.completed == 0)
        #expect(faces.failures.count == 1)
    }

    @Test func batchModelSnapshotsChangeWithDiskRevision() {
        let asset = unavailableAsset()
        let changed = unavailableAsset(size: 456)
        #expect(asset.revisionID != changed.revisionID)
        let ollama = BatchRecognitionModelStore()
        let original = ollama.model(for: "fixture", assets: [asset])
        #expect(original === ollama.model(for: "fixture", assets: [asset]))
        #expect(original !== ollama.model(for: "fixture", assets: [changed]))
        let faces = BatchFaceRecognitionModelStore()
        let initialFaces = faces.model(for: "fixture", assets: [asset])
        #expect(initialFaces === faces.model(for: "fixture", assets: [asset]))
        #expect(initialFaces !== faces.model(for: "fixture", assets: [changed]))
    }

    @Test func recursiveScanSkipsHiddenPackagesSymlinksAndInvalidImages() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        for path in ["nested/photo.PNG", "root.png", ".hidden/photo.png", "Skip.app/photo.png"] {
            let file = root.appendingPathComponent(path)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: file)
        }
        try Data("not an image".utf8).write(to: root.appendingPathComponent("bad.png"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("linked.png"), withDestinationURL: root.appendingPathComponent("root.png"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let images = try DiskImageLoader.scan(root: root)
        #expect(Set(images.map(\.relativePath)) == ["nested/photo.PNG", "root.png"])
        #expect(images.allSatisfy { $0.width == 20 && $0.height == 10 && $0.byteSize > 0 })
        #expect(images.allSatisfy { $0.id.hasPrefix("disk:") })
        #expect(throws: (any Error).self) { try DiskImageLoader.scan(root: root.appendingPathComponent("missing")) }
    }
}

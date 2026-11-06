//o
//  HomeBuddyTests.swift
//  HomeBuddyTests
//
//  Created by Atman An on 2026/8/26.
//

import AppKit
import Photos
import SQLite3
import Testing
@testable import HomeBuddy

nonisolated private final class PhotoTypeFixture: PHAsset, @unchecked Sendable {
    let fixtureType: PHAssetMediaType
    let fixtureSubtypes: PHAssetMediaSubtype
    let fixtureID: String
    let fixtureModificationDate: Date?

    init(type: PHAssetMediaType, subtypes: PHAssetMediaSubtype, id: String = "fixture", modificationDate: Date? = nil) {
        fixtureType = type
        fixtureSubtypes = subtypes
        fixtureID = id
        fixtureModificationDate = modificationDate
        super.init()
    }

    override var mediaType: PHAssetMediaType { fixtureType }
    override var mediaSubtypes: PHAssetMediaSubtype { fixtureSubtypes }
    override var localIdentifier: String { fixtureID }
    override var modificationDate: Date? { fixtureModificationDate }
}

@MainActor
struct HomeBuddyTests {

    @Test func livePhotoDetectionUsesPhotosMediaSubtype() {
        #expect(LibraryAsset(PhotoTypeFixture(type: .image, subtypes: .photoLive)).isLivePhoto)
        #expect(LibraryAsset(PhotoTypeFixture(type: .image, subtypes: [.photoLive, .photoHDR])).isLivePhoto)
        #expect(!LibraryAsset(PhotoTypeFixture(type: .image, subtypes: [])).isLivePhoto)
        #expect(!LibraryAsset(PhotoTypeFixture(type: .image, subtypes: .photoHDR)).isLivePhoto)
        #expect(!LibraryAsset(PhotoTypeFixture(type: .video, subtypes: .photoLive)).isLivePhoto)
    }

    @Test func videoAssetsAreIdentifiedAndUseVideoAlbum() {
        #expect(LibraryAsset(PhotoTypeFixture(type: .video, subtypes: [])).isVideo)
        #expect(!LibraryAsset(PhotoTypeFixture(type: .image, subtypes: [])).isVideo)
        #expect(PhotoAlbum.videoAlbum.id == "virtual:videos")
        #expect(PhotoAlbum.videoAlbum.isVideoAlbum)
    }

    @Test func hiddenMediaRequiresPasswordAndRemainsHiddenAfterRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("hidden.json")
        let photo = LibraryAsset(PhotoTypeFixture(type: .image, subtypes: [], id: "photo-1"))
        let video = LibraryAsset(PhotoTypeFixture(type: .video, subtypes: [], id: "video-1"))
        var storedPassword: Data?
        var input = "correct-password"
        var errors: [String] = []
        func makeStore() -> HiddenMediaStore {
            HiddenMediaStore(fileURL: file, passwordReader: { storedPassword },
                             passwordWriter: { storedPassword = $0 }, prompt: { _ in input },
                             errorPresenter: { errors.append($0) })
        }
        let store = makeStore()
        #expect(store.isHiding)
        store.toggleHidden(photo)
        store.toggleHidden(video)
        #expect(store.visibleAssets([photo, video]).isEmpty)
        #expect(storedPassword == Data("correct-password".utf8))

        input = "incorrect-password"
        store.setHiding(false)
        #expect(store.isHiding)
        #expect(!errors.isEmpty)
        input = "correct-password"
        store.setHiding(false)
        #expect(!store.isHiding)
        #expect(store.visibleAssets([photo, video]).count == 2)
        store.toggleHidden(photo)
        store.setHiding(true)
        #expect(store.visibleAssets([photo, video]).map(\.localIdentifier) == [photo.localIdentifier])

        let restarted = makeStore()
        #expect(restarted.isHiding)
        #expect(restarted.isVisible(photo))
        #expect(!restarted.isVisible(video))
        storedPassword = nil
        restarted.setHiding(false)
        restarted.toggleHidden(photo)
        #expect(restarted.isHiding)
        #expect(storedPassword == nil)
        #expect(!restarted.isVisible(video))
    }

    @Test func hiddenMediaUsesStableDiskPathsAndFailsClosedOnCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = DiskDirectory(id: "root", title: "root", path: directory.path, bookmark: Data(), lastScan: nil, imageCount: 1)
        let child = DiskDirectory(id: "child", title: "child", path: directory.appendingPathComponent("sub").path,
                                  bookmark: Data(), lastScan: nil, imageCount: 1)
        let first = DiskImage(id: "disk:first", relativePath: "sub/a.jpg", modificationTime: 1, byteSize: 1, width: 10, height: 10)
        let second = DiskImage(id: "disk:second", relativePath: "a.jpg", modificationTime: 2, byteSize: 2, width: 20, height: 20)
        let firstAsset = LibraryAsset(directory: root, image: first)
        let secondAsset = LibraryAsset(directory: child, image: second)
        #expect(HiddenMediaStore.identity(for: firstAsset) == HiddenMediaStore.identity(for: secondAsset))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("hidden.json")
        try Data("invalid".utf8).write(to: file)
        let store = HiddenMediaStore(fileURL: file, errorPresenter: { _ in })
        #expect(store.isHiding)
        #expect(!store.isVisible(firstAsset))
        #expect(store.visibleAssets([firstAsset, secondAsset]).isEmpty)
    }

    @Test func videoDurationFormattingHandlesInvalidAndLongDurations() {
        #expect(VideoMetadata.formattedDuration(0) != nil)
        #expect(VideoMetadata.formattedDuration(90) != nil)
        #expect(VideoMetadata.formattedDuration(3601) != nil)
        #expect(VideoMetadata.formattedDuration(-1) == nil)
        #expect(VideoMetadata.formattedDuration(.infinity) == nil)
        #expect(VideoMetadata.formattedDuration(.nan) == nil)
    }

    @Test func videoMetadataCachePreservesRecognitionAndSeparatesRevisions() throws {
        var pointer: OpaquePointer?
        #expect(sqlite3_open(":memory:", &pointer) == SQLITE_OK)
        let database = try #require(pointer)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, "CREATE TABLE photo_metadata(asset_id TEXT PRIMARY KEY, ollama_text TEXT); INSERT INTO photo_metadata VALUES ('video-id', 'existing result');", nil, nil, nil) == SQLITE_OK)
        let cache = VideoMetadataDatabase(database: database)
        try cache.migrate()
        try cache.migrate()

        let first = VideoMetadataRevision(identifier: "video-id", modificationTime: 1, width: 1920, height: 1080)
        let second = VideoMetadataRevision(identifier: "video-id", modificationTime: 2, width: 1920, height: 1080)
        let resized = VideoMetadataRevision(identifier: "video-id", modificationTime: 1, width: 1080, height: 1920)
        let record = VideoMetadataRecord(filename: "test.mov", typeIdentifier: "com.apple.quicktime-movie",
                                         duration: 123.5, creationTime: 10, latitude: 31.2, longitude: 121.5, updatedAt: 20)
        let newer = VideoMetadataRecord(filename: "new.mov", typeIdentifier: nil, duration: nil,
                                        creationTime: nil, latitude: nil, longitude: nil, updatedAt: 30)
        #expect(cache.read(revision: first) == nil)
        #expect(cache.write(record, revision: first))
        #expect(cache.read(revision: first) == record)
        #expect(cache.read(revision: second) == nil)
        #expect(cache.read(revision: resized) == nil)
        #expect(cache.write(newer, revision: second))
        #expect(cache.write(record, revision: first))
        #expect(cache.read(revision: second) == newer)
        var query: OpaquePointer?
        #expect(sqlite3_prepare_v2(database, "SELECT ollama_text FROM photo_metadata WHERE asset_id = 'video-id';", -1, &query, nil) == SQLITE_OK)
        defer { sqlite3_finalize(query) }
        #expect(sqlite3_step(query) == SQLITE_ROW)
        #expect(String(cString: try #require(sqlite3_column_text(query, 0))) == "existing result")
    }

    @Test func videoCoverPathsAreVersionedAndConfinedToCacheDirectory() throws {
        let id = "../" + UUID().uuidString
        let video = LibraryAsset(PhotoTypeFixture(type: .video, subtypes: [], id: id, modificationDate: Date(timeIntervalSince1970: 1)))
        let changed = LibraryAsset(PhotoTypeFixture(type: .video, subtypes: [], id: id, modificationDate: Date(timeIntervalSince1970: 2)))
        let url = try VideoCoverStore.url(for: video)
        #expect(url.deletingLastPathComponent().lastPathComponent == "video-covers")
        #expect(url.pathExtension == "jpg")
        #expect(url == (try VideoCoverStore.url(for: video)))
        #expect(url != (try VideoCoverStore.url(for: changed)))
        #expect(throws: (any Error).self) { try VideoCoverStore.data(for: video) }
        let photo = LibraryAsset(PhotoTypeFixture(type: .image, subtypes: []))
        #expect(throws: (any Error).self) { try VideoCoverStore.url(for: photo) }
        let oldDatabase = LibraryAsset(PhotoTypeFixture(type: .video, subtypes: []), databaseURL: URL(fileURLWithPath: "/tmp/old-cache.sqlite"))
        #expect(throws: (any Error).self) { try VideoCoverStore.url(for: oldDatabase) }
    }

    @Test func videoCoverThumbnailScalesAndRejectsUnreadableFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(VideoCoverStore.thumbnail(at: url, maximumSize: 500) == nil)
        try Data("not an image".utf8).write(to: url)
        #expect(VideoCoverStore.thumbnail(at: url, maximumSize: 500) == nil)

        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let jpeg = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        try jpeg.write(to: url)
        let thumbnail = try #require(VideoCoverStore.thumbnail(at: url, maximumSize: 500))
        #expect(thumbnail.width == 500)
        #expect(thumbnail.height == 200)
        #expect(VideoCoverStore.thumbnail(at: url, maximumSize: 0) == nil)
    }

    @Test func videoCoverCountsAndProgressUseValidCurrentCovers() async throws {
        let id = UUID().uuidString
        let cached = LibraryAsset(PhotoTypeFixture(type: .video, subtypes: [], id: id + "-cached"))
        let missing = LibraryAsset(PhotoTypeFixture(type: .video, subtypes: [], id: id + "-missing"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id, isDirectory: true)
        let cachedURL = directory.appendingPathComponent("cached.jpg")
        let missingURL = directory.appendingPathComponent("missing.jpg")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let jpeg = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        try jpeg.write(to: cachedURL)
        try Data("invalid".utf8).write(to: missingURL)

        let paths = [(cached.localIdentifier, cachedURL), (missing.localIdentifier, missingURL)]
        let existing = await VideoCoverStore.existingCoverIDs(at: paths)
        #expect(existing == [cached.localIdentifier])
        let model = BatchVideoCoverModel(assets: [cached, missing], existingCovers: { _ in
            await VideoCoverStore.existingCoverIDs(at: paths)
        }, extractCover: { _ in
            throw DiskLibraryError.message("fixture failure")
        })
        model.startOrResume()
        for _ in 0..<200 where model.phase == .running {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.phase == .paused)
        #expect(model.completed == 1)
        #expect(model.remainingCount == 1)
        #expect(model.progress == 0.5)
        #expect(model.failures.count == 1)

        try jpeg.write(to: missingURL)
        model.startOrResume()
        for _ in 0..<200 where model.phase == .running {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.phase == .finished)
        #expect(model.completed == 2)
        #expect(model.remainingCount == 0)
        #expect(model.failures.isEmpty)

        try FileManager.default.removeItem(at: cachedURL)
        model.startOrResume()
        for _ in 0..<200 where model.phase == .running {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.phase == .paused)
        #expect(model.completed == 1)
        #expect(model.remainingCount == 1)
    }

    @Test func emptyVideoCoverTaskFinishes() async throws {
        let model = BatchVideoCoverModel(assets: [])
        model.startOrResume()
        model.pause()
        #expect(model.phase == .paused)
        model.startOrResume()
        for _ in 0..<200 where model.phase == .running {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.phase == .finished)
        #expect(model.progress == 1)
        #expect(model.remainingCount == 0)
    }

    @Test func faceOverlayFitsCoverAndFlipsVisionCoordinates() {
        let portrait = FaceOverlayGeometry.imageRect(
            imageSize: CGSize(width: 600, height: 900),
            viewportSize: CGSize(width: 260, height: 390), padding: 0
        )
        #expect(portrait == CGRect(x: 0, y: 0, width: 260, height: 390))
        let face = FaceOverlayGeometry.faceRect(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), in: portrait)
        #expect(face == CGRect(x: 65, y: 97.5, width: 130, height: 97.5))

        let landscape = FaceOverlayGeometry.imageRect(
            imageSize: CGSize(width: 400, height: 200),
            viewportSize: CGSize(width: 300, height: 300), padding: 0
        )
        #expect(landscape == CGRect(x: 0, y: 75, width: 300, height: 150))
        let upperLeft = FaceOverlayGeometry.faceRect(CGRect(x: 0, y: 0.8, width: 0.2, height: 0.2), in: landscape)
        #expect(upperLeft == CGRect(x: 0, y: 75, width: 60, height: 30))
    }

    @Test func faceOverlayKeepsPhotoViewerPadding() {
        let rect = FaceOverlayGeometry.imageRect(
            imageSize: CGSize(width: 400, height: 200),
            viewportSize: CGSize(width: 400, height: 300), padding: 24
        )
        #expect(rect == CGRect(x: 24, y: 62, width: 352, height: 176))
        #expect(FaceOverlayGeometry.imageRect(imageSize: .zero, viewportSize: CGSize(width: 300, height: 300), padding: 0) == .zero)
    }

    @Test func horizontalSwipeNavigatesOnceWithoutMomentum() {
        var state = PhotoViewerScrollState()
        #expect(state.handle(delta: CGSize(width: 20, height: 1), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 25, height: 1), phase: .changed,
                             momentumPhase: [], isZoomed: false) == .navigate(45))
        #expect(state.handle(delta: CGSize(width: 80, height: 0), phase: .changed,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: .zero, phase: .ended,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 80, height: 0), phase: [],
                             momentumPhase: .began, isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: -45, height: 0), phase: .began,
                             momentumPhase: [], isZoomed: false) == .navigate(-45))
    }

    @Test func verticalSwipeAndSmallSwipeDoNotNavigate() {
        var state = PhotoViewerScrollState()
        #expect(state.handle(delta: CGSize(width: 45, height: 90), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 10, height: 0), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: .zero, phase: .ended,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 80, height: 0), phase: [],
                             momentumPhase: .changed, isZoomed: false) == .none)
    }

    @Test func zoomedSwipePansBothAxesIncludingMomentum() {
        var state = PhotoViewerScrollState()
        let delta = CGSize(width: 60, height: -80)
        #expect(state.handle(delta: delta, phase: .began,
                             momentumPhase: [], isZoomed: true) == .pan(delta))
        let reverse = CGSize(width: -20, height: 30)
        #expect(state.handle(delta: reverse, phase: .changed,
                             momentumPhase: [], isZoomed: true) == .pan(reverse))
        #expect(state.handle(delta: delta, phase: [],
                             momentumPhase: .changed, isZoomed: true) == .pan(delta))
    }

    @Test func zoomResetDuringPanDoesNotSwitchPhotos() {
        var state = PhotoViewerScrollState()
        let delta = CGSize(width: 60, height: 0)
        #expect(state.handle(delta: delta, phase: .began,
                             momentumPhase: [], isZoomed: true) == .pan(delta))
        #expect(state.handle(delta: delta, phase: .changed,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: delta, phase: [],
                             momentumPhase: .changed, isZoomed: false) == .none)
        #expect(state.handle(delta: delta, phase: .began,
                             momentumPhase: [], isZoomed: false) == .navigate(60))
    }

    @Test func cancelledSwipeDoesNotLeakIntoNextGesture() {
        var state = PhotoViewerScrollState()
        _ = state.handle(delta: CGSize(width: 30, height: 0), phase: .began,
                         momentumPhase: [], isZoomed: false)
        #expect(state.handle(delta: .zero, phase: .cancelled,
                             momentumPhase: [], isZoomed: false) == .none)
        #expect(state.handle(delta: CGSize(width: 20, height: 0), phase: .began,
                             momentumPhase: [], isZoomed: false) == .none)
    }

    @Test func panBoundsFollowZoomAndViewport() {
        let image = CGSize(width: 1000, height: 1000)
        let viewport = CGSize(width: 548, height: 548)
        let offset = CGSize(width: 1000, height: -1000)
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: image,
                    viewportSize: viewport, zoomScale: 2) == CGSize(width: 226, height: -226))
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: image,
                    viewportSize: viewport, zoomScale: 1) == .zero)
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: image,
                    viewportSize: CGSize(width: 348, height: 348), zoomScale: 2)
                == CGSize(width: 126, height: -126))
    }

    @Test func smallerImageAxisStaysCentered() {
        let offset = CGSize(width: 1000, height: -1000)
        let viewport = CGSize(width: 548, height: 548)
        #expect(PhotoViewerGeometry.boundedOffset(offset,
                    imageSize: CGSize(width: 1000, height: 100), viewportSize: viewport,
                    zoomScale: 2) == CGSize(width: 226, height: 0))
        #expect(PhotoViewerGeometry.boundedOffset(offset,
                    imageSize: CGSize(width: 100, height: 1000), viewportSize: viewport,
                    zoomScale: 2) == CGSize(width: 0, height: -226))
        #expect(PhotoViewerGeometry.boundedOffset(offset, imageSize: .zero,
                    viewportSize: viewport, zoomScale: 2) == .zero)
    }

    @Test func chromaConfigurationNormalizesValues() {
        let configuration = ChromaConfiguration(
            baseURL: "  http://127.0.0.1:8000/// ",
            tenant: " ",
            database: "photos",
            collection: " "
        )

        #expect(configuration.normalizedBaseURL == "http://127.0.0.1:8000")
        #expect(configuration.normalizedTenant == ChromaConfiguration.defaultTenant)
        #expect(configuration.normalizedDatabase == "photos")
        #expect(configuration.normalizedCollection == ChromaConfiguration.defaultCollection)
    }

    @Test func chromaConfigurationRejectsInvalidUpsertCounts() async {
        let service = ChromaService()
        let configuration = ChromaConfiguration(
            baseURL: "http://127.0.0.1:8000",
            tenant: "tenant",
            database: "database",
            collection: "faces"
        )

        do {
            try await service.upsert(
                ids: ["one"],
                embeddings: [],
                collectionID: "collection-id",
                configuration: configuration
            )
            #expect(Bool(false), "不匹配的 ids/embeddings 应该在发起网络请求前失败")
        } catch let error as ChromaService.ServiceError {
            #expect(error == .invalidConfiguration("ids 与 embeddings 数量必须一致且不能为空。"))
        } catch {
            #expect(Bool(false), "应返回 ChromaService.ServiceError")
        }
    }

    @Test func faceSuggestionsKeepFiveClosestDistinctPeople() {
        let people = (1...7).map { Person(id: "p\($0)", displayName: "人物\($0)") }
        let matches: [(String, Double, String?, String?)] = [
            ("v1", 0.22, "p2", FaceRecognitionService.modelIdentifier),
            ("v2", 0.10, "p1", FaceRecognitionService.modelIdentifier),
            ("v3", 0.11, "p1", FaceRecognitionService.modelIdentifier),
            ("v4", 0.18, "p3", FaceRecognitionService.modelIdentifier),
            ("v5", 0.19, "p4", FaceRecognitionService.modelIdentifier),
            ("v6", 0.20, "p5", FaceRecognitionService.modelIdentifier),
            ("v7", 0.21, "p6", FaceRecognitionService.modelIdentifier),
            ("v8", 0.01, "p7", "other-model"),
            ("v9", 0.02, "unknown", FaceRecognitionService.modelIdentifier),
            ("v10", 0.36, "p7", FaceRecognitionService.modelIdentifier),
            ("v11", .nan, "p7", FaceRecognitionService.modelIdentifier)
        ]
        let query = ChromaQueryResult(
            ids: [matches.map(\.0)],
            distances: [matches.map(\.1)],
            metadatas: [matches.map { match in
                guard let personID = match.2, let modelID = match.3 else { return nil }
                return ["person_id": personID, "model_id": modelID]
            }]
        )

        let candidates = FaceCandidateRanking.topFive(from: query, people: people)
        #expect(candidates.map(\.personID) == ["p1", "p3", "p4", "p5", "p6"])
        #expect(candidates.first?.similarityPercent == 90)
    }

    @Test func faceSuggestionsDeduplicateNamesAndHandleMissingResults() {
        let people = [Person(id: "a", displayName: " José "), Person(id: "b", displayName: "jose")]
        let query = ChromaQueryResult(
            ids: [["one", "two"]],
            distances: [[0.20, 0.10]],
            metadatas: [[
                ["person_id": "a", "model_id": FaceRecognitionService.modelIdentifier],
                ["person_id": "b", "model_id": FaceRecognitionService.modelIdentifier]
            ]]
        )
        #expect(FaceCandidateRanking.topFive(from: query, people: people).map(\.personID) == ["b"])
        #expect(FaceCandidateRanking.topFive(
            from: ChromaQueryResult(ids: [], distances: [], metadatas: []), people: people
        ).isEmpty)
    }

    @Test func mostLabeledPeopleCountOnlyLatestResultsAndRespondToReassignment() {
        var database: OpaquePointer?
        #expect(sqlite3_open(":memory:", &database) == SQLITE_OK)
        defer { sqlite3_close(database) }

        let fixture = """
            CREATE TABLE people (person_id TEXT, display_name TEXT);
            CREATE TABLE face_detection_results (
                id INTEGER, asset_id TEXT, modification_time REAL,
                detector_version TEXT, detected_at REAL
            );
            CREATE TABLE detected_faces (id INTEGER, result_id INTEGER, person_id TEXT);
            INSERT INTO people VALUES
                ('p1', 'Alice'), ('p2', 'Bob'), ('p3', 'Carol'), ('p4', 'Dana'),
                ('p5', 'Eve'), ('p6', 'Frank'), ('p7', 'Grace'), ('p8', 'Unlabeled');
            INSERT INTO face_detection_results VALUES
                (1, 'asset1', 1, 'vision-face-1', 1),
                (2, 'asset1', 1, 'facedetect-antelopev2-1', 2),
                (3, 'asset2', 1, 'facedetect-antelopev2-1', 2),
                (4, 'asset3', 1, 'facedetect-antelopev2-1', 2),
                (5, 'asset3', 2, 'facedetect-antelopev2-1', 3),
                (6, 'asset4', 1, 'facedetect-antelopev2-1', 2),
                (7, 'asset5', 1, 'facedetect-antelopev2-1', 2),
                (8, 'asset6', 1, 'facedetect-antelopev2-1', 2);
            INSERT INTO detected_faces VALUES
                (1, 2, 'p1'), (2, 2, 'p1'), (3, 2, 'p2'),
                (4, 3, 'p1'), (5, 3, 'p2'), (6, 5, 'p3'),
                (7, 6, 'p4'), (8, 7, 'p5'), (9, 8, 'p6'),
                (10, 1, 'p7'), (11, 4, 'p7'), (12, 5, NULL);
            """
        #expect(sqlite3_exec(database, fixture, nil, nil, nil) == SQLITE_OK)

        func ranked() -> [String] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, PhotoMetadataCache.mostLabeledPeopleSQL,
                                     -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            var people: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = sqlite3_column_text(statement, 0) else { continue }
                people.append("\(String(cString: id)):\(sqlite3_column_int(statement, 2))")
            }
            return people
        }

        #expect(ranked() == ["p1:3", "p2:2", "p3:1", "p4:1", "p5:1"])
        #expect(sqlite3_exec(database, "UPDATE detected_faces SET person_id = 'p2' WHERE id = 1;", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(database, "UPDATE detected_faces SET person_id = NULL WHERE id = 2;", nil, nil, nil) == SQLITE_OK)
        #expect(ranked() == ["p2:3", "p1:1", "p3:1", "p4:1", "p5:1"])
    }

    @Test func personAlbumSummariesSeparateConfirmedAndPotentialPhotos() {
        var database: OpaquePointer?
        #expect(sqlite3_open(":memory:", &database) == SQLITE_OK)
        defer { sqlite3_close(database) }

        let fixture = """
            CREATE TABLE people (person_id TEXT, display_name TEXT);
            CREATE TABLE face_detection_results (
                id INTEGER, asset_id TEXT, modification_time REAL, detector_version TEXT, detected_at REAL
            );
            CREATE TABLE detected_faces (
                result_id INTEGER, face_index INTEGER, person_id TEXT, candidate_person_id TEXT,
                x REAL, y REAL, width REAL, height REAL
            );
            INSERT INTO people VALUES ('p1', 'Alice'), ('p2', 'Bob');
            INSERT INTO face_detection_results VALUES
                (1, 'photo1', 1, 'facedetect-antelopev2-1', 1),
                (2, 'photo2', 1, 'facedetect-antelopev2-1', 2),
                (3, 'photo1', 2, 'facedetect-antelopev2-1', 3);
            INSERT INTO detected_faces VALUES
                (1, 0, 'p1', NULL, 0.1, 0.2, 0.3, 0.4),
                (1, 1, NULL, 'p2', 0.2, 0.3, 0.2, 0.3),
                (2, 0, 'p2', NULL, 0.3, 0.4, 0.2, 0.2),
                (3, 0, NULL, 'p1', 0.1, 0.2, 0.3, 0.4),
                (3, 1, NULL, 'p2', 0.2, 0.3, 0.2, 0.3);
            """
        #expect(sqlite3_exec(database, fixture, nil, nil, nil) == SQLITE_OK)

        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(database, PhotoMetadataCache.personAlbumSummarySQL,
                                   -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        var summaries: [String: (recognized: Int, potential: Int, avatarAsset: String)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0),
                  let avatar = sqlite3_column_text(statement, 4) else { continue }
            summaries[String(cString: id)] = (
                Int(sqlite3_column_int(statement, 2)),
                Int(sqlite3_column_int(statement, 3)),
                String(cString: avatar)
            )
        }

        #expect(summaries["p1"]?.recognized == 0)
        #expect(summaries["p1"]?.potential == 1)
        #expect(summaries["p1"]?.avatarAsset == "photo1")
        #expect(summaries["p2"]?.recognized == 1)
        #expect(summaries["p2"]?.potential == 1)
        #expect(summaries["p2"]?.avatarAsset == "photo2")

        sqlite3_reset(statement)
        let videos = """
            INSERT INTO face_detection_results VALUES
                (4, 'video1', 1, 'facedetect-antelopev2-1', 4),
                (5, 'video2', 1, 'facedetect-antelopev2-1', 5);
            INSERT INTO detected_faces VALUES
                (4, 0, 'p1', NULL, 0.1, 0.2, 0.3, 0.4),
                (5, 0, NULL, 'p1', 0.2, 0.3, 0.2, 0.3),
                (5, 1, NULL, 'p2', 0.2, 0.3, 0.2, 0.3);
            """
        #expect(sqlite3_exec(database, videos, nil, nil, nil) == SQLITE_OK)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        #expect(sqlite3_bind_text(statement, 1, "[\"video1\",\"video2\"]", -1, transient) == SQLITE_OK)
        var videoSummaries: [String: (recognized: Int, potential: Int, avatarAsset: String, assets: Set<String>)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0),
                  let avatar = sqlite3_column_text(statement, 4),
                  let asset = sqlite3_column_text(statement, 9) else { continue }
            let personID = String(cString: id)
            var summary = videoSummaries[personID] ?? (
                Int(sqlite3_column_int(statement, 2)), Int(sqlite3_column_int(statement, 3)),
                String(cString: avatar), []
            )
            summary.assets.insert(String(cString: asset))
            videoSummaries[personID] = summary
        }
        #expect(videoSummaries["p1"]?.recognized == 1)
        #expect(videoSummaries["p1"]?.potential == 1)
        #expect(videoSummaries["p1"]?.avatarAsset == "video1")
        #expect(videoSummaries["p1"]?.assets == Set(["video1", "video2"]))
        #expect(videoSummaries["p2"]?.recognized == 0)
        #expect(videoSummaries["p2"]?.potential == 1)
        #expect(videoSummaries["p2"]?.avatarAsset == "video2")
        sqlite3_reset(statement)
        #expect(sqlite3_bind_text(statement, 1, "[]", -1, transient) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_DONE)
    }

}

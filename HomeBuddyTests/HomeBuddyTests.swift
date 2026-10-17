//
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

    init(type: PHAssetMediaType, subtypes: PHAssetMediaSubtype) {
        fixtureType = type
        fixtureSubtypes = subtypes
        super.init()
    }

    override var mediaType: PHAssetMediaType { fixtureType }
    override var mediaSubtypes: PHAssetMediaSubtype { fixtureSubtypes }
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

}

//
//  PhotoLibraryStore.swift
//  HomeBuddy
//

import Photos
import Combine
import SwiftUI

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

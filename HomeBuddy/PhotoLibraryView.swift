//
//  PhotoLibraryView.swift
//  HomeBuddy
//

import AppKit
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

struct PhotoLibraryView: View {
    let album: PhotoAlbum
    let assets: [PHAsset]
    @State private var selectedIndex: Int?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)
    ]

    var body: some View {
        Group {
            if let selectedIndex {
                PhotoViewerView(
                    assets: assets,
                    initialIndex: selectedIndex,
                    onBack: { self.selectedIndex = nil }
                )
            } else if assets.isEmpty {
                ContentUnavailableView(
                    "“\(album.title)”中还没有照片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("这个相册中暂时没有可显示的图片。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            Button {
                                selectedIndex = index
                            } label: {
                                PhotoThumbnailView(asset: asset)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .accessibilityLabel("查看照片")
                            .help("点击查看大图")
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(album.title)
        .frame(minWidth: 420, minHeight: 300)
    }
}

private struct PhotoThumbnailView: View {
    let asset: PHAsset
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 140, maxWidth: .infinity, minHeight: 140, maxHeight: 220)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: asset.localIdentifier) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            let targetSize = CGSize(width: 500, height: 500)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { nsImage, _ in
                guard let nsImage else { return }
                Task { @MainActor in
                    image = Image(nsImage: nsImage)
                }
            }
        }
    }
}

private struct PhotoViewerView: View {
    let assets: [PHAsset]
    let initialIndex: Int
    let onBack: () -> Void

    @State private var currentIndex: Int
    @State private var image: NSImage?
    @State private var metadata: PhotoMetadata?
    @State private var isShowingInfo = false

    init(assets: [PHAsset], initialIndex: Int, onBack: @escaping () -> Void) {
        self.assets = assets
        self.initialIndex = initialIndex
        self.onBack = onBack
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentAsset: PHAsset {
        assets[currentIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("返回相册", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Text("照片 \(currentIndex + 1) / \(assets.count)")
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    isShowingInfo.toggle()
                } label: {
                    Label("照片信息", systemImage: "info.circle")
                }
                .help("显示或隐藏照片信息")
            }
            .padding()

            HStack(spacing: 0) {
                ZStack {
                    Color.black

                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(24)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isShowingInfo {
                    PhotoInfoSidebar(asset: currentAsset, metadata: metadata)
                        .frame(width: 300)
                }
            }

            HStack(spacing: 20) {
                Button {
                    showPrevious()
                } label: {
                    Label("上一张", systemImage: "chevron.left")
                }
                .disabled(currentIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button {
                    showNext()
                } label: {
                    Label("下一张", systemImage: "chevron.right")
                }
                .disabled(currentIndex == assets.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .task(id: currentAsset.localIdentifier) {
            loadCurrentImage()
            loadMetadata()
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: showPrevious()
            case .right: showNext()
            default: break
            }
        }
        .onExitCommand(perform: onBack)
    }

    private func showPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func showNext() {
        guard currentIndex + 1 < assets.count else { return }
        currentIndex += 1
    }

    private func loadCurrentImage() {
        image = nil

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImage(
            for: currentAsset,
            targetSize: CGSize(width: 2400, height: 2400),
            contentMode: .aspectFit,
            options: options
        ) { nsImage, _ in
            guard let nsImage else { return }
            Task { @MainActor in
                image = nsImage
            }
        }
    }

    private func loadMetadata() {
        let asset = currentAsset
        let assetID = asset.localIdentifier
        metadata = nil

        PhotoMetadataCache.shared.metadata(for: asset) { cachedMetadata in
            guard currentAsset.localIdentifier == assetID else { return }
            if let cachedMetadata {
                metadata = cachedMetadata
            } else {
                loadMetadataFromPhotos(asset: asset, assetID: assetID)
            }
        }
    }

    private func loadMetadataFromPhotos(asset: PHAsset, assetID: String) {

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { data, uti, _, _ in
            guard let data else { return }
            let parsedMetadata = PhotoMetadata(asset: asset, data: data, uti: uti)
            PhotoMetadataCache.shared.save(parsedMetadata, for: asset)
            Task { @MainActor in
                guard currentAsset.localIdentifier == assetID else { return }
                metadata = parsedMetadata
            }
        }
    }
}

struct PhotoMetadata {
    let fileType: String?
    let fileSize: String
    let pixelSize: String
    let creationDate: String
    let camera: String?
    let lens: String?
    let exposure: String?
    let iso: String?
    let focalLength: String?
    let location: String?

    init(
        fileType: String?, fileSize: String, pixelSize: String, creationDate: String,
        camera: String?, lens: String?, exposure: String?, iso: String?,
        focalLength: String?, location: String?
    ) {
        self.fileType = fileType
        self.fileSize = fileSize
        self.pixelSize = pixelSize
        self.creationDate = creationDate
        self.camera = camera
        self.lens = lens
        self.exposure = exposure
        self.iso = iso
        self.focalLength = focalLength
        self.location = location
    }

    init(asset: PHAsset, data: Data, uti: String?) {
        fileType = uti.flatMap { UTType($0)?.localizedDescription } ?? uti
        fileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        pixelSize = "\(asset.pixelWidth) × \(asset.pixelHeight)"
        creationDate = asset.creationDate.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "未知"

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            camera = nil
            lens = nil
            exposure = nil
            iso = nil
            focalLength = nil
            location = nil
            return
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]

        let make = tiff?[kCGImagePropertyTIFFMake as String] as? String
        let model = tiff?[kCGImagePropertyTIFFModel as String] as? String
        camera = [make, model].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        lens = exif?[kCGImagePropertyExifLensModel as String] as? String
        exposure = Self.exposureValue(exif?[kCGImagePropertyExifExposureTime as String])
        iso = Self.isoValue(exif?[kCGImagePropertyExifISOSpeedRatings as String])
        focalLength = Self.focalLengthValue(exif?[kCGImagePropertyExifFocalLength as String])
        location = gps == nil ? nil : "包含 GPS 信息"
    }

    private static func exposureValue(_ value: Any?) -> String? {
        guard let value = value as? Double else { return nil }
        return value >= 1 ? String(format: "%.2f 秒", value) : String(format: "1/%.0f 秒", 1 / value)
    }

    private static func isoValue(_ value: Any?) -> String? {
        if let values = value as? [NSNumber], let first = values.first {
            return "ISO \(first.intValue)"
        }
        if let value = value as? NSNumber {
            return "ISO \(value.intValue)"
        }
        return nil
    }

    private static func focalLengthValue(_ value: Any?) -> String? {
        guard let value = value as? Double else { return nil }
        return String(format: "%.0f mm", value)
    }
}

private struct PhotoInfoSidebar: View {
    let asset: PHAsset
    let metadata: PhotoMetadata?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("照片信息")
                    .font(.title3.weight(.semibold))

                if let databaseURL = PhotoMetadataCache.shared.databaseURL {
                    Text("SQLite 缓存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(databaseURL.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                if let metadata {
                    infoSection("基本信息", rows: [
                        ("分辨率", metadata.pixelSize),
                        ("文件类型", metadata.fileType ?? "未知"),
                        ("文件大小", metadata.fileSize),
                        ("拍摄时间", metadata.creationDate),
                        ("状态", asset.isFavorite ? "已收藏" : "未收藏")
                    ])

                    let shootingRows = [
                        ("相机", metadata.camera),
                        ("镜头", metadata.lens),
                        ("曝光时间", metadata.exposure),
                        ("感光度", metadata.iso),
                        ("焦距", metadata.focalLength),
                        ("位置", metadata.location)
                    ].compactMap { row -> (String, String)? in
                        guard let value = row.1 else { return nil }
                        return (row.0, value)
                    }
                    if !shootingRows.isEmpty {
                        infoSection("拍摄信息", rows: shootingRows)
                    }
                } else {
                    ProgressView("正在读取照片信息…")
                }
            }
            .padding(20)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func infoSection(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(row.1)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                Divider()
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

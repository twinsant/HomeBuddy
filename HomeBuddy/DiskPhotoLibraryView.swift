import SwiftUI
import ImageIO

struct DiskPhotoLibraryView: View {
    let directory: DiskDirectory
    let revision: Int
    let isScanning: Bool
    @State private var images: [DiskImage] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if isScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在递归扫描目录…").foregroundStyle(.secondary)
                }
                .padding(8)
            }
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView("无法加载目录", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                PhotoLibraryView(
                    album: PhotoAlbum(id: directory.id, title: directory.title, isAllPhotos: false, isFaceAlbum: false, isRecents: false),
                    assets: images.map { LibraryAsset(directory: directory, image: $0) }
                )
            }
        }
        .task(id: "\(directory.id):\(revision)") {
            isLoading = true
            defer { isLoading = false }
            do {
                let loaded = try await PhotoMetadataCache.shared.diskLibraryOperation { try $0.images(directoryID: directory.id) }
                try Task.checkCancellation()
                images = loaded
                errorMessage = nil
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

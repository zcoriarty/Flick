//
//  ProductView.swift
//  Flick
//

import PhotosUI
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

struct ProductView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var isImportingMedia = false

    var body: some View {
        VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
            ProductMediaSection(
                assets: appModel.productMediaAssets,
                isImporting: isImportingMedia,
                removeAction: appModel.removeProductMedia
            )
        }
        .flickScrollablePage()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Product")
            }
            ToolbarItem(placement: .primaryAction) {
                PhotosPicker(
                    selection: $selectedMediaItems,
                    maxSelectionCount: 12,
                    matching: .any(of: [.images, .videos]),
                    preferredItemEncoding: .current
                ) {
                    Label("Add media", systemImage: "plus")
                }
                .disabled(isImportingMedia)
            }
        }
        .onChange(of: selectedMediaItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            selectedMediaItems = []
            Task {
                await importMediaItems(newItems)
            }
        }
        
    }

    @MainActor
    private func importMediaItems(_ items: [PhotosPickerItem]) async {
        isImportingMedia = true
        defer { isImportingMedia = false }

        for item in items {
            do {
                guard let contentType = item.flickPreferredContentType else {
                    throw ProductMediaImportError.unsupportedType
                }

                if contentType.conforms(to: .movie) {
                    guard let movie = try await item.loadTransferable(type: ProductMovieTransfer.self) else {
                        throw ProductMediaImportError.missingData
                    }
                    try appModel.addProductMedia(fileURL: movie.fileURL, contentType: contentType)
                } else {
                    guard let image = try await item.loadTransferable(type: ProductImageTransfer.self) else {
                        throw ProductMediaImportError.missingData
                    }
                    try appModel.addProductMedia(fileURL: image.fileURL, contentType: contentType)
                }
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct ProductImageTransfer: Transferable {
    var fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { receivedFile in
            let fileExtension = receivedFile.file.pathExtension.isEmpty ? "jpg" : receivedFile.file.pathExtension
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(fileExtension)")

            try FileManager.default.copyItem(at: receivedFile.file, to: copyURL)
            return ProductImageTransfer(fileURL: copyURL)
        }
    }
}

private struct ProductMovieTransfer: Transferable {
    var fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { receivedFile in
            let fileExtension = receivedFile.file.pathExtension.isEmpty ? "mov" : receivedFile.file.pathExtension
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(fileExtension)")

            try FileManager.default.copyItem(at: receivedFile.file, to: copyURL)
            return ProductMovieTransfer(fileURL: copyURL)
        }
    }
}

private struct ProductMediaSection: View {
    var assets: [MediaAsset]
    var isImporting: Bool
    var removeAction: (MediaAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Media library",
                subtitle: "\(assets.count) uploaded asset\(assets.count == 1 ? "" : "s") available for Create",
                systemImage: "photo.stack"
            )

            if isImporting {
                FlickGlassCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Importing media")
                            .font(.callout.weight(.semibold))
                    }
                }
            }

            if assets.isEmpty {
                FlickEmptyStateCard(
                    title: "No uploaded media",
                    message: "Add images or videos here so they can be used from the Create tab later.",
                    systemImage: "photo.badge.plus"
                )
            } else {
                ResponsiveGrid(minimum: 170) {
                    ForEach(assets) { asset in
                        ProductMediaCard(asset: asset) {
                            removeAction(asset)
                        }
                    }
                }
            }
        }
    }
}

private struct ProductMediaCard: View {
    var asset: MediaAsset
    var removeAction: () -> Void

    var body: some View {
        FlickGlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    LocalAssetImage(fileURL: asset.localFileURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    if asset.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .shadow(radius: 8)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: FlickStyle.cardCornerRadius))

                HStack(alignment: .firstTextBaseline) {
                    StatusBadge(
                        title: asset.mediaType.productDisplayName,
                        tint: asset.mediaType.productTint,
                        systemImage: asset.mediaType.productSystemImage
                    )

                    Spacer(minLength: 8)

                    Button(role: .destructive, action: removeAction) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Remove product media")
                }

                Text(asset.productMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private enum ProductMediaImportError: LocalizedError {
    case unsupportedType
    case missingData

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "This item is not an image or video that Flick can import."
        case .missingData:
            "Flick could not load the selected media item."
        }
    }
}

private extension PhotosPickerItem {
    var flickPreferredContentType: UTType? {
        supportedContentTypes.first { $0.conforms(to: .movie) }
            ?? supportedContentTypes.first { $0.conforms(to: .image) }
    }
}

private extension MediaAsset {
    var localFileURL: URL? {
        localFilePath.map { URL(fileURLWithPath: $0) }
    }

    var productMetadata: String {
        let created = createdAt.formatted(date: .abbreviated, time: .omitted)
        guard let fileSize else { return "Added \(created)" }
        return "\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) - added \(created)"
    }
}

private extension AssetMediaType {
    var productDisplayName: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .thumbnail: "Thumbnail"
        }
    }

    var productSystemImage: String {
        switch self {
        case .image, .thumbnail: "photo"
        case .video: "video"
        }
    }

    var productTint: Color {
        switch self {
        case .image: .blue
        case .video: .purple
        case .thumbnail: .secondary
        }
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    ProductView()
        .environment(appModel)
}

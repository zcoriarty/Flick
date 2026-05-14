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
    @State private var selectedMediaAsset: MediaAsset?
    @State private var isImportingMedia = false

    var body: some View {
        VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
            ProductMediaSection(
                assets: appModel.productMediaAssets,
                isImporting: isImportingMedia,
                selectAction: { asset in
                    selectedMediaAsset = asset
                }
            )
        }
        .flickScrollablePage()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Product")
                    .font(.system(.body, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)
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
        .sheet(item: $selectedMediaAsset) { asset in
            ProductMediaDetailSheet(asset: asset)
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
                    try await appModel.addProductMedia(fileURL: movie.fileURL, contentType: contentType)
                } else {
                    guard let image = try await item.loadTransferable(type: ProductImageTransfer.self) else {
                        throw ProductMediaImportError.missingData
                    }
                    try await appModel.addProductMedia(fileURL: image.fileURL, contentType: contentType)
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
    var selectAction: (MediaAsset) -> Void

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
                ResponsiveGrid(minimum: 154, spacing: 12) {
                    ForEach(assets) { asset in
                        ProductMediaCard(asset: asset) {
                            selectAction(asset)
                        }
                    }
                }
            }
        }
    }
}

private struct ProductMediaCard: View {
    var asset: MediaAsset
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VerticalMediaFrame(fileURL: asset.localFileURL, cornerRadius: 0)
                .overlay {
                    if asset.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .clipShape(.rect(cornerRadius: 8))
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(asset.mediaType.productDisplayName) product media")
        .accessibilityHint("Opens media details")
    }
}

private struct ProductMediaDetailSheet: View {
    @Environment(FlickAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var asset: MediaAsset

    var body: some View {
        NavigationStack {
            List {
                mediaSection
                overviewSection
                storageSection
                tagsSection
                timestampsSection
            }
            .flickSettingsListStyle()
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteAsset()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Media Details")
                        .font(.system(.body, weight: .semibold))
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var mediaSection: some View {
        Section {
            ProductMediaDetailPreview(asset: asset)
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .listRowBackground(Color.clear)
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            FlickSettingsValueRow(
                title: "Type",
                systemImage: asset.mediaType.productSystemImage,
                iconColor: asset.mediaType.productTint,
                value: asset.mediaType.productDisplayName
            )
            FlickSettingsValueRow(
                title: "Source",
                systemImage: "tray.and.arrow.down",
                iconColor: .blue,
                value: asset.source.productDisplayName
            )
            FlickSettingsValueRow(
                title: "Dimensions",
                systemImage: "rectangle.expand.vertical",
                iconColor: .teal,
                value: asset.productDimensions
            )
            FlickSettingsValueRow(
                title: "Duration",
                systemImage: "timer",
                iconColor: .orange,
                value: asset.productDuration
            )
            FlickSettingsValueRow(
                title: "File Size",
                systemImage: "doc",
                iconColor: .indigo,
                value: asset.productFileSize
            )
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            FlickSettingsValueRow(
                title: "Local Path",
                systemImage: "folder",
                iconColor: .blue,
                value: asset.localFilePath ?? "Not set",
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Storage Bucket",
                systemImage: "externaldrive",
                iconColor: .purple,
                value: asset.storageBucket ?? "Not set",
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Storage Path",
                systemImage: "point.3.connected.trianglepath.dotted",
                iconColor: .purple,
                value: asset.storagePath ?? "Not set",
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Public URL",
                systemImage: "link",
                iconColor: .green,
                value: asset.publicURL?.absoluteString ?? "Not set",
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Signed URL Expiration",
                systemImage: "calendar.badge.clock",
                iconColor: .orange,
                value: asset.productSignedURLExpiration
            )
            FlickSettingsValueRow(
                title: "Checksum",
                systemImage: "number",
                iconColor: .secondary,
                value: asset.checksum ?? "Not set",
                valueLineLimit: nil
            )
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            FlickSettingsValueRow(
                title: "Trend Tags",
                systemImage: "tag",
                iconColor: .pink,
                value: asset.productTrendTags,
                valueLineLimit: nil
            )
        }
    }

    private var timestampsSection: some View {
        Section("Timestamps") {
            FlickSettingsValueRow(
                title: "Created",
                systemImage: "calendar",
                iconColor: .green,
                value: asset.productCreatedAt
            )
            FlickSettingsValueRow(
                title: "Updated",
                systemImage: "clock.arrow.circlepath",
                iconColor: .teal,
                value: asset.productUpdatedAt
            )
            FlickSettingsValueRow(
                title: "ID",
                systemImage: "number.square",
                iconColor: .secondary,
                value: asset.id.uuidString,
                valueLineLimit: nil
            )
        }
    }

    private func deleteAsset() {
        Task {
            do {
                try await appModel.removeProductMedia(asset)
                dismiss()
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct ProductMediaDetailPreview: View {
    var asset: MediaAsset

    var body: some View {
        VStack(spacing: 12) {
            VerticalMediaFrame(fileURL: asset.localFileURL, cornerRadius: 18, maxPixelSize: 1_920)
                .frame(maxWidth: 360)
                .overlay {
                    if asset.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

    var productDimensions: String {
        guard width > 0, height > 0 else { return "Not set" }
        return "\(width.formatted()) x \(height.formatted())"
    }

    var productDuration: String {
        guard let duration else { return "Not set" }

        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var productFileSize: String {
        guard let fileSize else { return "Not set" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var productSignedURLExpiration: String {
        guard let signedURLExpiration else { return "Not set" }
        return signedURLExpiration.formatted(date: .abbreviated, time: .shortened)
    }

    var productTrendTags: String {
        guard !trendTags.isEmpty else { return "None" }
        return trendTags.map(\.name).joined(separator: ", ")
    }

    var productCreatedAt: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var productUpdatedAt: String {
        updatedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension AssetSource {
    var productDisplayName: String {
        rawValue.capitalized
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

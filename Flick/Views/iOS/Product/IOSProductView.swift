//
//  IOSProductView.swift
//  Flick
//

import PhotosUI
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

#if !os(macOS)
struct IOSProductView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var isProductEditorPresented = false

    var body: some View {
        List {
            ProductListSection(
                products: appModel.overview.products,
                mediaCountsByProductID: mediaCountsByProductID,
                createAction: { isProductEditorPresented = true },
                deleteAction: deleteProduct
            )
        }
        .flickSettingsListStyle()
        .flickToolbarTitle("Products")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Product", systemImage: "plus") {
                    isProductEditorPresented = true
                }
            }
        }
        .sheet(isPresented: $isProductEditorPresented) {
            ProductEditorSheet(
                saveAction: { name, summary in
                    try await appModel.createProduct(name: name, summary: summary)
                },
                completion: { _ in }
            )
        }
    }

    private var mediaCountsByProductID: [UUID: Int] {
        appModel.productMediaAssets.reduce(into: [UUID: Int]()) { result, asset in
            for productID in asset.productIDs {
                result[productID, default: 0] += 1
            }
        }
    }

    private func deleteProduct(_ product: FlickProduct) {
        Task {
            do {
                try await appModel.deleteProduct(id: product.id)
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct ProductMediaDetailSelection: Identifiable {
    var id: UUID
}

private struct ProductListSection: View {
    var products: [FlickProduct]
    var mediaCountsByProductID: [UUID: Int]
    var createAction: () -> Void
    var deleteAction: (FlickProduct) -> Void

    var body: some View {
        Section {
            ForEach(products) { product in
                NavigationLink {
                    ProductDetailView(productID: product.id)
                } label: {
                    FlickSettingsRowLabel(
                        title: product.name,
                        systemImage: "shippingbox",
                        iconColor: .blue,
                        value: mediaCountText(for: product)
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteAction(product)
                    }
                }
            }

            FlickSettingsActionRow(
                title: "New Product",
                systemImage: "plus.circle",
                iconColor: .green,
                value: products.isEmpty ? "Create first" : nil,
                action: createAction
            )
        } header: {
            Text("Products")
        } footer: {
            Text("Create a product, then add media inside that product.")
        }
    }

    private func mediaCountText(for product: FlickProduct) -> String {
        let count = mediaCountsByProductID[product.id, default: 0]
        return "\(count) media"
    }
}

private struct ProductDetailView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var selectedMediaSelection: ProductMediaDetailSelection?
    @State private var pendingImageCropItems: [ProductImageCropItem] = []
    @State private var activeImageCropItem: ProductImageCropItem?
    @State private var isImportingMedia = false

    var productID: UUID

    private var product: FlickProduct? {
        appModel.overview.products.first { $0.id == productID }
    }

    private var mediaAssets: [MediaAsset] {
        appModel.productMediaAssets(for: [productID])
    }

    var body: some View {
        Group {
            if let product {
                productMediaContent(product)
            } else {
                List {
                    Section {
                        ProductMessageRow(
                            title: "Product unavailable",
                            message: "This product may have been removed."
                        )
                    }
                }
                .flickSettingsListStyle()
            }
        }
        .flickToolbarTitle(product?.name ?? "Product")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if product != nil {
                    PhotosPicker(
                        selection: $selectedMediaItems,
                        maxSelectionCount: 12,
                        matching: .any(of: [.images, .videos]),
                        preferredItemEncoding: .current
                    ) {
                        Label("Add Media", systemImage: "plus")
                    }
                    .disabled(isImportingMedia || activeImageCropItem != nil)
                }
            }
        }
        .onChange(of: selectedMediaItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            selectedMediaItems = []

            Task {
                await importMediaItems(newItems)
            }
        }
        .sheet(item: $selectedMediaSelection) { selection in
            ProductMediaDetailSheet(assetID: selection.id)
        }
        .sheet(item: $activeImageCropItem) { item in
            ProductImageCropSheet(
                item: item,
                importAction: { data, contentType in
                    try await appModel.addProductMedia(data: data, contentType: contentType, productIDs: [productID])
                }
            )
        }
        .onChange(of: activeImageCropItem) { _, newItem in
            guard newItem == nil else { return }
            presentNextImageCrop()
        }
    }

    private func productMediaContent(_ product: FlickProduct) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if isImportingMedia {
                    ProductImportingIndicator()
                }

                if mediaAssets.isEmpty {
                    FlickEmptyStateCard(
                        title: "No media yet",
                        message: "Use the toolbar plus button to add images or videos to \(product.name).",
                        systemImage: "photo.badge.plus"
                    )
                } else {
                    ProductMediaGrid(assets: mediaAssets) { asset in
                        selectedMediaSelection = ProductMediaDetailSelection(id: asset.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .flickAppBackground()
        .scrollEdgeEffectStyle(.soft, for: .top)
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
                    try await appModel.addProductMedia(fileURL: movie.fileURL, contentType: contentType, productIDs: [productID])
                } else {
                    guard let image = try await item.loadTransferable(type: ProductImageTransfer.self) else {
                        throw ProductMediaImportError.missingData
                    }
                    enqueueImageCrop(ProductImageCropItem(fileURL: image.fileURL, contentType: contentType))
                }
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func enqueueImageCrop(_ item: ProductImageCropItem) {
        pendingImageCropItems.append(item)
        presentNextImageCrop()
    }

    private func presentNextImageCrop() {
        guard activeImageCropItem == nil, !pendingImageCropItems.isEmpty else { return }
        activeImageCropItem = pendingImageCropItems.removeFirst()
    }
}

private struct ProductImportingIndicator: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Importing media")
                .font(.callout.weight(.semibold))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct ProductMediaGrid: View {
    var assets: [MediaAsset]
    var selectAction: (MediaAsset) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(assets) { asset in
                ProductMediaCard(asset: asset) {
                    selectAction(asset)
                }
            }
        }
    }
}

private struct ProductMessageRow: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.primary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProductSelectionRow: View {
    var product: FlickProduct
    var isSelected: Bool

    var body: some View {
        FlickSettingsRow(
            title: product.name,
            systemImage: "shippingbox",
            iconColor: .blue
        ) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct ProductEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var summary = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var saveAction: (String, String) async throws -> FlickProduct
    var completion: (FlickProduct) -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Product") {
                    #if os(iOS)
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    #else
                    TextField("Name", text: $name)
                    #endif

                    TextField("Notes", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("New Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let product = try await saveAction(name, summary)
                completion(product)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
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

private struct ProductMediaCard: View {
    var asset: MediaAsset
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VerticalMediaFrame(fileURL: asset.localFileURL, remoteURL: asset.publicURL, cornerRadius: 0)
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

    var assetID: UUID

    private var asset: MediaAsset? {
        appModel.overview.assets.first { $0.id == assetID }
    }

    var body: some View {
        NavigationStack {
            List {
                if let asset {
                    mediaSection(asset)
                    productsSection(asset)
                    overviewSection(asset)
                    storageSection(asset)
                    timestampsSection(asset)
                } else {
                    ProductMessageRow(
                        title: "Media unavailable",
                        message: "This media item may have been removed."
                    )
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("Media Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if let asset {
                            deleteAsset(asset)
                        }
                    }
                    .disabled(asset == nil)
                }
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

    private func mediaSection(_ asset: MediaAsset) -> some View {
        Section {
            ProductMediaDetailPreview(asset: asset)
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .listRowBackground(Color.clear)
        }
    }

    private func productsSection(_ asset: MediaAsset) -> some View {
        Section {
            if appModel.overview.products.isEmpty {
                ProductMessageRow(
                    title: "No products",
                    message: "Create a product before assigning media."
                )
            } else {
                ForEach(appModel.overview.products) { product in
                    let isSelected = asset.productIDs.contains(product.id)

                    Button {
                        toggleProduct(product, for: asset)
                    } label: {
                        ProductSelectionRow(product: product, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected && asset.productIDs.count == 1)
                }
            }
        } header: {
            Text("Products")
        } footer: {
            Text("Media must stay attached to at least one product.")
        }
    }

    private func overviewSection(_ asset: MediaAsset) -> some View {
        Section("Overview") {
            FlickSettingsValueRow(
                title: "Type",
                systemImage: asset.mediaType.productSystemImage,
                iconColor: asset.mediaType.productTint,
                value: asset.mediaType.productDisplayName
            )
            FlickSettingsValueRow(
                title: "Products",
                systemImage: "shippingbox",
                iconColor: .blue,
                value: productSummary(products: appModel.overview.products, productIDs: Set(asset.productIDs)),
                valueLineLimit: 2
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
                iconColor: FlickStyle.appTint,
                value: asset.productFileSize
            )
        }
    }

    private func storageSection(_ asset: MediaAsset) -> some View {
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

    private func timestampsSection(_ asset: MediaAsset) -> some View {
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

    private func toggleProduct(_ product: FlickProduct, for asset: MediaAsset) {
        var productIDs = Set(asset.productIDs)

        if productIDs.contains(product.id) {
            guard productIDs.count > 1 else { return }
            productIDs.remove(product.id)
        } else {
            productIDs.insert(product.id)
        }

        Task {
            do {
                try await appModel.updateProductMediaProducts(assetID: asset.id, productIDs: productIDs)
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteAsset(_ asset: MediaAsset) {
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
            VerticalMediaFrame(fileURL: asset.localFileURL, remoteURL: asset.publicURL, cornerRadius: 18, maxPixelSize: 1_920)
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

private func productSummary(products: [FlickProduct], productIDs: Set<UUID>) -> String {
    let names = products
        .filter { productIDs.contains($0.id) }
        .map(\.name)

    switch names.count {
    case 0:
        return "None"
    case 1:
        return names[0]
    case 2:
        return names.joined(separator: ", ")
    default:
        return "\(names.count) products"
    }
}

#Preview {
    @Previewable @State var appModel = FlickAppModel.live()
    IOSProductView()
        .environment(appModel)
}
#endif

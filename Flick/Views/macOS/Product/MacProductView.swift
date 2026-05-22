//
//  MacProductView.swift
//  Flick
//

#if os(macOS) || targetEnvironment(macCatalyst)
import SwiftUI
import UniformTypeIdentifiers

struct MacProductView: View {
    @Environment(FlickAppModel.self) private var appModel

    @State private var selectedProductID: UUID?
    @State private var selectedMediaSelection: MacProductMediaDetailSelection?
    @State private var isProductEditorPresented = false
    @State private var isFileImporterPresented = false
    @State private var isImportingMedia = false

    private var selectedProduct: FlickProduct? {
        selectedProductID.flatMap { productID in
            appModel.overview.products.first { $0.id == productID }
        } ?? appModel.overview.products.first
    }

    private var mediaCountsByProductID: [UUID: Int] {
        appModel.productMediaAssets.reduce(into: [UUID: Int]()) { result, asset in
            for productID in asset.productIDs {
                result[productID, default: 0] += 1
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            productSidebar
                .frame(width: 320)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .macWorkspacePage()
        .navigationTitle("Products")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Product", systemImage: "plus") {
                    isProductEditorPresented = true
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Import Media", systemImage: "photo.badge.plus") {
                    isFileImporterPresented = true
                }
                .disabled(selectedProduct == nil || isImportingMedia)
            }
        }
        .sheet(isPresented: $isProductEditorPresented) {
            MacProductEditorSheet(
                saveAction: { name, summary in
                    try await appModel.createProduct(name: name, summary: summary)
                },
                completion: { product in
                    selectedProductID = product.id
                }
            )
        }
        .sheet(item: $selectedMediaSelection) { selection in
            MacProductMediaDetailSheet(assetID: selection.id)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            importSelectedFiles(result)
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: appModel.overview.products) { _, _ in
            reconcileSelection()
        }
    }

    private var productSidebar: some View {
        MacWorkspacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Products")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text(appModel.overview.products.count.formatted())
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if appModel.overview.products.isEmpty {
                    MacInlineEmptyState(
                        title: "No products",
                        message: "Create a product, then import media and attach it to the product library.",
                        systemImage: "shippingbox"
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(appModel.overview.products) { product in
                            MacProductSidebarRow(
                                product: product,
                                mediaCount: mediaCountsByProductID[product.id, default: 0],
                                isSelected: selectedProduct?.id == product.id,
                                selectAction: { selectedProductID = product.id },
                                deleteAction: { deleteProduct(product) }
                            )
                        }
                    }
                }

                Button("New Product", systemImage: "plus", action: { isProductEditorPresented = true })
                    .buttonStyle(.glassProminent)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedProduct {
            let mediaAssets = appModel.productMediaAssets(for: [selectedProduct.id])

            VStack(alignment: .leading, spacing: 24) {
                MacWorkspaceHeader(
                    title: selectedProduct.name,
                    subtitle: selectedProduct.summary.isEmpty ? "No product notes" : selectedProduct.summary,
                    metrics: [
                        MacWorkspaceMetric(title: "Media", value: mediaAssets.count.formatted()),
                        MacWorkspaceMetric(title: "Images", value: mediaAssets.filter { $0.mediaType == .image }.count.formatted()),
                        MacWorkspaceMetric(title: "Videos", value: mediaAssets.filter { $0.mediaType == .video }.count.formatted())
                    ]
                )

                if isImportingMedia {
                    MacProductImportingPanel()
                }

                MacWorkspaceSection(title: "Media Library", systemImage: "photo.stack") {
                    if mediaAssets.isEmpty {
                        MacInlineEmptyState(
                            title: "No media",
                            message: "Import images or videos for this product from the toolbar.",
                            systemImage: "photo.badge.plus"
                        )
                    } else {
                        MacProductMediaGrid(assets: mediaAssets) { asset in
                            selectedMediaSelection = MacProductMediaDetailSelection(id: asset.id)
                        }
                    }
                }
            }
        } else {
            MacInlineEmptyState(
                title: "No product selected",
                message: "Create a product to organize reference media for slideshow generation.",
                systemImage: "shippingbox"
            )
        }
    }

    private func reconcileSelection() {
        guard let selectedProductID else {
            self.selectedProductID = appModel.overview.products.first?.id
            return
        }
        guard appModel.overview.products.contains(where: { $0.id == selectedProductID }) else {
            self.selectedProductID = appModel.overview.products.first?.id
            return
        }
    }

    private func deleteProduct(_ product: FlickProduct) {
        Task {
            do {
                try await appModel.deleteProduct(id: product.id)
                reconcileSelection()
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func importSelectedFiles(_ result: Result<[URL], Error>) {
        guard let productID = selectedProduct?.id else { return }

        Task { @MainActor in
            isImportingMedia = true
            defer { isImportingMedia = false }

            do {
                let urls = try result.get()
                for url in urls {
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    guard let contentType = UTType(filenameExtension: url.pathExtension) else {
                        throw MacProductMediaImportError.unsupportedType
                    }
                    guard contentType.conforms(to: .image) || contentType.conforms(to: .movie) else {
                        throw MacProductMediaImportError.unsupportedType
                    }

                    try await appModel.addProductMedia(fileURL: url, contentType: contentType, productIDs: [productID])
                }
            } catch {
                appModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct MacProductMediaDetailSelection: Identifiable {
    var id: UUID
}

private struct MacProductSidebarRow: View {
    var product: FlickProduct
    var mediaCount: Int
    var isSelected: Bool
    var selectAction: () -> Void
    var deleteAction: () -> Void

    var body: some View {
        Button(action: selectAction) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(isSelected ? FlickStyle.appTint : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text("\(mediaCount.formatted()) media")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? FlickStyle.appTint.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive, action: deleteAction)
        }
    }
}

private struct MacProductImportingPanel: View {
    var body: some View {
        MacWorkspacePanel {
            HStack(spacing: 12) {
                ProgressView()
                Text("Importing media")
                    .font(.callout.weight(.semibold))
            }
        }
    }
}

private struct MacProductMediaGrid: View {
    var assets: [MediaAsset]
    var selectAction: (MediaAsset) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14, alignment: .top)],
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(assets) { asset in
                Button {
                    selectAction(asset)
                } label: {
                    MacProductMediaCard(asset: asset)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MacProductMediaCard: View {
    var asset: MediaAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VerticalMediaFrame(fileURL: asset.localFileURL, remoteURL: asset.publicURL, cornerRadius: 10, maxPixelSize: 720)
                .overlay {
                    if asset.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }

            HStack {
                Label(asset.macProductDisplayType, systemImage: asset.mediaType.macProductSystemImage)
                Spacer(minLength: 8)
                Text(asset.macProductDimensions)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MacProductEditorSheet: View {
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
                    TextField("Name", text: $name)

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
        .frame(minWidth: 460, minHeight: 360)
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

private struct MacProductMediaDetailSheet: View {
    @Environment(FlickAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var assetID: UUID

    private var asset: MediaAsset? {
        appModel.overview.assets.first { $0.id == assetID }
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 22) {
                if let asset {
                    MacProductMediaDetailPreview(asset: asset)
                        .frame(width: 260)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            MacProductMediaProductsPanel(
                                asset: asset,
                                products: appModel.overview.products,
                                toggleAction: { product in toggleProduct(product, for: asset) }
                            )
                            MacProductMediaMetadataPanel(asset: asset, products: appModel.overview.products)
                        }
                        .padding(20)
                    }
                } else {
                    MacInlineEmptyState(
                        title: "Media unavailable",
                        message: "This media item may have been removed.",
                        systemImage: "photo.badge.exclamationmark"
                    )
                    .padding(20)
                }
            }
            .flickAppBackground()
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
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 620)
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

private struct MacProductMediaDetailPreview: View {
    var asset: MediaAsset

    var body: some View {
        VStack(spacing: 14) {
            VerticalMediaFrame(fileURL: asset.localFileURL, remoteURL: asset.publicURL, cornerRadius: 18, maxPixelSize: 1_920)
                .overlay {
                    if asset.mediaType == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 1)
                }

            StatusBadge(
                title: asset.macProductDisplayType,
                tint: asset.mediaType.macProductTint,
                systemImage: asset.mediaType.macProductSystemImage
            )
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .flickAppBackground()
    }
}

private struct MacProductMediaProductsPanel: View {
    var asset: MediaAsset
    var products: [FlickProduct]
    var toggleAction: (FlickProduct) -> Void

    var body: some View {
        MacWorkspaceSection(title: "Products", systemImage: "shippingbox") {
            MacWorkspacePanel {
                VStack(alignment: .leading, spacing: 10) {
                    if products.isEmpty {
                        SettingsMessageRow(title: "No products", message: "Create a product before assigning media.")
                    } else {
                        ForEach(products) { product in
                            let isSelected = asset.productIDs.contains(product.id)

                            Button {
                                toggleAction(product)
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? .blue : .secondary)
                                    Text(product.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSelected && asset.productIDs.count == 1)
                        }
                    }
                }
            }
        }
    }
}

private struct MacProductMediaMetadataPanel: View {
    var asset: MediaAsset
    var products: [FlickProduct]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MacWorkspaceSection(title: "Overview", systemImage: "info.circle") {
                MacWorkspacePanel {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        MacDetailRow(title: "Type", value: asset.macProductDisplayType)
                        MacDetailRow(title: "Products", value: macProductSummary(products: products, productIDs: Set(asset.productIDs)), valueLineLimit: 2)
                        MacDetailRow(title: "Source", value: asset.source.macProductDisplayName)
                        MacDetailRow(title: "Dimensions", value: asset.macProductDimensions)
                        MacDetailRow(title: "Duration", value: asset.macProductDuration)
                        MacDetailRow(title: "File Size", value: asset.macProductFileSize)
                    }
                }
            }

            MacWorkspaceSection(title: "Storage", systemImage: "externaldrive") {
                MacWorkspacePanel {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        MacDetailRow(title: "Local Path", value: asset.localFilePath ?? "Not set", valueLineLimit: nil)
                        MacDetailRow(title: "Bucket", value: asset.storageBucket ?? "Not set", valueLineLimit: nil)
                        MacDetailRow(title: "Path", value: asset.storagePath ?? "Not set", valueLineLimit: nil)
                        MacDetailRow(title: "Public URL", value: asset.publicURL?.absoluteString ?? "Not set", valueLineLimit: nil)
                        MacDetailRow(title: "Signed URL", value: asset.macProductSignedURLExpiration)
                        MacDetailRow(title: "Checksum", value: asset.checksum ?? "Not set", valueLineLimit: nil)
                    }
                }
            }

            MacWorkspaceSection(title: "Timestamps", systemImage: "calendar") {
                MacWorkspacePanel {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        MacDetailRow(title: "Created", value: asset.macProductCreatedAt)
                        MacDetailRow(title: "Updated", value: asset.macProductUpdatedAt)
                        MacDetailRow(title: "ID", value: asset.id.uuidString, valueLineLimit: nil)
                    }
                }
            }
        }
    }
}

private enum MacProductMediaImportError: LocalizedError {
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "This item is not an image or video that Flick can import."
        }
    }
}

private extension MediaAsset {
    var macProductDimensions: String {
        guard width > 0, height > 0 else { return "Not set" }
        return "\(width.formatted()) x \(height.formatted())"
    }

    var macProductDuration: String {
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

    var macProductFileSize: String {
        guard let fileSize else { return "Not set" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var macProductSignedURLExpiration: String {
        guard let signedURLExpiration else { return "Not set" }
        return signedURLExpiration.formatted(date: .abbreviated, time: .shortened)
    }

    var macProductCreatedAt: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var macProductUpdatedAt: String {
        updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var macProductDisplayType: String {
        mediaType.macProductDisplayName
    }
}

private extension AssetSource {
    var macProductDisplayName: String {
        rawValue.capitalized
    }
}

private extension AssetMediaType {
    var macProductDisplayName: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .thumbnail: "Thumbnail"
        }
    }

    var macProductSystemImage: String {
        switch self {
        case .image, .thumbnail: "photo"
        case .video: "video"
        }
    }

    var macProductTint: Color {
        switch self {
        case .image: .blue
        case .video: .purple
        case .thumbnail: .secondary
        }
    }
}

private func macProductSummary(products: [FlickProduct], productIDs: Set<UUID>) -> String {
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
#endif

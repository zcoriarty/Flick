//
//  CreateProductImageSection.swift
//  Flick
//

import SwiftUI

struct CreateProductImageSection: View {
    var products: [FlickProduct]
    var productImageAssets: [MediaAsset]
    var isAutonomous: Bool
    @Binding var selectedProductID: UUID?
    @Binding var selectedProductImageAssetID: UUID?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 76), spacing: 10, alignment: .top)
    ]

    var body: some View {
        Section("Product") {
            if products.isEmpty {
                CreateMessageRow(
                    title: "No products",
                    message: "Create a product before attaching product media to this slideshow."
                )
            } else {
                productMenu

                if let selectedProduct {
                    if selectedProductImageAssets.isEmpty {
                        CreateMessageRow(
                            title: "No product images",
                            message: "Add an image to \(selectedProduct.name) before analyzing with this product."
                        )
                    } else if isAutonomous {
                        FlickSettingsRow(
                            title: "Product image",
                            systemImage: "shuffle",
                            iconColor: .blue
                        ) {
                            Text(randomImageValue)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        manualImageGrid
                    }
                }
            }
        }
        .onChange(of: selectedProductID) { _, _ in
            selectedProductImageAssetID = nil
        }
        .onChange(of: productImageAssets) { _, _ in
            reconcileSelectedProductImage()
        }
        .onChange(of: isAutonomous) { _, isAutonomous in
            if isAutonomous {
                selectedProductImageAssetID = nil
            }
        }
    }

    private var productMenu: some View {
        Menu {
            Button {
                selectedProductID = nil
                selectedProductImageAssetID = nil
            } label: {
                CreateMenuOptionLabel(title: "None", isSelected: selectedProductID == nil)
            }

            ForEach(products) { product in
                Button {
                    selectedProductID = product.id
                    selectedProductImageAssetID = nil
                } label: {
                    CreateMenuOptionLabel(title: product.name, isSelected: selectedProductID == product.id)
                }
            }
        } label: {
            FlickSettingsRow(
                title: "Product",
                systemImage: "shippingbox",
                iconColor: .blue
            ) {
                HStack(spacing: 6) {
                    Text(selectedProduct?.name ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var manualImageGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
            ForEach(selectedProductImageAssets) { asset in
                Button {
                    selectedProductImageAssetID = asset.id
                } label: {
                    ProductImageChoice(
                        asset: asset,
                        isSelected: selectedProductImageAssetID == asset.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var selectedProduct: FlickProduct? {
        guard let selectedProductID else { return nil }
        return products.first { $0.id == selectedProductID }
    }

    private var selectedProductImageAssets: [MediaAsset] {
        guard let selectedProductID else { return [] }
        return productImageAssets.filter { asset in
            asset.productIDs.contains(selectedProductID)
        }
    }

    private var randomImageValue: String {
        let count = selectedProductImageAssets.count
        return "\(count) \(count == 1 ? "image" : "images")"
    }

    private func reconcileSelectedProductImage() {
        guard let selectedProductImageAssetID else { return }
        guard selectedProductImageAssets.contains(where: { $0.id == selectedProductImageAssetID }) else {
            self.selectedProductImageAssetID = nil
            return
        }
    }
}

private struct ProductImageChoice: View {
    var asset: MediaAsset
    var isSelected: Bool

    var body: some View {
        VerticalMediaFrame(fileURL: asset.localFileURL, cornerRadius: 8, maxPixelSize: 720)
            .frame(width: 76, height: 136)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(5)
                }
            }
            .accessibilityLabel("Product image")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct CreateMenuOptionLabel: View {
    var title: String
    var isSelected: Bool

    var body: some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

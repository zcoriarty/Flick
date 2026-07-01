//
//  CreateAutomationProductImageSection.swift
//  Flick
//

import SwiftUI

struct CreateAutomationProductImageSection: View {
    var products: [FlickProduct]
    var productImageAssets: [MediaAsset]
    @Binding var selectedProductID: UUID?
    @Binding var selectedProductImageAssetIDs: Set<UUID>

    private let gridColumns = [
        GridItem(.adaptive(minimum: 76), spacing: 10, alignment: .top)
    ]

    var body: some View {
        Section("Product Images") {
            if products.isEmpty {
                CreateMessageRow(
                    title: "No products",
                    message: "No product media will be attached to automated posts."
                )
            } else {
                productMenu

                if let selectedProduct {
                    if selectedProductImageAssets.isEmpty {
                        CreateMessageRow(
                            title: "No product images",
                            message: "Add images to \(selectedProduct.name) before publishing an automation."
                        )
                    } else {
                        imageGrid
                    }
                } else {
                    CreateMessageRow(
                        title: "No product selected",
                        message: "Posts generated from this automation will not include product media."
                    )
                }
            }
        }
        .onChange(of: selectedProductID) { _, _ in
            selectedProductImageAssetIDs.removeAll()
        }
        .onChange(of: productImageAssets) { _, _ in
            reconcileSelectedProductImages()
        }
    }

    private var productMenu: some View {
        Menu {
            Button {
                selectedProductID = nil
                selectedProductImageAssetIDs.removeAll()
            } label: {
                CreateProductMenuOptionLabel(title: "None", isSelected: selectedProductID == nil)
            }

            ForEach(products) { product in
                Button {
                    selectedProductID = product.id
                    selectedProductImageAssetIDs.removeAll()
                } label: {
                    CreateProductMenuOptionLabel(title: product.name, isSelected: selectedProductID == product.id)
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

    private var imageGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
            ForEach(selectedProductImageAssets) { asset in
                Button {
                    toggle(asset)
                } label: {
                    ProductImageChoice(
                        asset: asset,
                        isSelected: selectedProductImageAssetIDs.contains(asset.id)
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

    private func toggle(_ asset: MediaAsset) {
        if selectedProductImageAssetIDs.contains(asset.id) {
            selectedProductImageAssetIDs.remove(asset.id)
        } else {
            selectedProductImageAssetIDs.insert(asset.id)
        }
    }

    private func reconcileSelectedProductImages() {
        let availableIDs = Set(selectedProductImageAssets.map(\.id))
        selectedProductImageAssetIDs = selectedProductImageAssetIDs.intersection(availableIDs)
    }
}

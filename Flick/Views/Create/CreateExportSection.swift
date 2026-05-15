//
//  CreateExportSection.swift
//  Flick
//

import SwiftUI

struct CreateExportSection: View {
    var draft: SlideshowDraft
    var assetsByID: [UUID: MediaAsset]
    var isExporting: Bool
    var exportAction: () -> Void

    private var isReady: Bool {
        draft.slides.allSatisfy { slide in
            guard let imageAssetID = slide.imageAssetID else { return false }
            return assetsByID[imageAssetID]?.hasAvailableMediaLocation == true && slide.generationStatus == .complete
        }
    }

    var body: some View {
        Section("Export") {
            FlickSettingsValueRow(
                title: "Image sequence",
                systemImage: "square.stack.3d.up",
                iconColor: isReady ? .green : .orange,
                value: isReady ? "Ready" : "Needs images"
            )

            FlickSettingsValueRow(
                title: "Rendered outputs",
                systemImage: "checkmark.seal",
                iconColor: draft.exportedImageAssetIDs.isEmpty ? .secondary : .green,
                value: "\(draft.exportedImageAssetIDs.count)"
            )

            Button(action: exportAction) {
                HStack(spacing: 10) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }

                    Text(isExporting ? "Exporting" : "Export Image Sequence")
                        .fontWeight(.semibold)

                    Spacer()

                    Text("2560x1440")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isExporting || draft.slides.isEmpty || !isReady)

            if !draft.exportedImageAssetIDs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.exportedImageAssetIDs, id: \.self) { assetID in
                        if let asset = assetsByID[assetID] {
                            Text(asset.publicURL?.absoluteString ?? asset.localFilePath ?? asset.storagePath ?? asset.id.uuidString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

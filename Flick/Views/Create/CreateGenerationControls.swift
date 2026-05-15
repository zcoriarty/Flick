//
//  CreateGenerationControls.swift
//  Flick
//

import SwiftUI

struct CreateGenerationControls: View {
    var draft: SlideshowDraft
    var assetsByID: [UUID: MediaAsset]
    var isGenerating: Bool
    var message: String?
    var generateMissingAction: () -> Void

    private var completeCount: Int {
        draft.slides.filter { slide in
            guard let imageAssetID = slide.imageAssetID else { return false }
            guard let asset = assetsByID[imageAssetID] else { return false }
            return asset.hasAvailableMediaLocation
                && SlideshowImageGenerationSettings.draft.isSatisfied(by: asset)
                && slide.generationStatus == .complete
        }.count
    }

    private var missingCount: Int {
        draft.slides.filter { slide in
            guard let imageAssetID = slide.imageAssetID else { return true }
            guard let asset = assetsByID[imageAssetID], asset.hasAvailableMediaLocation else { return true }
            return !SlideshowImageGenerationSettings.draft.isSatisfied(by: asset)
        }.count
    }

    private var actionTitle: String {
        if isGenerating {
            return "Generating"
        }
        if completeCount == 0 {
            return "Generate Images"
        }
        return "Generate Missing Images"
    }

    var body: some View {
        Section("Images") {
            FlickSettingsValueRow(
                title: "Generated images",
                systemImage: "photo.stack",
                iconColor: completeCount == draft.slides.count ? .green : .blue,
                value: "\(completeCount) of \(draft.slides.count)"
            )

            Button(action: generateMissingAction) {
                HStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.badge.plus")
                    }

                    Text(actionTitle)
                        .fontWeight(.semibold)

                    Spacer()
                }
            }
            .disabled(isGenerating || draft.slides.isEmpty || missingCount == 0)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

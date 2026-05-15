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
        draft.createGeneratedImageCount(assetsByID: assetsByID)
    }

    private var missingCount: Int {
        draft.createMissingImageCount(assetsByID: assetsByID)
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

            if let message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        if isGenerating || missingCount > 0 {
            Button(action: generateMissingAction) {
                HStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.badge.plus")
                    }

                    Text(actionTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: -16, bottom: 0, trailing: -16))
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isGenerating || draft.slides.isEmpty || missingCount == 0)
        }
    }
}

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
    var generateAction: () -> Void

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
        if missingCount == 0 {
            return "Redo Image Generation"
        }
        return "Generate Missing Images"
    }

    private var hasRunGeneration: Bool {
        completeCount > 0
    }

    private var shouldShowAction: Bool {
        isGenerating || missingCount > 0 || completeCount > 0
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

        if shouldShowAction {
            styledButton
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: -16, bottom: 0, trailing: -16))
            .controlSize(.large)
            .disabled(isGenerating || draft.slides.isEmpty)
        }
    }

    @ViewBuilder
    private var styledButton: some View {
        if hasRunGeneration {
            generationButton
                .buttonStyle(.glass)
        } else {
            generationButton
                .buttonStyle(.glassProminent)
        }
    }

    private var generationButton: some View {
        Button(action: generateAction) {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: missingCount == 0 && hasRunGeneration ? "arrow.clockwise" : "photo.badge.plus")
                }

                Text(actionTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

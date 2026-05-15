//
//  CreateSlideRail.swift
//  Flick
//

import SwiftUI

struct CreateSlideRail: View {
    var slides: [Slide]
    var assetsByID: [UUID: MediaAsset]
    var openAction: (UUID) -> Void

    var body: some View {
        Section("Slides") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(slides.sorted { $0.index < $1.index }) { slide in
                        Button {
                            openAction(slide.id)
                        } label: {
                            SlideRailItem(
                                slide: slide,
                                asset: slide.imageAssetID.flatMap { assetsByID[$0] }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct SlideRailItem: View {
    var slide: Slide
    var asset: MediaAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                GeneratedSlideImageView(asset: asset)
                    .frame(width: 74, height: 132)
                    .clipShape(.rect(cornerRadius: 8))

                Text("\(slide.index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Slide \(slide.index + 1)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(slide.generationStatus.tint)
                        .frame(width: 7, height: 7)
                    Text(slide.generationStatus.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 90, alignment: .leading)
        .padding(8)
        .background(
            Color.secondary.opacity(0.08),
            in: .rect(cornerRadius: 10)
        )
        .accessibilityElement(children: .combine)
    }
}

struct GeneratedSlideImageView: View {
    var asset: MediaAsset?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let fileURL = asset?.localFileURL {
                LocalAssetImage(fileURL: fileURL, contentMode: contentMode)
            } else if let publicURL = asset?.publicURL {
                AsyncImage(url: publicURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.secondary.opacity(0.2), .secondary.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

private extension SlideGenerationStatus {
    var tint: Color {
        switch self {
        case .notStarted: .secondary
        case .generating: .blue
        case .complete: .green
        case .failed: .red
        }
    }
}

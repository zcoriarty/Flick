//
//  TemplateDetailView.swift
//  Flick
//

import SwiftUI

struct TemplateDetailView: View {
    @Environment(FlickAppModel.self) private var appModel
    var template: ExampleSlideshowTemplate

    @State private var fullSizeSlide: ExampleSlideshowSlide?

    var body: some View {
        VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
            header
            slideGrid
            sourceDetails
        }
        .flickScrollablePage()
        .flickToolbarTitle(template.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Use Template", systemImage: "wand.and.sparkles") {
                    appModel.createDraft(from: template)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .sheet(item: $fullSizeSlide) { slide in
            ExampleSlideFullSizePreviewSheet(slide: slide)
        }
    }

    private var header: some View {
        FlickGlassCard {
            HStack(alignment: .top, spacing: 16) {
                VerticalMediaFrame(
                    fileURL: template.displayablePreviewSlide?.localURL,
                    remoteURL: template.displayablePreviewSlide?.remoteURL
                )
                    .frame(width: 120)

                VStack(alignment: .leading, spacing: 10) {
                    StatusBadge(title: template.niche, tint: FlickStyle.appTint, systemImage: "tag")
                    Text(template.subtitle)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(template.slideCount) slides from @\(template.profile)")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        if let views = template.metrics.views {
                            Label(views, systemImage: "play.rectangle")
                        }
                        if let likes = template.metrics.likes {
                            Label(likes, systemImage: "heart")
                        }
                        if let bookmarks = template.metrics.bookmarks {
                            Label(bookmarks, systemImage: "bookmark")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var slideGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Slides", subtitle: nil, systemImage: "photo.stack")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 180), spacing: 12, alignment: .top)], spacing: 18) {
                ForEach(template.slides) { slide in
                    TemplateSlideTile(slide: slide) {
                        fullSizeSlide = slide
                    }
                }
            }
        }
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Source", subtitle: nil, systemImage: "info.circle")
            FlickGlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    DetailRow(title: "Creator", value: "@\(template.profile)")
                    DetailRow(title: "Followers", value: template.creator.followerCount ?? "Unknown")
                    DetailRow(title: "Medium", value: template.product.medium ?? "None")
                    DetailRow(title: "Product", value: template.product.name ?? "None")
                }
            }
        }
    }
}

private struct TemplateSlideTile: View {
    var slide: ExampleSlideshowSlide
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VerticalMediaFrame(fileURL: slide.localURL, remoteURL: slide.remoteURL, cornerRadius: 8)
                .overlay(alignment: .bottomLeading) {
                    Text("Slide \(slide.index)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.48), in: .capsule)
                        .padding(7)
                }
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview slide \(slide.index)")
        .accessibilityHint("Opens full-size preview")
    }
}

struct ExampleSlideFullSizePreviewSheet: View {
    var slide: ExampleSlideshowSlide

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                let size = previewSize(in: proxy.size)

                VerticalMediaFrame(
                    fileURL: slide.localURL,
                    remoteURL: slide.remoteURL,
                    cornerRadius: 18,
                    maxPixelSize: 1_920
                )
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalPadding / 2)
                .padding(.vertical, verticalPadding / 2)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.48), in: .circle)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("Close full-size slide")
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full-size slide \(slide.index)")
        #if os(macOS) || targetEnvironment(macCatalyst)
        .frame(
            minWidth: 460,
            idealWidth: 560,
            maxWidth: 760,
            minHeight: 620,
            idealHeight: 760,
            maxHeight: 920
        )
        #endif
    }

    private var horizontalPadding: CGFloat { 32 }
    private var verticalPadding: CGFloat { 88 }

    private func previewSize(in size: CGSize) -> CGSize {
        let availableWidth = max(1, size.width - horizontalPadding)
        let availableHeight = max(1, size.height - verticalPadding)
        let widthFromHeight = availableHeight * VerticalMediaFrame.targetAspectRatio
        let width = min(availableWidth, widthFromHeight)
        return CGSize(width: width, height: width / VerticalMediaFrame.targetAspectRatio)
    }
}

private struct DetailRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

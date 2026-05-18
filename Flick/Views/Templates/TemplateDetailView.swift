//
//  TemplateDetailView.swift
//  Flick
//

import SwiftUI

struct TemplateDetailView: View {
    @Environment(FlickAppModel.self) private var appModel
    var template: ExampleSlideshowTemplate

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
    }

    private var header: some View {
        FlickGlassCard {
            HStack(alignment: .top, spacing: 16) {
                VerticalMediaFrame(fileURL: template.displayablePreviewSlide?.localURL)
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
                    TemplateSlideTile(slide: slide)
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

    var body: some View {
        VerticalMediaFrame(fileURL: slide.localURL, cornerRadius: 8)
            .overlay(alignment: .bottomLeading) {
                Text("Slide \(slide.index)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.48), in: .capsule)
                    .padding(7)
            }
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

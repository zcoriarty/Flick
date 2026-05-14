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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(template.title)
            }
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
                LocalAssetImage(fileURL: template.displayablePreviewSlide?.localURL)
                    .frame(width: 120)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: FlickStyle.controlCornerRadius))
                    .compositingGroup()

                VStack(alignment: .leading, spacing: 10) {
                    StatusBadge(title: template.niche, tint: .indigo, systemImage: "tag")
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
        VStack(alignment: .leading, spacing: 6) {
            LocalAssetImage(fileURL: slide.localURL, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))
                .compositingGroup()

            Text("Slide \(slide.index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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

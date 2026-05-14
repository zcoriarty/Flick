//
//  TemplateCard.swift
//  Flick
//

import SwiftUI

struct TemplateCard: View {
    var template: ExampleSlideshowTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(displayMedium)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(displayProduct)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.niche) template from \(template.title), \(template.slideCount) slides")
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            LocalAssetImage(fileURL: template.displayablePreviewSlide?.localURL, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 7))
                .compositingGroup()

            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                if let views = template.metrics.views {
                    MetricOverlayLabel(value: views, systemImage: "play.fill")
                }
                if let likes = template.metrics.likes {
                    MetricOverlayLabel(value: likes, systemImage: "heart.fill")
                }
            }
            .padding(8)
        }
    }

    private var displayMedium: String {
        guard let medium = template.product.medium?.trimmingCharacters(in: .whitespacesAndNewlines), !medium.isEmpty else {
            return "None"
        }
        return medium
    }

    private var displayProduct: String {
        guard let product = template.product.name?.trimmingCharacters(in: .whitespacesAndNewlines), !product.isEmpty else {
            return "No product"
        }
        return product
    }
}

private struct MetricOverlayLabel: View {
    var value: String
    var systemImage: String

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

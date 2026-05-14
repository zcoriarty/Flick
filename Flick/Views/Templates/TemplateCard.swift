//
//  TemplateCard.swift
//  Flick
//

import SwiftUI

struct TemplateCard: View {
    var template: ExampleSlideshowTemplate

    var body: some View {
        thumbnail
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.niche) template from \(template.title), \(template.slideCount) slides")
    }

    private var thumbnail: some View {
        VerticalMediaFrame(fileURL: template.displayablePreviewSlide?.localURL, cornerRadius: 0)
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.74)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .topTrailing) {
                Text("\(template.slideCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.48), in: .capsule)
                    .padding(7)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayMedium)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(displayProduct)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 8) {
                        if let views = template.metrics.views {
                            MetricOverlayLabel(value: views, systemImage: "play.fill")
                        }
                        if let likes = template.metrics.likes {
                            MetricOverlayLabel(value: likes, systemImage: "heart.fill")
                        }
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 8))
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

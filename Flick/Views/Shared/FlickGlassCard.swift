//
//  FlickGlassCard.swift
//  Flick
//

import SwiftUI

struct FlickGlassCard<Content: View>: View {
    var interactive = false
    let content: Content

    init(interactive: Bool = false, @ViewBuilder content: () -> Content) {
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: FlickStyle.cardCornerRadius))
            .glassEffect(glass, in: .rect(cornerRadius: FlickStyle.cardCornerRadius))
    }

    private var glass: Glass {
        let base = Glass.regular
        return interactive ? base.interactive() : base
    }
}

struct StatusBadge: View {
    var title: String
    var tint: Color
    var systemImage: String?

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FlickEmptyStateCard: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?

    init(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String? = nil,
        actionSystemImage: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.action = action
    }

    var body: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, systemImage: actionSystemImage ?? "arrow.right", action: action)
                        .buttonStyle(.glass)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String?
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TagChip: View {
    var tag: TrendTag

    var body: some View {
        Text(tag.name)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Color(hex: tag.colorHex))
            .background(Color(hex: tag.colorHex).opacity(0.12), in: .capsule)
    }
}

struct ResponsiveGrid<Content: View>: View {
    var minimum: CGFloat = 210
    var spacing: CGFloat = 12
    let content: Content

    init(minimum: CGFloat = 210, spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.minimum = minimum
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: spacing)], spacing: spacing) {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func flickScrollablePage() -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                self
            }
            .padding(FlickStyle.pagePadding)
        }
        .background(FlickStyle.pageBackground.ignoresSafeArea())
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

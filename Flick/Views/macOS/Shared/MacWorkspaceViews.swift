//
//  MacWorkspaceViews.swift
//  Flick
//

#if os(macOS) || targetEnvironment(macCatalyst)
import SwiftUI

struct MacWorkspaceHeader: View {
    var title: String
    var subtitle: String
    var metrics: [MacWorkspaceMetric] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 20)

            if !metrics.isEmpty {
                HStack(spacing: 18) {
                    ForEach(metrics) { metric in
                        MacWorkspaceMetricView(metric: metric)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MacWorkspaceMetric: Identifiable {
    var id: String { title }
    var title: String
    var value: String
}

struct MacWorkspaceMetricView: View {
    var metric: MacWorkspaceMetric

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(metric.value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .lineLimit(1)
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct MacWorkspaceSection<Content: View>: View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: title, subtitle: subtitle, systemImage: systemImage)
            content
        }
    }
}

struct MacWorkspacePanel<Content: View>: View {
    var minHeight: CGFloat?
    let content: Content

    init(minHeight: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(.thinMaterial, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }
}

struct MacDetailRow: View {
    var title: String
    var value: String
    var valueLineLimit: Int? = 1

    var body: some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(valueLineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MacInlineEmptyState: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        MacWorkspacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    func macWorkspacePage(horizontalPadding: CGFloat = 28, verticalPadding: CGFloat = 28) -> some View {
        ScrollView {
            self
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .flickAppBackground()
    }
}
#endif

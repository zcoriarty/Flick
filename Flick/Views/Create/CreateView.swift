//
//  CreateView.swift
//  Flick
//

import SwiftUI

struct CreateView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var prompt = ""
    @State private var selectedMode: CreateMode = .prompt

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                strategyBuilder
                draftPreview
                qualityChecks
            }
            .flickScrollablePage()
            .navigationTitle("Create")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Send to queue", systemImage: "tray.and.arrow.down") {
                        appModel.selectedSection = .queue
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(appModel.overview.drafts.isEmpty)
                }
            }
        }
    }

    private var strategyBuilder: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Generation strategy", subtitle: "Prompt, trend template, app feature, or previous winner", systemImage: "wand.and.stars")

            FlickGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(CreateMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Describe the product, audience, pain point, trend, and CTA for a new slideshow.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $prompt)
                            .frame(minHeight: 110)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(
                                .background.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius, style: .continuous)
                            )
                            .accessibilityLabel("Generation prompt")
                    }

                    ResponsiveGrid(minimum: 190) {
                        StrategyBriefTile(title: "App feature", value: appModel.overview.campaigns.first?.appFeature ?? "Unassigned", systemImage: "app.badge")
                        StrategyBriefTile(title: "Audience", value: appModel.overview.campaigns.first?.audience ?? "Unassigned", systemImage: "person.text.rectangle")
                        StrategyBriefTile(title: "CTA", value: "Unassigned", systemImage: "arrow.up.forward.circle")
                        StrategyBriefTile(title: "Slide count", value: "\(appModel.overview.drafts.first?.slides.count ?? 0)", systemImage: "rectangle.stack")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var draftPreview: some View {
        if let draft = appModel.overview.drafts.first {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Slideshow draft", subtitle: "Text overlays, ordering, preview, and platform targets", systemImage: "rectangle.stack.badge.play")

                ResponsiveGrid(minimum: 230) {
                    ForEach(draft.slides) { slide in
                        SlidePreviewCard(slide: slide)
                    }
                }

                FlickGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(draft.title)
                                .font(.headline)
                            Spacer()
                            StatusBadge(title: draft.status.rawValue.capitalized, tint: .teal, systemImage: "doc.text")
                        }

                        Text(draft.caption)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack {
                            ForEach(draft.hashtags, id: \.self) { hashtag in
                                Text("#\(hashtag)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Slideshow draft", subtitle: "Draft content will appear here after generation or import", systemImage: "rectangle.stack.badge.play")
                FlickEmptyStateCard(
                    title: "No draft yet",
                    message: "Create or import a slideshow draft before editing slides, captions, hashtags, and platform targets.",
                    systemImage: "rectangle.stack.badge.plus"
                )
            }
        }
    }

    @ViewBuilder
    private var qualityChecks: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Preflight checks", subtitle: "Required before approval and publishing", systemImage: "checklist")
            if appModel.overview.drafts.isEmpty {
                FlickEmptyStateCard(
                    title: "No content to check",
                    message: "Preflight checks run against a real draft and its rendered media.",
                    systemImage: "checklist.unchecked"
                )
            } else {
                ResponsiveGrid(minimum: 260) {
                    QualityCheckRow(title: "1080 x 1920 aspect ratio", status: .needsReview)
                    QualityCheckRow(title: "Readable text contrast", status: .needsReview)
                    QualityCheckRow(title: "Supabase public URLs", status: .needsReview)
                    QualityCheckRow(title: "TikTok publish settings", status: .needsReview)
                    QualityCheckRow(title: "CTA present", status: .needsReview)
                    QualityCheckRow(title: "Caption length valid", status: .needsReview)
                }
            }
        }
    }
}

private enum CreateMode: String, CaseIterable, Identifiable {
    case prompt
    case trend
    case appFeature
    case winner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prompt: "Prompt"
        case .trend: "Trend"
        case .appFeature: "Feature"
        case .winner: "Winner"
        }
    }

    var systemImage: String {
        switch self {
        case .prompt: "text.cursor"
        case .trend: "sparkles.rectangle.stack"
        case .appFeature: "app.badge"
        case .winner: "trophy"
        }
    }
}

private struct StrategyBriefTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
            }
        }
    }
}

private struct SlidePreviewCard: View {
    var slide: Slide

    var body: some View {
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    LinearGradient(
                        colors: [slide.role.tint.opacity(0.65), .black.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 14) {
                        Text(slide.overlayText)
                            .font(.system(.title3, design: .rounded, weight: .black))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding()
                        Image(systemName: slide.role.systemImage)
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                }
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(.rect(cornerRadius: FlickStyle.cardCornerRadius))
                .compositingGroup()

                HStack {
                    Text("\(slide.index + 1). \(slide.role.rawValue.capitalized)")
                        .font(.headline)
                    Spacer()
                    Text("\(slide.duration.formatted(.number.precision(.fractionLength(1))))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(slide.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private enum QualityCheckStatus {
    case ready
    case needsReview
    case needsWork

    var title: String {
        switch self {
        case .ready: "Ready"
        case .needsReview: "Review"
        case .needsWork: "Needs work"
        }
    }

    var tint: Color {
        switch self {
        case .ready: .green
        case .needsReview: .orange
        case .needsWork: .red
        }
    }
}

private struct QualityCheckRow: View {
    var title: String
    var status: QualityCheckStatus

    var body: some View {
        FlickGlassCard {
            HStack {
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer()
                StatusBadge(title: status.title, tint: status.tint, systemImage: "circle.fill")
            }
        }
    }
}

private extension SlideRole {
    var tint: Color {
        switch self {
        case .hook: .orange
        case .problem: .red
        case .proof: .blue
        case .demo: .teal
        case .benefit: .green
        case .cta: .purple
        }
    }

    var systemImage: String {
        switch self {
        case .hook: "quote.opening"
        case .problem: "exclamationmark.bubble"
        case .proof: "chart.line.uptrend.xyaxis"
        case .demo: "iphone"
        case .benefit: "sparkle"
        case .cta: "arrow.up.forward"
        }
    }
}

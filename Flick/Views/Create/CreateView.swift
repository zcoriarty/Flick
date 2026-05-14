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
        List {
            generateSection
            draftsSection
            preflightSection
        }
        .flickSettingsListStyle()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Create")
                    .font(.system(.body, weight: .semibold))
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Send to queue", systemImage: "tray.and.arrow.down") {
                    appModel.selectedSection = .queue
                }
                .disabled(appModel.overview.drafts.isEmpty)
            }
        }
    }

    private var generateSection: some View {
        Section("Generate") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Mode", selection: $selectedMode) {
                    ForEach(CreateMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .accessibilityElement(children: .contain)

            PromptEditorRow(prompt: $prompt, mode: selectedMode)

            ForEach(generationBriefs) { brief in
                CreateSettingsValueRow(title: brief.title, value: brief.value)
            }
        }
    }

    @ViewBuilder
    private var draftsSection: some View {
        Section("Drafts") {
            if let draft = appModel.overview.drafts.first {
                let assetsByID = Dictionary(uniqueKeysWithValues: appModel.overview.assets.map { ($0.id, $0) })

                CreateSettingsValueRow(title: "Title", value: draft.title, valueLineLimit: 2)
                FlickSettingsRow(title: "Status") {
                    StatusBadge(title: draft.status.rawValue.capitalized, tint: .teal, systemImage: "circle.fill")
                }
                CreateSettingsValueRow(title: "Caption", value: draft.caption, valueLineLimit: 3)
                CreateSettingsValueRow(title: "Hashtags", value: draft.hashtagDisplayValue, valueLineLimit: 2)

                ForEach(draft.slides) { slide in
                    SlidePreviewRow(slide: slide, asset: slide.imageAssetID.flatMap { assetsByID[$0] })
                }
            } else {
                CreateMessageRow(
                    title: "No draft yet",
                    message: "Create or import a slideshow draft before editing slides, captions, hashtags, and platform targets."
                )
            }
        }
    }

    @ViewBuilder
    private var preflightSection: some View {
        Section("Preflight checks") {
            if appModel.overview.drafts.isEmpty {
                CreateMessageRow(
                    title: "No content to check",
                    message: "Preflight checks run against a real draft and its rendered media."
                )
            } else {
                ForEach(preflightChecks) { check in
                    FlickSettingsRow(title: check.title) {
                        StatusBadge(title: check.status.title, tint: check.status.tint, systemImage: "circle.fill")
                    }
                }
            }
        }
    }

    private var generationBriefs: [GenerationBrief] {
        switch selectedMode {
        case .prompt:
            [
                GenerationBrief(title: "Source", value: "Custom prompt"),
                GenerationBrief(title: "Product media", value: appModel.productMediaAssets.count.formatted()),
                GenerationBrief(title: "Slide count", value: appModel.overview.drafts.first?.slides.count.formatted() ?? "No draft"),
                GenerationBrief(title: "Platform", value: appModel.overview.drafts.first?.targetPlatforms.displayNames ?? "TikTok")
            ]
        case .trend:
            trendBriefs
        case .appFeature:
            appFeatureBriefs
        case .winner:
            winnerBriefs
        }
    }

    private var trendBriefs: [GenerationBrief] {
        guard let trend = appModel.overview.trends.first(where: { $0.status == .winning })
            ?? appModel.overview.trends.first(where: { $0.status == .active })
            ?? appModel.overview.trends.first
        else {
            return [
                GenerationBrief(title: "Trend", value: "No saved trend"),
                GenerationBrief(title: "Source", value: "Unassigned"),
                GenerationBrief(title: "Status", value: "Unassigned"),
                GenerationBrief(title: "Tags", value: "No tags")
            ]
        }

        return [
            GenerationBrief(title: "Trend", value: trend.name),
            GenerationBrief(title: "Source", value: trend.source),
            GenerationBrief(title: "Status", value: trend.status.displayName),
            GenerationBrief(title: "Tags", value: trend.tags.displayNames)
        ]
    }

    private var appFeatureBriefs: [GenerationBrief] {
        guard let campaign = appModel.overview.campaigns.first else {
            return [
                GenerationBrief(title: "App feature", value: "Unassigned"),
                GenerationBrief(title: "Audience", value: "Unassigned"),
                GenerationBrief(title: "Goal", value: "Unassigned"),
                GenerationBrief(title: "Campaign", value: "No campaign")
            ]
        }

        return [
            GenerationBrief(title: "App feature", value: campaign.appFeature),
            GenerationBrief(title: "Audience", value: campaign.audience),
            GenerationBrief(title: "Goal", value: campaign.goal),
            GenerationBrief(title: "Campaign", value: campaign.name)
        ]
    }

    private var winnerBriefs: [GenerationBrief] {
        guard let winner = appModel.overview.dashboard.bestRecentPost
            ?? appModel.overview.analyticsPerformance.max(by: { $0.views < $1.views })
        else {
            return [
                GenerationBrief(title: "Winner", value: "No winner yet"),
                GenerationBrief(title: "Views", value: "No analytics"),
                GenerationBrief(title: "Engagement", value: "No analytics"),
                GenerationBrief(title: "Tags", value: "No tags")
            ]
        }

        return [
            GenerationBrief(title: "Winner", value: winner.title),
            GenerationBrief(title: "Views", value: winner.views.formatted()),
            GenerationBrief(title: "Engagement", value: winner.engagementRate.formatted(.percent.precision(.fractionLength(1)))),
            GenerationBrief(title: "Tags", value: winner.tags.displayNames)
        ]
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

    var placeholder: String {
        switch self {
        case .prompt: "Describe the product, audience, pain point, trend, and CTA for a new slideshow."
        case .trend: "Describe how this saved trend should be adapted for the next slideshow."
        case .appFeature: "Describe the feature benefit, target audience, proof point, and CTA."
        case .winner: "Describe what to remix from the current winner and what should change."
        }
    }
}

private struct GenerationBrief: Identifiable {
    var title: String
    var value: String

    var id: String { title }
}

private struct PromptEditorRow: View {
    @Binding var prompt: String
    var mode: CreateMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("\(mode.title) generation prompt")

                if prompt.isEmpty {
                    Text(mode.placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(8)
            .background(
                Color.secondary.opacity(0.08),
                in: .rect(cornerRadius: FlickStyle.controlCornerRadius)
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CreateSettingsValueRow: View {
    var title: String
    var value: String
    var valueLineLimit: Int? = 2

    var body: some View {
        FlickSettingsRow(title: title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(valueLineLimit)
        }
    }
}

private struct CreateMessageRow: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.primary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SlidePreviewRow: View {
    var slide: Slide
    var asset: MediaAsset?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SlideThumbnail(slide: slide, asset: asset)
                .frame(width: 54, height: 96)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Slide \(slide.index + 1)")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text("\(slide.duration.formatted(.number.precision(.fractionLength(1))))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(slide.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(slide.overlayText)
                    .font(.callout)
                    .lineLimit(2)

                Text(slide.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SlideThumbnail: View {
    var slide: Slide
    var asset: MediaAsset?

    var body: some View {
        ZStack {
            if let localFilePath = asset?.localFilePath {
                LocalAssetImage(fileURL: URL(fileURLWithPath: localFilePath))
            } else {
                LinearGradient(
                    colors: [slide.role.tint.opacity(0.65), .black.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Text("\(slide.index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.45), in: .circle)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 6))
    }
}

private let preflightChecks: [QualityCheckItem] = [
    QualityCheckItem(title: "1080 x 1920 aspect ratio", status: .needsReview),
    QualityCheckItem(title: "Readable text contrast", status: .needsReview),
    QualityCheckItem(title: "Supabase public URLs", status: .needsReview),
    QualityCheckItem(title: "TikTok publish settings", status: .needsReview),
    QualityCheckItem(title: "CTA present", status: .needsReview),
    QualityCheckItem(title: "Caption length valid", status: .needsReview)
]

private struct QualityCheckItem: Identifiable {
    var title: String
    var status: QualityCheckStatus

    var id: String { title }
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
}

private extension SlideshowDraft {
    var hashtagDisplayValue: String {
        guard !hashtags.isEmpty else { return "None" }
        return hashtags.map { "#\($0)" }.joined(separator: " ")
    }
}

private extension Array where Element == SocialPlatform {
    var displayNames: String {
        guard !isEmpty else { return "Unassigned" }
        return map(\.displayName).joined(separator: ", ")
    }
}

private extension Array where Element == TrendTag {
    var displayNames: String {
        guard !isEmpty else { return "No tags" }
        return map(\.name).joined(separator: ", ")
    }
}

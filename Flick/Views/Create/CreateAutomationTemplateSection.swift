//
//  CreateAutomationTemplateSection.swift
//  Flick
//

import SwiftUI

struct CreateAutomationTemplateSection: View {
    var templateStore: TemplateLibraryStore
    var localTemplates: [ExampleSlideshowTemplate] = []
    @Binding var selectedTemplateIDs: Set<String>
    @Binding var selectedTemplateNicheIDs: Set<String>
    var selectAction: () -> Void
    var retryAction: () -> Void

    private var summariesByID: [String: ExampleSlideshowCollectionSummary] {
        Dictionary(uniqueKeysWithValues: templateStore.summaries.map { ($0.id, $0) })
    }

    private var selectedNicheSummaries: [ExampleSlideshowCollectionSummary] {
        selectedTemplateNicheIDs
            .compactMap { summariesByID[$0] }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var templatesByID: [String: ExampleSlideshowTemplate] {
        Dictionary(uniqueKeysWithValues: (localTemplates + templateStore.templates).map { ($0.id, $0) })
    }

    private var selectedTemplates: [ExampleSlideshowTemplate] {
        selectedTemplateIDs
            .compactMap { templatesByID[$0] }
            .sorted { $0.subtitle.localizedCaseInsensitiveCompare($1.subtitle) == .orderedAscending }
    }

    private var hasSelection: Bool {
        !selectedTemplateIDs.isEmpty || !selectedTemplateNicheIDs.isEmpty
    }

    private var selectionSummary: String {
        let nicheCount = selectedTemplateNicheIDs.count
        let templateCount = selectedTemplateIDs.count

        switch (nicheCount, templateCount) {
        case (0, 0):
            return templateStore.loadedTemplateCountText
        case (0, 1):
            return "1 selected"
        case (0, _):
            return "\(templateCount) selected"
        case (1, 0):
            return "1 niche"
        case (_, 0):
            return "\(nicheCount) niches"
        default:
            let nicheText = nicheCount == 1 ? "1 niche" : "\(nicheCount) niches"
            let templateText = templateCount == 1 ? "1 template" : "\(templateCount) templates"
            return "\(nicheText), \(templateText)"
        }
    }

    var body: some View {
        Section("Templates") {
            switch templateStore.status {
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading templates")
                        .foregroundStyle(.secondary)
                }
            case let .failed(message):
                CreateMessageRow(
                    title: "Templates unavailable",
                    message: message,
                    actionTitle: "Retry",
                    actionSystemImage: "arrow.clockwise",
                    action: retryAction
                )
            case .loaded:
                if !hasSelection {
                    CreateMessageRow(
                        title: "No templates selected",
                        message: "Select one or more templates. Flick will choose one for each automated post."
                    )
                } else {
                    ForEach(selectedNicheSummaries) { summary in
                        SelectedAutomationNicheRow(summary: summary) {
                            selectedTemplateNicheIDs.remove(summary.id)
                        }
                    }

                    ForEach(selectedTemplates) { template in
                        SelectedAutomationTemplateRow(template: template) {
                            selectedTemplateIDs.remove(template.id)
                        }
                    }
                }

                FlickSettingsActionRow(
                    title: hasSelection ? "Change templates" : "Select templates",
                    systemImage: "rectangle.stack.badge.play",
                    iconColor: FlickStyle.appTint,
                    value: selectionSummary,
                    action: selectAction
                )
            }
        }
    }
}

private struct SelectedAutomationNicheRow: View {
    var summary: ExampleSlideshowCollectionSummary
    var removeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(FlickStyle.appTint)
                .frame(width: 44, height: 44)
                .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("\(summary.slideshowCount) templates")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Remove", systemImage: "xmark.circle", action: removeAction)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SelectedAutomationTemplateRow: View {
    var template: ExampleSlideshowTemplate
    var removeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerticalMediaFrame(
                fileURL: template.displayablePreviewSlide?.localURL,
                remoteURL: template.displayablePreviewSlide?.remoteURL,
                cornerRadius: 8
            )
                .frame(width: 44, height: 78)

            VStack(alignment: .leading, spacing: 4) {
                Text(template.subtitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("@\(template.profile) - \(template.niche)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Remove", systemImage: "xmark.circle", action: removeAction)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

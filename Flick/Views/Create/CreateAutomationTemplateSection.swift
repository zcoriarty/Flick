//
//  CreateAutomationTemplateSection.swift
//  Flick
//

import SwiftUI

struct CreateAutomationTemplateSection: View {
    var loadState: CreateTemplateLoadState
    @Binding var selectedTemplateIDs: Set<String>
    var selectAction: () -> Void
    var retryAction: () -> Void

    private var templatesByID: [String: ExampleSlideshowTemplate] {
        Dictionary(uniqueKeysWithValues: loadState.collections.flatMap(\.templates).map { ($0.id, $0) })
    }

    private var selectedTemplates: [ExampleSlideshowTemplate] {
        selectedTemplateIDs
            .compactMap { templatesByID[$0] }
            .sorted { $0.subtitle.localizedCaseInsensitiveCompare($1.subtitle) == .orderedAscending }
    }

    private var selectableTemplateCount: Int {
        loadState.collections
            .flatMap(\.templates)
            .filter(\.hasDisplayablePreview)
            .count
    }

    var body: some View {
        Section("Templates") {
            switch loadState {
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
                if selectedTemplates.isEmpty {
                    CreateMessageRow(
                        title: "No templates selected",
                        message: "Select one or more templates. Flick will choose one for each automated post."
                    )
                } else {
                    ForEach(selectedTemplates) { template in
                        SelectedAutomationTemplateRow(template: template) {
                            selectedTemplateIDs.remove(template.id)
                        }
                    }
                }

                FlickSettingsActionRow(
                    title: selectedTemplateIDs.isEmpty ? "Select templates" : "Change templates",
                    systemImage: "rectangle.stack.badge.play",
                    iconColor: FlickStyle.appTint,
                    value: selectedTemplateIDs.isEmpty ? "\(selectableTemplateCount) available" : "\(selectedTemplateIDs.count) selected",
                    action: selectAction
                )
            }
        }
    }
}

private struct SelectedAutomationTemplateRow: View {
    var template: ExampleSlideshowTemplate
    var removeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerticalMediaFrame(fileURL: template.displayablePreviewSlide?.localURL, cornerRadius: 8)
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

//
//  CreateTemplateSection.swift
//  Flick
//

import SwiftUI

enum CreateTemplateLoadState {
    case loading
    case loaded([ExampleSlideshowCollection])
    case failed(String)

    var collections: [ExampleSlideshowCollection] {
        guard case let .loaded(collections) = self else { return [] }
        return collections
    }
}

struct CreateTemplateSection: View {
    var loadState: CreateTemplateLoadState
    var selectedTemplate: ExampleSlideshowTemplate?
    var selectAction: () -> Void
    var clearAction: () -> Void
    var retryAction: () -> Void

    private var selectableTemplateCount: Int {
        loadState.collections
            .flatMap(\.templates)
            .filter(\.hasDisplayablePreview)
            .count
    }

    var body: some View {
        Section("Template") {
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
                if let selectedTemplate {
                    SelectedTemplateRow(
                        template: selectedTemplate,
                        clearAction: clearAction
                    )
                }

                FlickSettingsActionRow(
                    title: selectedTemplate == nil ? "Select template" : "Change template",
                    systemImage: "rectangle.stack.badge.play",
                    iconColor: .indigo,
                    value: "\(selectableTemplateCount) available",
                    action: selectAction
                )
            }
        }
    }
}

struct AnalyzeTemplateSection: View {
    var selectedTemplate: ExampleSlideshowTemplate?
    var isPlanning: Bool
    var hasAnalyzedTemplate: Bool
    var action: () -> Void

    var body: some View {
        if selectedTemplate != nil {
            styledButton
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: -16, bottom: 0, trailing: -16))
            .controlSize(.large)
            .disabled(isPlanning)
        }
    }

    @ViewBuilder
    private var styledButton: some View {
        if hasAnalyzedTemplate {
            analyzeButton
                .buttonStyle(.glass)
        } else {
            analyzeButton
                .buttonStyle(.glassProminent)
        }
    }

    private var analyzeButton: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isPlanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: hasAnalyzedTemplate ? "arrow.clockwise" : "wand.and.stars")
                }

                Text(actionTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var actionTitle: String {
        if isPlanning {
            return "Analyzing Template"
        }
        return hasAnalyzedTemplate ? "Redo Analysis" : "Analyze Template"
    }
}

private struct SelectedTemplateRow: View {
    var template: ExampleSlideshowTemplate
    var clearAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VerticalMediaFrame(fileURL: template.displayablePreviewSlide?.localURL, cornerRadius: 8)
                .frame(width: 54, height: 96)

            VStack(alignment: .leading, spacing: 5) {
                Text(template.subtitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("@\(template.profile)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    StatusBadge(title: template.niche, tint: .indigo, systemImage: "tag")
                    Text("\(template.slideCount) slides")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button("Clear", systemImage: "xmark.circle", action: clearAction)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct CreatePlanningProgressRow: View {
    var step: String
    var startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            HStack(spacing: 8) {
                Text(cleanStep)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(elapsedText(at: context.date), systemImage: "timer")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var cleanStep: String {
        step.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func elapsedText(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

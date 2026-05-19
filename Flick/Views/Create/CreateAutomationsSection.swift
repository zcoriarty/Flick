//
//  CreateAutomationsSection.swift
//  Flick
//

import SwiftUI

struct CreateAutomationsSection: View {
    var automations: [ContentAutomation]
    var templates: [ExampleSlideshowTemplate]
    var products: [FlickProduct]
    var editAction: (ContentAutomation) -> Void
    var deleteAction: (ContentAutomation) -> Void

    var body: some View {
        Section("Automations") {
            if automations.isEmpty {
                CreateMessageRow(
                    title: "No automations yet",
                    message: "Publish this setup to save an automation that syncs through iCloud."
                )
            } else {
                ForEach(automations) { automation in
                    Button {
                        editAction(automation)
                    } label: {
                        AutomationRow(
                            automation: automation,
                            templates: templates,
                            products: products
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteAction(automation)
                        }
                    }
                }
            }
        }
    }
}

private extension RelativeDateTimeFormatter {
    static var automationShort: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}

private struct AutomationRow: View {
    var automation: ContentAutomation
    var templates: [ExampleSlideshowTemplate]
    var products: [FlickProduct]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: automation.status == .active ? "calendar.badge.clock" : "pause.circle")
                .foregroundStyle(automation.status == .active ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(automation.displayName(templates: templates, products: products))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(automation.schedule.summary())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let nextScheduledAt = automation.nextScheduledAt {
                    Text("Next post \(RelativeDateTimeFormatter.automationShort.localizedString(for: nextScheduledAt, relativeTo: Date()))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let lastErrorMessage = automation.lastErrorMessage, !lastErrorMessage.isEmpty {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 10)

            StatusBadge(
                title: automation.status.displayName,
                tint: automation.status == .active ? .green : .secondary,
                systemImage: automation.status == .active ? "circle.fill" : "pause.fill"
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

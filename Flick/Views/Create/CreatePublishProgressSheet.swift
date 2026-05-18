//
//  CreatePublishProgressSheet.swift
//  Flick
//

import SwiftUI

struct CreatePublishProgressSheet: View {
    @Environment(\.dismiss) private var dismiss

    var progress: ManualPublishProgress?

    var body: some View {
        NavigationStack {
            List {
                if let progress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.title)
                                .font(.headline)
                                .lineLimit(2)

                            Text("\(progress.completedCount) of \(progress.totalCount) complete")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            ProgressView(value: Double(progress.completedCount), total: Double(max(progress.totalCount, 1)))
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Steps") {
                        ForEach(progress.steps) { step in
                            CreatePublishProgressStepRow(step: step)
                        }
                    }

                    if let errorMessage = progress.errorMessage {
                        Section("Error") {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Starting publish")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("Publishing")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(progress?.isFinished == false)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(progress?.isFinished == false)
    }
}

private struct CreatePublishProgressStepRow: View {
    var step: ManualPublishProgressStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            stateIcon
                .frame(width: 42, height: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.body.weight(.semibold))
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch step.state {
        case .pending:
            Image(systemName: step.systemImage)
                .foregroundStyle(.secondary)
        case .current:
            HStack(spacing: 6) {
                Image(systemName: step.systemImage)
                    .foregroundStyle(.blue)
                ProgressView()
                    .controlSize(.mini)
            }
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }
}

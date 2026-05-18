//
//  CreateDraftsSheet.swift
//  Flick
//

import SwiftUI

struct CreateDraftsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var drafts: [SlideshowDraft]
    var assetsByID: [UUID: MediaAsset]
    var selectedDraftID: UUID?
    var selectAction: (UUID) -> Void
    var deleteAction: (UUID) -> Void

    private var sortedDrafts: [SlideshowDraft] {
        drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedDrafts.isEmpty {
                    Section {
                        CreateMessageRow(
                            title: "No drafts",
                            message: "Unposted drafts will appear here after you create a slideshow plan."
                        )
                    }
                } else {
                    Section("Unposted Drafts") {
                        ForEach(sortedDrafts) { draft in
                            Button {
                                selectAction(draft.id)
                                dismiss()
                            } label: {
                                CreateDraftSummaryRow(
                                    draft: draft,
                                    assetsByID: assetsByID,
                                    isSelected: selectedDraftID == draft.id
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteAction(draft.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("Drafts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CreateDraftSummaryRow: View {
    var draft: SlideshowDraft
    var assetsByID: [UUID: MediaAsset]
    var isSelected: Bool

    private var generatedCount: Int {
        draft.slides.filter { slide in
            guard let imageAssetID = slide.imageAssetID else { return false }
            return slide.generationStatus == .complete && assetsByID[imageAssetID]?.hasAvailableMediaLocation == true
        }.count
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "doc.text")
                .font(.title3)
                .foregroundStyle(isSelected ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 7) {
                Text(draft.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label("\(generatedCount) of \(draft.slides.count)", systemImage: "photo.stack")
                    Text(draft.status.createDisplayName)
                    Text(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !draft.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(draft.topic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension SlideshowDraftStatus {
    var createDisplayName: String {
        switch self {
        case .needsReview:
            "Needs review"
        default:
            rawValue.capitalized
        }
    }
}

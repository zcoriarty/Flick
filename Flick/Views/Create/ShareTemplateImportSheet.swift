//
//  ShareTemplateImportSheet.swift
//  Flick
//

import SwiftUI

struct ShareTemplateImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    var session: ShareImportSession
    var nicheSummaries: [ExampleSlideshowCollectionSummary]
    var isCreating: Bool
    var createAction: (String, String) -> Void
    var discardAction: () -> Void

    @State private var title: String
    @State private var niche: String

    init(
        session: ShareImportSession,
        nicheSummaries: [ExampleSlideshowCollectionSummary],
        isCreating: Bool,
        createAction: @escaping (String, String) -> Void,
        discardAction: @escaping () -> Void
    ) {
        self.session = session
        self.nicheSummaries = nicheSummaries
        self.isCreating = isCreating
        self.createAction = createAction
        self.discardAction = discardAction
        _title = State(initialValue: "")
        _niche = State(initialValue: nicheSummaries.first?.title ?? "Imported")
    }

    var body: some View {
        NavigationStack {
            List {
                photosSection
                detailsSection
            }
            .flickSettingsListStyle()
            .flickToolbarTitle("Import Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        discardAction()
                        dismiss()
                    }
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createAction(title, niche)
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
        }
        .interactiveDismissDisabled(isCreating)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var canCreate: Bool {
        !niche.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.images.isEmpty
    }

    private var photosSection: some View {
        Section("Photos") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(session.images.prefix(18)) { image in
                        LocalAssetImage(fileURL: image.fileURL, contentMode: .fill, maxPixelSize: 360)
                            .frame(width: 74, height: 132)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)

            FlickSettingsValueRow(
                title: "Slides",
                systemImage: "rectangle.stack",
                iconColor: FlickStyle.appTint,
                value: "\(session.images.count)"
            )
        }
    }

    private var detailsSection: some View {
        Section("Template") {
            TextField("Name (optional)", text: $title)

            TextField("Niche", text: $niche)

            if !nicheSummaries.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(nicheSummaries) { summary in
                            Button {
                                niche = summary.title
                            } label: {
                                ShareImportNicheChip(
                                    title: summary.title,
                                    isSelected: niche.caseInsensitiveCompare(summary.title) == .orderedSame
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

}

private struct ShareImportNicheChip: View {
    var title: String
    var isSelected: Bool

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Color.gray.opacity(0.14) : Color.clear)
            )
    }
}

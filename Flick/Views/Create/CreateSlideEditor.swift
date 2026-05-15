//
//  CreateSlideEditor.swift
//  Flick
//

import SwiftUI

struct CreateSlideEditor: View {
    @Binding var draft: SlideshowDraft
    @Binding var selectedSlideID: UUID?
    var assetsByID: [UUID: MediaAsset]
    var isGenerating: Bool
    var moveAction: (UUID, MoveDirection) -> Void
    var duplicateAction: (UUID) -> Void
    var deleteAction: (UUID) -> Void
    var rewritePromptAction: (UUID, String) -> Void
    var regenerateAction: (UUID, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: CreateSlideEditorTab = .text
    @State private var promptRewriteInstruction = ""
    @State private var regenerationInstruction = ""

    var body: some View {
        NavigationStack {
            Form {
                if draft.slides.isEmpty {
                    CreateMessageRow(
                        title: "No slides",
                        message: "This draft does not have any slides to edit."
                    )
                } else if let index = selectedSlideIndex {
                    let slide = draft.slides[index]
                    let focusedAsset = slide.imageAssetID.flatMap { assetsByID[$0] }

                    CreateSlidePreviewPager(
                        slides: sortedSlides,
                        assetsByID: assetsByID,
                        selectedSlideID: $selectedSlideID
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    editorTabPicker
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    switch selectedTab {
                    case .text:
                        CreateSlideTextEditor(slide: $draft.slides[index])
                    case .image:
                        CreateSlideImageEditor(
                            slide: $draft.slides[index],
                            hasImage: focusedAsset != nil,
                            isGenerating: isGenerating,
                            promptRewriteInstruction: $promptRewriteInstruction,
                            regenerationInstruction: $regenerationInstruction,
                            isFirst: sortedSlides.first?.id == slide.id,
                            isLast: sortedSlides.last?.id == slide.id,
                            moveAction: moveAction,
                            duplicateAction: duplicateAction,
                            deleteAction: { slideID in
                                selectedSlideID = nextSlideID(afterDeleting: slideID)
                                deleteAction(slideID)
                                if selectedSlideID == nil {
                                    dismiss()
                                }
                            },
                            rewritePromptAction: rewritePromptAction,
                            regenerateAction: regenerateAction
                        )
                    }
                } else {
                    CreateMessageRow(
                        title: "No slide selected",
                        message: "Select a slide from the rail to edit it."
                    )
                }
            }
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
        }
        .onAppear(perform: focusInitialSlideIfNeeded)
        .onChange(of: selectedSlideID) { _, _ in
            promptRewriteInstruction = ""
            regenerationInstruction = ""
        }
        .onChange(of: slideIDs) { _, _ in
            focusInitialSlideIfNeeded()
        }
    }

    private var editorTabPicker: some View {
        Picker("Edit", selection: $selectedTab) {
            ForEach(CreateSlideEditorTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var editorTitle: String {
        guard let slide = draft.slides.first(where: { $0.id == focusedSlideID }) else {
            return "Slide"
        }
        return "Slide \(slide.index + 1)"
    }

    private var focusedSlideID: UUID? {
        selectedSlideID ?? sortedSlides.first?.id
    }

    private var selectedSlideIndex: Int? {
        guard let focusedSlideID else { return nil }
        return draft.slides.firstIndex { $0.id == focusedSlideID }
    }

    private var sortedSlides: [Slide] {
        draft.slides.sorted { $0.index < $1.index }
    }

    private var slideIDs: [UUID] {
        sortedSlides.map(\.id)
    }

    private func focusInitialSlideIfNeeded() {
        guard !sortedSlides.isEmpty else {
            selectedSlideID = nil
            return
        }

        if let selectedSlideID, slideIDs.contains(selectedSlideID) {
            return
        }
        selectedSlideID = sortedSlides.first?.id
    }

    private func nextSlideID(afterDeleting slideID: UUID) -> UUID? {
        let slides = sortedSlides
        guard let deletedIndex = slides.firstIndex(where: { $0.id == slideID }) else {
            return slides.first?.id
        }

        if slides.count <= 1 {
            return nil
        }

        let nextIndex = slides.index(after: deletedIndex)
        if nextIndex < slides.endIndex {
            return slides[nextIndex].id
        }
        return slides[slides.index(before: deletedIndex)].id
    }
}

private struct CreateSlidePreviewPager: View {
    var slides: [Slide]
    var assetsByID: [UUID: MediaAsset]
    @Binding var selectedSlideID: UUID?

    var body: some View {
        TabView(selection: $selectedSlideID) {
            ForEach(slides) { slide in
                VStack(spacing: 8) {
                    CreateSlidePreviewCanvas(
                        slide: slide,
                        asset: slide.imageAssetID.flatMap { assetsByID[$0] }
                    )
                    .accessibilityLabel("Slide \(slide.index + 1)")

                    CreateSlidePageIndicator(
                        slides: slides,
                        selectedSlideID: $selectedSlideID
                    )
                }
                .tag(Optional(slide.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 226)
    }
}

private struct CreateSlidePageIndicator: View {
    var slides: [Slide]
    @Binding var selectedSlideID: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(slides) { slide in
                Circle()
                    .fill(slide.id == selectedSlideID ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .contentShape(.rect)
                    .onTapGesture {
                        selectedSlideID = slide.id
                    }
                    .accessibilityLabel("Slide \(slide.index + 1)")
                    .accessibilityAddTraits(slide.id == selectedSlideID ? [.isSelected] : [])
            }
        }
        .frame(height: 12)
    }
}

private enum CreateSlideEditorTab: String, CaseIterable, Identifiable {
    case text
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        }
    }
}

private struct CreateSlideTextEditor: View {
    @Binding var slide: Slide

    var body: some View {
        Section("Text") {
            CreateTextEditorRow(
                title: "Headline",
                systemImage: "textformat.size",
                text: $slide.overlayText,
                placeholder: "Main overlay text Flick renders on top.",
                minHeight: 82
            )

            CreateTextEditorRow(
                title: "Supporting",
                systemImage: "text.alignleft",
                text: $slide.supportingText,
                placeholder: "Optional supporting line.",
                minHeight: 58
            )

            CreateTextEditorRow(
                title: "CTA",
                systemImage: "arrow.right.circle",
                text: $slide.ctaText,
                placeholder: "Optional CTA.",
                minHeight: 50
            )
        }

        Section("Style") {
            TextField(
                "Font preset",
                text: Binding(
                    get: { slide.textStyle.fontPreset ?? "" },
                    set: { slide.textStyle.fontPreset = $0 }
                )
            )

            HStack(spacing: 12) {
                TextField("Text color", text: $slide.textStyle.foregroundHex)
                    .textInputAutocapitalization(.never)
                TextField("Backdrop color", text: $slide.textStyle.backgroundHex)
                    .textInputAutocapitalization(.never)
            }

            Picker("Alignment", selection: $slide.textStyle.alignment) {
                Text("Left").tag("left")
                Text("Center").tag("center")
                Text("Right").tag("right")
            }
            .pickerStyle(.segmented)

            CreateSlideLayoutMenuRow(
                title: "Role",
                systemImage: "tag",
                value: slide.role.displayName
            ) {
                ForEach(SlideRole.allCases) { role in
                    Button {
                        slide.role = role
                    } label: {
                        CreateMenuOptionLabel(title: role.displayName, isSelected: slide.role == role)
                    }
                }
            }

            CreateSlideLayoutMenuRow(
                title: "Text position",
                systemImage: "text.alignleft",
                value: slide.textPosition.displayName
            ) {
                ForEach(TextPosition.allCases) { position in
                    Button {
                        slide.textPosition = position
                    } label: {
                        CreateMenuOptionLabel(title: position.displayName, isSelected: slide.textPosition == position)
                    }
                }
            }

            TextField("Text-safe area", text: $slide.textSafeArea, axis: .vertical)
                .lineLimit(1...2)
                .textInputAutocapitalization(.never)

            TextField("Subject area", text: $slide.mainSubjectArea, axis: .vertical)
                .lineLimit(1...2)
                .textInputAutocapitalization(.never)
        }
        .onChange(of: slide.textPosition) { _, newValue in
            if slide.textSafeArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                slide.textSafeArea = newValue.defaultSafeArea
            }
            if slide.mainSubjectArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                slide.mainSubjectArea = newValue.defaultSubjectArea
            }
        }
    }
}

private struct CreateSlideImageEditor: View {
    @Binding var slide: Slide
    var hasImage: Bool
    var isGenerating: Bool
    @Binding var promptRewriteInstruction: String
    @Binding var regenerationInstruction: String
    var isFirst: Bool
    var isLast: Bool
    var moveAction: (UUID, MoveDirection) -> Void
    var duplicateAction: (UUID) -> Void
    var deleteAction: (UUID) -> Void
    var rewritePromptAction: (UUID, String) -> Void
    var regenerateAction: (UUID, String) -> Void

    var body: some View {
        Section("Prompt") {
            CreateTextEditorRow(
                title: "Image prompt",
                systemImage: "photo",
                text: $slide.prompt,
                placeholder: "The exact one-image prompt used for this slide.",
                minHeight: 150
            )

            CreateTextEditorRow(
                title: "Rewrite instruction",
                systemImage: "wand.and.stars",
                text: $promptRewriteInstruction,
                placeholder: "Ask GPT-5.5 to update this slide prompt after your manual edits.",
                minHeight: 70
            )

            Button {
                rewritePromptAction(slide.id, promptRewriteInstruction)
            } label: {
                Label("Rewrite Prompt", systemImage: "sparkles")
            }
            .disabled(promptRewriteInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
        }

        Section("Generation") {
            CreateTextEditorRow(
                title: "Instruction",
                systemImage: "arrow.clockwise",
                text: $regenerationInstruction,
                placeholder: "Example: Make this feel more premium and keep the left side open for text.",
                minHeight: 70
            )

            Button {
                regenerateAction(slide.id, regenerationInstruction)
            } label: {
                Label(regenerationTitle, systemImage: "arrow.clockwise")
            }
            .disabled(isGenerating)

            if let message = slide.generationErrorMessage, !message.isEmpty {
                CreateMessageRow(title: "Generation failed", message: message)
            }
        }

        CreateSlideActionsEditor(
            slide: $slide,
            isFirst: isFirst,
            isLast: isLast,
            moveAction: moveAction,
            duplicateAction: duplicateAction,
            deleteAction: deleteAction
        )
    }

    private var regenerationTitle: String {
        if isGenerating {
            return "Generating"
        }
        return hasImage ? "Regenerate Image" : "Generate This Image"
    }
}

private struct CreateSlideLayoutMenuRow<MenuContent: View>: View {
    var title: String
    var systemImage: String
    var value: String
    @ViewBuilder var menuContent: () -> MenuContent

    var body: some View {
        Menu {
            menuContent()
        } label: {
            FlickSettingsRow(
                title: title,
                systemImage: systemImage,
                iconColor: .indigo
            ) {
                HStack(spacing: 6) {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(value)
    }
}

private struct CreateMenuOptionLabel: View {
    var title: String
    var isSelected: Bool

    var body: some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct CreateSlideActionsEditor: View {
    @Binding var slide: Slide
    var isFirst: Bool
    var isLast: Bool
    var moveAction: (UUID, MoveDirection) -> Void
    var duplicateAction: (UUID) -> Void
    var deleteAction: (UUID) -> Void

    var body: some View {
        Section("Actions") {
            Button {
                moveAction(slide.id, .earlier)
            } label: {
                Label("Move Earlier", systemImage: "arrow.up")
            }
            .disabled(isFirst)

            Button {
                moveAction(slide.id, .later)
            } label: {
                Label("Move Later", systemImage: "arrow.down")
            }
            .disabled(isLast)

            Button {
                duplicateAction(slide.id)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) {
                deleteAction(slide.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isFirst && isLast)
        }
    }
}

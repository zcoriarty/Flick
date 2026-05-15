//
//  CreateSlideEditor.swift
//  Flick
//

import SwiftUI

struct CreateSlideEditor: View {
    @Binding var draft: SlideshowDraft
    var selectedSlideID: UUID?
    var asset: MediaAsset?
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
                if let index = draft.slides.firstIndex(where: { $0.id == selectedSlideID }) {
                    let slide = draft.slides[index]

                    if let asset {
                        Section {
                            CreateSlidePreviewCanvas(slide: slide, asset: asset)
                                .listRowInsets(EdgeInsets())
                        }
                    }

                    Picker("Edit", selection: $selectedTab) {
                        ForEach(CreateSlideEditorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .text:
                        CreateSlideTextEditor(slide: $draft.slides[index])
                    case .image:
                        CreateSlideImageEditor(
                            slide: $draft.slides[index],
                            hasImage: asset != nil,
                            isGenerating: isGenerating,
                            promptRewriteInstruction: $promptRewriteInstruction,
                            regenerationInstruction: $regenerationInstruction,
                            rewritePromptAction: rewritePromptAction,
                            regenerateAction: regenerateAction
                        )
                    case .layout:
                        CreateSlideLayoutEditor(slide: $draft.slides[index])
                    case .actions:
                        CreateSlideActionsEditor(
                            slide: $draft.slides[index],
                            isFirst: index == 0,
                            isLast: index == draft.slides.count - 1,
                            moveAction: moveAction,
                            duplicateAction: duplicateAction,
                            deleteAction: { slideID in
                                deleteAction(slideID)
                                dismiss()
                            }
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
        .onChange(of: selectedSlideID) { _, _ in
            promptRewriteInstruction = ""
            regenerationInstruction = ""
        }
    }

    private var editorTitle: String {
        guard let slide = draft.slides.first(where: { $0.id == selectedSlideID }) else {
            return "Slide"
        }
        return "Slide \(slide.index + 1)"
    }
}

private enum CreateSlideEditorTab: String, CaseIterable, Identifiable {
    case text
    case image
    case layout
    case actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .layout: "Layout"
        case .actions: "Actions"
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
        }
    }
}

private struct CreateSlideImageEditor: View {
    @Binding var slide: Slide
    var hasImage: Bool
    var isGenerating: Bool
    @Binding var promptRewriteInstruction: String
    @Binding var regenerationInstruction: String
    var rewritePromptAction: (UUID, String) -> Void
    var regenerateAction: (UUID, String) -> Void

    var body: some View {
        Section("Prompt") {
            CreateTextEditorRow(
                title: "Image prompt",
                systemImage: "photo.badge.sparkles",
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
    }

    private var regenerationTitle: String {
        if isGenerating {
            return "Generating"
        }
        return hasImage ? "Regenerate Image" : "Generate This Image"
    }
}

private struct CreateSlideLayoutEditor: View {
    @Binding var slide: Slide

    var body: some View {
        Section("Layout") {
            Picker("Role", selection: $slide.role) {
                ForEach(SlideRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }

            Picker("Text position", selection: $slide.textPosition) {
                ForEach(TextPosition.allCases) { position in
                    Text(position.displayName).tag(position)
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

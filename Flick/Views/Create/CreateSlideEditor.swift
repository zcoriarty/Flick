//
//  CreateSlideEditor.swift
//  Flick
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
            .flickToolbarTitle(editorTitle)
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
        pager
            .frame(height: 360)
    }

    @ViewBuilder
    private var pager: some View {
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
        #if !os(macOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
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
    @State private var draftText: String

    init(slide: Binding<Slide>) {
        self._slide = slide
        self._draftText = State(initialValue: slide.wrappedValue.text)
    }

    var body: some View {
        Group {
            Section("Text") {
                CreateTextEditorRow(
                    title: "Text",
                    systemImage: "textformat.size",
                    text: $draftText,
                    placeholder: "Overlay text Flick renders on top.",
                    minHeight: 120
                )

                if hasPendingTextChange {
                    Button {
                        slide.text = draftText
                    } label: {
                        Text("Update Text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
            }

            Section("Style") {
                CreateSlideStyleMenuRow(
                    title: "Font",
                    systemImage: "textformat",
                    value: CreateSlideFontFamily(rawValue: slide.textStyle.fontName)?.title ?? slide.textStyle.fontName
                ) {
                    ForEach(CreateSlideFontFamily.allCases) { fontFamily in
                        Button {
                            slide.textStyle.fontName = fontFamily.rawValue
                        } label: {
                            CreateMenuOptionLabel(
                                title: fontFamily.title,
                                isSelected: slide.textStyle.fontName == fontFamily.rawValue
                            )
                        }
                    }
                }

                CreateSlideStyleMenuRow(
                    title: "Weight",
                    systemImage: "bold",
                    value: CreateSlideFontWeight(rawValue: slide.textStyle.weight)?.title ?? slide.textStyle.weight
                ) {
                    ForEach(CreateSlideFontWeight.allCases) { fontWeight in
                        Button {
                            slide.textStyle.weight = fontWeight.rawValue
                        } label: {
                            CreateMenuOptionLabel(
                                title: fontWeight.title,
                                isSelected: slide.textStyle.weight == fontWeight.rawValue
                            )
                        }
                    }
                }

                CreateSlideSizeSliderRow(
                    value: $slide.textStyle.sizeScale
                )

                CreateSlideColorPickerRow(
                    title: "Text color",
                    systemImage: "paintbrush",
                    hex: $slide.textStyle.foregroundHex
                )

                CreateSlideStyleMenuRow(
                    title: "Border",
                    systemImage: "square",
                    value: CreateSlideTextBorder.value(for: slide.textStyle.outlineColorHex).title
                ) {
                    ForEach(CreateSlideTextBorder.allCases) { border in
                        Button {
                            slide.textStyle.outlineColorHex = border.rawValue
                        } label: {
                            CreateMenuOptionLabel(
                                title: border.title,
                                isSelected: CreateSlideTextBorder.value(for: slide.textStyle.outlineColorHex) == border
                            )
                        }
                    }
                }

                CreateSlideStyleMenuRow(
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
            }
        }
        .onChange(of: slide.id) { _, _ in
            draftText = slide.text
        }
        .onChange(of: slide.text) { oldValue, newValue in
            if draftText == oldValue {
                draftText = newValue
            }
        }
    }

    private var hasPendingTextChange: Bool {
        draftText != slide.text
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

private enum CreateSlideFontFamily: String, CaseIterable, Identifiable {
    case system = "System"
    case rounded = "System Rounded"
    case serif = "Serif"
    case monospaced = "Monospaced"

    var id: String { rawValue }
    var title: String { rawValue }
}

private enum CreateSlideFontWeight: String, CaseIterable, Identifiable {
    case regular = "Regular"
    case medium = "Medium"
    case semibold = "Semibold"
    case bold = "Bold"
    case black = "Black"

    var id: String { rawValue }
    var title: String { rawValue }
}

private enum CreateSlideTextBorder: String, CaseIterable, Identifiable {
    case black = "#000000"
    case white = "#FFFFFF"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Black"
        case .white: "White"
        }
    }

    static func value(for hex: String) -> CreateSlideTextBorder {
        let normalizedHex = hex.uppercased()
        return allCases.first { $0.rawValue == normalizedHex } ?? .black
    }
}

private struct CreateSlideStyleMenuRow<MenuContent: View>: View {
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
                iconColor: FlickStyle.appTint
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

private struct CreateSlideColorPickerRow: View {
    var title: String
    var systemImage: String
    @Binding var hex: String

    var body: some View {
        ColorPicker(
            selection: Binding(
                get: { Color(hex: hex) },
                set: { hex = $0.flickHexString }
            ),
            supportsOpacity: false
        ) {
            FlickSettingsRow(
                title: title,
                systemImage: systemImage,
                iconColor: FlickStyle.appTint
            ) {
                Text(hex.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityValue(hex.uppercased())
    }
}

private struct CreateSlideSizeSliderRow: View {
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlickSettingsRow(
                title: "Size",
                systemImage: "textformat.size",
                iconColor: FlickStyle.appTint
            ) {
                Text(formattedValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: 0.7...1.5, step: 0.05)
                .accessibilityLabel("Text size")
                .accessibilityValue(formattedValue)
        }
    }

    private var formattedValue: String {
        "\(Int((value * 100).rounded()))%"
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

private extension Color {
    var flickHexString: String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#FFFFFF"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
        #else
        return "#FFFFFF"
        #endif
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

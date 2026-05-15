//
//  CreatePlanSection.swift
//  Flick
//

import SwiftUI

struct CreatePlanSection: View {
    @Binding var draft: SlideshowDraft
    @Binding var styleGuideJSON: String

    @State private var presentedSheet: CreatePlanSheet?

    var body: some View {
        Section("Plan") {
            CreatePlanRow(
                title: "Briefing",
                systemImage: "doc.text",
                value: draft.title,
                detail: compactDetail([draft.topic, draft.audience, draft.goal])
            ) {
                presentedSheet = .briefing
            }

            CreatePlanRow(
                title: "Narrative arc",
                systemImage: "arrow.triangle.branch",
                value: draft.narrativeArc.joined(separator: " -> "),
                detail: "\(draft.slides.count) slides"
            ) {
                presentedSheet = .narrativeArc
            }

            CreatePlanRow(
                title: "Summary",
                systemImage: "list.bullet.rectangle",
                value: draft.planSummary,
                detail: draft.globalVisualMotif
            ) {
                presentedSheet = .summary
            }

            CreatePlanRow(
                title: "Style guide",
                systemImage: "paintpalette",
                value: styleGuide.styleName,
                detail: styleGuide.promptSummary
            ) {
                presentedSheet = .styleGuide
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .briefing:
                CreatePlanBriefingSheet(draft: $draft)
            case .narrativeArc:
                CreatePlanTextSheet(
                    title: "Narrative Arc",
                    text: narrativeArcText,
                    placeholder: "Opening -> Detail -> Proof -> Close"
                )
            case .summary:
                CreatePlanTextSheet(
                    title: "Plan Summary",
                    text: $draft.planSummary,
                    placeholder: "Summarize the source-of-truth plan for this carousel."
                )
            case .styleGuide:
                CreateStyleGuideSheet(styleGuide: styleGuideBinding)
            }
        }
    }

    private var styleGuide: TemplateStyleGuide {
        guard
            let data = styleGuideJSON.data(using: .utf8),
            let guide = try? JSONDecoder.flick.decode(TemplateStyleGuide.self, from: data)
        else {
            return .empty
        }
        return guide
    }

    private var styleGuideBinding: Binding<TemplateStyleGuide> {
        Binding(
            get: { styleGuide },
            set: { styleGuideJSON = $0.encodedJSONString() }
        )
    }

    private var narrativeArcText: Binding<String> {
        Binding(
            get: { draft.narrativeArc.joined(separator: " -> ") },
            set: { value in
                draft.narrativeArc = value
                    .components(separatedBy: CharacterSet(charactersIn: "→>,-\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func compactDetail(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private enum CreatePlanSheet: String, Identifiable {
    case briefing
    case narrativeArc
    case summary
    case styleGuide

    var id: String { rawValue }
}

private struct CreatePlanRow: View {
    var title: String
    var systemImage: String
    var value: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var previewText: String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            return value
        }

        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "Tap to edit" : detail
    }
}

private struct CreatePlanBriefingSheet: View {
    @Binding var draft: SlideshowDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    CreatePlainSheetTextField(placeholder: "Title", text: $draft.title)
                    CreatePlainSheetTextField(placeholder: "Topic", text: $draft.topic)
                    CreatePlainSheetTextField(placeholder: "Audience", text: $draft.audience)
                    CreatePlainSheetTextField(placeholder: "Goal", text: $draft.goal)
                    CreatePlainSheetTextField(placeholder: "Tone", text: $draft.tone)
                    CreatePlainSheetTextField(placeholder: "Global visual motif", text: $draft.globalVisualMotif, axis: .vertical)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .background(Color.clear)
            .navigationTitle("Briefing")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CreatePlanTextSheet: View {
    var title: String
    @Binding var text: String
    var placeholder: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CreatePlainSheetTextEditor(text: $text, placeholder: placeholder)
            .navigationTitle(title)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CreateStyleGuideSheet: View {
    @Binding var styleGuide: TemplateStyleGuide
    @State private var editingField: StyleGuideField?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Style") {
                    ForEach(StyleGuideField.styleFields) { field in
                        StyleGuideFieldRow(field: field, styleGuide: styleGuide) {
                            editingField = field
                        }
                    }
                }

                Section("Rules") {
                    ForEach(StyleGuideField.ruleFields) { field in
                        StyleGuideFieldRow(field: field, styleGuide: styleGuide) {
                            editingField = field
                        }
                    }
                }
            }
            .navigationTitle("Style Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingField) { field in
                StyleGuideFieldEditor(field: field, styleGuide: $styleGuide)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct StyleGuideFieldRow: View {
    var field: StyleGuideField
    var styleGuide: TemplateStyleGuide
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: field.systemImage)
                    .foregroundStyle(.indigo)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(field.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(field.preview(in: styleGuide))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct StyleGuideFieldEditor: View {
    var field: StyleGuideField
    @Binding var styleGuide: TemplateStyleGuide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CreatePlainSheetTextEditor(text: textBinding, placeholder: field.placeholder)
            .navigationTitle(field.title)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { field.value(in: styleGuide) },
            set: { field.apply($0, to: &styleGuide) }
        )
    }
}

private struct CreatePlainSheetTextField: View {
    var placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $text, axis: axis)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .lineLimit(axis == .vertical ? 2...5 : 1...1)
                .padding(.vertical, 14)

            Divider()
        }
    }
}

private struct CreatePlainSheetTextEditor: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 21)
                    .padding(.top, 20)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.clear)
    }
}

private enum StyleGuideField: String, CaseIterable, Identifiable {
    case styleName
    case visualTraits
    case colorPalette
    case lighting
    case recurringMotifs
    case reuseStructurally
    case avoidCopyingDirectly
    case imageGenerationRules

    var id: String { rawValue }

    static let styleFields: [StyleGuideField] = [
        .styleName,
        .visualTraits,
        .colorPalette,
        .lighting,
        .recurringMotifs
    ]

    static let ruleFields: [StyleGuideField] = [
        .reuseStructurally,
        .avoidCopyingDirectly,
        .imageGenerationRules
    ]

    var title: String {
        switch self {
        case .styleName: "Style name"
        case .visualTraits: "Visual traits"
        case .colorPalette: "Color palette"
        case .lighting: "Lighting"
        case .recurringMotifs: "Motifs"
        case .reuseStructurally: "Reuse structurally"
        case .avoidCopyingDirectly: "Avoid copying"
        case .imageGenerationRules: "Image rules"
        }
    }

    var systemImage: String {
        switch self {
        case .styleName: "sparkles"
        case .visualTraits: "eye"
        case .colorPalette: "paintpalette"
        case .lighting: "sun.max"
        case .recurringMotifs: "circle.hexagongrid"
        case .reuseStructurally: "rectangle.stack"
        case .avoidCopyingDirectly: "hand.raised"
        case .imageGenerationRules: "photo.badge.checkmark"
        }
    }

    var placeholder: String {
        isList ? "Enter one item per line." : "Enter \(title.lowercased())."
    }

    var isList: Bool {
        switch self {
        case .visualTraits,
             .colorPalette,
             .recurringMotifs,
             .reuseStructurally,
             .avoidCopyingDirectly,
             .imageGenerationRules:
            true
        default:
            false
        }
    }

    func preview(in guide: TemplateStyleGuide) -> String {
        let value = value(in: guide)
            .replacingOccurrences(of: "\n", with: " • ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Tap to edit" : value
    }

    func value(in guide: TemplateStyleGuide) -> String {
        switch self {
        case .styleName: guide.styleName
        case .visualTraits: guide.visualTraits.joined(separator: "\n")
        case .colorPalette: guide.colorPalette.joined(separator: "\n")
        case .lighting: guide.lighting
        case .recurringMotifs: guide.recurringMotifs.joined(separator: "\n")
        case .reuseStructurally: guide.reuseStructurally.joined(separator: "\n")
        case .avoidCopyingDirectly: guide.avoidCopyingDirectly.joined(separator: "\n")
        case .imageGenerationRules: guide.imageGenerationRules.joined(separator: "\n")
        }
    }

    func apply(_ value: String, to guide: inout TemplateStyleGuide) {
        switch self {
        case .styleName:
            guide.styleName = value
        case .visualTraits:
            guide.visualTraits = lines(from: value)
        case .colorPalette:
            guide.colorPalette = lines(from: value)
        case .lighting:
            guide.lighting = value
        case .recurringMotifs:
            guide.recurringMotifs = lines(from: value)
        case .reuseStructurally:
            guide.reuseStructurally = lines(from: value)
        case .avoidCopyingDirectly:
            guide.avoidCopyingDirectly = lines(from: value)
        case .imageGenerationRules:
            guide.imageGenerationRules = lines(from: value)
        }
    }

    private func lines(from value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

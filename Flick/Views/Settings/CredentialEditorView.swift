//
//  CredentialEditorView.swift
//  Flick
//

import SwiftUI

struct CredentialEditorDraft: Identifiable, Hashable {
    var id: String { definition.id }
    var definition: CredentialDefinition
    var value: String
    var originalValue: String
    var source: CredentialStatus.Source
    var isStoredSecurely: Bool

    var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasChanges: Bool {
        trimmedValue != originalValue
    }

    var canSave: Bool {
        !trimmedValue.isEmpty && hasChanges
    }
}

struct CredentialEditorView: View {
    @Binding var drafts: [CredentialEditorDraft]
    var saveAction: (CredentialEditorDraft) -> Void
    var deleteAction: (CredentialEditorDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach($drafts) { $draft in
                CredentialEditorRow(
                    draft: $draft,
                    saveAction: {
                        saveAction(draft)
                    },
                    deleteAction: {
                        deleteAction(draft)
                    }
                )
            }
        }
    }
}

struct CredentialEditorRow: View {
    @Binding var draft: CredentialEditorDraft
    @State private var isValueVisible = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isEditing = false

    var saveAction: () -> Void
    var deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.definition.name)
                        .font(.callout.weight(.semibold))
                    Text(draft.definition.key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                StatusBadge(
                    title: draft.source.rawValue,
                    tint: draft.source.tint,
                    systemImage: draft.source.systemImage
                )
            }

            CredentialValueField(
                title: draft.definition.name,
                value: $draft.value,
                isValueVisible: $isValueVisible,
                isEditing: isEditing,
                editAction: toggleEditing
            )

            if isEditing {
                actionButtons
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: isEditing)
        .onChange(of: draft.originalValue) { _, _ in
            isEditing = false
        }
        .accessibilityElement(children: .contain)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(CredentialCapsuleButtonStyle(tint: .red))
            .disabled(!draft.isStoredSecurely)
            .confirmationDialog("Delete \(draft.definition.name)?", isPresented: $isDeleteConfirmationPresented) {
                Button("Delete", role: .destructive, action: deleteAction)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the Keychain value for \(draft.definition.key).")
            }

            Button(action: saveAction) {
                Label("Save", systemImage: "checkmark")
            }
                .buttonStyle(CredentialCapsuleButtonStyle(tint: .blue))
                .disabled(!draft.canSave)
        }
    }

    private func toggleEditing() {
        isEditing.toggle()
    }
}

private struct CredentialValueField: View {
    var title: String
    @Binding var value: String
    @Binding var isValueVisible: Bool
    var isEditing: Bool
    var editAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            valueField

            Button(action: editAction) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isEditing ? .blue : .secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEditing ? "Stop editing \(title)" : "Edit \(title)")
        }
    }

    private var valueField: some View {
        HStack(spacing: 8) {
            Group {
                if isValueVisible {
                    TextField("Value", text: $value)
                } else {
                    SecureField("Value", text: $value)
                }
            }
            .font(.system(.callout, design: .monospaced))
            .credentialEditorInputBehavior()
            .disabled(!isEditing)
            .accessibilityLabel("\(title) value")
            .accessibilityHint(isEditing ? "Editing enabled" : "Tap Edit to change this value")

            Button {
                isValueVisible.toggle()
            } label: {
                Image(systemName: isValueVisible ? "eye.slash" : "eye")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isValueVisible ? "Hide \(title)" : "Show \(title)")
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            .background.opacity(0.35),
            in: RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius, style: .continuous)
        )
    }
}

private struct CredentialCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                tint.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.55),
                in: Capsule()
            )
    }
}

extension View {
    @ViewBuilder
    func credentialEditorInputBehavior() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
            .autocorrectionDisabled()
        #endif
    }
}

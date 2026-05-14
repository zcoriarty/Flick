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
        FlickGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Label("Stored credential editor", systemImage: "key.fill")
                        .font(.headline)
                    Spacer()
                    StatusBadge(title: "\(storedCount) stored", tint: .blue, systemImage: "lock.fill")
                }

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
    }

    private var storedCount: Int {
        drafts.filter(\.isStoredSecurely).count
    }
}

private struct CredentialEditorRow: View {
    @Binding var draft: CredentialEditorDraft
    @State private var isValueVisible = false
    @State private var isDeleteConfirmationPresented = false

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
                isValueVisible: $isValueVisible
            )

            ViewThatFits(in: .horizontal) {
                horizontalFooter
                verticalFooter
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var horizontalFooter: some View {
        HStack(spacing: 8) {
            StatusBadge(title: draft.definition.storagePolicy.rawValue, tint: draft.definition.storagePolicy.tint, systemImage: "lock.shield")
            Spacer(minLength: 8)
            actionButtons
        }
    }

    private var verticalFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(title: draft.definition.storagePolicy.rawValue, tint: draft.definition.storagePolicy.tint, systemImage: "lock.shield")
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                isDeleteConfirmationPresented = true
            }
                .disabled(!draft.isStoredSecurely)
                .confirmationDialog("Delete \(draft.definition.name)?", isPresented: $isDeleteConfirmationPresented) {
                    Button("Delete", role: .destructive, action: deleteAction)
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This removes the Keychain value for \(draft.definition.key).")
                }

            Button("Save", systemImage: "checkmark", action: saveAction)
                .buttonStyle(.glassProminent)
                .disabled(!draft.canSave)
        }
    }
}

private struct CredentialValueField: View {
    var title: String
    @Binding var value: String
    @Binding var isValueVisible: Bool

    var body: some View {
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
            .accessibilityLabel("\(title) value")

            Button {
                isValueVisible.toggle()
            } label: {
                Image(systemName: isValueVisible ? "eye.slash" : "eye")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isValueVisible ? "Hide \(title)" : "Show \(title)")
        }
        .padding(10)
        .background(
            .background.opacity(0.35),
            in: RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius, style: .continuous)
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

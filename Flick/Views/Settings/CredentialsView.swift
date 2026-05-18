//
//  CredentialsView.swift
//  Flick
//

import SwiftUI

struct CredentialsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var credentialDrafts: [CredentialEditorDraft] = []
    @State private var isClearCredentialsConfirmationPresented = false

    var body: some View {
        List {
            Section("Credentials") {
                if let credentialMessage = appModel.credentialMessage {
                    SettingsMessageRow(title: "Credential status", message: credentialMessage)
                }

                ForEach($credentialDrafts) { $draft in
                    CredentialEditorRow(
                        draft: $draft,
                        saveAction: {
                            saveCredential(draft)
                        },
                        deleteAction: {
                            deleteCredential(draft)
                        }
                    )
                }

                Button("Clear stored credentials", role: .destructive) {
                    isClearCredentialsConfirmationPresented = true
                }
                .confirmationDialog("Clear stored credentials?", isPresented: $isClearCredentialsConfirmationPresented) {
                    Button("Clear stored", role: .destructive) {
                        clearStoredCredentials()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This removes every credential Flick has stored in Keychain.")
                }
            }
        }
        .flickSettingsListStyle()
        .flickToolbarTitle("Credentials")
        .onAppear(perform: reloadCredentialDrafts)
    }

    private func clearStoredCredentials() {
        if appModel.clearStoredCredentials() {
            reloadCredentialDrafts()
        }
    }

    private func saveCredential(_ draft: CredentialEditorDraft) {
        if appModel.storeCredentialValue(draft.trimmedValue, for: draft.definition.key) {
            reloadCredentialDrafts()
        }
    }

    private func deleteCredential(_ draft: CredentialEditorDraft) {
        if appModel.deleteStoredCredential(for: draft.definition.key) {
            reloadCredentialDrafts()
        }
    }

    private func reloadCredentialDrafts() {
        let keychainValues = appModel.secureCredentialValues()

        credentialDrafts = CredentialDefinition.supported.map { definition in
            let storedValue = keychainValues[definition.key] ?? ""
            return CredentialEditorDraft(
                definition: definition,
                value: storedValue,
                originalValue: storedValue,
                source: storedValue.isEmpty ? .missing : .secureStore,
                isStoredSecurely: keychainValues[definition.key] != nil
            )
        }
    }
}

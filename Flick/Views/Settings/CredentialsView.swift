//
//  CredentialsView.swift
//  Flick
//

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct CredentialsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var credentialDrafts: [CredentialEditorDraft] = []
    @State private var credentialsExportDocument = CredentialExportDocument(values: [:])
    @State private var isClearCredentialsConfirmationPresented = false
    @State private var isCredentialImportPresented = false

    var body: some View {
        List {
            Section {
                if let credentialMessage = appModel.credentialMessage {
                    SettingsMessageRow(title: "Credential status", message: credentialMessage)
                }

                ForEach($credentialDrafts) { $draft in
                    CredentialEditorRow(
                        draft: $draft,
                        saveAction: {
                            Task {
                                await saveCredential(draft)
                            }
                        },
                        deleteAction: {
                            Task {
                                await deleteCredential(draft)
                            }
                        }
                    )
                }

                Button("Clear stored credentials", role: .destructive) {
                    isClearCredentialsConfirmationPresented = true
                }
                .confirmationDialog("Clear stored credentials?", isPresented: $isClearCredentialsConfirmationPresented) {
                    Button("Clear stored", role: .destructive) {
                        Task {
                            await clearStoredCredentials()
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This removes every credential Flick has stored in Keychain.")
                }
            } header: {
                Text("Credentials")
            } footer: {
                Text("Credentials are stored in this device's Keychain and do not automatically sync between iPhone and Mac. Use Import and Export to copy them between devices.")
            }
        }
        .flickSettingsListStyle()
        .flickToolbarTitle("Credentials")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Import", systemImage: "square.and.arrow.down") {
                    isCredentialImportPresented = true
                }
                exportButton
            }
        }
        .sheet(isPresented: $isCredentialImportPresented, onDismiss: reloadCredentialDrafts) {
            CredentialImportView()
        }
        .onAppear(perform: reloadCredentialDrafts)
    }

    @ViewBuilder
    private var exportButton: some View {
        ShareLink(
            item: credentialsExportDocument,
            subject: Text("Flick Credentials"),
            preview: SharePreview("flick-credentials.json")
        ) {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(credentialsExportDocument.isEmpty)
        .accessibilityHint(credentialsExportDocument.isEmpty ? "No stored credentials to export" : "Exports stored credentials as JSON")
    }

    private func clearStoredCredentials() async {
        if await appModel.clearStoredCredentials() {
            reloadCredentialDrafts()
        }
    }

    private func saveCredential(_ draft: CredentialEditorDraft) async {
        if await appModel.storeCredentialValue(draft.trimmedValue, for: draft.definition.key) {
            reloadCredentialDrafts()
        }
    }

    private func deleteCredential(_ draft: CredentialEditorDraft) async {
        if await appModel.deleteStoredCredential(for: draft.definition.key) {
            reloadCredentialDrafts()
        }
    }

    private func reloadCredentialDrafts() {
        let keychainValues = appModel.secureCredentialValues()
        credentialsExportDocument = CredentialExportDocument(values: keychainValues)
        if credentialsExportDocument.isEmpty {
            try? CredentialExportDocument.removeTemporaryFile()
        }

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

struct CredentialExportDocument: Transferable, Hashable {
    var values: [String: String]

    var isEmpty: Bool {
        values.isEmpty
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { document in
            SentTransferredFile(try document.writeTemporaryFile())
        }
    }

    func jsonData() throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: values,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(contentsOf: [0x0A])
        return data
    }

    func writeTemporaryFile() throws -> URL {
        try Self.removeTemporaryFile()
        try FileManager.default.createDirectory(at: Self.exportDirectory, withIntermediateDirectories: true)

        let exportURL = Self.exportFileURL
        try jsonData().write(to: exportURL, options: .atomic)
        return exportURL
    }

    private static var exportDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FlickCredentialExports", isDirectory: true)
    }

    private static var exportFileURL: URL {
        exportDirectory.appendingPathComponent("flick-credentials.json")
    }

    static func removeTemporaryFile() throws {
        guard FileManager.default.fileExists(atPath: exportFileURL.path) else { return }
        try FileManager.default.removeItem(at: exportFileURL)
    }
}

//
//  CredentialImportView.swift
//  Flick
//

import SwiftUI
import UniformTypeIdentifiers

struct CredentialImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FlickAppModel.self) private var appModel
    @State private var errorMessage: String?
    @State private var isFileImporterPresented = false
    @State private var isImporting = false
    @State private var jsonText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste a Flick credential export or choose its JSON file. Existing values are replaced only for keys in the JSON; all other credentials stay unchanged.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                credentialEditor

                VStack(alignment: .leading, spacing: 6) {
                    Button("Choose JSON File", systemImage: "doc.badge.plus") {
                        isFileImporterPresented = true
                    }

                    Text("Unsupported keys and empty values are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Import error: \(errorMessage)")
                }
            }
            .padding()
            .frame(idealWidth: 560, idealHeight: 480)
            .navigationTitle("Import Credentials")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: importCredentials) {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(trimmedJSONText.isEmpty || isImporting)
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
    }

    private var credentialEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $jsonText)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .credentialEditorInputBehavior()

            if jsonText.isEmpty {
                Text("{\n  \"OPENAI_API_KEY\": \"…\",\n  \"R2_BUCKET\": \"…\"\n}")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(8)
        .frame(minHeight: 260)
        .background(
            .background.opacity(0.35),
            in: .rect(cornerRadius: FlickStyle.controlCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        }
        .accessibilityLabel("Credential JSON")
    }

    private var trimmedJSONText: String {
        jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func importCredentials() {
        errorMessage = nil

        let document: CredentialImportDocument
        do {
            document = try CredentialImportDocument(jsonText: trimmedJSONText)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isImporting = true
        Task {
            defer { isImporting = false }
            if await appModel.importCredentialValues(document.values) != nil {
                dismiss()
            } else {
                errorMessage = appModel.lastErrorMessage ?? "Flick could not import the credentials."
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                throw CredentialImportFileError.accessDenied
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            _ = try CredentialImportDocument(data: data)
            guard let text = String(data: data, encoding: .utf8) else {
                throw CredentialImportFileError.invalidTextEncoding
            }

            jsonText = text
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum CredentialImportFileError: LocalizedError {
    case accessDenied
    case invalidTextEncoding

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Flick could not access the selected JSON file."
        case .invalidTextEncoding:
            "The selected JSON file must use UTF-8 text encoding."
        }
    }
}

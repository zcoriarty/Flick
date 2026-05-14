//
//  SettingsView.swift
//  Flick
//

import SwiftUI

struct SettingsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var credentialDrafts: [CredentialEditorDraft] = []
    @State private var isClearCredentialsConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
            credentials
            storage
            workerRole
            diagnostics
        }
        .flickScrollablePage()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
            }
        }
        .onAppear(perform: reloadCredentialDrafts)
        
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Credentials", subtitle: "Edit and store credentials directly in Keychain", systemImage: "key")

            FlickGlassCard {
                HStack(alignment: .top, spacing: 12) {
                    HStack(alignment: .top) {
                        Label("Keychain credentials", systemImage: "lock.shield")
                            .font(.headline)
                        StatusBadge(title: "\(appModel.configuration.secureStoredCredentialKeys.count) stored", tint: .blue, systemImage: "key.fill")
                    }
                    Spacer(minLength: 12)
                    Button("Clear stored", systemImage: "trash", role: .destructive) {
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

            if let credentialMessage = appModel.credentialMessage {
                Text(credentialMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CredentialEditorView(
                drafts: $credentialDrafts,
                saveAction: saveCredential,
                deleteAction: deleteCredential
            )
        }
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
        let secureValues = appModel.secureCredentialValues()
        let statusesByKey = Dictionary(uniqueKeysWithValues: appModel.configuration.credentialStatuses.map { ($0.key, $0) })

        credentialDrafts = CredentialDefinition.supported.map { definition in
            let storedValue = secureValues[definition.key] ?? ""
            let source = statusesByKey[definition.key]?.source ?? (storedValue.isEmpty ? .missing : .secureStore)
            return CredentialEditorDraft(
                definition: definition,
                value: storedValue,
                originalValue: storedValue,
                source: source,
                isStoredSecurely: secureValues[definition.key] != nil
            )
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Supabase storage", subtitle: "Workspace-scoped media buckets and URL strategy", systemImage: "externaldrive.badge.icloud")
            FlickGlassCard {
                ResponsiveGrid(minimum: 230) {
                    BucketRow(name: appModel.configuration.storageBuckets.generatedImages, purpose: "Generated slideshow images")
                    BucketRow(name: appModel.configuration.storageBuckets.renderedVideos, purpose: "Rendered MP4 exports")
                    BucketRow(name: appModel.configuration.storageBuckets.referenceImages, purpose: "Trend and reference uploads")
                    BucketRow(name: appModel.configuration.storageBuckets.thumbnails, purpose: "Queue and analytics previews")
                }
            }
        }
    }

    private var workerRole: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Worker role", subtitle: "Mac executes autonomous scheduled work; iPhone monitors and approves", systemImage: "desktopcomputer.and.macbook")
            if appModel.overview.devices.isEmpty {
                FlickEmptyStateCard(
                    title: "No devices registered",
                    message: "Device registration will appear here after the app persists real device identity and worker capability state.",
                    systemImage: "desktopcomputer.and.macbook"
                )
            } else {
                ResponsiveGrid(minimum: 280) {
                    ForEach(appModel.overview.devices) { device in
                        FlickGlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(device.name)
                                        .font(.headline)
                                    Spacer()
                                    StatusBadge(title: device.platform.rawValue, tint: device.isPrimaryWorker ? .green : .blue, systemImage: "circle.fill")
                                }
                                Text(device.capabilities.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Diagnostics", subtitle: "CloudKit, worker, publishing, Supabase, and cleanup logs", systemImage: "stethoscope")
            FlickGlassCard {
                ResponsiveGrid(minimum: 230) {
                    DiagnosticRow(title: "CloudKit sync", value: "\(appModel.overview.dashboard.syncHealth.pendingChanges) pending changes", systemImage: "icloud")
                    DiagnosticRow(title: "Render directory", value: appModel.configuration.renderDirectory.path(percentEncoded: false), systemImage: "folder")
                    DiagnosticRow(title: "Primary worker", value: appModel.overview.dashboard.workerStatus.isOnline ? "Online" : "Offline", systemImage: "desktopcomputer")
                    DiagnosticRow(title: "Notifications", value: "Approval, failure, token, analytics, and worker alerts", systemImage: "bell")
                }
            }
        }
    }
}

private struct BucketRow: View {
    var name: String
    var purpose: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.callout.weight(.semibold))
            Text(purpose)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiagnosticRow: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.purple)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(3)
            }
        }
    }
}

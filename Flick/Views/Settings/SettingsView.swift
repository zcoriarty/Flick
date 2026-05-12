//
//  SettingsView.swift
//  Flick
//

import SwiftUI

struct SettingsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var credentialPasteText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                credentials
                storage
                workerRole
                diagnostics
            }
            .flickScrollablePage()
            .navigationTitle("Settings")
        }
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Credentials", subtitle: "Paste env vars once and store them in Keychain", systemImage: "key")

            FlickGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Label("Secure credential import", systemImage: "lock.shield")
                            .font(.headline)
                        Spacer()
                        StatusBadge(title: "\(appModel.configuration.secureStoredCredentialKeys.count) stored", tint: .blue, systemImage: "key.fill")
                    }

                    TextEditor(text: $credentialPasteText)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 150)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .credentialEditorInputBehavior()
                        .background(
                            .background.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius, style: .continuous)
                        )
                        .accessibilityLabel("Paste environment variables")

                    HStack {
                        Button("Store securely", systemImage: "lock") {
                            appModel.storeCredentialEnvironment(credentialPasteText)
                            credentialPasteText = ""
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(credentialPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear stored", systemImage: "trash", role: .destructive) {
                            appModel.clearStoredCredentials()
                        }
                        .buttonStyle(.glass)

                        Spacer()

                        if let credentialMessage = appModel.credentialMessage {
                            Text(credentialMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ResponsiveGrid(minimum: 270) {
                ForEach(appModel.configuration.credentialStatuses) { status in
                    FlickGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(status.name)
                                    .font(.headline)
                                Spacer()
                                StatusBadge(title: status.isPresent ? "Found" : "Missing", tint: status.isPresent ? .green : .orange, systemImage: status.isPresent ? "checkmark.circle" : "exclamationmark.circle")
                            }
                            StatusBadge(title: status.source.rawValue, tint: status.source.tint, systemImage: status.source.systemImage)
                            StatusBadge(title: status.storagePolicy.rawValue, tint: status.storagePolicy.tint, systemImage: "lock.shield")
                        }
                    }
                }
            }
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

private extension CredentialStatus.Source {
    var tint: Color {
        switch self {
        case .secureStore: .blue
        case .localEnvironment: .orange
        case .missing: .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .secureStore: "lock.fill"
        case .localEnvironment: "doc.text"
        case .missing: "minus.circle"
        }
    }
}

private extension View {
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

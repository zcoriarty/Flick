//
//  MacSettingsView.swift
//  Flick
//

#if os(macOS) || targetEnvironment(macCatalyst)
import SwiftUI

struct MacSettingsView: View {
    @Environment(FlickAppModel.self) private var appModel
    @State private var selectedPanel: MacSettingsPanel = .credentials

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            sidebar
                .frame(width: 260)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .macWorkspacePage()
        .navigationTitle("Settings")
    }

    private var sidebar: some View {
        MacWorkspacePanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                VStack(spacing: 8) {
                    ForEach(MacSettingsPanel.allCases) { panel in
                        MacSettingsSidebarButton(
                            panel: panel,
                            isSelected: selectedPanel == panel
                        ) {
                            selectedPanel = panel
                        }
                    }
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    MacDetailRow(
                        title: "Credentials",
                        value: appModel.configuration.secureStoredCredentialKeys.count.formatted()
                    )
                    MacDetailRow(
                        title: "iCloud",
                        value: appModel.overview.dashboard.syncHealth.iCloudAvailable ? "Available" : "Unavailable"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedPanel {
        case .credentials:
            CredentialsView()
                .frame(minHeight: 520)
        case .storage:
            MacStorageSettingsDetail(
                configuration: appModel.configuration,
                isRunning: appModel.isR2SmokeTestRunning,
                result: appModel.r2SmokeTestResult,
                errorMessage: appModel.r2SmokeTestErrorMessage,
                runAction: runR2SmokeTest
            )
        case .diagnostics:
            MacDiagnosticsSettingsDetail(
                iCloudAvailable: appModel.overview.dashboard.syncHealth.iCloudAvailable,
                renderDirectory: appModel.configuration.renderDirectory
            )
        }
    }

    private func runR2SmokeTest() {
        Task {
            await appModel.runR2SmokeTest()
        }
    }
}

private enum MacSettingsPanel: String, CaseIterable, Identifiable {
    case credentials
    case storage
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .credentials: "Credentials"
        case .storage: "R2 Storage"
        case .diagnostics: "Diagnostics"
        }
    }

    var subtitle: String {
        switch self {
        case .credentials: "Keychain values"
        case .storage: "Buckets and paths"
        case .diagnostics: "Local app state"
        }
    }

    var systemImage: String {
        switch self {
        case .credentials: "lock.shield"
        case .storage: "externaldrive"
        case .diagnostics: "stethoscope"
        }
    }
}

private struct MacSettingsSidebarButton: View {
    var panel: MacSettingsPanel
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: panel.systemImage)
                    .foregroundStyle(isSelected ? FlickStyle.appTint : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(panel.title)
                        .font(.callout.weight(.semibold))
                    Text(panel.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? FlickStyle.appTint.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct MacStorageSettingsDetail: View {
    var configuration: AppConfiguration
    var isRunning: Bool
    var result: R2StorageSmokeTestResult?
    var errorMessage: String?
    var runAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            MacWorkspaceHeader(
                title: "R2 Storage",
                subtitle: "Verify upload access and inspect the paths used for product media, generated images, rendered posts, references, and thumbnails."
            )

            MacR2SmokeTestPanel(
                isRunning: isRunning,
                result: result,
                errorMessage: errorMessage,
                action: runAction
            )

            MacWorkspaceSection(title: "Connection", systemImage: "network") {
                MacWorkspacePanel {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        MacDetailRow(title: "Bucket", value: configuration.r2.bucket ?? "Not configured", valueLineLimit: nil)
                        MacDetailRow(title: "Public URL", value: configuration.r2.publicBaseURL?.absoluteString ?? "Not configured", valueLineLimit: nil)
                        MacDetailRow(title: "S3 endpoint", value: configuration.r2.endpointURL?.absoluteString ?? "Not configured", valueLineLimit: nil)
                    }
                }
            }

            MacWorkspaceSection(title: "Storage Paths", systemImage: "folder") {
                MacWorkspacePanel {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        MacDetailRow(title: "Product media", value: configuration.storagePaths.productMedia, valueLineLimit: nil)
                        MacDetailRow(title: "Generated", value: configuration.storagePaths.generatedImages, valueLineLimit: nil)
                        MacDetailRow(title: "Rendered", value: configuration.storagePaths.renderedImages, valueLineLimit: nil)
                        MacDetailRow(title: "References", value: configuration.storagePaths.referenceImages, valueLineLimit: nil)
                        MacDetailRow(title: "Thumbnails", value: configuration.storagePaths.thumbnails, valueLineLimit: nil)
                    }
                }
            }
        }
    }
}

private struct MacR2SmokeTestPanel: View {
    var isRunning: Bool
    var result: R2StorageSmokeTestResult?
    var errorMessage: String?
    var action: () -> Void

    var body: some View {
        MacWorkspacePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Smoke Test", systemImage: "checkmark.seal")
                        .font(.headline)
                        .foregroundStyle(statusTint)
                    Spacer(minLength: 12)
                    StatusBadge(title: statusTitle, tint: statusTint, systemImage: statusSystemImage)
                    Button(isRunning ? "Testing" : "Run Test", systemImage: isRunning ? "clock" : "play.fill", action: action)
                        .buttonStyle(.glassProminent)
                        .disabled(isRunning)
                }

                if let result {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        MacDetailRow(title: "Result", value: result.diagnosticMessages.joined(separator: "\n"), valueLineLimit: nil)
                        MacDetailRow(title: "Object", value: "\(result.bucket)/\(result.path)", valueLineLimit: nil)
                        MacDetailRow(title: "Public URL", value: "\(result.publicURLAccessText): \(result.publicURL.absoluteString)", valueLineLimit: nil)
                        MacDetailRow(title: "Signed URL", value: "\(result.signedURLAccessText), expires \(result.signedURLExpiration.formatted(date: .abbreviated, time: .shortened))", valueLineLimit: nil)
                    }
                } else if let errorMessage {
                    SettingsMessageRow(title: "R2 test failed", message: errorMessage)
                } else {
                    Text("Run the smoke test to confirm writes, public reads, signed URLs, and cleanup against the configured bucket.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusTitle: String {
        if isRunning { return "Testing" }
        if errorMessage != nil { return "Fail" }
        guard let result else { return "Idle" }
        return result.isSuccessful ? "Pass" : "Check"
    }

    private var statusTint: Color {
        if isRunning { return .blue }
        if errorMessage != nil { return .red }
        guard let result else { return .secondary }
        return result.isSuccessful ? .green : .orange
    }

    private var statusSystemImage: String {
        if isRunning { return "clock" }
        if errorMessage != nil { return "xmark.circle.fill" }
        guard let result else { return "circle" }
        return result.isSuccessful ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
}

private struct MacDiagnosticsSettingsDetail: View {
    var iCloudAvailable: Bool
    var renderDirectory: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            MacWorkspaceHeader(
                title: "Diagnostics",
                subtitle: "Local sync and render state for this Mac.",
                metrics: [
                    MacWorkspaceMetric(title: "iCloud", value: iCloudAvailable ? "Available" : "Unavailable")
                ]
            )

            MacWorkspacePanel {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    MacDetailRow(title: "iCloud account", value: iCloudAvailable ? "Available" : "Unavailable")
                    MacDetailRow(title: "Render directory", value: renderDirectory.path(percentEncoded: false), valueLineLimit: nil)
                }
            }
        }
    }
}
#endif

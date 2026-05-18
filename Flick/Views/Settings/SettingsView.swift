//
//  SettingsView.swift
//  Flick
//

import SwiftUI

struct SettingsView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        List {
            credentialsSection
            storageSection
            workerRoleSection
            diagnosticsSection
        }
        .flickSettingsListStyle()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.system(.body, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var credentialsSection: some View {
        Section {
            CredentialsNavigationRow(storedCount: appModel.configuration.secureStoredCredentialKeys.count)
        }
    }

    private var storageSection: some View {
        Section("Cloudflare R2 storage") {
            R2SmokeTestRow(
                isRunning: appModel.isR2SmokeTestRunning,
                result: appModel.r2SmokeTestResult,
                errorMessage: appModel.r2SmokeTestErrorMessage,
                action: runR2SmokeTest
            )

            if let result = appModel.r2SmokeTestResult {
                R2SmokeTestDetailRow(result: result)
            } else if let errorMessage = appModel.r2SmokeTestErrorMessage {
                SettingsMessageRow(title: "R2 test failed", message: errorMessage)
            }

            FlickSettingsValueRow(
                title: "Bucket",
                systemImage: "shippingbox",
                iconColor: .blue,
                value: appModel.configuration.r2.bucket ?? "Not configured",
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Public base URL",
                systemImage: "link",
                iconColor: .green,
                value: appModel.configuration.r2.publicBaseURL?.absoluteString ?? "Not configured",
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "S3 endpoint",
                systemImage: "network",
                iconColor: .orange,
                value: appModel.configuration.r2.endpointURL?.absoluteString ?? "Not configured",
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Generated images path",
                systemImage: "photo",
                iconColor: .blue,
                value: appModel.configuration.storagePaths.generatedImages,
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Rendered images path",
                systemImage: "film",
                iconColor: .purple,
                value: appModel.configuration.storagePaths.renderedImages,
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Reference images path",
                systemImage: "sparkles.rectangle.stack",
                iconColor: .orange,
                value: appModel.configuration.storagePaths.referenceImages,
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Thumbnails path",
                systemImage: "rectangle.stack",
                iconColor: .green,
                value: appModel.configuration.storagePaths.thumbnails,
                valueLineLimit: nil
            )
        }
    }

    private func runR2SmokeTest() {
        Task {
            await appModel.runR2SmokeTest()
        }
    }

    private var workerRoleSection: some View {
        Section("Worker role") {
            if appModel.overview.devices.isEmpty {
                SettingsMessageRow(
                    title: "No devices registered",
                    message: "Device registration will appear here after the app persists real device identity and worker capability state."
                )
            } else {
                ForEach(appModel.overview.devices) { device in
                    DeviceRow(device: device)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            FlickSettingsValueRow(
                title: "CloudKit sync",
                systemImage: "icloud",
                iconColor: .blue,
                value: "\(appModel.overview.dashboard.syncHealth.pendingChanges) pending changes"
            )
            FlickSettingsValueRow(
                title: "Render directory",
                systemImage: "folder",
                iconColor: .orange,
                value: appModel.configuration.renderDirectory.path(percentEncoded: false),
                valueLineLimit: nil
            )
            FlickSettingsValueRow(
                title: "Primary worker",
                systemImage: "desktopcomputer",
                iconColor: appModel.overview.dashboard.workerStatus.isOnline ? .green : .secondary,
                value: appModel.overview.dashboard.workerStatus.isOnline ? "Online" : "Offline"
            )
            FlickSettingsValueRow(
                title: "Notifications",
                systemImage: "bell",
                iconColor: .purple,
                value: "Approval, failure, token, analytics, and worker alerts",
                valueLineLimit: 2
            )
        }
    }
}

private struct CredentialsNavigationRow: View {
    var storedCount: Int

    var body: some View {
        NavigationLink {
            CredentialsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                Text("Credentials")
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                StatusBadge(title: "\(storedCount) stored", tint: .blue, systemImage: "key.fill")

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct DeviceRow: View {
    var device: FlickDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 12)
                StatusBadge(title: device.platform.rawValue, tint: device.isPrimaryWorker ? .green : .blue, systemImage: "circle.fill")
            }

            Text(device.capabilities.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsMessageRow: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.primary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct R2SmokeTestRow: View {
    var isRunning: Bool
    var result: R2StorageSmokeTestResult?
    var errorMessage: String?
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(statusTint)
                    .frame(width: 24)

                Text("Cloudflare R2 Smoke Test")
                    .foregroundStyle(.primary)

                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: action) {
                    Label(isRunning ? "Testing" : "Run Test", systemImage: isRunning ? "clock" : "play.fill")
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(Color.primary)
                .disabled(isRunning)

                StatusBadge(title: statusTitle, tint: statusTint, systemImage: statusSystemImage)
                Spacer()
            }
            .padding(.leading, 34)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
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

private struct R2SmokeTestDetailRow: View {
    var result: R2StorageSmokeTestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsMessageRow(title: result.isSuccessful ? "Result" : "What to check", message: result.diagnosticMessages.joined(separator: "\n"))
            SettingsMessageRow(title: "Bucket", message: result.bucket)
            SettingsMessageRow(title: "S3 endpoint", message: result.endpointURL.absoluteString)
            SettingsMessageRow(title: "Public base URL", message: result.publicBaseURL.absoluteString)
            SettingsMessageRow(title: "Prefix placeholders", message: result.ensuredPrefixPaths.joined(separator: "\n"))
            SettingsMessageRow(title: "Object", message: "\(result.bucket)/\(result.path)")
            SettingsMessageRow(title: "Public URL", message: "\(result.publicURLAccessText): \(result.publicURL.absoluteString)")
            SettingsMessageRow(title: "Signed URL", message: "\(result.signedURLAccessText), expires \(result.signedURLExpiration.formatted(date: .abbreviated, time: .shortened))")

            if !result.cleanupSucceeded {
                SettingsMessageRow(
                    title: "Cleanup",
                    message: result.cleanupError ?? "The smoke-test object could not be removed."
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

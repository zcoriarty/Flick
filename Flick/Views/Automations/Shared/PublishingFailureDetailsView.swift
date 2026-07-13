//
//  PublishingFailureDetailsView.swift
//  Flick
//

import SwiftUI

struct PublishingFailureDetailsView: View {
    var failure: PlatformFailure
    var job: PublishingJob
    var showsMessage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsMessage {
                Label(failure.message, systemImage: "xmark.octagon")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !failure.suggestedFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(failure.suggestedFix, systemImage: "wrench.and.screwdriver")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("Technical details") {
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticValue("Failure type", value: failure.kind.rawValue)
                    if let pipelineStage = failure.pipelineStage {
                        diagnosticValue("Failed step", value: pipelineStage.displayName)
                    }
                    diagnosticValue("Job ID", value: job.id.uuidString)
                    diagnosticValue("Attempt", value: job.attemptCount.formatted())
                    if let httpStatusCode = failure.httpStatusCode {
                        diagnosticValue("HTTP status", value: httpStatusCode.formatted())
                    }
                    if let platformCode = failure.platformCode, !platformCode.isEmpty {
                        diagnosticValue("Platform code", value: platformCode)
                    }
                    if let platformLogID = failure.platformLogID, !platformLogID.isEmpty {
                        diagnosticValue("Platform log ID", value: platformLogID)
                    }
                    diagnosticValue(
                        "Failed at",
                        value: (failure.failedAt ?? job.lastAttemptAt ?? job.updatedAt).formatted(.iso8601)
                    )
                    if let rawResponse = failure.rawResponse?.trimmingCharacters(in: .whitespacesAndNewlines), !rawResponse.isEmpty {
                        Text("Raw response")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(rawResponse)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ShareLink(item: failure.diagnosticReport(for: job)) {
                        Label("Share Diagnostic Report", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, 8)
            }
            .font(.footnote)
        }
    }

    private func diagnosticValue(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private extension PlatformFailure {
    func diagnosticReport(for job: PublishingJob) -> String {
        [
            "Flick publishing failure",
            "Job ID: \(job.id.uuidString)",
            "Automation ID: \(job.automationID?.uuidString ?? "none")",
            "Draft ID: \(job.draftID.uuidString)",
            "Account ID: \(job.accountID.uuidString)",
            "Platform: \(job.platform.rawValue)",
            "Job status: \(job.status.rawValue)",
            "Attempt: \(job.attemptCount)",
            "Failed at: \((failedAt ?? job.lastAttemptAt ?? job.updatedAt).formatted(.iso8601))",
            "Failure type: \(kind.rawValue)",
            pipelineStage.map { "Failed step: \($0.displayName)" },
            httpStatusCode.map { "HTTP status: \($0)" },
            platformCode.map { "Platform code: \($0)" },
            platformLogID.map { "Platform log ID: \($0)" },
            "Message: \(message)",
            "Suggested fix: \(suggestedFix)",
            rawResponse.map { "Raw response:\n\($0)" }
        ]
        .compactMap(\.self)
        .joined(separator: "\n")
    }
}

enum AutomationPostPublishAction: Identifiable {
    case retryJob(UUID)
    case repostJob(UUID)
    case repostPost(UUID)

    var id: String {
        switch self {
        case let .retryJob(id): "retry-\(id.uuidString)"
        case let .repostJob(id): "repost-job-\(id.uuidString)"
        case let .repostPost(id): "repost-post-\(id.uuidString)"
        }
    }

    var buttonTitle: String {
        switch self {
        case .retryJob: "Retry Failed Post"
        case .repostJob, .repostPost: "Repost"
        }
    }

    var systemImage: String {
        switch self {
        case .retryJob: "arrow.clockwise.circle.fill"
        case .repostJob, .repostPost: "paperplane.fill"
        }
    }

    var value: String {
        switch self {
        case .retryJob: "Check and resume failed post"
        case .repostJob, .repostPost: "Publish the generated post again"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .retryJob: "Retry this failed post?"
        case .repostJob, .repostPost: "Repost this post?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .retryJob:
            "Flick will check the saved slide images, reuse existing rendered files, repair only missing Cloudflare uploads, refresh authorization if needed, and resume from the first incomplete step. It will not regenerate AI images."
        case .repostJob, .repostPost:
            "This creates a new publish job and submits the generated post again. It may create a duplicate if the platform is still processing the original."
        }
    }
}

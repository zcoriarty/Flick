//
//  QueueView.swift
//  Flick
//

import SwiftUI

struct QueueView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        List {
            publishingJobsSection
            cadenceRulesSection
        }
        .flickSettingsListStyle()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Queue")
                    .font(.system(.body, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                Button(appModel.overview.workspace.automationPaused ? "Resume" : "Pause", systemImage: appModel.overview.workspace.automationPaused ? "play.fill" : "pause.fill") {
                    appModel.toggleAutomationPaused()
                }
            }
        }
    }

    private var cadenceRulesSection: some View {
        Section("Cadence rules") {
            if appModel.overview.cadenceRules.isEmpty {
                QueueMessageRow(
                    title: "No cadence rules",
                    message: "Cadence rules are created per authorized account before autonomous scheduling starts."
                )
            } else {
                ForEach(appModel.overview.cadenceRules) { rule in
                    CadenceRuleRow(rule: rule, accountName: accountName(for: rule.accountID))
                }
            }
        }
    }

    private var publishingJobsSection: some View {
        Section("Publishing jobs") {
            if appModel.overview.publishingJobs.isEmpty {
                QueueMessageRow(
                    title: "No queued content",
                    message: "Send an approved slideshow draft to the queue to see its slides, caption, account, and publish status here."
                )
            } else {
                ForEach(appModel.overview.publishingJobs.sorted { $0.scheduledAt < $1.scheduledAt }) { job in
                    PublishingJobRow(job: job)
                }
            }
        }
    }

    private func accountName(for accountID: UUID?) -> String {
        guard let accountID else { return "Workspace default" }
        return appModel.overview.accounts.first(where: { $0.id == accountID })?.displayName ?? "Unknown account"
    }
}

private struct CadenceRuleRow: View {
    var rule: CadenceRule
    var accountName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(accountName)
                        .font(.body.weight(.semibold))
                    Text("\(rule.postsPerDay) posts/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                StatusBadge(
                    title: rule.requireApproval ? "Manual approval" : "Auto",
                    tint: rule.requireApproval ? .orange : .green,
                    systemImage: "checkmark.seal"
                )
            }

            Text(rule.allowedTimeWindows.displayValue)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("\(rule.minimumGapMinutes)m gap · \(rule.maxRetries) retries · Pause after \(rule.pauseOnErrorCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PublishingJobRow: View {
    @Environment(FlickAppModel.self) private var appModel
    var job: PublishingJob

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(draftTitle, systemImage: job.platform.systemImage)
                        .font(.body.weight(.semibold))
                    Text("Scheduled \(job.scheduledAt, style: .date) at \(job.scheduledAt, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                StatusBadge(title: job.status.displayName, tint: job.status.tint, systemImage: "circle.fill")
            }

            HStack(spacing: 16) {
                Label(accountTitle, systemImage: "person.crop.circle")
                Label(job.publishMode.displayName, systemImage: "rectangle.stack")
                Label("\(job.attemptCount) attempts", systemImage: "arrow.clockwise")
                if let worker = job.workerDeviceID {
                    Label(worker.uuidString.prefix(8).description, systemImage: "desktopcomputer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let draft {
                QueueDraftContentPreview(draft: draft)
            } else {
                StatusBadge(title: "Draft content missing", tint: .red, systemImage: "exclamationmark.triangle")
            }

            if account == nil {
                MissingAuthorizedAccountWarning(platform: job.platform)
            }

            if let lastError = job.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lastError.message)
                        .font(.callout.weight(.semibold))
                    Text(lastError.suggestedFix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    .red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius, style: .continuous)
                )
            }

            ViewThatFits(in: .horizontal) {
                actionButtons
                VStack(alignment: .leading, spacing: 8) {
                    actionButtons
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var actionButtons: some View {
        HStack {
            if job.status == .awaitingApproval {
                Button("Approve", systemImage: "checkmark") {
                    appModel.approve(job: job)
                }
                .buttonStyle(.borderedProminent)
            }
            if job.status == .failed {
                Button("Retry", systemImage: "arrow.clockwise") {
                    appModel.retry(job: job)
                }
                .buttonStyle(.borderedProminent)
            }
            if job.status == .queued {
                Button("Pause", systemImage: "pause") {
                    appModel.pause(job: job)
                }
                .buttonStyle(.bordered)
            }
            if job.status == .paused {
                Button("Resume", systemImage: "play") {
                    appModel.resume(job: job)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 8)
            Button("Duplicate", systemImage: "plus.square.on.square") {
                if let draft = appModel.overview.drafts.first(where: { $0.id == job.draftID }) {
                    appModel.duplicateDraft(draft)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var draftTitle: String {
        draft?.title ?? "Untitled draft"
    }

    private var draft: SlideshowDraft? {
        appModel.overview.drafts.first(where: { $0.id == job.draftID })
    }

    private var accountTitle: String {
        account?.displayName ?? "No authorized account"
    }

    private var account: ConnectedAccount? {
        appModel.overview.accounts.first(where: { $0.id == job.accountID && $0.authorizationSource == .loginKit })
    }
}

private struct QueueDraftContentPreview: View {
    var draft: SlideshowDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(draft.slides.sorted { $0.index < $1.index }) { slide in
                        QueueSlideThumb(slide: slide)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.caption)
                    .font(.callout)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    ForEach(draft.hashtags, id: \.self) { hashtag in
                        Text("#\(hashtag)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct QueueSlideThumb: View {
    var slide: Slide

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [slide.role.tint.opacity(0.45), .black.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                StatusBadge(title: "\(slide.index + 1)", tint: .white, systemImage: nil)
                Spacer(minLength: 0)
                Text(slide.overlayText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
            }
            .padding(10)
        }
        .frame(width: 110, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius, style: .continuous))
        .accessibilityLabel("Slide \(slide.index + 1), \(slide.overlayText)")
    }
}

private struct MissingAuthorizedAccountWarning: View {
    var platform: SocialPlatform

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("No authorized \(platform.displayName) account selected")
                    .font(.callout.weight(.semibold))
                Text("Only accounts connected through Login Kit are eligible for publishing jobs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            .orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: FlickStyle.controlCornerRadius, style: .continuous)
        )
    }
}

private struct QueueMessageRow: View {
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

private extension SlideRole {
    var tint: Color {
        switch self {
        case .hook: .orange
        case .problem: .red
        case .proof: .blue
        case .demo: .teal
        case .benefit: .green
        case .cta: .purple
        }
    }
}

private extension Array where Element == String {
    var displayValue: String {
        isEmpty ? "No allowed windows" : joined(separator: "  ")
    }
}

private extension PublishMode {
    var displayName: String {
        switch self {
        case .photoDirectPost: "Photo direct post"
        case .photoUploadForCompletion: "Photo upload"
        case .videoDirectPost: "Video direct post"
        case .videoUploadForCompletion: "Video upload"
        }
    }
}

//
//  QueueView.swift
//  Flick
//

import SwiftUI

struct QueueView: View {
    @Environment(FlickAppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FlickStyle.sectionSpacing) {
                publishingJobs
                cadenceRules
            }
            .flickScrollablePage()
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .principal) {
                    Text("Queue")
                }
                #else
                ToolbarItem(placement: .title) {
                    Text("Queue")
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button(appModel.overview.workspace.automationPaused ? "Resume" : "Pause", systemImage: appModel.overview.workspace.automationPaused ? "play.fill" : "pause.fill") {
                        appModel.toggleAutomationPaused()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private var cadenceRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Cadence rules", subtitle: "Per-account timing, approval, retry, and pause behavior", systemImage: "clock.badge.checkmark")
            if appModel.overview.cadenceRules.isEmpty {
                FlickEmptyStateCard(
                    title: "No cadence rules",
                    message: "Cadence rules are created per authorized account before autonomous scheduling starts.",
                    systemImage: "clock.badge.questionmark"
                )
            } else {
                ResponsiveGrid(minimum: 280) {
                    ForEach(appModel.overview.cadenceRules) { rule in
                        FlickGlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(accountName(for: rule.accountID))
                                            .font(.headline)
                                        Text("\(rule.postsPerDay) posts/day")
                                            .font(.title3.weight(.bold))
                                    }
                                    Spacer()
                                    StatusBadge(title: rule.requireApproval ? "Manual approval" : "Auto", tint: rule.requireApproval ? .orange : .green, systemImage: "checkmark.seal")
                                }
                                Label(rule.allowedTimeWindows.joined(separator: "  "), systemImage: "calendar")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 14) {
                                    Label("\(rule.minimumGapMinutes)m gap", systemImage: "arrow.left.arrow.right")
                                    Label("\(rule.maxRetries) retries", systemImage: "arrow.clockwise")
                                    Label("Pause after \(rule.pauseOnErrorCount)", systemImage: "pause.circle")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var publishingJobs: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Publishing jobs", subtitle: "Draft content, account, approval, media, retries, and diagnostics", systemImage: "tray.full")
            if appModel.overview.publishingJobs.isEmpty {
                QueueEmptyState()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(appModel.overview.publishingJobs.sorted { $0.scheduledAt < $1.scheduledAt }) { job in
                        PublishingJobRow(job: job)
                    }
                }
            }
        }
    }

    private func accountName(for accountID: UUID?) -> String {
        guard let accountID else { return "Workspace default" }
        return appModel.overview.accounts.first(where: { $0.id == accountID })?.displayName ?? "Unknown account"
    }
}

private struct PublishingJobRow: View {
    @Environment(FlickAppModel.self) private var appModel
    var job: PublishingJob

    var body: some View {
        FlickGlassCard(interactive: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(draftTitle, systemImage: job.platform.systemImage)
                            .font(.headline)
                        Text("Scheduled \(job.scheduledAt, style: .date) at \(job.scheduledAt, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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

                HStack {
                    if job.status == .awaitingApproval {
                        Button("Approve", systemImage: "checkmark") {
                            appModel.approve(job: job)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    if job.status == .failed {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            appModel.retry(job: job)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    if job.status == .queued {
                        Button("Pause", systemImage: "pause") {
                            appModel.pause(job: job)
                        }
                        .buttonStyle(.glass)
                    }
                    if job.status == .paused {
                        Button("Resume", systemImage: "play") {
                            appModel.resume(job: job)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    Spacer()
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        if let draft = appModel.overview.drafts.first(where: { $0.id == job.draftID }) {
                            appModel.duplicateDraft(draft)
                        }
                    }
                    .buttonStyle(.glass)
                }
            }
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

private struct QueueEmptyState: View {
    var body: some View {
        FlickGlassCard {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No queued content")
                        .font(.headline)
                    Text("Send an approved slideshow draft to the queue to see its slides, caption, account, and publish status here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
            }
        }
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

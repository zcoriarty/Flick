//
//  AutomationDashboardSnapshot.swift
//  Flick
//

import Foundation

struct AutomationDashboardSnapshot: Hashable {
    var items: [AutomationDashboardItem]
    var activeProgresses: [AutomationPostProgress]

    var activeCount: Int {
        items.filter { $0.automation.status == .active }.count
    }

    var publishedPostCount: Int {
        items.reduce(0) { $0 + $1.publishedPosts.count }
    }

    var nextPostAt: Date? {
        items
            .filter { $0.automation.status == .active }
            .compactMap(\.nextScheduledAt)
            .min()
    }

    static func make(
        overview: FlickOverviewState,
        exampleTemplates: [ExampleSlideshowTemplate] = []
    ) -> AutomationDashboardSnapshot {
        let accountsByID = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, $0) })
        let assetsByID = Dictionary(uniqueKeysWithValues: overview.assets.map { ($0.id, $0) })
        let draftsByID = Dictionary(uniqueKeysWithValues: overview.drafts.map { ($0.id, $0) })
        let postsByAutomation = Dictionary(grouping: overview.publishedPosts.filter { $0.automationID != nil }) { post in
            post.automationID ?? UUID()
        }
        let jobsByAutomation = Dictionary(grouping: overview.publishingJobs.filter { $0.automationID != nil }) { job in
            job.automationID ?? UUID()
        }
        let activeProgresses = overview.automationPostProgresses.activeAutomationPostProgresses
        let progressesByAutomation = Dictionary(grouping: activeProgresses) { progress in
            progress.automationID
        }

        let items = overview.automations
            .sortedForAutomationDashboard()
            .map { automation in
                let posts = (postsByAutomation[automation.id] ?? []).sorted { $0.publishedAt > $1.publishedAt }
                let jobs = (jobsByAutomation[automation.id] ?? []).sorted { $0.updatedAt > $1.updatedAt }
                let targets = AutomationTargetSummary.targets(
                    for: automation,
                    accounts: overview.accounts
                )
                let postPreviews = posts.map { post in
                    let draft = draftsByID[post.draftID]
                    return AutomationPostPreview(
                        post: post,
                        draft: draft,
                        accountName: accountsByID[post.accountID]?.displayName,
                        thumbnailAsset: previewAsset(for: draft, assetsByID: assetsByID)
                    )
                }

                return AutomationDashboardItem(
                    automation: automation,
                    displayName: automation.displayName(
                        templates: exampleTemplates,
                        products: overview.products
                    ),
                    productName: automation.productID.flatMap { productID in
                        overview.products.first { $0.id == productID }?.name
                    },
                    targets: targets,
                    publishedPosts: posts,
                    publishingJobs: jobs,
                    postPreviews: postPreviews,
                    activeProgresses: progressesByAutomation[automation.id] ?? []
                )
            }

        return AutomationDashboardSnapshot(items: items, activeProgresses: activeProgresses)
    }

    private static func previewAsset(
        for draft: SlideshowDraft?,
        assetsByID: [UUID: MediaAsset]
    ) -> MediaAsset? {
        guard let draft else { return nil }

        if let exportedAsset = draft.exportedImageAssetIDs.compactMap({ assetsByID[$0] }).first {
            return exportedAsset
        }

        return draft.slides
            .sorted { $0.index < $1.index }
            .compactMap(\.imageAssetID)
            .compactMap { assetsByID[$0] }
            .first
    }
}

struct AutomationDashboardItem: Identifiable, Hashable {
    var id: UUID { automation.id }

    var automation: ContentAutomation
    var displayName: String
    var productName: String?
    var targets: [AutomationTargetSummary]
    var publishedPosts: [PublishedPost]
    var publishingJobs: [PublishingJob]
    var postPreviews: [AutomationPostPreview]
    var activeProgresses: [AutomationPostProgress]

    var scheduleSummary: String {
        automation.schedule.summary()
    }

    var nextScheduledAt: Date? {
        automation.nextScheduledAt
    }

    var previousPostedAt: Date? {
        publishedPosts.first?.publishedAt ?? automation.lastRunAt
    }

    var accountPlatformSummary: String {
        targets.map(\.displayName).joined(separator: ", ")
    }

    var targetPlatformSummary: String {
        automation.targetPlatforms.map(\.displayName).joined(separator: ", ")
    }

    var awaitingDraftUploadCount: Int {
        publishingJobs.filter { $0.status == .awaitingUserCompletion }.count
    }

    var failedJobCount: Int {
        publishingJobs.filter { $0.status == .failed }.count
    }
}

struct AutomationTargetSummary: Identifiable, Hashable {
    var platform: SocialPlatform
    var accountID: UUID?
    var accountName: String?

    var id: String {
        "\(platform.rawValue)-\(accountID?.uuidString ?? "unassigned")"
    }

    var displayName: String {
        guard let accountName, !accountName.isEmpty else {
            return platform.displayName
        }

        return "\(accountName) - \(platform.displayName)"
    }

    static func targets(
        for automation: ContentAutomation,
        accounts: [ConnectedAccount]
    ) -> [AutomationTargetSummary] {
        let targetPlatforms = automation.targetPlatforms.isEmpty ? [SocialPlatform.tiktok] : automation.targetPlatforms

        return targetPlatforms.flatMap { platform in
            let matchingAccounts = accounts
                .filter { account in
                    account.platform == platform && account.isPublishingEnabled
                }
                .sorted { lhs, rhs in
                    lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }

            guard !matchingAccounts.isEmpty else {
                return [
                    AutomationTargetSummary(
                        platform: platform,
                        accountID: nil,
                        accountName: nil
                    )
                ]
            }

            return matchingAccounts.map { account in
                AutomationTargetSummary(
                    platform: platform,
                    accountID: account.id,
                    accountName: account.displayName
                )
            }
        }
    }
}

struct AutomationPostPreview: Identifiable, Hashable {
    var id: UUID { post.id }

    var post: PublishedPost
    var draft: SlideshowDraft?
    var accountName: String?
    var thumbnailAsset: MediaAsset?

    var displayTitle: String {
        let caption = post.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            return caption
        }

        if let draftTitle = draft?.title.trimmingCharacters(in: .whitespacesAndNewlines), !draftTitle.isEmpty {
            return draftTitle
        }

        return "\(post.platform.displayName) post"
    }

    var subtitle: String {
        if let accountName, !accountName.isEmpty {
            return "\(post.platform.displayName) - \(accountName)"
        }

        return post.platform.displayName
    }
}

private extension Array where Element == ContentAutomation {
    func sortedForAutomationDashboard() -> [ContentAutomation] {
        sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .active
            }

            switch (lhs.nextScheduledAt, rhs.nextScheduledAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate < rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }
}

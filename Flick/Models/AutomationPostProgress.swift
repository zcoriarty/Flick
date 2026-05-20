//
//  AutomationPostProgress.swift
//  Flick
//

import Foundation

struct AutomationPostProgress: Identifiable, Codable, Hashable {
    var id: UUID
    var automationID: UUID
    var draftID: UUID?
    var title: String
    var templateTitle: String?
    var productName: String?
    var scheduledAt: Date
    var startedAt: Date
    var updatedAt: Date
    var finishedAt: Date?
    var errorMessage: String?
    var steps: [AutomationPostProgressStep]

    var isActive: Bool {
        finishedAt == nil
    }

    var completedCount: Int {
        steps.filter { $0.state == .completed }.count
    }

    var totalCount: Int {
        steps.count
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var currentStep: AutomationPostProgressStep? {
        steps.first { $0.state == .current }
            ?? steps.first { $0.state == .failed }
            ?? steps.first { $0.state == .pending }
            ?? steps.last
    }

    var currentStepIndex: Int {
        guard let currentStep, let index = steps.firstIndex(where: { $0.id == currentStep.id }) else {
            return min(completedCount + 1, max(totalCount, 1))
        }
        return index + 1
    }

    static func make(
        automationID: UUID,
        title: String,
        productName: String?,
        scheduledAt: Date,
        now: Date = Date()
    ) -> AutomationPostProgress {
        AutomationPostProgress(
            id: UUID(),
            automationID: automationID,
            title: title,
            productName: productName,
            scheduledAt: scheduledAt,
            startedAt: now,
            updatedAt: now,
            steps: [
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.selectTemplate,
                    title: "Select template",
                    detail: "Choosing the template for this scheduled post.",
                    systemImage: "rectangle.stack"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.planSlideshow,
                    title: "Plan post",
                    detail: "Writing the carousel structure and caption.",
                    systemImage: "text.badge.checkmark"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.generateImages,
                    title: "Generate visuals",
                    detail: "Creating slide images for this post.",
                    systemImage: "sparkles"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.renderImages,
                    title: "Render slides",
                    detail: "Compositing text onto the final images.",
                    systemImage: "photo.on.rectangle"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.uploadMedia,
                    title: "Upload media",
                    detail: "Uploading rendered images for publishing.",
                    systemImage: "icloud.and.arrow.up"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.publishTikTok,
                    title: "Publish to TikTok",
                    detail: "Sending the prepared image sequence.",
                    systemImage: "paperplane"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.recordResult,
                    title: "Sync result",
                    detail: "Saving the publish result for every device.",
                    systemImage: "checkmark.icloud"
                )
            ]
        )
    }
}

struct AutomationPostProgressStep: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
    var state: AutomationPostProgressStepState = .pending
    var updatedAt: Date?
}

enum AutomationPostProgressStepState: String, Codable, Hashable {
    case pending
    case current
    case completed
    case failed
}

enum AutomationPostProgressStepID {
    static let selectTemplate = "select-template"
    static let planSlideshow = "plan-slideshow"
    static let generateImages = "generate-images"
    static let renderImages = "render-images"
    static let uploadMedia = "upload-media"
    static let publishTikTok = "publish-tiktok"
    static let recordResult = "record-result"
}

extension Array where Element == AutomationPostProgress {
    var activeAutomationPostProgresses: [AutomationPostProgress] {
        filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.startedAt > rhs.startedAt
            }
    }
}

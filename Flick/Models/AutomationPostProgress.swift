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
    var creationModelName: String?
    var targetPlatforms: [SocialPlatform]
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
        creationModelName: String? = nil,
        targetPlatforms: [SocialPlatform] = [.tiktok],
        scheduledAt: Date,
        now: Date = Date()
    ) -> AutomationPostProgress {
        AutomationPostProgress(
            id: UUID(),
            automationID: automationID,
            title: title,
            productName: productName,
            creationModelName: creationModelName,
            targetPlatforms: normalizedTargetPlatforms(targetPlatforms),
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
                    id: AutomationPostProgressStepID.renderVideo,
                    title: "Render video",
                    detail: "Encoding a vertical video for video platforms.",
                    systemImage: "film"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.uploadMedia,
                    title: "Upload media",
                    detail: "Uploading rendered images for publishing.",
                    systemImage: "icloud.and.arrow.up"
                ),
                AutomationPostProgressStep(
                    id: AutomationPostProgressStepID.publishTikTok,
                    title: "Publish",
                    detail: "Sending prepared media to the selected platforms.",
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

    var normalizedTargetPlatforms: [SocialPlatform] {
        Self.normalizedTargetPlatforms(targetPlatforms)
    }

    private static func normalizedTargetPlatforms(_ platforms: [SocialPlatform]) -> [SocialPlatform] {
        var seen = Set<SocialPlatform>()
        let uniquePlatforms = platforms.filter { seen.insert($0).inserted }
        return uniquePlatforms.isEmpty ? [.tiktok] : uniquePlatforms
    }
}

extension AutomationPostProgress {
    private enum CodingKeys: String, CodingKey {
        case id
        case automationID
        case draftID
        case title
        case templateTitle
        case productName
        case creationModelName
        case targetPlatforms
        case scheduledAt
        case startedAt
        case updatedAt
        case finishedAt
        case errorMessage
        case steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        automationID = try container.decode(UUID.self, forKey: .automationID)
        draftID = try container.decodeIfPresent(UUID.self, forKey: .draftID)
        title = try container.decode(String.self, forKey: .title)
        templateTitle = try container.decodeIfPresent(String.self, forKey: .templateTitle)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        creationModelName = try container.decodeIfPresent(String.self, forKey: .creationModelName)
        targetPlatforms = Self.normalizedTargetPlatforms(
            try container.decodeIfPresent([SocialPlatform].self, forKey: .targetPlatforms) ?? [.tiktok]
        )
        scheduledAt = try container.decode(Date.self, forKey: .scheduledAt)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        steps = try container.decode([AutomationPostProgressStep].self, forKey: .steps)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(automationID, forKey: .automationID)
        try container.encodeIfPresent(draftID, forKey: .draftID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(templateTitle, forKey: .templateTitle)
        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(creationModelName, forKey: .creationModelName)
        try container.encode(normalizedTargetPlatforms, forKey: .targetPlatforms)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encode(steps, forKey: .steps)
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
    static let renderVideo = "render-video"
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

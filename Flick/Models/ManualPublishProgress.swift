//
//  ManualPublishProgress.swift
//  Flick
//

import Foundation

struct ManualPublishProgress: Identifiable, Hashable {
    var id: UUID
    var title: String
    var startedAt: Date
    var finishedAt: Date?
    var steps: [ManualPublishProgressStep]
    var errorMessage: String?

    var isFinished: Bool {
        finishedAt != nil
    }

    var completedCount: Int {
        steps.filter { $0.state == .completed }.count
    }

    var totalCount: Int {
        steps.count
    }

    static func make(for draft: SlideshowDraft, now: Date = Date()) -> ManualPublishProgress {
        let sortedSlides = draft.slides.sorted { $0.index < $1.index }
        var steps = [
            ManualPublishProgressStep(
                id: ManualPublishProgressStepID.validate,
                title: "Validate settings",
                detail: "Checking account, media, and TikTok options.",
                systemImage: "checklist"
            ),
            ManualPublishProgressStep(
                id: ManualPublishProgressStepID.createJob,
                title: "Create publish job",
                detail: "Recording this manual publish attempt.",
                systemImage: "tray.full"
            )
        ]

        steps.append(
            ManualPublishProgressStep(
                id: ManualPublishProgressStepID.renderImages,
                title: "Snapshot slides",
                detail: "Rendering the current edited slides.",
                systemImage: "rectangle.stack"
            )
        )

        steps.append(contentsOf: sortedSlides.map { slide in
            ManualPublishProgressStep(
                id: ManualPublishProgressStepID.uploadSlide(slide.id),
                title: "Upload slide \(slide.index + 1)",
                detail: "Uploading the rendered image to Supabase.",
                systemImage: "icloud.and.arrow.up"
            )
        })

        steps.append(contentsOf: [
            ManualPublishProgressStep(
                id: ManualPublishProgressStepID.publishTikTok,
                title: "Publish to TikTok",
                detail: "Sending the prepared image sequence.",
                systemImage: "paperplane"
            ),
            ManualPublishProgressStep(
                id: ManualPublishProgressStepID.recordResult,
                title: "Record result",
                detail: "Saving the final publish status.",
                systemImage: "checkmark.seal"
            )
        ])

        return ManualPublishProgress(
            id: UUID(),
            title: draft.title,
            startedAt: now,
            steps: steps,
            errorMessage: nil
        )
    }
}

struct ManualPublishProgressStep: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
    var state: ManualPublishProgressStepState = .pending
    var updatedAt: Date?
}

enum ManualPublishProgressStepState: String, Hashable {
    case pending
    case current
    case completed
    case failed
}

enum ManualPublishProgressStepID {
    static let validate = "validate"
    static let createJob = "create-job"
    static let renderImages = "render-images"
    static let publishTikTok = "publish-tiktok"
    static let recordResult = "record-result"

    static func uploadSlide(_ id: UUID) -> String {
        "upload-slide-\(id.uuidString)"
    }
}

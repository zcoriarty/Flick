//
//  DraftTikTokSettings+PublishSettings.swift
//  Flick
//

import Foundation

extension DraftTikTokSettings {
    func manualPublishSettings(description: String) -> TikTokManualPublishSettings? {
        publishSettings(description: description, allowsDraftUpload: true)
    }

    func automatedPublishSettings(description: String) -> TikTokManualPublishSettings? {
        publishSettings(description: description, allowsDraftUpload: false)
    }

    private func publishSettings(
        description: String,
        allowsDraftUpload: Bool
    ) -> TikTokManualPublishSettings? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }

        let shouldPostAsDraft = allowsDraftUpload && postAsDraft
        guard shouldPostAsDraft || privacyLevel != nil else { return nil }
        guard shouldPostAsDraft || !disclosesVideoContent || promotesYourBrand || promotesBrandedContent else { return nil }

        return TikTokManualPublishSettings(
            title: normalizedTitle,
            description: description,
            postAsDraft: shouldPostAsDraft,
            privacyLevel: privacyLevel ?? .selfOnly,
            allowComment: allowComment,
            allowDuet: allowDuet,
            allowStitch: allowStitch,
            disclosesVideoContent: disclosesVideoContent,
            promotesYourBrand: promotesYourBrand,
            promotesBrandedContent: promotesBrandedContent
        )
    }
}

extension SlideshowDraft {
    var publishDescription: String {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedHashtags = hashtags
            .map { hashtag in
                let cleanValue = hashtag.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                return cleanValue.isEmpty ? "" : "#\(cleanValue)"
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return [trimmedCaption, formattedHashtags]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

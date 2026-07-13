//
//  DraftTikTokSettings+PublishSettings.swift
//  Flick
//

import Foundation

nonisolated extension DraftTikTokSettings {
    func manualPublishSettings(description: String) -> TikTokManualPublishSettings? {
        publishSettings(description: description, allowsDraftUpload: true)
    }

    func automatedPublishSettings(description: String) -> TikTokManualPublishSettings? {
        publishSettings(description: description, allowsDraftUpload: true)
    }

    private func publishSettings(
        description: String,
        allowsDraftUpload: Bool
    ) -> TikTokManualPublishSettings? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

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

nonisolated extension DraftYouTubeSettings {
    func manualPublishSettings(
        fallbackTitle: String,
        fallbackDescription: String,
        fallbackHashtags: [String]
    ) -> YouTubeManualPublishSettings? {
        publishSettings(
            fallbackTitle: fallbackTitle,
            fallbackDescription: fallbackDescription,
            fallbackHashtags: fallbackHashtags
        )
    }

    func automatedPublishSettings(
        fallbackTitle: String,
        fallbackDescription: String,
        fallbackHashtags: [String]
    ) -> YouTubeManualPublishSettings? {
        publishSettings(
            fallbackTitle: fallbackTitle,
            fallbackDescription: fallbackDescription,
            fallbackHashtags: fallbackHashtags
        )
    }

    private func publishSettings(
        fallbackTitle: String,
        fallbackDescription: String,
        fallbackHashtags: [String]
    ) -> YouTubeManualPublishSettings? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = normalizedTitle.isEmpty
            ? fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            : normalizedTitle
        guard !resolvedTitle.isEmpty else { return nil }

        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDescription = normalizedDescription.isEmpty
            ? fallbackDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            : normalizedDescription
        let resolvedTags = (tags + fallbackHashtags)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# \n\t")) }
            .filter { !$0.isEmpty }
            .uniqued()

        return YouTubeManualPublishSettings(
            title: resolvedTitle,
            description: resolvedDescription,
            tags: resolvedTags,
            privacyStatus: privacyStatus,
            categoryID: categoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "22" : categoryID,
            selfDeclaredMadeForKids: selfDeclaredMadeForKids,
            containsSyntheticMedia: containsSyntheticMedia,
            notifySubscribers: notifySubscribers
        )
    }
}

nonisolated extension SlideshowDraft {
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

nonisolated private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

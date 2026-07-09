//
//  TikTokManualPublishSettings.swift
//  Flick
//

import Foundation

struct TikTokManualPublishSettings: Hashable {
    var title: String
    var description: String
    var postAsDraft: Bool
    var privacyLevel: TikTokPrivacyLevel
    var allowComment: Bool
    var allowDuet: Bool
    var allowStitch: Bool
    var disclosesVideoContent: Bool
    var promotesYourBrand: Bool
    var promotesBrandedContent: Bool

    init(
        title: String,
        description: String,
        postAsDraft: Bool,
        privacyLevel: TikTokPrivacyLevel,
        allowComment: Bool,
        allowDuet: Bool,
        allowStitch: Bool,
        disclosesVideoContent: Bool,
        promotesYourBrand: Bool,
        promotesBrandedContent: Bool
    ) {
        self.title = title
        self.description = TikTokRequiredHashtags.appendingMissing(to: description)
        self.postAsDraft = postAsDraft
        self.privacyLevel = privacyLevel
        self.allowComment = allowComment
        self.allowDuet = allowDuet
        self.allowStitch = allowStitch
        self.disclosesVideoContent = disclosesVideoContent
        self.promotesYourBrand = promotesYourBrand
        self.promotesBrandedContent = promotesBrandedContent
    }

    var publishMode: PublishMode {
        postAsDraft ? .photoUploadForCompletion : .photoDirectPost
    }
}

private enum TikTokRequiredHashtags {
    static let values = ["abcxyz", "fyp"]

    static func appendingMissing(to description: String) -> String {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingTags = Set(trimmedDescription.tikTokHashtags)
        let missingTags = values.filter { !existingTags.contains($0) }
        guard !missingTags.isEmpty else { return trimmedDescription }

        let formattedTags = missingTags
            .map { "#\($0)" }
            .joined(separator: " ")
        guard !trimmedDescription.isEmpty else { return formattedTags }
        return "\(trimmedDescription)\n\n\(formattedTags)"
    }
}

private extension String {
    var tikTokHashtags: [String] {
        var tags: [String] = []
        var searchIndex = startIndex

        while let hashIndex = self[searchIndex...].firstIndex(of: "#") {
            let tagStart = index(after: hashIndex)
            var tagEnd = tagStart

            while tagEnd < endIndex, self[tagEnd].isTikTokHashtagCharacter {
                tagEnd = index(after: tagEnd)
            }

            if tagStart < tagEnd {
                tags.append(String(self[tagStart..<tagEnd]).lowercased())
            }
            searchIndex = tagEnd
        }

        return tags
    }
}

private extension Character {
    var isTikTokHashtagCharacter: Bool {
        unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }
}

struct YouTubeManualPublishSettings: Hashable {
    var title: String
    var description: String
    var tags: [String]
    var privacyStatus: YouTubePrivacyStatus
    var categoryID: String
    var selfDeclaredMadeForKids: Bool
    var containsSyntheticMedia: Bool
    var notifySubscribers: Bool

    var publishMode: PublishMode {
        .videoDirectPost
    }
}

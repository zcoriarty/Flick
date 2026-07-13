//
//  CreateDraftPublishModels.swift
//  Flick
//

import Foundation

nonisolated struct DraftTikTokSettings: Codable, Hashable {
    var title: String
    var postAsDraft: Bool
    var privacyLevel: TikTokPrivacyLevel?
    var allowComment: Bool
    var allowDuet: Bool
    var allowStitch: Bool
    var disclosesVideoContent: Bool
    var promotesYourBrand: Bool
    var promotesBrandedContent: Bool

    init(
        title: String = "",
        postAsDraft: Bool = false,
        privacyLevel: TikTokPrivacyLevel? = nil,
        allowComment: Bool = false,
        allowDuet: Bool = false,
        allowStitch: Bool = false,
        disclosesVideoContent: Bool = false,
        promotesYourBrand: Bool = false,
        promotesBrandedContent: Bool = false
    ) {
        self.title = title
        self.postAsDraft = postAsDraft
        self.privacyLevel = privacyLevel
        self.allowComment = allowComment
        self.allowDuet = allowDuet
        self.allowStitch = allowStitch
        self.disclosesVideoContent = disclosesVideoContent
        self.promotesYourBrand = promotesYourBrand
        self.promotesBrandedContent = promotesBrandedContent
    }
}

nonisolated enum YouTubePrivacyStatus: String, CaseIterable, Codable, Identifiable, Hashable {
    case `private`
    case unlisted
    case `public`

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .private: "Private"
        case .unlisted: "Unlisted"
        case .public: "Public"
        }
    }
}

nonisolated struct DraftYouTubeSettings: Codable, Hashable {
    var title: String
    var description: String
    var tags: [String]
    var privacyStatus: YouTubePrivacyStatus
    var categoryID: String
    var selfDeclaredMadeForKids: Bool
    var containsSyntheticMedia: Bool
    var notifySubscribers: Bool

    init(
        title: String = "",
        description: String = "",
        tags: [String] = [],
        privacyStatus: YouTubePrivacyStatus = .private,
        categoryID: String = "22",
        selfDeclaredMadeForKids: Bool = false,
        containsSyntheticMedia: Bool = false,
        notifySubscribers: Bool = false
    ) {
        self.title = title
        self.description = description
        self.tags = tags
        self.privacyStatus = privacyStatus
        self.categoryID = categoryID
        self.selfDeclaredMadeForKids = selfDeclaredMadeForKids
        self.containsSyntheticMedia = containsSyntheticMedia
        self.notifySubscribers = notifySubscribers
    }
}

nonisolated struct SelectedSong: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    var duration: TimeInterval?
}

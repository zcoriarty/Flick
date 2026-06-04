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

    var publishMode: PublishMode {
        postAsDraft ? .photoUploadForCompletion : .photoDirectPost
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

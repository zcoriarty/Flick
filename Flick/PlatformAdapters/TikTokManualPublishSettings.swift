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

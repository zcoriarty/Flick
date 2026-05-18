//
//  CreateDraftPublishModels.swift
//  Flick
//

import Foundation

struct DraftTikTokSettings: Codable, Hashable {
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

struct SelectedSong: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    var duration: TimeInterval?
}

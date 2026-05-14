//
//  TikTokPrivacyLevel.swift
//  Flick
//

enum TikTokPrivacyLevel: String, CaseIterable, Codable, Hashable {
    case publicToEveryone = "PUBLIC_TO_EVERYONE"
    case mutualFollowFriends = "MUTUAL_FOLLOW_FRIENDS"
    case followerOfCreator = "FOLLOWER_OF_CREATOR"
    case selfOnly = "SELF_ONLY"

    static var preferredDefault: TikTokPrivacyLevel {
        .publicToEveryone
    }

    static var directPostOptions: [String] {
        allCases.map(\.rawValue)
    }
}

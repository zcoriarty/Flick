//
//  TikTokAudience.swift
//  Flick
//

enum TikTokAudience: String, CaseIterable, Identifiable, Hashable {
    case publicEveryone
    case friendsOnly
    case selfOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .publicEveryone: "Public"
        case .friendsOnly: "Friends only"
        case .selfOnly: "Private"
        }
    }

    var privacyLevel: TikTokPrivacyLevel {
        switch self {
        case .publicEveryone: .publicToEveryone
        case .friendsOnly: .mutualFollowFriends
        case .selfOnly: .selfOnly
        }
    }

    nonisolated init?(privacyLevel: TikTokPrivacyLevel) {
        switch privacyLevel {
        case .publicToEveryone:
            self = .publicEveryone
        case .mutualFollowFriends:
            self = .friendsOnly
        case .selfOnly:
            self = .selfOnly
        case .followerOfCreator:
            return nil
        }
    }
}

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
}

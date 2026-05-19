//
//  LoginKitAccountStore.swift
//  Flick
//

import CryptoKit
import Foundation

struct LoginKitAccountStore {
    private let key = "authorized_accounts.login_kit.v1"
    var store: SecretStoring = KeychainSecretStore(synchronizesAcrossDevices: true)

    func loadAccounts() -> [ConnectedAccount] {
        guard
            let data = try? store.data(for: key),
            let accounts = try? JSONDecoder.flick.decode([ConnectedAccount].self, from: data)
        else {
            return []
        }

        return accounts
            .filter { $0.authorizationSource == .loginKit }
            .map(\.normalizedForCurrentLoginKitDefaults)
            .sortedForPersistence
    }

    func saveAccounts(_ accounts: [ConnectedAccount]) throws {
        let loginKitAccounts = accounts
            .filter { $0.authorizationSource == .loginKit }
            .sortedForPersistence
        let data = try JSONEncoder.flick.encode(loginKitAccounts)
        try store.save(data, for: key)
    }

    func upsert(_ account: ConnectedAccount) throws {
        guard account.authorizationSource == .loginKit else { return }
        var accounts = loadAccounts()
        if let index = accounts.firstIndex(where: { $0.platform == account.platform && $0.platformUserID == account.platformUserID }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        try saveAccounts(accounts)
    }

    func deleteAccount(id accountID: UUID) throws {
        let accounts = loadAccounts().filter { $0.id != accountID }
        try saveAccounts(accounts)
    }
}

struct LoginKitTokenBundle: Codable, Hashable {
    var platform: SocialPlatform
    var platformUserID: String
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var scopes: [String]
    var accessTokenExpiresAt: Date
    var refreshTokenExpiresAt: Date
    var updatedAt: Date
}

struct LoginKitTokenStore {
    private let prefix = "login_kit_tokens.v1"
    var store: SecretStoring = KeychainSecretStore(synchronizesAcrossDevices: true)

    func save(_ bundle: LoginKitTokenBundle, for account: ConnectedAccount) throws {
        let data = try JSONEncoder.flick.encode(bundle)
        try store.save(data, for: key(for: account))
    }

    func tokenBundle(for account: ConnectedAccount) throws -> LoginKitTokenBundle? {
        guard let data = try store.data(for: key(for: account)) else { return nil }
        return try JSONDecoder.flick.decode(LoginKitTokenBundle.self, from: data)
    }

    func deleteTokenBundle(for account: ConnectedAccount) throws {
        try store.delete(key(for: account))
    }

    private func key(for account: ConnectedAccount) -> String {
        "\(prefix).\(account.platform.rawValue).\(account.platformUserID)"
    }
}

struct LoginKitAuthorizedUser: Codable, Hashable {
    var platform: SocialPlatform
    var openID: String
    var displayName: String
    var avatarURL: URL?
    var scopes: [String]
}

enum LoginKitAccountMapper {
    static func connectedAccount(from user: LoginKitAuthorizedUser, now: Date = Date()) -> ConnectedAccount {
        ConnectedAccount(
            id: stableID(platform: user.platform, platformUserID: user.openID),
            platform: user.platform,
            displayName: user.displayName,
            platformUserID: user.openID,
            avatarURL: user.avatarURL,
            scopes: user.scopes,
            status: user.scopes.contains("user.info.basic") ? .connected : .missingScope,
            authorizationSource: .loginKit,
            tokenStatus: .valid,
            isPublishingEnabled: user.scopes.contains("video.publish") || user.scopes.contains("video.upload"),
            defaultPrivacyLevel: user.platform == .tiktok ? TikTokPrivacyLevel.preferredDefault.rawValue : "Platform default",
            lastValidatedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func stableID(platform: SocialPlatform, platformUserID: String) -> UUID {
        let key = "\(platform.rawValue):\(platformUserID)"
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

extension JSONDecoder {
    static var flick: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var flick: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension Array where Element == ConnectedAccount {
    var sortedForPersistence: [ConnectedAccount] {
        sorted {
            if $0.platform.rawValue == $1.platform.rawValue {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.platform.displayName < $1.platform.displayName
        }
    }
}

private extension ConnectedAccount {
    var normalizedForCurrentLoginKitDefaults: ConnectedAccount {
        guard platform == .tiktok, defaultPrivacyLevel != TikTokPrivacyLevel.preferredDefault.rawValue else {
            return self
        }

        var account = self
        account.defaultPrivacyLevel = TikTokPrivacyLevel.preferredDefault.rawValue
        return account
    }
}

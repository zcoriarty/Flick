//
//  YouTubeOAuthClient.swift
//  Flick
//

import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import Security

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class YouTubeOAuthClient {
    var urlSession: URLSession
    var tokenStore: YouTubeTokenStore

    private var activeSession: ASWebAuthenticationSession?
    private let presentationContextProvider = OAuthPresentationContextProvider()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "YouTubeOAuth")

    init(
        urlSession: URLSession = .shared,
        tokenStore: YouTubeTokenStore? = nil
    ) {
        self.urlSession = urlSession
        self.tokenStore = tokenStore ?? YouTubeTokenStore()
    }

    func authorize(configuration: YouTubeConfiguration) async throws -> ConnectedAccount {
        guard AccountManagementPolicy.canAuthorize(.youtubeShorts) else {
            throw YouTubeOAuthError.authorizationUnavailableOnThisPlatform
        }
        guard configuration.clientIDPresent, configuration.redirectURI != nil, configuration.callbackScheme != nil else {
            throw YouTubeOAuthError.notConfigured("YouTube OAuth needs GOOGLE_CLIENT_ID and GOOGLE_REVERSED_CLIENT_ID.")
        }

        let authorization = try await requestAuthorizationCode(configuration: configuration)
        let tokenResponse = try await exchangeCode(
            authorization.code,
            codeVerifier: authorization.codeVerifier,
            configuration: configuration
        )
        guard let refreshToken = tokenResponse.refreshToken, !refreshToken.isEmpty else {
            throw YouTubeOAuthError.missingRefreshToken
        }

        let scopes = tokenResponse.scopes.isEmpty ? configuration.requestedScopes : tokenResponse.scopes
        let account = try await refreshAuthorizedAccount(accessToken: tokenResponse.accessToken, scopes: scopes)
        let bundle = tokenResponse.tokenBundle(
            platformUserID: account.platformUserID,
            refreshToken: refreshToken,
            scopes: scopes
        )
        try await tokenStore.saveAsync(bundle, for: account)
        logger.info("Stored YouTube OAuth token bundle channelID=\(account.platformUserID, privacy: .public)")
        return account
    }

    func refreshAuthorizedAccount(accessToken: String, scopes: [String]) async throws -> ConnectedAccount {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "id,snippet,status"),
            URLQueryItem(name: "mine", value: "true")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeOAuthError.channelRequestFailed(statusCode: nil, message: "YouTube did not return a valid channel response.", rawResponse: rawResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(YouTubeAPIErrorEnvelope.self, from: data)
            throw YouTubeOAuthError.channelRequestFailed(
                statusCode: httpResponse.statusCode,
                message: payload?.error.message ?? "YouTube channel lookup failed with HTTP \(httpResponse.statusCode).",
                rawResponse: rawResponse
            )
        }

        let payload: YouTubeChannelListResponse
        do {
            payload = try JSONDecoder().decode(YouTubeChannelListResponse.self, from: data)
        } catch {
            throw YouTubeOAuthError.channelRequestFailed(
                statusCode: httpResponse.statusCode,
                message: "Could not decode YouTube channel response: \(error.localizedDescription)",
                rawResponse: rawResponse
            )
        }
        guard let channel = payload.items.first else {
            throw YouTubeOAuthError.channelRequestFailed(
                statusCode: httpResponse.statusCode,
                message: "The authorized Google account did not return a YouTube channel.",
                rawResponse: rawResponse
            )
        }

        let now = Date()
        let hasUploadScope = scopes.contains(YouTubeConfiguration.uploadScope)
        let hasReadonlyScope = scopes.contains(YouTubeConfiguration.readonlyScope)
        return ConnectedAccount(
            id: Self.stableID(platform: .youtubeShorts, platformUserID: channel.id),
            platform: .youtubeShorts,
            displayName: channel.snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "YouTube channel" : channel.snippet.title,
            platformUserID: channel.id,
            avatarURL: channel.snippet.bestThumbnailURL,
            scopes: scopes.sorted(),
            status: hasUploadScope && hasReadonlyScope ? .connected : .missingScope,
            authorizationSource: .nativeOAuth,
            tokenStatus: .valid,
            isPublishingEnabled: hasUploadScope,
            defaultPrivacyLevel: YouTubePrivacyStatus.private.rawValue,
            lastValidatedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    private func requestAuthorizationCode(configuration: YouTubeConfiguration) async throws -> YouTubeAuthorizationCode {
        guard
            let clientID = configuration.clientID,
            let redirectURI = configuration.redirectURI,
            let callbackScheme = configuration.callbackScheme
        else {
            throw YouTubeOAuthError.notConfigured("YouTube OAuth needs GOOGLE_CLIENT_ID and GOOGLE_REVERSED_CLIENT_ID.")
        }

        let codeVerifier = PKCE.makeCodeVerifier()
        let state = PKCE.makeCodeVerifier(length: 48)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.requestedScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: PKCE.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account")
        ]

        guard let authorizationURL = components.url else {
            throw YouTubeOAuthError.notConfigured("Could not build the YouTube OAuth URL.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.activeSession = nil
                }

                if let error {
                    continuation.resume(throwing: YouTubeOAuthError.authorizationFailed(error))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: YouTubeOAuthError.missingAuthorizationCode)
                    return
                }

                do {
                    let result = try Self.parseAuthorizationCallback(callbackURL, expectedState: state)
                    continuation.resume(returning: YouTubeAuthorizationCode(code: result.code, codeVerifier: codeVerifier))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            session.presentationContextProvider = presentationContextProvider
            activeSession = session
            if !session.start() {
                activeSession = nil
                continuation.resume(throwing: YouTubeOAuthError.authorizationFailedMessage("Could not start YouTube authorization."))
            }
        }
    }

    private func exchangeCode(
        _ code: String,
        codeVerifier: String,
        configuration: YouTubeConfiguration
    ) async throws -> YouTubeAccessTokenResponse {
        guard let clientID = configuration.clientID, let redirectURI = configuration.redirectURI else {
            throw YouTubeOAuthError.notConfigured("YouTube OAuth needs a client ID and redirect URI.")
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString)
        ].formURLEncodedData

        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeOAuthError.tokenExchangeFailed(statusCode: nil, message: "Google did not return a valid token response.", rawResponse: rawResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(GoogleOAuthErrorResponse.self, from: data)
            throw YouTubeOAuthError.tokenExchangeFailed(
                statusCode: httpResponse.statusCode,
                message: payload?.displayMessage ?? "Google token exchange failed with HTTP \(httpResponse.statusCode).",
                rawResponse: rawResponse
            )
        }

        do {
            return try JSONDecoder().decode(YouTubeAccessTokenResponse.self, from: data)
        } catch {
            throw YouTubeOAuthError.tokenExchangeFailed(
                statusCode: httpResponse.statusCode,
                message: "Could not decode Google token response: \(error.localizedDescription)",
                rawResponse: rawResponse
            )
        }
    }

    private static func parseAuthorizationCallback(_ url: URL, expectedState: String) throws -> (code: String, state: String) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw YouTubeOAuthError.missingAuthorizationCode
        }
        let queryItems = components.queryItems ?? []
        if let error = queryItems.value(named: "error") {
            throw YouTubeOAuthError.authorizationFailedMessage(error)
        }
        guard queryItems.value(named: "state") == expectedState else {
            throw YouTubeOAuthError.stateMismatch
        }
        guard let code = queryItems.value(named: "code"), !code.isEmpty else {
            throw YouTubeOAuthError.missingAuthorizationCode
        }
        return (code, expectedState)
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

nonisolated struct YouTubeTokenStore {
    private let prefix = "youtube_oauth_tokens.v1"
    var store: SecretStoring = KeychainSecretStore(synchronizesAcrossDevices: false)

    func save(_ bundle: LoginKitTokenBundle, for account: ConnectedAccount) throws {
        let data = try JSONEncoder.flick.encode(bundle)
        try store.save(data, for: key(for: account))
    }

    func saveAsync(_ bundle: LoginKitTokenBundle, for account: ConnectedAccount) async throws {
        let data = try JSONEncoder.flick.encode(bundle)
        try await store.saveAsync(data, for: key(for: account))
    }

    func tokenBundle(for account: ConnectedAccount) throws -> LoginKitTokenBundle? {
        guard let data = try store.data(for: key(for: account)) else { return nil }
        return try JSONDecoder.flick.decode(LoginKitTokenBundle.self, from: data)
    }

    func tokenBundleAsync(for account: ConnectedAccount) async throws -> LoginKitTokenBundle? {
        guard let data = try await store.dataAsync(for: key(for: account)) else { return nil }
        return try JSONDecoder.flick.decode(LoginKitTokenBundle.self, from: data)
    }

    func deleteTokenBundle(for account: ConnectedAccount) throws {
        try store.delete(key(for: account))
    }

    func deleteTokenBundleAsync(for account: ConnectedAccount) async throws {
        try await store.deleteAsync(key(for: account))
    }

    private func key(for account: ConnectedAccount) -> String {
        "\(prefix).\(account.platform.rawValue).\(account.platformUserID)"
    }
}

enum YouTubeOAuthError: LocalizedError {
    case notConfigured(String)
    case authorizationUnavailableOnThisPlatform
    case authorizationCanceled
    case authorizationFailedMessage(String)
    case stateMismatch
    case missingAuthorizationCode
    case missingRefreshToken
    case missingStoredToken(accountID: UUID, platformUserID: String)
    case keychainReadFailed(accountID: UUID, underlyingMessage: String)
    case refreshTokenExpired(accountID: UUID, expiredAt: Date)
    case tokenExchangeFailed(statusCode: Int?, message: String, rawResponse: String)
    case refreshRequestFailed(accountID: UUID, statusCode: Int?, message: String, rawResponse: String)
    case channelRequestFailed(statusCode: Int?, message: String, rawResponse: String)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(message):
            return message
        case .authorizationUnavailableOnThisPlatform:
            return AccountManagementPolicy.unavailableMessage(for: .youtubeShorts)
        case .authorizationCanceled:
            return "YouTube authorization was canceled."
        case let .authorizationFailedMessage(message):
            return message
        case .stateMismatch:
            return "YouTube authorization state did not match the active login request."
        case .missingAuthorizationCode:
            return "YouTube did not return an authorization code."
        case .missingRefreshToken:
            return "Google did not return a refresh token. Try connecting the YouTube channel again and approve offline access."
        case .missingStoredToken:
            return "Authorize this YouTube channel on this Mac before scheduled publishing can use it."
        case let .keychainReadFailed(_, underlyingMessage):
            return "Could not read the YouTube OAuth token bundle from Keychain: \(underlyingMessage)"
        case let .refreshTokenExpired(_, expiredAt):
            return "The stored YouTube refresh token expired at \(expiredAt.formatted(.iso8601)). Reconnect YouTube and try again."
        case let .tokenExchangeFailed(statusCode, message, _),
             let .refreshRequestFailed(_, statusCode, message, _),
             let .channelRequestFailed(statusCode, message, _):
            let http = statusCode.map { " HTTP \($0)." } ?? ""
            return "\(message)\(http)"
        }
    }

    var diagnosticDescription: String {
        switch self {
        case let .notConfigured(message):
            "notConfigured message=\(message)"
        case .authorizationUnavailableOnThisPlatform:
            "authorizationUnavailableOnThisPlatform"
        case .authorizationCanceled:
            "authorizationCanceled"
        case let .authorizationFailedMessage(message):
            "authorizationFailed message=\(message)"
        case .stateMismatch:
            "stateMismatch"
        case .missingAuthorizationCode:
            "missingAuthorizationCode"
        case .missingRefreshToken:
            "missingRefreshToken"
        case let .missingStoredToken(accountID, platformUserID):
            "missingStoredToken accountID=\(accountID.uuidString) platformUserID=\(platformUserID)"
        case let .keychainReadFailed(accountID, underlyingMessage):
            "keychainReadFailed accountID=\(accountID.uuidString) underlying=\(underlyingMessage)"
        case let .refreshTokenExpired(accountID, expiredAt):
            "refreshTokenExpired accountID=\(accountID.uuidString) expiredAt=\(expiredAt.formatted(.iso8601))"
        case let .tokenExchangeFailed(statusCode, message, rawResponse):
            Self.diagnostic(kind: "tokenExchangeFailed", accountID: nil, statusCode: statusCode, message: message, rawResponse: rawResponse)
        case let .refreshRequestFailed(accountID, statusCode, message, rawResponse):
            Self.diagnostic(kind: "refreshRequestFailed", accountID: accountID, statusCode: statusCode, message: message, rawResponse: rawResponse)
        case let .channelRequestFailed(statusCode, message, rawResponse):
            Self.diagnostic(kind: "channelRequestFailed", accountID: nil, statusCode: statusCode, message: message, rawResponse: rawResponse)
        }
    }

    static func authorizationFailed(_ error: Error) -> YouTubeOAuthError {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return .authorizationCanceled
        }
        return .authorizationFailedMessage(error.localizedDescription)
    }

    private static func diagnostic(
        kind: String,
        accountID: UUID?,
        statusCode: Int?,
        message: String,
        rawResponse: String
    ) -> String {
        [
            kind,
            accountID.map { "accountID=\($0.uuidString)" },
            statusCode.map { "status=\($0)" },
            "message=\(message)",
            rawResponse.isEmpty ? nil : "rawResponse=\(rawResponse)"
        ]
        .compactMap(\.self)
        .joined(separator: " ")
    }
}

private struct YouTubeAuthorizationCode: Hashable {
    var code: String
    var codeVerifier: String
}

private struct YouTubeAccessTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: TimeInterval
    var refreshToken: String?
    var scope: String?
    var tokenType: String

    var scopes: [String] {
        (scope ?? "")
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func tokenBundle(
        platformUserID: String,
        refreshToken: String,
        scopes: [String],
        now: Date = Date()
    ) -> LoginKitTokenBundle {
        LoginKitTokenBundle(
            platform: .youtubeShorts,
            platformUserID: platformUserID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            scopes: scopes,
            accessTokenExpiresAt: now.addingTimeInterval(expiresIn),
            refreshTokenExpiresAt: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
            updatedAt: now
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

private struct YouTubeChannelListResponse: Decodable {
    var items: [YouTubeChannel]
}

private struct YouTubeChannel: Decodable {
    var id: String
    var snippet: Snippet

    struct Snippet: Decodable {
        var title: String
        var thumbnails: [String: Thumbnail]?

        var bestThumbnailURL: URL? {
            ["high", "medium", "default"]
                .compactMap { thumbnails?[$0]?.url }
                .first
        }
    }

    struct Thumbnail: Decodable {
        var url: URL?
    }
}

struct YouTubeAPIErrorEnvelope: Decodable {
    var error: YouTubeAPIError
}

struct YouTubeAPIError: Decodable {
    var code: Int?
    var message: String
    var status: String?
}

private struct GoogleOAuthErrorResponse: Decodable {
    var error: String
    var errorDescription: String?

    var displayMessage: String {
        errorDescription ?? error
    }

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private enum PKCE {
    private static let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func makeCodeVerifier(length: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let scene = scenes.first {
            return UIWindow(windowScene: scene)
        }
        preconditionFailure("YouTube OAuth requires an active window scene.")
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

private extension Array where Element == URLQueryItem {
    var formURLEncodedData: Data? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

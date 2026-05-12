//
//  TikTokLoginKitClient.swift
//  Flick
//

import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import Security
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class TikTokLoginKitClient {
    var urlSession: URLSession
    var accountStore: LoginKitAccountStore
    var tokenStore: LoginKitTokenStore

    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var pendingAuthorization: PendingTikTokAuthorization?
    private let presentationContextProvider = WebAuthenticationPresentationContextProvider()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "LoginKit")

    init(
        urlSession: URLSession = .shared,
        accountStore: LoginKitAccountStore? = nil,
        tokenStore: LoginKitTokenStore? = nil
    ) {
        self.urlSession = urlSession
        self.accountStore = accountStore ?? LoginKitAccountStore()
        self.tokenStore = tokenStore ?? LoginKitTokenStore()
    }

    func authorize(configuration: TikTokConfiguration) async throws -> LoginKitAuthorizationResult {
        let authorizationRequest = try TikTokAuthorizationRequest(configuration: configuration)
        if authorizationRequest.usesHTTPSCallback {
            logger.info("Opening TikTok Login Kit authorization in external browser for HTTPS callback.")
            pendingAuthorization = PendingTikTokAuthorization(request: authorizationRequest, configuration: configuration)
            try await openExternalAuthorization(authorizationRequest.authorizationURL)
            return .openedExternalBrowser
        }

        logger.info("Opening TikTok Login Kit authorization with web authentication session.")
        let callbackURL = try await performAuthorization(request: authorizationRequest)
        let account = try await completeAuthorization(callbackURL: callbackURL, request: authorizationRequest, configuration: configuration)
        return .completed(account)
    }

    func handleCallback(_ url: URL) async throws -> ConnectedAccount? {
        guard let pendingAuthorization, pendingAuthorization.request.matchesCallback(url) else {
            return nil
        }

        logger.info("Handling TikTok Login Kit callback.")
        self.pendingAuthorization = nil
        return try await completeAuthorization(
            callbackURL: url,
            request: pendingAuthorization.request,
            configuration: pendingAuthorization.configuration
        )
    }

    func cancelPendingAuthorization() {
        pendingAuthorization = nil
        webAuthenticationSession?.cancel()
        webAuthenticationSession = nil
    }

    private func completeAuthorization(
        callbackURL: URL,
        request: TikTokAuthorizationRequest,
        configuration: TikTokConfiguration
    ) async throws -> ConnectedAccount {
        let callback = try TikTokAuthorizationCallback(url: callbackURL, expectedState: request.state)
        let tokenResponse = try await exchangeCode(
            callback.code,
            codeVerifier: request.codeVerifier,
            configuration: configuration
        )
        let scopes = callback.scopes.isEmpty ? tokenResponse.scopes : callback.scopes
        let account = try await refreshAuthorizedAccount(accessToken: tokenResponse.accessToken, scopes: scopes)
        try tokenStore.save(tokenResponse.tokenBundle(for: account, scopes: scopes), for: account)
        logger.info("Stored TikTok Login Kit account metadata and token bundle.")
        return account
    }

    func refreshAuthorizedAccount(accessToken: String, scopes: [String]) async throws -> ConnectedAccount {
        var components = URLComponents(string: "https://open.tiktokapis.com/v2/user/info/")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "open_id,avatar_url,display_name,username")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw LoginKitError.userInfoRequestFailed
        }

        let payload = try JSONDecoder().decode(TikTokUserInfoResponse.self, from: data)
        guard payload.error.code == "ok" else {
            throw LoginKitError.platformError(payload.error.message)
        }

        let user = LoginKitAuthorizedUser(
            platform: .tiktok,
            openID: payload.data.user.openID,
            displayName: payload.data.user.bestDisplayName,
            avatarURL: payload.data.user.avatarURL,
            scopes: scopes
        )
        let account = LoginKitAccountMapper.connectedAccount(from: user)
        try accountStore.upsert(account)
        return account
    }

    private func performAuthorization(request: TikTokAuthorizationRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: request.authorizationURL, callback: request.callback) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.webAuthenticationSession = nil
                    if let error {
                        continuation.resume(throwing: LoginKitError.authorizationFailed(error))
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: LoginKitError.authorizationFailedMessage("TikTok did not return an authorization callback."))
                    }
                }
            }
            session.presentationContextProvider = presentationContextProvider
            webAuthenticationSession = session

            guard session.start() else {
                webAuthenticationSession = nil
                continuation.resume(throwing: LoginKitError.authorizationFailedMessage("Could not start TikTok Login Kit. Check the redirect URI and associated domain configuration."))
                return
            }
        }
    }

    private func openExternalAuthorization(_ url: URL) async throws {
        #if canImport(UIKit)
        let opened = await UIApplication.shared.open(url)
        guard opened else {
            throw LoginKitError.authorizationFailedMessage("Could not open TikTok authorization in the browser.")
        }
        #else
        throw LoginKitError.authorizationFailedMessage("TikTok browser authorization is only available in the iOS app.")
        #endif
    }

    private func exchangeCode(_ code: String, codeVerifier: String, configuration: TikTokConfiguration) async throws -> TikTokAccessTokenResponse {
        guard
            let clientID = configuration.clientID,
            let clientSecret = configuration.clientSecret,
            let redirectURI = configuration.redirectURI?.absoluteString
        else {
            throw LoginKitError.notConfigured("TikTok Login Kit needs client ID, client secret, and redirect URI.")
        }

        var request = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/oauth/token/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            URLQueryItem(name: "client_key", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ].formURLEncodedData

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoginKitError.tokenExchangeFailed("TikTok did not return a valid token response.")
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let payload = try? JSONDecoder().decode(TikTokOAuthErrorResponse.self, from: data)
            throw LoginKitError.tokenExchangeFailed(payload?.displayMessage ?? "TikTok token exchange failed with HTTP \(httpResponse.statusCode).")
        }

        return try JSONDecoder().decode(TikTokAccessTokenResponse.self, from: data)
    }
}

enum LoginKitError: LocalizedError {
    case notConfigured(String)
    case authorizationCanceled
    case authorizationFailedMessage(String)
    case stateMismatch
    case missingAuthorizationCode
    case tokenExchangeFailed(String)
    case userInfoRequestFailed
    case platformError(String)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(message):
            message
        case .authorizationCanceled:
            "TikTok authorization was canceled."
        case let .authorizationFailedMessage(message):
            message
        case .stateMismatch:
            "TikTok authorization state did not match the active login request."
        case .missingAuthorizationCode:
            "TikTok did not return an authorization code."
        case let .tokenExchangeFailed(message):
            message
        case .userInfoRequestFailed:
            "Could not refresh Login Kit account metadata."
        case let .platformError(message):
            message.isEmpty ? "Login Kit returned an error." : message
        }
    }

    static func authorizationFailed(_ error: Error) -> LoginKitError {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return .authorizationCanceled
        }
        return .authorizationFailedMessage(error.localizedDescription)
    }
}

enum LoginKitAuthorizationResult: Hashable {
    case completed(ConnectedAccount)
    case openedExternalBrowser
}

private struct PendingTikTokAuthorization {
    var request: TikTokAuthorizationRequest
    var configuration: TikTokConfiguration
}

struct TikTokAuthorizationRequest {
    var authorizationURL: URL
    var callback: ASWebAuthenticationSession.Callback
    var redirectURI: URL
    var state: String
    var codeVerifier: String
    var usesHTTPSCallback: Bool {
        redirectURI.scheme == "https"
    }

    init(
        configuration: TikTokConfiguration,
        state: String = OAuthPKCE.randomString(length: 32),
        codeVerifier: String = OAuthPKCE.randomString(length: 64)
    ) throws {
        guard let clientID = configuration.clientID else {
            throw LoginKitError.notConfigured("TikTok client ID is missing.")
        }
        guard let redirectURI = configuration.redirectURI else {
            throw LoginKitError.notConfigured("TikTok redirect URI is missing.")
        }

        self.state = state
        self.codeVerifier = codeVerifier
        self.redirectURI = redirectURI
        self.callback = try Self.callback(for: redirectURI)

        var components = URLComponents(string: "https://www.tiktok.com/v2/auth/authorize/")!
        components.queryItems = [
            URLQueryItem(name: "client_key", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.requestedScopes.joined(separator: ",")),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: OAuthPKCE.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        authorizationURL = components.url!
    }

    func matchesCallback(_ url: URL) -> Bool {
        guard url.scheme == redirectURI.scheme else { return false }
        if usesHTTPSCallback {
            return url.host == redirectURI.host && normalizedPath(url.path) == normalizedPath(redirectURI.path)
        }
        return true
    }

    private static func callback(for redirectURI: URL) throws -> ASWebAuthenticationSession.Callback {
        guard let scheme = redirectURI.scheme, !scheme.isEmpty else {
            throw LoginKitError.notConfigured("TikTok redirect URI needs a URL scheme.")
        }

        if scheme == "https" {
            guard let host = redirectURI.host, !host.isEmpty else {
                throw LoginKitError.notConfigured("TikTok HTTPS redirect URI needs a host.")
            }
            return .https(host: host, path: redirectURI.path.isEmpty ? "/" : redirectURI.path)
        }

        return .customScheme(scheme)
    }

    private func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}

struct TikTokAuthorizationCallback: Hashable {
    var code: String
    var scopes: [String]

    init(url: URL, expectedState: String) throws {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        if let error = queryItems.value(named: "error") {
            let description = queryItems.value(named: "error_description")
            throw LoginKitError.platformError(description ?? error)
        }

        guard queryItems.value(named: "state") == expectedState else {
            throw LoginKitError.stateMismatch
        }
        guard let code = queryItems.value(named: "code"), !code.isEmpty else {
            throw LoginKitError.missingAuthorizationCode
        }

        self.code = code
        self.scopes = Self.splitScopes(queryItems.value(named: "scopes") ?? queryItems.value(named: "scope"))
    }

    private static func splitScopes(_ value: String?) -> [String] {
        value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            ?? []
    }
}

private enum OAuthPKCE {
    private static let allowedCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func randomString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return String(bytes.map { allowedCharacters[Int($0) % allowedCharacters.count] })
    }

    static func codeChallenge(for codeVerifier: String) -> String {
        SHA256.hash(data: Data(codeVerifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct TikTokAccessTokenResponse: Decodable, Hashable {
    var openID: String
    var scope: String
    var accessToken: String
    var expiresIn: TimeInterval
    var refreshToken: String
    var refreshExpiresIn: TimeInterval
    var tokenType: String

    var scopes: [String] {
        scope
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func tokenBundle(for account: ConnectedAccount, scopes: [String], now: Date = Date()) -> LoginKitTokenBundle {
        LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: openID.isEmpty ? account.platformUserID : openID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            scopes: scopes,
            accessTokenExpiresAt: now.addingTimeInterval(expiresIn),
            refreshTokenExpiresAt: now.addingTimeInterval(refreshExpiresIn),
            updatedAt: now
        )
    }

    enum CodingKeys: String, CodingKey {
        case openID = "open_id"
        case scope
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshExpiresIn = "refresh_expires_in"
        case tokenType = "token_type"
    }
}

private struct TikTokOAuthErrorResponse: Decodable {
    var error: String
    var errorDescription: String?
    var logID: String?

    var displayMessage: String {
        var parts = [errorDescription ?? error]
        if let logID, !logID.isEmpty {
            parts.append("Log ID: \(logID)")
        }
        return parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case logID = "log_id"
    }
}

private final class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = windowScenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let window = windowScenes.flatMap(\.windows).first {
            return window
        }
        if let windowScene = windowScenes.first {
            return UIWindow(windowScene: windowScene)
        }
        preconditionFailure("TikTok Login Kit requires an active window scene.")
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

private struct TikTokUserInfoResponse: Decodable {
    var data: DataContainer
    var error: ErrorContainer

    struct DataContainer: Decodable {
        var user: User
    }

    struct User: Decodable {
        var openID: String
        var avatarURL: URL?
        var displayName: String?
        var username: String?

        var bestDisplayName: String {
            if let username, !username.isEmpty {
                return "@\(username)"
            }
            return displayName ?? "TikTok account"
        }

        enum CodingKeys: String, CodingKey {
            case openID = "open_id"
            case avatarURL = "avatar_url"
            case displayName = "display_name"
            case username
        }
    }

    struct ErrorContainer: Decodable {
        var code: String
        var message: String
    }
}

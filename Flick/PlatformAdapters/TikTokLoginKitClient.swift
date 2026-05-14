//
//  TikTokLoginKitClient.swift
//  Flick
//

import AuthenticationServices
import Foundation
import OSLog
#if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenAuthSDK)
import TikTokOpenAuthSDK
import TikTokOpenSDKCore
#endif

@MainActor
final class TikTokLoginKitClient {
    var urlSession: URLSession
    var accountStore: LoginKitAccountStore
    var tokenStore: LoginKitTokenStore

    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenAuthSDK)
    private var activeAuthorizationRequest: TikTokAuthRequest?
    #endif
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

    func authorize(configuration: TikTokConfiguration) async throws -> ConnectedAccount {
        guard AccountManagementPolicy.canAuthorizeAccountsOnThisDevice else {
            throw LoginKitError.authorizationUnavailableOnThisPlatform
        }

        logger.info("Opening TikTok Login Kit authorization with TikTok OpenSDK.")
        let authorizationCode = try await requestAuthorizationCode(configuration: configuration)
        return try await completeAuthorization(authorizationCode, configuration: configuration)
    }

    func cancelPendingAuthorization() {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenAuthSDK)
        activeAuthorizationRequest = nil
        #endif
    }

    private func completeAuthorization(
        _ authorizationCode: TikTokAuthorizationCode,
        configuration: TikTokConfiguration
    ) async throws -> ConnectedAccount {
        let tokenResponse = try await exchangeCode(
            authorizationCode.code,
            codeVerifier: authorizationCode.codeVerifier,
            configuration: configuration
        )
        let scopes = authorizationCode.scopes.isEmpty ? tokenResponse.scopes : authorizationCode.scopes
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

    private func requestAuthorizationCode(configuration: TikTokConfiguration) async throws -> TikTokAuthorizationCode {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenAuthSDK)
        let parameters = try TikTokLoginKitAuthorizationParameters(configuration: configuration)
        try configureOpenSDKClientKey(from: configuration)
        let request = TikTokAuthRequest(scopes: parameters.scopes, redirectURI: parameters.redirectURI)
        request.state = parameters.state

        return try await withCheckedThrowingContinuation { continuation in
            activeAuthorizationRequest = request
            let didSend = request.send { [weak self, weak request] response in
                Task { @MainActor in
                    self?.finishAuthorization(
                        response: response,
                        request: request,
                        parameters: parameters,
                        continuation: continuation
                    )
                }
            }
            if !didSend {
                activeAuthorizationRequest = nil
                continuation.resume(throwing: LoginKitError.authorizationFailedMessage("Could not start TikTok Login Kit. Check the OpenSDK Info.plist configuration and associated domain setup."))
            }
        }
        #else
        throw LoginKitError.notConfigured("TikTok OpenSDK is not linked for the iOS app.")
        #endif
    }

    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenAuthSDK)
    private func configureOpenSDKClientKey(from configuration: TikTokConfiguration) throws {
        guard let configuredClientID = configuration.clientID else {
            throw LoginKitError.notConfigured("TikTok client ID is missing.")
        }
        guard let infoDictionary = Bundle.main.infoDictionary as NSDictionary? else {
            throw LoginKitError.notConfigured("Could not configure TikTok OpenSDK client key.")
        }

        infoDictionary.setValue(configuredClientID, forKey: "TikTokClientKey")
    }

    private func finishAuthorization(
        response: TikTokBaseResponse,
        request: TikTokAuthRequest?,
        parameters: TikTokLoginKitAuthorizationParameters,
        continuation: CheckedContinuation<TikTokAuthorizationCode, Error>
    ) {
        defer {
            activeAuthorizationRequest = nil
        }

        guard let authResponse = response as? TikTokAuthResponse else {
            continuation.resume(throwing: LoginKitError.authorizationFailedMessage("TikTok Login Kit returned an unexpected authorization response."))
            return
        }

        guard authResponse.errorCode == .noError else {
            continuation.resume(throwing: LoginKitError.authorizationFailed(authResponse))
            return
        }
        guard authResponse.state == parameters.state else {
            continuation.resume(throwing: LoginKitError.stateMismatch)
            return
        }
        guard let code = authResponse.authCode, !code.isEmpty else {
            continuation.resume(throwing: LoginKitError.missingAuthorizationCode)
            return
        }
        guard let codeVerifier = request?.pkce.codeVerifier, !codeVerifier.isEmpty else {
            continuation.resume(throwing: LoginKitError.authorizationFailedMessage("TikTok Login Kit did not retain a PKCE verifier for token exchange."))
            return
        }

        let scopes = Array(authResponse.grantedPermissions ?? parameters.scopes).sorted()
        continuation.resume(returning: TikTokAuthorizationCode(
            code: code,
            codeVerifier: codeVerifier,
            scopes: scopes
        ))
    }
    #endif

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
    case authorizationUnavailableOnThisPlatform
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
        case .authorizationUnavailableOnThisPlatform:
            AccountManagementPolicy.unavailableMessage
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

    #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenAuthSDK)
    static func authorizationFailed(_ response: TikTokAuthResponse) -> LoginKitError {
        if response.errorCode == .cancelled {
            return .authorizationCanceled
        }

        let message = response.errorDescription ?? response.error ?? "TikTok authorization failed with code \(response.errorCode.rawValue)."
        return .authorizationFailedMessage(message)
    }
    #endif
}

struct TikTokLoginKitAuthorizationParameters: Hashable {
    var scopes: Set<String>
    var redirectURI: String
    var state: String

    init(configuration: TikTokConfiguration, state: String = UUID().uuidString) throws {
        guard configuration.clientIDPresent else {
            throw LoginKitError.notConfigured("TikTok client ID is missing.")
        }
        guard let redirectURI = configuration.redirectURI else {
            throw LoginKitError.notConfigured("TikTok redirect URI is missing.")
        }
        guard redirectURI.scheme == "https", redirectURI.host?.isEmpty == false else {
            throw LoginKitError.notConfigured("TikTok Login Kit for iOS requires an HTTPS universal-link redirect URI.")
        }
        guard !configuration.requestedScopes.isEmpty else {
            throw LoginKitError.notConfigured("TikTok Login Kit needs at least one requested scope.")
        }

        self.scopes = Set(configuration.requestedScopes)
        self.redirectURI = redirectURI.absoluteString
        self.state = state
    }
}

private struct TikTokAuthorizationCode: Hashable {
    var code: String
    var codeVerifier: String
    var scopes: [String]
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

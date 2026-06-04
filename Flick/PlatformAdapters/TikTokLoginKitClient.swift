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
    private var activeAuthorizationContinuation: CheckedContinuation<TikTokAuthorizationCode, Error>?
    private var activeAuthorizationTimeoutTask: Task<Void, Never>?
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
        completeActiveAuthorization(.failure(LoginKitError.authorizationCanceled))
        #endif
    }

    private func completeAuthorization(
        _ authorizationCode: TikTokAuthorizationCode,
        configuration: TikTokConfiguration
    ) async throws -> ConnectedAccount {
        logger.info("Completing TikTok Login Kit authorization scopes=\(authorizationCode.scopes.joined(separator: ","), privacy: .public)")
        let tokenResponse = try await exchangeCode(
            authorizationCode.code,
            codeVerifier: authorizationCode.codeVerifier,
            configuration: configuration
        )
        let scopes = authorizationCode.scopes.isEmpty ? tokenResponse.scopes : authorizationCode.scopes
        logger.info("TikTok Login Kit token exchange succeeded openID=\(tokenResponse.openID, privacy: .public) scopes=\(scopes.joined(separator: ","), privacy: .public)")
        let account = try await refreshAuthorizedAccount(accessToken: tokenResponse.accessToken, scopes: scopes)
        try tokenStore.save(tokenResponse.tokenBundle(for: account, scopes: scopes), for: account)
        logger.info("Stored TikTok Login Kit account metadata and token bundle.")
        return account
    }

    func refreshAuthorizedAccount(accessToken: String, scopes: [String]) async throws -> ConnectedAccount {
        var components = URLComponents(string: "https://open.tiktokapis.com/v2/user/info/")!
        let fields = ["open_id", "avatar_url", "display_name"]
        components.queryItems = [
            URLQueryItem(name: "fields", value: fields.joined(separator: ","))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        logger.info("Refreshing TikTok Login Kit account metadata fields=\(fields.joined(separator: ","), privacy: .public) scopes=\(scopes.joined(separator: ","), privacy: .public)")
        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            let error = LoginKitError.userInfoRequestFailed(
                statusCode: nil,
                code: nil,
                message: "TikTok did not return a valid account metadata response.",
                logID: nil,
                rawResponse: rawResponse
            )
            logUserInfoFailure(error)
            throw error
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(TikTokUserInfoErrorResponse.self, from: data)
            let error = LoginKitError.userInfoRequestFailed(
                statusCode: httpResponse.statusCode,
                code: payload?.error.code,
                message: payload?.error.displayMessage ?? "TikTok account metadata request failed with HTTP \(httpResponse.statusCode).",
                logID: payload?.error.logID,
                rawResponse: rawResponse
            )
            logUserInfoFailure(error)
            throw error
        }

        let payload: TikTokUserInfoResponse
        do {
            payload = try JSONDecoder().decode(TikTokUserInfoResponse.self, from: data)
        } catch {
            let loginError = LoginKitError.userInfoRequestFailed(
                statusCode: httpResponse.statusCode,
                code: nil,
                message: "Could not decode TikTok account metadata: \(error.localizedDescription)",
                logID: nil,
                rawResponse: rawResponse
            )
            logUserInfoFailure(loginError)
            throw loginError
        }
        guard payload.error.code == "ok" else {
            let error = LoginKitError.userInfoRequestFailed(
                statusCode: httpResponse.statusCode,
                code: payload.error.code,
                message: payload.error.displayMessage,
                logID: payload.error.logID,
                rawResponse: rawResponse
            )
            logUserInfoFailure(error)
            throw error
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

    private func logUserInfoFailure(_ error: LoginKitError) {
        logger.error("TikTok Login Kit account metadata failure: \(error.diagnosticDescription, privacy: .public)")
        print("[TikTokLoginKit] Account metadata failure: \(error.diagnosticDescription)")
    }

    private func requestAuthorizationCode(configuration: TikTokConfiguration) async throws -> TikTokAuthorizationCode {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(TikTokOpenAuthSDK)
        let parameters = try TikTokLoginKitAuthorizationParameters(configuration: configuration)
        try configureOpenSDKClientKey(from: configuration)
        let request = TikTokAuthRequest(scopes: parameters.scopes, redirectURI: parameters.redirectURI)
        request.state = parameters.state

        return try await withCheckedThrowingContinuation { continuation in
            activeAuthorizationRequest = request
            activeAuthorizationContinuation = continuation
            activeAuthorizationTimeoutTask?.cancel()
            activeAuthorizationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.completeActiveAuthorization(.failure(LoginKitError.authorizationTimedOut))
                }
            }

            let didSend = request.send { [weak self, weak request] response in
                Task { @MainActor in
                    self?.finishAuthorization(
                        response: response,
                        request: request,
                        parameters: parameters
                    )
                }
            }
            if !didSend {
                completeActiveAuthorization(.failure(LoginKitError.authorizationFailedMessage("Could not start TikTok Login Kit. Check the OpenSDK Info.plist configuration and associated domain setup.")))
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
        parameters: TikTokLoginKitAuthorizationParameters
    ) {
        guard let authResponse = response as? TikTokAuthResponse else {
            completeActiveAuthorization(.failure(LoginKitError.authorizationFailedMessage("TikTok Login Kit returned an unexpected authorization response.")))
            return
        }

        guard authResponse.errorCode == .noError else {
            completeActiveAuthorization(.failure(LoginKitError.authorizationFailed(authResponse)))
            return
        }
        guard authResponse.state == parameters.state else {
            completeActiveAuthorization(.failure(LoginKitError.stateMismatch))
            return
        }
        guard let code = authResponse.authCode, !code.isEmpty else {
            completeActiveAuthorization(.failure(LoginKitError.missingAuthorizationCode))
            return
        }
        guard let codeVerifier = request?.pkce.codeVerifier, !codeVerifier.isEmpty else {
            completeActiveAuthorization(.failure(LoginKitError.authorizationFailedMessage("TikTok Login Kit did not retain a PKCE verifier for token exchange.")))
            return
        }

        let scopes = Array(authResponse.grantedPermissions ?? parameters.scopes).sorted()
        completeActiveAuthorization(.success(TikTokAuthorizationCode(
            code: code,
            codeVerifier: codeVerifier,
            scopes: scopes
        )))
    }

    private func completeActiveAuthorization(_ result: Result<TikTokAuthorizationCode, Error>) {
        guard let continuation = activeAuthorizationContinuation else { return }

        activeAuthorizationContinuation = nil
        activeAuthorizationTimeoutTask?.cancel()
        activeAuthorizationTimeoutTask = nil
        activeAuthorizationRequest = nil

        switch result {
        case let .success(authorizationCode):
            continuation.resume(returning: authorizationCode)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
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
    case authorizationTimedOut
    case authorizationFailedMessage(String)
    case stateMismatch
    case missingAuthorizationCode
    case tokenExchangeFailed(String)
    case userInfoRequestFailed(statusCode: Int?, code: String?, message: String, logID: String?, rawResponse: String)
    case platformError(String)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(message):
            return message
        case .authorizationUnavailableOnThisPlatform:
            return AccountManagementPolicy.unavailableMessage
        case .authorizationCanceled:
            return "TikTok authorization was canceled."
        case .authorizationTimedOut:
            return "TikTok authorization timed out. TikTok redirected to the configured Universal Link, but Flick did not receive the callback. Verify the thready.it.com apple-app-site-association file, Apple CDN cache, and reinstall the app after the Associated Domain is live."
        case let .authorizationFailedMessage(message):
            return message
        case .stateMismatch:
            return "TikTok authorization state did not match the active login request."
        case .missingAuthorizationCode:
            return "TikTok did not return an authorization code."
        case let .tokenExchangeFailed(message):
            return message
        case let .userInfoRequestFailed(statusCode, code, message, logID, _):
            let http = statusCode.map { " HTTP \($0)." } ?? ""
            let codeSuffix = code.map { " TikTok code: \($0)." } ?? ""
            let logSuffix = logID.map { " TikTok log ID: \($0)." } ?? ""
            return "Could not refresh Login Kit account metadata.\(http) \(message)\(codeSuffix)\(logSuffix)"
        case let .platformError(message):
            return message.isEmpty ? "Login Kit returned an error." : message
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
        case .authorizationTimedOut:
            "authorizationTimedOut"
        case let .authorizationFailedMessage(message):
            "authorizationFailed message=\(message)"
        case .stateMismatch:
            "stateMismatch"
        case .missingAuthorizationCode:
            "missingAuthorizationCode"
        case let .tokenExchangeFailed(message):
            "tokenExchangeFailed message=\(message)"
        case let .userInfoRequestFailed(statusCode, code, message, logID, rawResponse):
            [
                "userInfoRequestFailed",
                statusCode.map { "status=\($0)" },
                code.map { "code=\($0)" },
                logID.map { "logID=\($0)" },
                "message=\(message)",
                rawResponse.isEmpty ? nil : "rawResponse=\(rawResponse)"
            ]
            .compactMap(\.self)
            .joined(separator: " ")
        case let .platformError(message):
            "platformError message=\(message)"
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
        try TikTokRedirectPolicy.validateLoginKitRedirectURI(redirectURI)
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

        var bestDisplayName: String {
            return displayName ?? "TikTok account"
        }

        enum CodingKeys: String, CodingKey {
            case openID = "open_id"
            case avatarURL = "avatar_url"
            case displayName = "display_name"
        }
    }

    struct ErrorContainer: Decodable {
        var code: String
        var message: String
        var logID: String?

        var displayMessage: String {
            message.isEmpty ? code : message
        }

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case logID = "log_id"
        }
    }
}

private struct TikTokUserInfoErrorResponse: Decodable {
    var error: TikTokUserInfoResponse.ErrorContainer
}

//
//  TikTokAdapter.swift
//  Flick
//

import Foundation
import OSLog

struct TikTokAdapter: SocialPlatformAdapter {
    let configuration: TikTokConfiguration
    var tokenStore: LoginKitTokenStore
    var urlSession: URLSession
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "TikTokPublishing")

    var platform: SocialPlatform { .tiktok }

    init(
        configuration: TikTokConfiguration,
        tokenStore: SecretStoring = KeychainSecretStore(synchronizesAcrossDevices: true),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenStore = LoginKitTokenStore(store: tokenStore)
        self.urlSession = urlSession
    }

    func connectAccount() async throws -> ConnectedAccount {
        guard configuration.clientIDPresent, configuration.redirectURI != nil else {
            throw PlatformAdapterError.notConfigured("TikTok OAuth requires a client ID and redirect URI.")
        }

        throw PlatformAdapterError.missingAccountToken
    }

    func validateAccount(_ account: ConnectedAccount) async throws -> PlatformAccountStatus {
        guard account.platform == .tiktok else {
            throw PlatformAdapterError.futurePlatform(account.platform)
        }
        guard account.tokenStatus == .valid else {
            throw PlatformAdapterError.missingAccountToken
        }

        return PlatformAccountStatus(
            accountID: account.id,
            status: account.status,
            scopes: account.scopes,
            canDirectPublish: account.scopes.contains("video.publish"),
            privacyOptions: TikTokPrivacyLevel.directPostOptions,
            lastCheckedAt: Date()
        )
    }

    func prepareMedia(_ draft: SlideshowDraft, mode: PublishMode) async throws -> PreparedPlatformMedia {
        switch mode {
        case .photoDirectPost, .photoUploadForCompletion:
            return PreparedPlatformMedia(mode: mode, imageURLs: [], videoURL: nil, warnings: missingImageWarnings(for: draft))
        case .videoDirectPost, .videoUploadForCompletion:
            return PreparedPlatformMedia(mode: mode, imageURLs: [], videoURL: nil, warnings: ["Video rendering must complete before TikTok upload."])
        }
    }

    func publish(_ job: PublishingJob, media: PreparedPlatformMedia) async throws -> PublishResult {
        throw PlatformAdapterError.missingAccountToken
    }

    func publish(
        _ job: PublishingJob,
        account: ConnectedAccount,
        media: PreparedPlatformMedia,
        settings: TikTokManualPublishSettings
    ) async throws -> PublishResult {
        guard job.platform == .tiktok else {
            throw PlatformAdapterError.futurePlatform(job.platform)
        }
        guard account.platform == .tiktok, account.id == job.accountID else {
            throw PlatformAdapterError.futurePlatform(account.platform)
        }
        guard configuration.clientIDPresent else {
            throw PlatformAdapterError.notConfigured("TikTok client ID is missing.")
        }
        guard configuration.verifiedBaseURL != nil else {
            throw PlatformAdapterError.notConfigured("TikTok photo publishing requires a verified media URL prefix.")
        }
        guard !media.imageURLs.isEmpty else {
            throw PlatformAdapterError.notConfigured("TikTok photo publishing needs at least one rendered image URL.")
        }
        guard media.imageURLs.count <= 35 else {
            throw PlatformAdapterError.notConfigured("TikTok photo publishing supports up to 35 images.")
        }
        guard account.scopes.contains(settings.requiredScope) else {
            throw PlatformAdapterError.notConfigured("TikTok account is missing the \(settings.requiredScope) scope.")
        }
        let tokenBundle = try await validTokenBundle(for: account)

        logger.info("Initializing TikTok photo publish jobID=\(job.id.uuidString, privacy: .public) mode=\(settings.tikTokPostMode.rawValue, privacy: .public) images=\(media.imageURLs.count, privacy: .public) privacy=\(settings.privacyLevel.rawValue, privacy: .public)")
        var request = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/post/publish/content/init/")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(tokenBundle.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TikTokPhotoPublishRequest(
                postInfo: TikTokPhotoPostInfo(settings: settings),
                sourceInfo: TikTokPhotoSourceInfo(photoImages: media.imageURLs.map(\.absoluteString)),
                postMode: settings.tikTokPostMode.rawValue,
                mediaType: "PHOTO"
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TikTokPublishAPIError(code: "invalid_response", message: "TikTok returned an invalid response.", logID: nil, rawResponse: rawResponse)
        }

        let payload: TikTokContentInitResponse
        do {
            payload = try JSONDecoder().decode(TikTokContentInitResponse.self, from: data)
        } catch {
            let apiError = TikTokPublishAPIError(
                code: "invalid_response",
                message: "TikTok returned an unreadable publish response: \(error.localizedDescription)",
                logID: nil,
                rawResponse: rawResponse
            )
            logPublishFailure(apiError)
            throw apiError
        }
        guard (200..<300).contains(httpResponse.statusCode), payload.error.code == "ok" else {
            let apiError = TikTokPublishAPIError(
                code: payload.error.code,
                message: payload.error.message.isEmpty ? "TikTok publish initialization failed with HTTP \(httpResponse.statusCode)." : payload.error.message,
                logID: payload.error.logID,
                rawResponse: rawResponse
            )
            logPublishFailure(apiError)
            throw apiError
        }
        guard let publishID = payload.data?.publishID else {
            let apiError = TikTokPublishAPIError(code: "missing_publish_id", message: "TikTok did not return a publish ID.", logID: payload.error.logID, rawResponse: rawResponse)
            logPublishFailure(apiError)
            throw apiError
        }

        logger.info("TikTok photo publish initialized jobID=\(job.id.uuidString, privacy: .public) publishID=\(publishID, privacy: .public)")
        return PublishResult(
            platform: .tiktok,
            platformPostID: publishID,
            platformURL: nil,
            publishedAt: Date(),
            rawResponse: rawResponse
        )
    }

    func fetchAnalytics(for post: PublishedPost) async throws -> AnalyticsSnapshot {
        guard post.platform == .tiktok else {
            throw PlatformAdapterError.futurePlatform(post.platform)
        }
        throw PlatformAdapterError.missingAccountToken
    }

    private func missingImageWarnings(for draft: SlideshowDraft) -> [String] {
        let missingImageCount = draft.slides.filter { $0.imageAssetID == nil }.count
        guard missingImageCount > 0 else { return [] }
        return ["\(missingImageCount) slide images still need generated or uploaded Supabase URLs."]
    }

    private func validTokenBundle(for account: ConnectedAccount) async throws -> LoginKitTokenBundle {
        let bundle: LoginKitTokenBundle
        do {
            guard let storedBundle = try tokenStore.tokenBundle(for: account) else {
                throw TikTokOAuthTokenError.missingStoredToken(accountID: account.id, platformUserID: account.platformUserID)
            }
            bundle = storedBundle
        } catch let error as TikTokOAuthTokenError {
            logOAuthFailure(error)
            throw error
        } catch {
            let tokenError = TikTokOAuthTokenError.keychainReadFailed(accountID: account.id, underlyingMessage: error.localizedDescription)
            logOAuthFailure(tokenError)
            throw tokenError
        }

        let refreshLeeway: TimeInterval = 60
        if bundle.accessTokenExpiresAt > Date().addingTimeInterval(refreshLeeway) {
            return bundle
        }

        guard bundle.refreshTokenExpiresAt > Date() else {
            let tokenError = TikTokOAuthTokenError.refreshTokenExpired(accountID: account.id, expiredAt: bundle.refreshTokenExpiresAt)
            logOAuthFailure(tokenError)
            throw tokenError
        }

        logger.info("Refreshing TikTok access token accountID=\(account.id.uuidString, privacy: .public)")
        do {
            let refreshedBundle = try await refreshTokenBundle(bundle, for: account)
            try tokenStore.save(refreshedBundle, for: account)
            logger.info("Refreshed TikTok access token accountID=\(account.id.uuidString, privacy: .public) scopes=\(refreshedBundle.scopes.joined(separator: ","), privacy: .public)")
            return refreshedBundle
        } catch let error as TikTokOAuthTokenError {
            logOAuthFailure(error)
            throw error
        } catch {
            let tokenError = TikTokOAuthTokenError.refreshRequestFailed(
                accountID: account.id,
                statusCode: nil,
                message: error.localizedDescription,
                logID: nil,
                rawResponse: ""
            )
            logOAuthFailure(tokenError)
            throw tokenError
        }
    }

    private func refreshTokenBundle(_ bundle: LoginKitTokenBundle, for account: ConnectedAccount) async throws -> LoginKitTokenBundle {
        guard let clientID = configuration.clientID, let clientSecret = configuration.clientSecret else {
            throw TikTokOAuthTokenError.refreshNotConfigured(accountID: account.id)
        }

        var request = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/oauth/token/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            URLQueryItem(name: "client_key", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: bundle.refreshToken)
        ].formURLEncodedData

        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TikTokOAuthTokenError.refreshRequestFailed(
                accountID: account.id,
                statusCode: nil,
                message: "TikTok did not return a valid token refresh response.",
                logID: nil,
                rawResponse: rawResponse
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(TikTokOAuthErrorEnvelope.self, from: data)
            throw TikTokOAuthTokenError.refreshRequestFailed(
                accountID: account.id,
                statusCode: httpResponse.statusCode,
                message: payload?.displayMessage ?? "TikTok token refresh failed with HTTP \(httpResponse.statusCode).",
                logID: payload?.logID,
                rawResponse: rawResponse
            )
        }

        do {
            let payload = try JSONDecoder().decode(TikTokAccessTokenRefreshResponse.self, from: data)
            return payload.tokenBundle(fallbackPlatformUserID: account.platformUserID)
        } catch {
            throw TikTokOAuthTokenError.refreshRequestFailed(
                accountID: account.id,
                statusCode: httpResponse.statusCode,
                message: "Could not decode TikTok token refresh response: \(error.localizedDescription)",
                logID: nil,
                rawResponse: rawResponse
            )
        }
    }

    private func logOAuthFailure(_ error: TikTokOAuthTokenError) {
        logger.error("TikTok OAuth token failure: \(error.diagnosticDescription, privacy: .public)")
        print("[TikTokPublishing] OAuth token failure: \(error.diagnosticDescription)")
    }

    private func logPublishFailure(_ error: TikTokPublishAPIError) {
        let detail = error.diagnosticDescription
        logger.error("TikTok publish API failure: \(detail, privacy: .public)")
        print("[TikTokPublishing] API failure: \(detail)")
    }
}

enum TikTokOAuthTokenError: LocalizedError {
    case missingStoredToken(accountID: UUID, platformUserID: String)
    case keychainReadFailed(accountID: UUID, underlyingMessage: String)
    case refreshTokenExpired(accountID: UUID, expiredAt: Date)
    case refreshNotConfigured(accountID: UUID)
    case refreshRequestFailed(accountID: UUID, statusCode: Int?, message: String, logID: String?, rawResponse: String)

    var errorDescription: String? {
        switch self {
        case .missingStoredToken:
            return "No TikTok OAuth token bundle was found in Keychain for this account."
        case let .keychainReadFailed(_, underlyingMessage):
            return "Could not read the TikTok OAuth token bundle from Keychain: \(underlyingMessage)"
        case let .refreshTokenExpired(_, expiredAt):
            return "The stored TikTok refresh token expired at \(expiredAt.formatted(.iso8601)). Reconnect TikTok and try again."
        case .refreshNotConfigured:
            return "TikTok token refresh needs a client key and client secret."
        case let .refreshRequestFailed(_, statusCode, message, logID, _):
            let http = statusCode.map { " HTTP \($0)." } ?? ""
            let logSuffix = logID.map { " TikTok log ID: \($0)." } ?? ""
            return "\(message)\(http)\(logSuffix)"
        }
    }

    var diagnosticDescription: String {
        switch self {
        case let .missingStoredToken(accountID, platformUserID):
            "missingStoredToken accountID=\(accountID.uuidString) platformUserID=\(platformUserID)"
        case let .keychainReadFailed(accountID, underlyingMessage):
            "keychainReadFailed accountID=\(accountID.uuidString) underlying=\(underlyingMessage)"
        case let .refreshTokenExpired(accountID, expiredAt):
            "refreshTokenExpired accountID=\(accountID.uuidString) expiredAt=\(expiredAt.formatted(.iso8601))"
        case let .refreshNotConfigured(accountID):
            "refreshNotConfigured accountID=\(accountID.uuidString)"
        case let .refreshRequestFailed(accountID, statusCode, message, logID, rawResponse):
            [
                "refreshRequestFailed accountID=\(accountID.uuidString)",
                statusCode.map { "status=\($0)" },
                logID.map { "logID=\($0)" },
                "message=\(message)",
                rawResponse.isEmpty ? nil : "rawResponse=\(rawResponse)"
            ]
            .compactMap(\.self)
            .joined(separator: " ")
        }
    }
}

enum TikTokPublishAPIError: LocalizedError {
    case api(code: String, message: String, logID: String?, rawResponse: String)

    init(code: String, message: String, logID: String?, rawResponse: String) {
        self = .api(code: code, message: message, logID: logID, rawResponse: rawResponse)
    }

    var code: String {
        switch self {
        case let .api(code, _, _, _): code
        }
    }

    var rawResponse: String {
        switch self {
        case let .api(_, _, _, rawResponse): rawResponse
        }
    }

    var diagnosticDescription: String {
        switch self {
        case let .api(code, message, logID, rawResponse):
            [
                "code=\(code)",
                logID.map { "logID=\($0)" },
                "message=\(message)",
                rawResponse.isEmpty ? nil : "rawResponse=\(rawResponse)"
            ]
            .compactMap(\.self)
            .joined(separator: " ")
        }
    }

    var errorDescription: String? {
        switch self {
        case let .api(code, message, logID, _):
            let suffix = logID.map { " TikTok log ID: \($0)." } ?? ""
            return "\(message) (\(code)).\(suffix)"
        }
    }
}

private struct TikTokAccessTokenRefreshResponse: Decodable {
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

    func tokenBundle(fallbackPlatformUserID: String, now: Date = Date()) -> LoginKitTokenBundle {
        LoginKitTokenBundle(
            platform: .tiktok,
            platformUserID: openID.isEmpty ? fallbackPlatformUserID : openID,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            scopes: scopes,
            accessTokenExpiresAt: now.addingTimeInterval(expiresIn),
            refreshTokenExpiresAt: now.addingTimeInterval(refreshExpiresIn),
            updatedAt: now
        )
    }

    private enum CodingKeys: String, CodingKey {
        case openID = "open_id"
        case scope
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshExpiresIn = "refresh_expires_in"
        case tokenType = "token_type"
    }
}

private struct TikTokOAuthErrorEnvelope: Decodable {
    var error: String
    var errorDescription: String?
    var logID: String?

    var displayMessage: String {
        errorDescription ?? error
    }

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case logID = "log_id"
    }
}

private enum TikTokPhotoPostMode: String {
    case directPost = "DIRECT_POST"
    case mediaUpload = "MEDIA_UPLOAD"
}

private struct TikTokPhotoPublishRequest: Encodable {
    var postInfo: TikTokPhotoPostInfo
    var sourceInfo: TikTokPhotoSourceInfo
    var postMode: String
    var mediaType: String

    private enum CodingKeys: String, CodingKey {
        case postInfo = "post_info"
        case sourceInfo = "source_info"
        case postMode = "post_mode"
        case mediaType = "media_type"
    }
}

private struct TikTokPhotoPostInfo: Encodable {
    var title: String?
    var description: String?
    var privacyLevel: String?
    var disableComment: Bool?
    var autoAddMusic: Bool?
    var brandContentToggle: Bool?
    var brandOrganicToggle: Bool?

    init(settings: TikTokManualPublishSettings) {
        title = settings.title.nilIfEmpty
        description = settings.description.nilIfEmpty

        guard !settings.postAsDraft else { return }
        privacyLevel = settings.privacyLevel.rawValue
        disableComment = !settings.allowComment
        autoAddMusic = false
        brandContentToggle = settings.disclosesVideoContent && settings.promotesBrandedContent
        brandOrganicToggle = settings.disclosesVideoContent && settings.promotesYourBrand
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case privacyLevel = "privacy_level"
        case disableComment = "disable_comment"
        case autoAddMusic = "auto_add_music"
        case brandContentToggle = "brand_content_toggle"
        case brandOrganicToggle = "brand_organic_toggle"
    }
}

private struct TikTokPhotoSourceInfo: Encodable {
    var source = "PULL_FROM_URL"
    var photoCoverIndex = 0
    var photoImages: [String]

    private enum CodingKeys: String, CodingKey {
        case source
        case photoCoverIndex = "photo_cover_index"
        case photoImages = "photo_images"
    }
}

private struct TikTokContentInitResponse: Decodable {
    var data: TikTokContentInitData?
    var error: TikTokAPIErrorEnvelope
}

private struct TikTokContentInitData: Decodable {
    var publishID: String

    private enum CodingKeys: String, CodingKey {
        case publishID = "publish_id"
    }
}

private struct TikTokAPIErrorEnvelope: Decodable {
    var code: String
    var message: String
    var logID: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case logID = "log_id"
    }
}

private extension TikTokManualPublishSettings {
    var tikTokPostMode: TikTokPhotoPostMode {
        postAsDraft ? .mediaUpload : .directPost
    }

    var requiredScope: String {
        postAsDraft ? "video.upload" : "video.publish"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element == URLQueryItem {
    var formURLEncodedData: Data? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

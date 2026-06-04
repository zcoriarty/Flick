//
//  YouTubeShortsAdapter.swift
//  Flick
//

import Foundation
import OSLog

struct YouTubeShortsAdapter: SocialPlatformPublishing {
    let configuration: YouTubeConfiguration
    var tokenStore: YouTubeTokenStore
    var urlSession: URLSession
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.orion.Flick", category: "YouTubePublishing")

    var platform: SocialPlatform { .youtubeShorts }

    init(
        configuration: YouTubeConfiguration,
        tokenStore: YouTubeTokenStore = YouTubeTokenStore(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.urlSession = urlSession
    }

    func validateAccount(_ account: ConnectedAccount) async throws -> PlatformAccountStatus {
        guard account.platform == .youtubeShorts else {
            throw PlatformAdapterError.futurePlatform(account.platform)
        }
        let bundle = try await validTokenBundle(for: account)
        let scopes = bundle.scopes.isEmpty ? account.scopes : bundle.scopes
        let canUpload = scopes.contains(YouTubeConfiguration.uploadScope)

        return PlatformAccountStatus(
            accountID: account.id,
            status: canUpload ? .connected : .missingScope,
            scopes: scopes,
            canDirectPublish: canUpload,
            privacyOptions: YouTubePrivacyStatus.allCases.map(\.displayName),
            lastCheckedAt: Date()
        )
    }

    func publish(
        _ job: PublishingJob,
        account: ConnectedAccount,
        media: PreparedPlatformMedia,
        settings: YouTubeManualPublishSettings
    ) async throws -> PublishResult {
        guard job.platform == .youtubeShorts else {
            throw PlatformAdapterError.futurePlatform(job.platform)
        }
        guard account.platform == .youtubeShorts, account.id == job.accountID else {
            throw PlatformAdapterError.futurePlatform(account.platform)
        }
        guard configuration.clientIDPresent else {
            throw PlatformAdapterError.notConfigured("YouTube OAuth client ID is missing.")
        }
        guard let videoURL = media.videoURL, videoURL.isFileURL else {
            throw PlatformAdapterError.notConfigured("YouTube Shorts publishing needs a rendered local MP4.")
        }
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw PlatformAdapterError.notConfigured("The rendered YouTube Shorts MP4 is no longer available on this device.")
        }

        let tokenBundle = try await validTokenBundle(for: account)
        let fileSize = try videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int(Data(contentsOf: videoURL).count)
        logger.info("Initializing YouTube Shorts upload jobID=\(job.id.uuidString, privacy: .public) channelID=\(account.platformUserID, privacy: .public) bytes=\(fileSize, privacy: .public) privacy=\(settings.privacyStatus.rawValue, privacy: .public)")

        let uploadURL = try await createResumableUploadSession(
            accessToken: tokenBundle.accessToken,
            settings: settings,
            fileSize: fileSize
        )
        let uploadResponse = try await uploadVideoFile(videoURL, to: uploadURL)
        let videoID = uploadResponse.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !videoID.isEmpty else {
            throw YouTubePublishAPIError(code: nil, status: nil, message: "YouTube did not return an uploaded video ID.", rawResponse: uploadResponse.rawResponse)
        }

        logger.info("YouTube Shorts upload completed jobID=\(job.id.uuidString, privacy: .public) videoID=\(videoID, privacy: .public)")
        return PublishResult(
            platform: .youtubeShorts,
            platformPostID: videoID,
            platformURL: URL(string: "https://www.youtube.com/shorts/\(videoID)"),
            publishedAt: Date(),
            platformStatus: uploadResponse.status?.uploadStatus,
            rawResponse: uploadResponse.rawResponse
        )
    }

    func publish(_ job: PublishingJob, media: PreparedPlatformMedia) async throws -> PublishResult {
        throw PlatformAdapterError.missingAccountToken
    }

    private func createResumableUploadSession(
        accessToken: String,
        settings: YouTubeManualPublishSettings,
        fileSize: Int
    ) async throws -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "part", value: "snippet,status"),
            URLQueryItem(name: "notifySubscribers", value: settings.notifySubscribers ? "true" : "false")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONEncoder().encode(YouTubeVideoInsertRequest(settings: settings))

        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubePublishAPIError(code: nil, status: nil, message: "YouTube did not return a valid upload-session response.", rawResponse: rawResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode), let location = httpResponse.value(forHTTPHeaderField: "Location"), let uploadURL = URL(string: location) else {
            let payload = try? JSONDecoder().decode(YouTubeAPIErrorEnvelope.self, from: data)
            throw YouTubePublishAPIError(
                code: payload?.error.code,
                status: payload?.error.status,
                message: payload?.error.message ?? "YouTube upload session creation failed with HTTP \(httpResponse.statusCode).",
                rawResponse: rawResponse
            )
        }

        return uploadURL
    }

    private func uploadVideoFile(_ videoURL: URL, to uploadURL: URL) async throws -> YouTubeVideoUploadResponse {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.upload(for: request, fromFile: videoURL)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubePublishAPIError(code: nil, status: nil, message: "YouTube did not return a valid upload response.", rawResponse: rawResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(YouTubeAPIErrorEnvelope.self, from: data)
            throw YouTubePublishAPIError(
                code: payload?.error.code,
                status: payload?.error.status,
                message: payload?.error.message ?? "YouTube video upload failed with HTTP \(httpResponse.statusCode).",
                rawResponse: rawResponse
            )
        }

        do {
            var payload = try JSONDecoder().decode(YouTubeVideoUploadResponse.self, from: data)
            payload.rawResponse = rawResponse
            return payload
        } catch {
            throw YouTubePublishAPIError(
                code: nil,
                status: nil,
                message: "Could not decode YouTube upload response: \(error.localizedDescription)",
                rawResponse: rawResponse
            )
        }
    }

    func validTokenBundle(for account: ConnectedAccount) async throws -> LoginKitTokenBundle {
        let bundle: LoginKitTokenBundle
        do {
            guard let storedBundle = try tokenStore.tokenBundle(for: account) else {
                throw YouTubeOAuthError.missingStoredToken(accountID: account.id, platformUserID: account.platformUserID)
            }
            bundle = storedBundle
        } catch let error as YouTubeOAuthError {
            throw error
        } catch {
            throw YouTubeOAuthError.keychainReadFailed(accountID: account.id, underlyingMessage: error.localizedDescription)
        }

        let refreshLeeway: TimeInterval = 60
        if bundle.accessTokenExpiresAt > Date().addingTimeInterval(refreshLeeway) {
            return bundle
        }
        guard bundle.refreshTokenExpiresAt > Date() else {
            throw YouTubeOAuthError.refreshTokenExpired(accountID: account.id, expiredAt: bundle.refreshTokenExpiresAt)
        }

        let refreshedBundle = try await refreshTokenBundle(bundle, for: account)
        try tokenStore.save(refreshedBundle, for: account)
        return refreshedBundle
    }

    private func refreshTokenBundle(_ bundle: LoginKitTokenBundle, for account: ConnectedAccount) async throws -> LoginKitTokenBundle {
        guard let clientID = configuration.clientID else {
            throw YouTubeOAuthError.notConfigured("YouTube token refresh needs GOOGLE_CLIENT_ID.")
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: bundle.refreshToken)
        ].formURLEncodedData

        let (data, response) = try await urlSession.data(for: request)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeOAuthError.refreshRequestFailed(accountID: account.id, statusCode: nil, message: "Google did not return a valid token refresh response.", rawResponse: rawResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? JSONDecoder().decode(GoogleOAuthRefreshErrorResponse.self, from: data)
            throw YouTubeOAuthError.refreshRequestFailed(
                accountID: account.id,
                statusCode: httpResponse.statusCode,
                message: payload?.displayMessage ?? "Google token refresh failed with HTTP \(httpResponse.statusCode).",
                rawResponse: rawResponse
            )
        }

        do {
            let payload = try JSONDecoder().decode(YouTubeRefreshTokenResponse.self, from: data)
            return payload.tokenBundle(from: bundle, now: Date())
        } catch {
            throw YouTubeOAuthError.refreshRequestFailed(
                accountID: account.id,
                statusCode: httpResponse.statusCode,
                message: "Could not decode Google token refresh response: \(error.localizedDescription)",
                rawResponse: rawResponse
            )
        }
    }
}

enum YouTubePublishAPIError: LocalizedError {
    case api(code: Int?, status: String?, message: String, rawResponse: String)

    init(code: Int?, status: String?, message: String, rawResponse: String) {
        self = .api(code: code, status: status, message: message, rawResponse: rawResponse)
    }

    var status: String? {
        switch self {
        case let .api(_, status, _, _): status
        }
    }

    var rawResponse: String {
        switch self {
        case let .api(_, _, _, rawResponse): rawResponse
        }
    }

    var errorDescription: String? {
        switch self {
        case let .api(code, status, message, _):
            let codeText = code.map { " HTTP \($0)." } ?? ""
            let statusText = status.map { " YouTube status: \($0)." } ?? ""
            return "\(message)\(codeText)\(statusText)"
        }
    }
}

private struct YouTubeVideoInsertRequest: Encodable {
    var snippet: Snippet
    var status: Status

    init(settings: YouTubeManualPublishSettings) {
        snippet = Snippet(
            title: settings.title,
            description: settings.description,
            tags: settings.tags.isEmpty ? nil : settings.tags,
            categoryID: settings.categoryID
        )
        status = Status(
            privacyStatus: settings.privacyStatus.rawValue,
            selfDeclaredMadeForKids: settings.selfDeclaredMadeForKids,
            containsSyntheticMedia: settings.containsSyntheticMedia
        )
    }

    struct Snippet: Encodable {
        var title: String
        var description: String
        var tags: [String]?
        var categoryID: String

        private enum CodingKeys: String, CodingKey {
            case title
            case description
            case tags
            case categoryID = "categoryId"
        }
    }

    struct Status: Encodable {
        var privacyStatus: String
        var selfDeclaredMadeForKids: Bool
        var containsSyntheticMedia: Bool
    }
}

private struct YouTubeVideoUploadResponse: Decodable {
    var id: String
    var status: Status?
    var rawResponse = ""

    struct Status: Decodable {
        var uploadStatus: String?
        var privacyStatus: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case status
    }
}

private struct YouTubeRefreshTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: TimeInterval
    var scope: String?
    var tokenType: String

    func tokenBundle(from existingBundle: LoginKitTokenBundle, now: Date) -> LoginKitTokenBundle {
        let scopes = (scope ?? "")
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return LoginKitTokenBundle(
            platform: .youtubeShorts,
            platformUserID: existingBundle.platformUserID,
            accessToken: accessToken,
            refreshToken: existingBundle.refreshToken,
            tokenType: tokenType,
            scopes: scopes.isEmpty ? existingBundle.scopes : scopes,
            accessTokenExpiresAt: now.addingTimeInterval(expiresIn),
            refreshTokenExpiresAt: existingBundle.refreshTokenExpiresAt,
            updatedAt: now
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

private struct GoogleOAuthRefreshErrorResponse: Decodable {
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

private extension Array where Element == URLQueryItem {
    var formURLEncodedData: Data? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

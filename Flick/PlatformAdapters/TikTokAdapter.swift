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
        guard let tokenBundle = try tokenStore.tokenBundle(for: account), tokenBundle.accessTokenExpiresAt > Date() else {
            throw PlatformAdapterError.missingAccountToken
        }

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

        let payload = try JSONDecoder().decode(TikTokContentInitResponse.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode), payload.error.code == "ok" else {
            throw TikTokPublishAPIError(
                code: payload.error.code,
                message: payload.error.message.isEmpty ? "TikTok publish initialization failed with HTTP \(httpResponse.statusCode)." : payload.error.message,
                logID: payload.error.logID,
                rawResponse: rawResponse
            )
        }
        guard let publishID = payload.data?.publishID else {
            throw TikTokPublishAPIError(code: "missing_publish_id", message: "TikTok did not return a publish ID.", logID: payload.error.logID, rawResponse: rawResponse)
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

    var errorDescription: String? {
        switch self {
        case let .api(code, message, logID, _):
            let suffix = logID.map { " TikTok log ID: \($0)." } ?? ""
            return "\(message) (\(code)).\(suffix)"
        }
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

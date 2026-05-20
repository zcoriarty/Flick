//
//  AppConfiguration.swift
//  Flick
//

import Foundation

struct AppConfiguration: Hashable {
    var r2: R2StorageConfiguration
    var tiktok: TikTokConfiguration
    var openAI: OpenAIConfiguration
    var meta: MetaConfiguration
    var storagePaths: R2StoragePaths
    var renderDirectory: URL
    var secureStoredCredentialKeys: Set<String>

    static var current: AppConfiguration {
        let credentialVault = CredentialVault()
        let values = credentialVault.loadValues()
        let secureStoredCredentialKeys = Set(values.keys)
        return AppConfiguration(
            r2: R2StorageConfiguration(values: values),
            tiktok: TikTokConfiguration(values: values),
            openAI: OpenAIConfiguration(values: values),
            meta: MetaConfiguration(values: values),
            storagePaths: R2StoragePaths(),
            renderDirectory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appending(path: "Flick/Renders", directoryHint: .isDirectory)
                ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Flick/Renders", directoryHint: .isDirectory),
            secureStoredCredentialKeys: secureStoredCredentialKeys
        )
    }

    var credentialStatuses: [CredentialStatus] {
        CredentialDefinition.supported.map(credentialStatus(for:))
    }

    private func credentialStatus(for definition: CredentialDefinition) -> CredentialStatus {
        let isPresent = secureStoredCredentialKeys.contains(definition.key)

        return CredentialStatus(
            key: definition.key,
            name: definition.name,
            isPresent: isPresent,
            source: isPresent ? .secureStore : .missing
        )
    }
}

struct R2StorageConfiguration: Hashable {
    var endpointURL: URL?
    var publicBaseURL: URL?
    var accountIDPresent: Bool
    var accessKeyIDPresent: Bool
    var secretAccessKeyPresent: Bool
    var bucket: String?

    var isConfigured: Bool {
        endpointURL != nil
            && publicBaseURL != nil
            && accessKeyIDPresent
            && secretAccessKeyPresent
            && bucket != nil
    }

    init(values: [String: String]) {
        let accountID = values.nonEmptyString("R2_ACCOUNT_ID")
        let derivedEndpointURL = accountID.flatMap { URL(string: "https://\($0).r2.cloudflarestorage.com") }
        endpointURL = values.nonEmptyURL("R2_S3_ENDPOINT")
            ?? derivedEndpointURL
        publicBaseURL = values.nonEmptyURL("R2_PUBLIC_BASE_URL")
        accountIDPresent = accountID != nil
        accessKeyIDPresent = values.hasNonEmptyValue("R2_ACCESS_KEY_ID")
        secretAccessKeyPresent = values.hasNonEmptyValue("R2_SECRET_ACCESS_KEY")
        bucket = values.nonEmptyString("R2_BUCKET")
    }
}

struct TikTokConfiguration: Hashable {
    var clientID: String?
    var clientSecret: String?
    var redirectURI: URL?
    var verifiedBaseURL: URL?
    var requestedScopes: [String]

    var clientIDPresent: Bool { clientID != nil }
    var clientSecretPresent: Bool { clientSecret != nil }

    init(values: [String: String]) {
        clientID = values.nonEmptyString("TIKTOK_CLIENT_ID")
        clientSecret = values.nonEmptyString("TIKTOK_CLIENT_SECRET")
        redirectURI = values.nonEmptyURL("TIKTOK_REDIRECT_URI")
        verifiedBaseURL = values.nonEmptyURL("TIKTOK_VERIFIED_BASE_URL")
            ?? values.nonEmptyURL("R2_PUBLIC_BASE_URL")
        requestedScopes = values
            .nonEmptyString("TIKTOK_SCOPES")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            ?? ["user.info.basic", "video.publish", "video.upload"]
    }
}

struct OpenAIConfiguration: Hashable {
    var apiKeyPresent: Bool

    init(values: [String: String]) {
        apiKeyPresent = values.hasNonEmptyValue("OPENAI_API_KEY")
    }
}

struct MetaConfiguration: Hashable {
    var clientIDPresent: Bool
    var clientSecretPresent: Bool

    init(values: [String: String]) {
        clientIDPresent = values.hasNonEmptyValue("META_CLIENT_ID")
        clientSecretPresent = values.hasNonEmptyValue("META_CLIENT_SECRET")
    }
}

struct R2StoragePaths: Hashable {
    var productMedia = "product-media"
    var generatedImages = "generated-slides"
    var renderedImages = "rendered-image-sequences"
    var referenceImages = "reference-images"
    var thumbnails = "thumbnails"

    var all: [String] {
        [
            productMedia,
            generatedImages,
            renderedImages,
            referenceImages,
            thumbnails
        ]
    }
}

struct CredentialDefinition: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var name: String

    static let supported: [CredentialDefinition] = [
        CredentialDefinition(key: "META_CLIENT_ID", name: "Meta client ID"),
        CredentialDefinition(key: "META_CLIENT_SECRET", name: "Meta client secret"),
        CredentialDefinition(key: "OPENAI_API_KEY", name: "OpenAI API key"),
        CredentialDefinition(key: "R2_ACCESS_KEY_ID", name: "Cloudflare R2 access key ID"),
        CredentialDefinition(key: "R2_ACCOUNT_ID", name: "Cloudflare R2 account ID"),
        CredentialDefinition(key: "R2_BUCKET", name: "Cloudflare R2 bucket"),
        CredentialDefinition(key: "R2_PUBLIC_BASE_URL", name: "Cloudflare R2 public base URL"),
        CredentialDefinition(key: "R2_S3_ENDPOINT", name: "Cloudflare R2 S3 endpoint"),
        CredentialDefinition(key: "R2_SECRET_ACCESS_KEY", name: "Cloudflare R2 secret access key"),
        CredentialDefinition(key: "TIKTOK_CLIENT_ID", name: "TikTok client ID"),
        CredentialDefinition(key: "TIKTOK_CLIENT_SECRET", name: "TikTok client secret"),
        CredentialDefinition(key: "TIKTOK_REDIRECT_URI", name: "TikTok redirect URI"),
        CredentialDefinition(key: "TIKTOK_SCOPES", name: "TikTok scopes"),
        CredentialDefinition(key: "TIKTOK_VERIFIED_BASE_URL", name: "TikTok verified URL prefix")
    ]

    static var supportedKeys: [String] {
        supported.map(\.key)
    }

    static let retiredKeys = [
        "POSTGRES_DATABASE",
        "POSTGRES_HOST",
        "POSTGRES_PASSWORD",
        "POSTGRES_PRISMA_URL",
        "POSTGRES_URL",
        "POSTGRES_URL_NON_POOLING",
        "POSTGRES_USER"
    ]

    static func definition(for key: String) -> CredentialDefinition? {
        supported.first { $0.key == key }
    }
}

struct CredentialStatus: Identifiable, Hashable {
    enum Source: String, Hashable {
        case secureStore = "Keychain"
        case missing = "Missing"
    }

    var id: String { key }
    var key: String
    var name: String
    var isPresent: Bool
    var source: Source
}

private extension Dictionary where Key == String, Value == String {
    func nonEmptyString(_ key: String) -> String? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    func hasNonEmptyValue(_ key: String) -> Bool {
        guard let value = self[key] else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func nonEmptyURL(_ key: String) -> URL? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return URL(string: value)
    }
}

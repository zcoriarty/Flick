//
//  AppConfiguration.swift
//  Flick
//

import Foundation

struct AppConfiguration: Hashable {
    var supabase: SupabaseConfiguration
    var tiktok: TikTokConfiguration
    var openAI: OpenAIConfiguration
    var meta: MetaConfiguration
    var storageBuckets: StorageBuckets
    var renderDirectory: URL
    var secureStoredCredentialKeys: Set<String>

    static var current: AppConfiguration {
        let credentialVault = CredentialVault()
        let values = credentialVault.loadValues()
        let secureStoredCredentialKeys = Set(values.keys)
        return AppConfiguration(
            supabase: SupabaseConfiguration(values: values),
            tiktok: TikTokConfiguration(values: values),
            openAI: OpenAIConfiguration(values: values),
            meta: MetaConfiguration(values: values),
            storageBuckets: StorageBuckets(),
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

struct SupabaseConfiguration: Hashable {
    var url: URL?
    var publishableKeyPresent: Bool
    var anonKeyPresent: Bool
    var serviceRoleKeyPresent: Bool
    var postgresURLPresent: Bool

    var apiKeyPresent: Bool {
        publishableKeyPresent || anonKeyPresent || serviceRoleKeyPresent
    }

    init(values: [String: String]) {
        url = values.nonEmptyURL("SUPABASE_URL")
        publishableKeyPresent = values.hasNonEmptyValue("SUPABASE_PUBLISHABLE_KEY")
        anonKeyPresent = values.hasNonEmptyValue("SUPABASE_ANON_KEY")
        serviceRoleKeyPresent = values.hasNonEmptyValue("SUPABASE_SERVICE_ROLE_KEY")
        postgresURLPresent = values.hasNonEmptyValue("POSTGRES_URL")
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

struct StorageBuckets: Hashable {
    var generatedImages = "flick-generated-images"
    var renderedVideos = "flick-rendered-videos"
    var referenceImages = "flick-reference-images"
    var thumbnails = "flick-thumbnails"
}

struct CredentialDefinition: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var name: String

    static let supported: [CredentialDefinition] = [
        CredentialDefinition(key: "META_CLIENT_ID", name: "Meta client ID"),
        CredentialDefinition(key: "META_CLIENT_SECRET", name: "Meta client secret"),
        CredentialDefinition(key: "OPENAI_API_KEY", name: "OpenAI API key"),
        CredentialDefinition(key: "POSTGRES_DATABASE", name: "Postgres database"),
        CredentialDefinition(key: "POSTGRES_HOST", name: "Postgres host"),
        CredentialDefinition(key: "POSTGRES_PASSWORD", name: "Postgres password"),
        CredentialDefinition(key: "POSTGRES_PRISMA_URL", name: "Postgres Prisma URL"),
        CredentialDefinition(key: "POSTGRES_URL", name: "Postgres URL"),
        CredentialDefinition(key: "POSTGRES_URL_NON_POOLING", name: "Postgres non-pooling URL"),
        CredentialDefinition(key: "POSTGRES_USER", name: "Postgres user"),
        CredentialDefinition(key: "SUPABASE_ANON_KEY", name: "Supabase anon key"),
        CredentialDefinition(key: "SUPABASE_JWT_SECRET", name: "Supabase JWT secret"),
        CredentialDefinition(key: "SUPABASE_PUBLISHABLE_KEY", name: "Supabase publishable key"),
        CredentialDefinition(key: "SUPABASE_SERVICE_ROLE_KEY", name: "Supabase service role key"),
        CredentialDefinition(key: "SUPABASE_URL", name: "Supabase URL"),
        CredentialDefinition(key: "TIKTOK_CLIENT_ID", name: "TikTok client ID"),
        CredentialDefinition(key: "TIKTOK_CLIENT_SECRET", name: "TikTok client secret"),
        CredentialDefinition(key: "TIKTOK_REDIRECT_URI", name: "TikTok redirect URI"),
        CredentialDefinition(key: "TIKTOK_SCOPES", name: "TikTok scopes"),
        CredentialDefinition(key: "TIKTOK_VERIFIED_BASE_URL", name: "TikTok verified URL prefix")
    ]

    static var supportedKeys: [String] {
        supported.map(\.key)
    }

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

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
        let values = LocalEnvironment.load()
        let secureStoredCredentialKeys = CredentialVault().storedKeys()
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
        let isConfigured = switch definition.key {
        case "META_CLIENT_ID": meta.clientIDPresent
        case "META_CLIENT_SECRET": meta.clientSecretPresent
        case "OPENAI_API_KEY": openAI.apiKeyPresent
        case "POSTGRES_DATABASE": false
        case "POSTGRES_HOST": false
        case "POSTGRES_PASSWORD": false
        case "POSTGRES_PRISMA_URL": false
        case "POSTGRES_URL": supabase.postgresURLPresent
        case "POSTGRES_URL_NON_POOLING": false
        case "POSTGRES_USER": false
        case "SUPABASE_ANON_KEY": supabase.anonKeyPresent
        case "SUPABASE_JWT_SECRET": false
        case "SUPABASE_SERVICE_ROLE_KEY": supabase.serviceRoleKeyPresent
        case "SUPABASE_URL": supabase.url != nil
        case "TIKTOK_CLIENT_ID": tiktok.clientIDPresent
        case "TIKTOK_CLIENT_SECRET": tiktok.clientSecretPresent
        case "TIKTOK_REDIRECT_URI": tiktok.redirectURI != nil
        case "TIKTOK_SCOPES": !tiktok.requestedScopes.isEmpty
        case "TIKTOK_VERIFIED_BASE_URL": tiktok.verifiedBaseURL != nil
        default: false
        }
        let isPresent = secureStoredCredentialKeys.contains(definition.key) || isConfigured

        return CredentialStatus(
            key: definition.key,
            name: definition.name,
            isPresent: isPresent,
            storagePolicy: definition.storagePolicy,
            source: secureStoredCredentialKeys.contains(definition.key) ? .secureStore : (isPresent ? .localEnvironment : .missing)
        )
    }
}

struct SupabaseConfiguration: Hashable {
    var url: URL?
    var anonKeyPresent: Bool
    var serviceRoleKeyPresent: Bool
    var postgresURLPresent: Bool

    init(values: [String: String]) {
        url = values.nonEmptyURL("SUPABASE_URL")
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
    var storagePolicy: CredentialStatus.StoragePolicy

    static let supported: [CredentialDefinition] = [
        CredentialDefinition(key: "META_CLIENT_ID", name: "Meta client ID", storagePolicy: .clientSafe),
        CredentialDefinition(key: "META_CLIENT_SECRET", name: "Meta client secret", storagePolicy: .keychainOrBackend),
        CredentialDefinition(key: "OPENAI_API_KEY", name: "OpenAI API key", storagePolicy: .keychainOrBackend),
        CredentialDefinition(key: "POSTGRES_DATABASE", name: "Postgres database", storagePolicy: .neverShip),
        CredentialDefinition(key: "POSTGRES_HOST", name: "Postgres host", storagePolicy: .neverShip),
        CredentialDefinition(key: "POSTGRES_PASSWORD", name: "Postgres password", storagePolicy: .neverShip),
        CredentialDefinition(key: "POSTGRES_PRISMA_URL", name: "Postgres Prisma URL", storagePolicy: .neverShip),
        CredentialDefinition(key: "POSTGRES_URL", name: "Postgres URL", storagePolicy: .neverShip),
        CredentialDefinition(key: "POSTGRES_URL_NON_POOLING", name: "Postgres non-pooling URL", storagePolicy: .neverShip),
        CredentialDefinition(key: "POSTGRES_USER", name: "Postgres user", storagePolicy: .neverShip),
        CredentialDefinition(key: "SUPABASE_ANON_KEY", name: "Supabase anon key", storagePolicy: .clientSafe),
        CredentialDefinition(key: "SUPABASE_JWT_SECRET", name: "Supabase JWT secret", storagePolicy: .neverShip),
        CredentialDefinition(key: "SUPABASE_SERVICE_ROLE_KEY", name: "Supabase service role key", storagePolicy: .neverShip),
        CredentialDefinition(key: "SUPABASE_URL", name: "Supabase URL", storagePolicy: .clientSafe),
        CredentialDefinition(key: "TIKTOK_CLIENT_ID", name: "TikTok client ID", storagePolicy: .clientSafe),
        CredentialDefinition(key: "TIKTOK_CLIENT_SECRET", name: "TikTok client secret", storagePolicy: .keychainOrBackend),
        CredentialDefinition(key: "TIKTOK_REDIRECT_URI", name: "TikTok redirect URI", storagePolicy: .clientSafe),
        CredentialDefinition(key: "TIKTOK_SCOPES", name: "TikTok scopes", storagePolicy: .clientSafe),
        CredentialDefinition(key: "TIKTOK_VERIFIED_BASE_URL", name: "TikTok verified URL prefix", storagePolicy: .clientSafe)
    ]

    static var supportedKeys: [String] {
        supported.map(\.key)
    }

    static func definition(for key: String) -> CredentialDefinition? {
        supported.first { $0.key == key }
    }
}

struct CredentialStatus: Identifiable, Hashable {
    enum StoragePolicy: String, Hashable {
        case clientSafe = "Client-safe config"
        case keychainOrBackend = "Keychain or backend only"
        case neverShip = "Never ship in client"
    }

    enum Source: String, Hashable {
        case secureStore = "Secure store"
        case localEnvironment = "Local environment"
        case missing = "Missing"
    }

    var id: String { key }
    var key: String
    var name: String
    var isPresent: Bool
    var storagePolicy: StoragePolicy
    var source: Source
}

enum LocalEnvironment {
    static func load() -> [String: String] {
        var values = ProcessInfo.processInfo.environment

        #if DEBUG
        for url in candidateDotEnvURLs() {
            guard let parsed = parseDotEnv(at: url) else { continue }
            values.merge(parsed) { current, _ in current }
        }
        #endif

        values.merge(CredentialVault().loadValues()) { _, secureValue in secureValue }

        return values
    }

    static func parseDotEnvContents(_ contents: String) -> [String: String] {
        contents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { values, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else { return }
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = parts[0]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .removingExportPrefix()
                let value = String(parts[1])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingMatchingQuotes()
                guard !key.isEmpty else { return }
                values[key] = value
            }
    }

    private static func parseDotEnv(at url: URL) -> [String: String]? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseDotEnvContents(contents)
    }

    private static func candidateDotEnvURLs() -> [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default
        let currentDirectory = URL(filePath: fileManager.currentDirectoryPath, directoryHint: .isDirectory)
        urls.append(currentDirectory.appending(path: ".env.local"))
        urls.append(currentDirectory.deletingLastPathComponent().appending(path: ".env.local"))

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appending(path: ".env.local"))
            urls.append(resourceURL.deletingLastPathComponent().appending(path: ".env.local"))
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        urls.append(projectRoot.appending(path: ".env.local"))

        return Array(NSOrderedSet(array: urls).compactMap { $0 as? URL })
    }
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

private extension String {
    func trimmingMatchingQuotes() -> String {
        guard count >= 2 else { return self }
        if (hasPrefix("\"") && hasSuffix("\"")) || (hasPrefix("'") && hasSuffix("'")) {
            return String(dropFirst().dropLast())
        }
        return self
    }

    func removingExportPrefix() -> String {
        if hasPrefix("export ") {
            return String(dropFirst("export ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return self
    }
}

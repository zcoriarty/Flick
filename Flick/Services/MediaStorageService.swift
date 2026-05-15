//
//  MediaStorageService.swift
//  Flick
//

import Foundation
import Supabase

struct LocalMediaAsset: Hashable {
    var id: UUID
    var data: Data
    var contentType: String
    var fileExtension: String
}

struct RemoteMediaAsset: Hashable {
    var storageBucket: String
    var storagePath: String
    var publicURL: URL?
    var signedURLExpiration: Date?
}

protocol MediaStorageProviding {
    func uploadAsset(_ asset: LocalMediaAsset, bucket: String, path: String) async throws -> RemoteMediaAsset
    func publicURL(bucket: String, path: String) throws -> URL
    func signedURL(bucket: String, path: String, expiresIn: TimeInterval) async throws -> URL
    func ensureAuthenticatedSession() async throws -> SupabaseSessionStatus
}

enum MediaStorageError: LocalizedError {
    case missingSupabaseConfiguration
    case invalidSignedURLExpiration(TimeInterval)
    case uploadFailed(statusCode: Int, response: String)
    case missingSupabaseClient
    case httpStatusUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case .missingSupabaseConfiguration:
            "Supabase URL and a Supabase API key are required for media storage."
        case let .invalidSignedURLExpiration(expiresIn):
            "Signed URL expiration must be a positive whole number of seconds. Received \(expiresIn)."
        case let .uploadFailed(statusCode, response):
            "Supabase upload failed with status \(statusCode): \(response)"
        case .missingSupabaseClient:
            "Supabase client is not initialized."
        case let .httpStatusUnavailable(url):
            "Could not read an HTTP status from \(url.absoluteString)."
        }
    }
}

struct SupabaseSessionStatus: Hashable {
    enum Mode: String, Hashable {
        case authenticated = "Authenticated"
        case serviceRole = "Service role"
    }

    var mode: Mode
    var userID: UUID?
    var expiresAt: Date?
    var didCreateNewSession: Bool

    var displayText: String {
        switch mode {
        case .authenticated:
            didCreateNewSession ? "Created anonymous auth session" : "Using existing auth session"
        case .serviceRole:
            "Using service role key; auth session skipped"
        }
    }
}

struct SupabaseStorageSmokeTestResult: Hashable {
    var bucket: String
    var path: String
    var sessionStatus: SupabaseSessionStatus
    var objectExists: Bool
    var publicURL: URL
    var publicURLStatusCode: Int?
    var signedURL: URL
    var signedURLStatusCode: Int?
    var signedURLExpiration: Date
    var cleanupSucceeded: Bool
    var cleanupError: String?

    var isSuccessful: Bool {
        objectExists && isHTTPStatusSuccessful(publicURLStatusCode) && isHTTPStatusSuccessful(signedURLStatusCode)
    }

    var publicURLAccessText: String {
        guard let publicURLStatusCode else { return "Not checked" }
        return isHTTPStatusSuccessful(publicURLStatusCode) ? "Reachable" : "HTTP \(publicURLStatusCode)"
    }

    var signedURLAccessText: String {
        guard let signedURLStatusCode else { return "Not checked" }
        return isHTTPStatusSuccessful(signedURLStatusCode) ? "Reachable" : "HTTP \(signedURLStatusCode)"
    }

    var summary: String {
        let outcome = isSuccessful ? "passed" : "completed with warnings"
        let publicAccess = publicURLAccessText.lowercased()
        let signedAccess = signedURLAccessText.lowercased()
        let cleanup = cleanupSucceeded ? "cleanup succeeded" : "cleanup needs attention"
        return "Supabase smoke test \(outcome); public URL is \(publicAccess); signed URL is \(signedAccess); \(cleanup)."
    }

    private func isHTTPStatusSuccessful(_ statusCode: Int?) -> Bool {
        guard let statusCode else { return false }
        return (200..<300).contains(statusCode)
    }
}

struct SupabaseStorageService: MediaStorageProviding {
    fileprivate enum APIKeySource {
        case publishable
        case anon
        case serviceRole
    }

    let projectURL: URL?
    let apiKey: String?
    let urlSession: URLSession
    private let apiKeySource: APIKeySource?
    private let client: SupabaseClient?

    init(credentials: [String: String] = CredentialVault().loadValues(), urlSession: URLSession = .shared) {
        projectURL = credentials.nonEmptyURL("SUPABASE_URL")
        let key = credentials.supabaseAPIKey()
        apiKey = key?.value
        apiKeySource = key?.source
        self.urlSession = urlSession
        if let projectURL, let apiKey {
            client = SupabaseClient(
                supabaseURL: projectURL,
                supabaseKey: apiKey,
                options: SupabaseClientOptions(
                    auth: .init(emitLocalSessionAsInitialSession: true),
                    global: .init(session: urlSession)
                )
            )
        } else {
            client = nil
        }
    }

    func uploadAsset(_ asset: LocalMediaAsset, bucket: String, path: String) async throws -> RemoteMediaAsset {
        let client = try configuredClient()
        _ = try await ensureAuthenticatedSession()

        try await client.storage
            .from(bucket)
            .upload(
                path,
                data: asset.data,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: asset.contentType,
                    upsert: false
                )
            )

        return RemoteMediaAsset(
            storageBucket: bucket,
            storagePath: path,
            publicURL: try publicURL(bucket: bucket, path: path),
            signedURLExpiration: nil
        )
    }

    func publicURL(bucket: String, path: String) throws -> URL {
        try configuredClient().storage
            .from(bucket)
            .getPublicURL(path: path)
    }

    func signedURL(bucket: String, path: String, expiresIn: TimeInterval) async throws -> URL {
        guard expiresIn > 0, expiresIn.rounded(.down) == expiresIn else {
            throw MediaStorageError.invalidSignedURLExpiration(expiresIn)
        }

        let client = try configuredClient()
        _ = try await ensureAuthenticatedSession()

        return try await client.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: Int(expiresIn))
    }

    func ensureAuthenticatedSession() async throws -> SupabaseSessionStatus {
        let client = try configuredClient()

        guard apiKeySource != .serviceRole else {
            return SupabaseSessionStatus(
                mode: .serviceRole,
                userID: nil,
                expiresAt: nil,
                didCreateNewSession: false
            )
        }

        do {
            let session = try await client.auth.session
            return sessionStatus(for: session, didCreateNewSession: false)
        } catch {
            let session = try await client.auth.signInAnonymously()
            return sessionStatus(for: session, didCreateNewSession: true)
        }
    }

    func runSmokeTest(
        bucket: String,
        path: String = "flick-smoke-tests/\(UUID().uuidString).txt",
        signedURLExpiresIn: TimeInterval = 600
    ) async throws -> SupabaseStorageSmokeTestResult {
        let client = try configuredClient()
        let payload = Data("Flick Supabase smoke test \(Date().ISO8601Format())".utf8)
        let asset = LocalMediaAsset(
            id: UUID(),
            data: payload,
            contentType: "text/plain",
            fileExtension: "txt"
        )

        let sessionStatus = try await ensureAuthenticatedSession()
        _ = try await uploadAsset(asset, bucket: bucket, path: path)
        let objectExists = try await client.storage.from(bucket).exists(path: path)
        let publicURL = try publicURL(bucket: bucket, path: path)
        let signedURL = try await signedURL(bucket: bucket, path: path, expiresIn: signedURLExpiresIn)
        let publicStatusCode = try? await httpStatusCode(for: publicURL)
        let signedStatusCode = try? await httpStatusCode(for: signedURL)

        let cleanupResult: Result<Void, Error>
        do {
            _ = try await client.storage.from(bucket).remove(paths: [path])
            cleanupResult = .success(())
        } catch {
            cleanupResult = .failure(error)
        }

        return SupabaseStorageSmokeTestResult(
            bucket: bucket,
            path: path,
            sessionStatus: sessionStatus,
            objectExists: objectExists,
            publicURL: publicURL,
            publicURLStatusCode: publicStatusCode,
            signedURL: signedURL,
            signedURLStatusCode: signedStatusCode,
            signedURLExpiration: Date().addingTimeInterval(signedURLExpiresIn),
            cleanupSucceeded: cleanupResult.isSuccess,
            cleanupError: cleanupResult.failureDescription
        )
    }

    private func configuredClient() throws -> SupabaseClient {
        guard projectURL != nil, apiKey != nil else {
            throw MediaStorageError.missingSupabaseConfiguration
        }
        guard let client else {
            throw MediaStorageError.missingSupabaseClient
        }
        return client
    }

    private func sessionStatus(for session: Session, didCreateNewSession: Bool) -> SupabaseSessionStatus {
        SupabaseSessionStatus(
            mode: .authenticated,
            userID: session.user.id,
            expiresAt: Date(timeIntervalSince1970: session.expiresAt),
            didCreateNewSession: didCreateNewSession
        )
    }

    private func httpStatusCode(for url: URL) async throws -> Int {
        let (_, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaStorageError.httpStatusUnavailable(url)
        }
        return httpResponse.statusCode
    }
}

private extension Dictionary where Key == String, Value == String {
    typealias SupabaseAPIKey = (value: String, source: SupabaseStorageService.APIKeySource)

    func nonEmptyValue(_ key: String) -> String? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    func nonEmptyURL(_ key: String) -> URL? {
        guard let value = nonEmptyValue(key) else { return nil }
        return URL(string: value)
    }

    func supabaseAPIKey() -> SupabaseAPIKey? {
        if let value = nonEmptyValue("SUPABASE_PUBLISHABLE_KEY") {
            return (value, .publishable)
        }
        if let value = nonEmptyValue("SUPABASE_ANON_KEY") {
            return (value, .anon)
        }
        if let value = nonEmptyValue("SUPABASE_SERVICE_ROLE_KEY") {
            return (value, .serviceRole)
        }
        return nil
    }
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failureDescription: String? {
        if case let .failure(error) = self {
            return error.localizedDescription
        }
        return nil
    }
}

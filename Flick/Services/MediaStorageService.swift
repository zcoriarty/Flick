//
//  MediaStorageService.swift
//  Flick
//

import Foundation

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
}

enum MediaStorageError: LocalizedError {
    case missingSupabaseConfiguration
    case signedURLsRequireStorageSDK
    case uploadFailed(statusCode: Int, response: String)

    var errorDescription: String? {
        switch self {
        case .missingSupabaseConfiguration:
            "Supabase URL and anon key are required for media storage."
        case .signedURLsRequireStorageSDK:
            "Signed URL creation should use an authenticated Supabase storage client."
        case let .uploadFailed(statusCode, response):
            "Supabase upload failed with status \(statusCode): \(response)"
        }
    }
}

struct SupabaseStorageService: MediaStorageProviding {
    let projectURL: URL?
    let anonKey: String?
    let urlSession: URLSession

    init(credentials: [String: String] = CredentialVault().loadValues(), urlSession: URLSession = .shared) {
        projectURL = credentials.nonEmptyURL("SUPABASE_URL")
        anonKey = credentials.nonEmptyValue("SUPABASE_ANON_KEY")
        self.urlSession = urlSession
    }

    func uploadAsset(_ asset: LocalMediaAsset, bucket: String, path: String) async throws -> RemoteMediaAsset {
        guard let projectURL, let anonKey else {
            throw MediaStorageError.missingSupabaseConfiguration
        }

        var request = URLRequest(url: objectURL(projectURL: projectURL, bucket: bucket, path: path))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(asset.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")

        let (data, response) = try await urlSession.upload(for: request, from: asset.data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaStorageError.uploadFailed(statusCode: -1, response: "Missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MediaStorageError.uploadFailed(statusCode: httpResponse.statusCode, response: body)
        }

        return RemoteMediaAsset(
            storageBucket: bucket,
            storagePath: path,
            publicURL: try publicURL(bucket: bucket, path: path),
            signedURLExpiration: nil
        )
    }

    func publicURL(bucket: String, path: String) throws -> URL {
        guard let projectURL else {
            throw MediaStorageError.missingSupabaseConfiguration
        }
        return projectURL
            .appending(path: "storage/v1/object/public")
            .appending(path: bucket)
            .appending(path: path)
    }

    func signedURL(bucket: String, path: String, expiresIn: TimeInterval) async throws -> URL {
        _ = bucket
        _ = path
        _ = expiresIn
        throw MediaStorageError.signedURLsRequireStorageSDK
    }

    private func objectURL(projectURL: URL, bucket: String, path: String) -> URL {
        projectURL
            .appending(path: "storage/v1/object")
            .appending(path: bucket)
            .appending(path: path)
    }
}

private extension Dictionary where Key == String, Value == String {
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
}

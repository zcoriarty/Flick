//
//  MediaStorageService.swift
//  Flick
//

import CryptoKit
import Foundation

struct LocalMediaAsset: Hashable {
    var data: Data
    var contentType: String
}

struct RemoteMediaAsset: Hashable {
    var storageBucket: String
    var storagePath: String
    var publicURL: URL?
    var signedURLExpiration: Date?
}

protocol MediaStorageProviding {
    func uploadAsset(_ asset: LocalMediaAsset, path: String) async throws -> RemoteMediaAsset
    func publicURL(path: String) throws -> URL
    func signedURL(path: String, expiresIn: TimeInterval) async throws -> URL
}

enum MediaStorageError: LocalizedError {
    case missingR2Configuration
    case invalidObjectPath(String)
    case invalidSignedURLExpiration(TimeInterval)
    case requestFailed(operation: String, statusCode: Int, response: String)
    case httpStatusUnavailable(URL)
    case objectAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .missingR2Configuration:
            "Cloudflare R2 account ID, access key ID, secret access key, bucket, and public base URL are required for media storage."
        case let .invalidObjectPath(path):
            "Cloudflare R2 object paths must be non-empty relative paths. Received \(path)."
        case let .invalidSignedURLExpiration(expiresIn):
            "Signed URL expiration must be a positive whole number of seconds. Received \(expiresIn)."
        case let .requestFailed(operation, statusCode, response):
            "Cloudflare R2 \(operation) failed with status \(statusCode): \(response)"
        case let .httpStatusUnavailable(url):
            "Could not read an HTTP status from \(url.absoluteString)."
        case let .objectAlreadyExists(path):
            "Cloudflare R2 object already exists at \(path)."
        }
    }
}

struct R2StorageSmokeTestResult: Hashable {
    var bucket: String
    var path: String
    var ensuredPrefixPaths: [String]
    var endpointURL: URL
    var publicBaseURL: URL
    var objectExists: Bool
    var publicURL: URL
    var publicURLStatusCode: Int?
    var publicURLCheckError: String?
    var signedURL: URL
    var signedURLStatusCode: Int?
    var signedURLCheckError: String?
    var signedURLExpiration: Date
    var cleanupSucceeded: Bool
    var cleanupError: String?

    var isSuccessful: Bool {
        objectExists
            && isHTTPStatusSuccessful(publicURLStatusCode)
            && isHTTPStatusSuccessful(signedURLStatusCode)
            && cleanupSucceeded
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
        return "Cloudflare R2 smoke test \(outcome); public URL is \(publicAccess); signed URL is \(signedAccess); \(cleanup)."
    }

    var diagnosticMessages: [String] {
        var messages: [String] = []
        if objectExists {
            messages.append("Upload verified: R2 returned the object through a signed HEAD request.")
        } else {
            messages.append("Upload warning: R2 did not find the object immediately after upload.")
        }

        if ensuredPrefixPaths.isEmpty {
            messages.append("No storage prefix placeholders were requested.")
        } else {
            messages.append("Storage structure ensured with placeholder objects: \(ensuredPrefixPaths.joined(separator: ", ")).")
        }

        if isHTTPStatusSuccessful(publicURLStatusCode) {
            messages.append("Public URL check passed through the configured custom domain.")
        } else if let publicURLStatusCode {
            messages.append("Public URL check returned HTTP \(publicURLStatusCode). Check that the custom domain is attached to this bucket and public access is enabled for the object path.")
        } else {
            messages.append("Public URL check could not complete: \(publicURLCheckError ?? "no HTTP response").")
        }

        if isHTTPStatusSuccessful(signedURLStatusCode) {
            messages.append("Signed S3 URL check passed through the R2 S3 endpoint.")
        } else if let signedURLStatusCode {
            messages.append("Signed S3 URL check returned HTTP \(signedURLStatusCode). Check that the R2 S3 key has Object Read permission for this bucket.")
        } else {
            messages.append("Signed S3 URL check could not complete: \(signedURLCheckError ?? "no HTTP response").")
        }

        if cleanupSucceeded {
            messages.append("Cleanup deleted the smoke-test object, so it should not remain visible in the Cloudflare dashboard.")
        } else {
            messages.append("Cleanup failed: \(cleanupError ?? "unknown cleanup error").")
        }

        return messages
    }

    private func isHTTPStatusSuccessful(_ statusCode: Int?) -> Bool {
        guard let statusCode else { return false }
        return (200..<300).contains(statusCode)
    }
}

struct R2StorageService: MediaStorageProviding {
    let endpointURL: URL?
    let publicBaseURL: URL?
    let accessKeyID: String?
    let secretAccessKey: String?
    let bucket: String?
    let urlSession: URLSession

    init(credentials: [String: String] = CredentialVault().loadValues(), urlSession: URLSession = .shared) {
        let accountID = credentials.nonEmptyValue("R2_ACCOUNT_ID")
        self.endpointURL = credentials.nonEmptyURL("R2_S3_ENDPOINT")
            ?? accountID.flatMap { URL(string: "https://\($0).r2.cloudflarestorage.com") }
        self.publicBaseURL = credentials.nonEmptyURL("R2_PUBLIC_BASE_URL")
        self.accessKeyID = credentials.nonEmptyValue("R2_ACCESS_KEY_ID")
        self.secretAccessKey = credentials.nonEmptyValue("R2_SECRET_ACCESS_KEY")
        self.bucket = credentials.nonEmptyValue("R2_BUCKET")
        self.urlSession = urlSession
    }

    func uploadAsset(_ asset: LocalMediaAsset, path: String) async throws -> RemoteMediaAsset {
        let configuration = try configuredStorage()
        let objectPath = try normalizedObjectPath(path)
        let request = try signedRequest(
            method: "PUT",
            path: objectPath,
            headers: [
                "cache-control": "3600",
                "content-type": asset.contentType
            ],
            body: asset.data,
            configuration: configuration
        )

        _ = try await send(request, operation: "upload")

        return RemoteMediaAsset(
            storageBucket: configuration.bucket,
            storagePath: objectPath,
            publicURL: try publicURL(path: objectPath),
            signedURLExpiration: nil
        )
    }

    func uploadJSONIfAbsent(_ data: Data, path: String, metadata: [String: String] = [:]) async throws -> Bool {
        let configuration = try configuredStorage()
        let objectPath = try normalizedObjectPath(path)
        var headers = metadata.reduce(into: [
            "cache-control": "3600",
            "content-type": "application/json",
            "if-none-match": "*"
        ]) { result, pair in
            result["x-amz-meta-\(pair.key.lowercased())"] = pair.value
        }
        headers["content-length"] = "\(data.count)"

        let request = try signedRequest(
            method: "PUT",
            path: objectPath,
            headers: headers,
            body: data,
            configuration: configuration
        )
        let (responseData, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaStorageError.httpStatusUnavailable(request.url!)
        }
        if httpResponse.statusCode == 412 {
            return false
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MediaStorageError.requestFailed(
                operation: "conditional upload",
                statusCode: httpResponse.statusCode,
                response: String(data: responseData, encoding: .utf8) ?? ""
            )
        }
        return true
    }

    func putJSON(_ data: Data, path: String, metadata: [String: String] = [:]) async throws {
        let configuration = try configuredStorage()
        let objectPath = try normalizedObjectPath(path)
        var headers = metadata.reduce(into: [
            "cache-control": "3600",
            "content-type": "application/json",
            "content-length": "\(data.count)"
        ]) { result, pair in
            result["x-amz-meta-\(pair.key.lowercased())"] = pair.value
        }
        headers["content-length"] = "\(data.count)"

        let request = try signedRequest(
            method: "PUT",
            path: objectPath,
            headers: headers,
            body: data,
            configuration: configuration
        )
        _ = try await send(request, operation: "put json")
    }

    func data(path: String) async throws -> Data {
        let configuration = try configuredStorage()
        let objectPath = try normalizedObjectPath(path)
        let request = try signedRequest(
            method: "GET",
            path: objectPath,
            headers: [:],
            body: Data(),
            configuration: configuration
        )
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaStorageError.httpStatusUnavailable(request.url!)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MediaStorageError.requestFailed(
                operation: "download",
                statusCode: httpResponse.statusCode,
                response: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    func objectExists(path: String) async throws -> Bool {
        try await objectExists(path: try normalizedObjectPath(path), configuration: try configuredStorage())
    }

    func deleteObject(path: String) async throws {
        try await deleteObject(path: try normalizedObjectPath(path), configuration: try configuredStorage())
    }

    func publicURL(path: String) throws -> URL {
        let configuration = try configuredStorage()
        let objectPath = try normalizedObjectPath(path)
        let base = publicObjectBaseURL(configuration: configuration).absoluteString.trimmingTrailingSlashes()
        guard let url = URL(string: "\(base)/\(R2PercentEncoding.path(objectPath))") else {
            throw MediaStorageError.invalidObjectPath(path)
        }
        return url
    }

    func signedURL(path: String, expiresIn: TimeInterval) async throws -> URL {
        guard expiresIn > 0, expiresIn.rounded(.down) == expiresIn else {
            throw MediaStorageError.invalidSignedURLExpiration(expiresIn)
        }

        let configuration = try configuredStorage()
        let objectPath = try normalizedObjectPath(path)
        let unsignedURL = try s3URL(for: objectPath, configuration: configuration)
        let signer = R2AWSV4Signer(
            accessKeyID: configuration.accessKeyID,
            secretAccessKey: configuration.secretAccessKey
        )

        return try signer.presignedURL(
            url: unsignedURL,
            method: "GET",
            expiresIn: Int(expiresIn),
            date: Date()
        )
    }

    func runSmokeTest(
        requiredPrefixes: [String],
        path: String = "flick-smoke-tests/\(UUID().uuidString).txt",
        signedURLExpiresIn: TimeInterval = 600
    ) async throws -> R2StorageSmokeTestResult {
        let configuration = try configuredStorage()
        let objectPath = try normalizedObjectPath(path)
        let ensuredPrefixPaths = try await ensurePrefixPlaceholders(requiredPrefixes)
        let payload = Data("Flick Cloudflare R2 smoke test \(Date().ISO8601Format())".utf8)
        let asset = LocalMediaAsset(
            data: payload,
            contentType: "text/plain"
        )

        _ = try await uploadAsset(asset, path: objectPath)
        let objectExists = try await objectExists(path: objectPath, configuration: configuration)
        let publicURL = try publicURL(path: objectPath)
        let signedURL = try await signedURL(path: objectPath, expiresIn: signedURLExpiresIn)
        let publicURLCheck = await checkedHTTPStatusCode(for: publicURL)
        let signedURLCheck = await checkedHTTPStatusCode(for: signedURL)

        let cleanupResult: Result<Void, Error>
        do {
            try await deleteObject(path: objectPath, configuration: configuration)
            cleanupResult = .success(())
        } catch {
            cleanupResult = .failure(error)
        }

        return R2StorageSmokeTestResult(
            bucket: configuration.bucket,
            path: objectPath,
            ensuredPrefixPaths: ensuredPrefixPaths,
            endpointURL: configuration.endpointURL,
            publicBaseURL: configuration.publicBaseURL,
            objectExists: objectExists,
            publicURL: publicURL,
            publicURLStatusCode: publicURLCheck.statusCode,
            publicURLCheckError: publicURLCheck.errorMessage,
            signedURL: signedURL,
            signedURLStatusCode: signedURLCheck.statusCode,
            signedURLCheckError: signedURLCheck.errorMessage,
            signedURLExpiration: Date().addingTimeInterval(signedURLExpiresIn),
            cleanupSucceeded: cleanupResult.isSuccess,
            cleanupError: cleanupResult.failureDescription
        )
    }

    private func ensurePrefixPlaceholders(_ prefixes: [String]) async throws -> [String] {
        var seenPrefixes = Set<String>()
        var placeholderPaths: [String] = []
        let placeholderData = Data("Flick Cloudflare R2 storage prefix placeholder.\n".utf8)

        for prefix in prefixes {
            let normalizedPrefix = try normalizedObjectPath(prefix)
            guard seenPrefixes.insert(normalizedPrefix).inserted else { continue }

            let placeholderPath = "\(normalizedPrefix)/.keep"
            _ = try await uploadAsset(
                LocalMediaAsset(
                    data: placeholderData,
                    contentType: "text/plain"
                ),
                path: placeholderPath
            )
            placeholderPaths.append(placeholderPath)
        }

        return placeholderPaths
    }

    private func configuredStorage() throws -> R2StorageClientConfiguration {
        guard
            let endpointURL,
            let publicBaseURL,
            let accessKeyID,
            let secretAccessKey,
            let bucket
        else {
            throw MediaStorageError.missingR2Configuration
        }

        return R2StorageClientConfiguration(
            endpointURL: endpointURL,
            publicBaseURL: publicBaseURL,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            bucket: bucket
        )
    }

    private func publicObjectBaseURL(configuration: R2StorageClientConfiguration) -> URL {
        guard
            publicBaseURLNeedsBucketPath(configuration.publicBaseURL, bucket: configuration.bucket),
            let bucketBaseURL = URL(string: "\(configuration.publicBaseURL.absoluteString.trimmingTrailingSlashes())/\(R2PercentEncoding.path(configuration.bucket))")
        else {
            return configuration.publicBaseURL
        }

        return bucketBaseURL
    }

    private func publicBaseURLNeedsBucketPath(_ publicBaseURL: URL, bucket: String) -> Bool {
        guard publicBaseURL.pathComponents.filter({ $0 != "/" }).isEmpty else {
            return false
        }

        let hostPrefix = publicBaseURL.host(percentEncoded: false)?.split(separator: ".").first.map(String.init)
        return hostPrefix?.localizedCaseInsensitiveCompare(bucket) == .orderedSame
    }

    private func objectExists(path: String, configuration: R2StorageClientConfiguration) async throws -> Bool {
        let request = try signedRequest(
            method: "HEAD",
            path: path,
            headers: [:],
            body: Data(),
            configuration: configuration
        )
        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaStorageError.httpStatusUnavailable(request.url!)
        }
        if httpResponse.statusCode == 404 { return false }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MediaStorageError.requestFailed(operation: "head object", statusCode: httpResponse.statusCode, response: "")
        }
        return true
    }

    private func deleteObject(path: String, configuration: R2StorageClientConfiguration) async throws {
        let request = try signedRequest(
            method: "DELETE",
            path: path,
            headers: [:],
            body: Data(),
            configuration: configuration
        )
        _ = try await send(request, operation: "delete")
    }

    private func signedRequest(
        method: String,
        path: String,
        headers: [String: String],
        body: Data,
        configuration: R2StorageClientConfiguration
    ) throws -> URLRequest {
        let url = try s3URL(for: path, configuration: configuration)
        let signer = R2AWSV4Signer(
            accessKeyID: configuration.accessKeyID,
            secretAccessKey: configuration.secretAccessKey
        )
        return try signer.signedRequest(
            url: url,
            method: method,
            headers: headers,
            body: body,
            date: Date()
        )
    }

    private func s3URL(for path: String, configuration: R2StorageClientConfiguration) throws -> URL {
        let endpoint = configuration.endpointURL.absoluteString.trimmingTrailingSlashes()
        let objectPath = try normalizedObjectPath(path)
        let bucketPath = "\(configuration.bucket)/\(objectPath)"
        guard let url = URL(string: "\(endpoint)/\(R2PercentEncoding.path(bucketPath))") else {
            throw MediaStorageError.invalidObjectPath(path)
        }
        return url
    }

    private func normalizedObjectPath(_ path: String) throws -> String {
        let normalizedPath = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.isEmpty else {
            throw MediaStorageError.invalidObjectPath(path)
        }
        return normalizedPath
    }

    private func send(_ request: URLRequest, operation: String) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaStorageError.httpStatusUnavailable(request.url ?? URL(fileURLWithPath: "/"))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw MediaStorageError.requestFailed(operation: operation, statusCode: httpResponse.statusCode, response: responseBody)
        }
        return data
    }

    private func httpStatusCode(for url: URL) async throws -> Int {
        let (_, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaStorageError.httpStatusUnavailable(url)
        }
        return httpResponse.statusCode
    }

    private func checkedHTTPStatusCode(for url: URL) async -> (statusCode: Int?, errorMessage: String?) {
        do {
            return (try await httpStatusCode(for: url), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}

private struct R2StorageClientConfiguration {
    var endpointURL: URL
    var publicBaseURL: URL
    var accessKeyID: String
    var secretAccessKey: String
    var bucket: String
}

private struct R2AWSV4Signer {
    var accessKeyID: String
    var secretAccessKey: String
    var region = "auto"
    var service = "s3"

    func signedRequest(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data,
        date: Date
    ) throws -> URLRequest {
        guard let host = url.host(percentEncoded: false) else {
            throw MediaStorageError.httpStatusUnavailable(url)
        }

        let dates = R2SigningDate(date: date)
        let payloadHash = R2SHA256.hexDigest(body)
        var signedHeaders = headers.normalizedHTTPHeaders()
        signedHeaders["host"] = host
        signedHeaders["x-amz-content-sha256"] = payloadHash
        signedHeaders["x-amz-date"] = dates.amzDate

        let canonicalHeaders = signedHeaders
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)\n" }
            .joined()
        let signedHeaderNames = signedHeaders.keys.sorted().joined(separator: ";")
        let canonicalRequest = [
            method,
            url.encodedPathForSigning,
            url.encodedQueryForSigning,
            canonicalHeaders,
            signedHeaderNames,
            payloadHash
        ].joined(separator: "\n")
        let signature = signature(for: canonicalRequest, dates: dates)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body.isEmpty ? nil : body
        for (name, value) in signedHeaders where name != "host" {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope(for: dates)), SignedHeaders=\(signedHeaderNames), Signature=\(signature)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    func presignedURL(url: URL, method: String, expiresIn: Int, date: Date) throws -> URL {
        guard let host = url.host(percentEncoded: false) else {
            throw MediaStorageError.httpStatusUnavailable(url)
        }

        let dates = R2SigningDate(date: date)
        let scope = credentialScope(for: dates)
        let queryItems = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Content-Sha256", "UNSIGNED-PAYLOAD"),
            ("X-Amz-Credential", "\(accessKeyID)/\(scope)"),
            ("X-Amz-Date", dates.amzDate),
            ("X-Amz-Expires", String(expiresIn)),
            ("X-Amz-SignedHeaders", "host")
        ]
        let canonicalQuery = R2PercentEncoding.query(queryItems)
        let canonicalRequest = [
            method,
            url.encodedPathForSigning,
            canonicalQuery,
            "host:\(host)\n",
            "host",
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")
        let signature = signature(for: canonicalRequest, dates: dates)
        let separator = canonicalQuery.isEmpty ? "" : "?"
        guard let signedURL = URL(string: "\(url.absoluteString)\(separator)\(canonicalQuery)&X-Amz-Signature=\(signature)") else {
            throw MediaStorageError.httpStatusUnavailable(url)
        }
        return signedURL
    }

    private func signature(for canonicalRequest: String, dates: R2SigningDate) -> String {
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            dates.amzDate,
            credentialScope(for: dates),
            R2SHA256.hexDigest(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")
        let signingKey = signingKey(for: dates.dateStamp)
        return R2HMAC.authenticationCode(for: stringToSign, key: signingKey).hexString
    }

    private func credentialScope(for dates: R2SigningDate) -> String {
        "\(dates.dateStamp)/\(region)/\(service)/aws4_request"
    }

    private func signingKey(for dateStamp: String) -> Data {
        let dateKey = R2HMAC.authenticationCode(for: dateStamp, key: Data("AWS4\(secretAccessKey)".utf8))
        let dateRegionKey = R2HMAC.authenticationCode(for: region, key: dateKey)
        let dateRegionServiceKey = R2HMAC.authenticationCode(for: service, key: dateRegionKey)
        return R2HMAC.authenticationCode(for: "aws4_request", key: dateRegionServiceKey)
    }
}

private struct R2SigningDate {
    var dateStamp: String
    var amzDate: String

    init(date: Date) {
        dateStamp = Self.dateStampFormatter.string(from: date)
        amzDate = Self.amzDateFormatter.string(from: date)
    }

    private static let dateStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let amzDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()
}

private enum R2SHA256 {
    static func hexDigest(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).hexString
    }
}

private enum R2HMAC {
    static func authenticationCode(for value: String, key: Data) -> Data {
        authenticationCode(for: Data(value.utf8), key: key)
    }

    static func authenticationCode(for data: Data, key: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }
}

enum R2PercentEncoding {
    static func path(_ value: String) -> String {
        value
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { percentEncode(String($0)) }
            .joined(separator: "/")
    }

    static func query(_ items: [(String, String)]) -> String {
        items
            .map { (percentEncode($0.0), percentEncode($0.1)) }
            .sorted {
                if $0.0 == $1.0 { return $0.1 < $1.1 }
                return $0.0 < $1.0
            }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension Dictionary where Key == String, Value == String {
    func normalizedHTTPHeaders() -> [String: String] {
        reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            let value = pair.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            result[key] = value
        }
    }

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

private extension URL {
    var encodedPathForSigning: String {
        let path = path(percentEncoded: true)
        return path.isEmpty ? "/" : path
    }

    var encodedQueryForSigning: String {
        query(percentEncoded: true) ?? ""
    }
}

extension String {
    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
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

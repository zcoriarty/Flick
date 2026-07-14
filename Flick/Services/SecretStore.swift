//
//  SecretStore.swift
//  Flick
//

import Foundation
import Security

nonisolated protocol SecretStoring {
    func data(for key: String) throws -> Data?
    func data(for keys: [String]) throws -> [String: Data]
    func save(_ data: Data, for key: String) throws
    func delete(_ key: String) throws

    func dataAsync(for key: String) async throws -> Data?
    func dataAsync(for keys: [String]) async throws -> [String: Data]
    func saveAsync(_ data: Data, for key: String) async throws
    func deleteAsync(_ key: String) async throws
}

nonisolated extension SecretStoring {
    func data(for keys: [String]) throws -> [String: Data] {
        try keys.reduce(into: [:]) { values, key in
            if let value = try data(for: key) {
                values[key] = value
            }
        }
    }

    /// Async compatibility entry points keep injected stores source-compatible.
    /// `KeychainSecretStore` supplies `@concurrent` witnesses below so Security
    /// framework calls never inherit a UI actor.
    func dataAsync(for key: String) async throws -> Data? {
        try data(for: key)
    }

    func dataAsync(for keys: [String]) async throws -> [String: Data] {
        try data(for: keys)
    }

    func saveAsync(_ data: Data, for key: String) async throws {
        try save(data, for: key)
    }

    func deleteAsync(_ key: String) async throws {
        try delete(key)
    }
}

nonisolated enum SecretStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status):
            "Keychain returned status \(status)."
        }
    }
}

nonisolated enum CredentialVaultError: LocalizedError, Equatable {
    case emptyValue(String)
    case noImportableValues
    case unsupportedKey(String)

    var errorDescription: String? {
        switch self {
        case let .emptyValue(key):
            "\(key) cannot be stored with an empty value."
        case .noImportableValues:
            "The JSON did not contain any supported, nonempty Flick credentials."
        case let .unsupportedKey(key):
            "\(key) is not a supported credential."
        }
    }
}

nonisolated struct CredentialImportResult: Hashable, Sendable {
    var storedKeys: [String]
    var ignoredKeys: [String]
}

nonisolated struct KeychainSecretStore: SecretStoring {
    var service = Bundle.main.bundleIdentifier ?? "com.orion.Flick"
    var synchronizesAcrossDevices = false

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        applySynchronizableReadPolicy(to: &query)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(status)
        }
        return item as? Data
    }

    func data(for keys: [String]) throws -> [String: Data] {
        let requestedKeys = Set(keys)
        guard !requestedKeys.isEmpty else { return [:] }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        applySynchronizableReadPolicy(to: &query)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return [:]
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(status)
        }

        let items = result as? [[String: Any]] ?? []
        return items.reduce(into: [:]) { values, item in
            guard
                let key = item[kSecAttrAccount as String] as? String,
                requestedKeys.contains(key),
                let data = item[kSecValueData as String] as? Data
            else {
                return
            }
            values[key] = data
        }
    }

    func save(_ data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        applySynchronizableWritePolicy(to: &query)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try update(data, for: key)
            return
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(status)
        }
    }

    func delete(_ key: String) throws {
        var query = baseQuery(for: key)
        applySynchronizableReadPolicy(to: &query)

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unhandledStatus(status)
        }
    }

    @concurrent
    func dataAsync(for key: String) async throws -> Data? {
        try data(for: key)
    }

    @concurrent
    func dataAsync(for keys: [String]) async throws -> [String: Data] {
        try data(for: keys)
    }

    @concurrent
    func saveAsync(_ data: Data, for key: String) async throws {
        try save(data, for: key)
    }

    @concurrent
    func deleteAsync(_ key: String) async throws {
        try delete(key)
    }

    private func update(_ data: Data, for key: String) throws {
        let attributes = [kSecValueData as String: data]
        var query = baseQuery(for: key)
        applySynchronizableWritePolicy(to: &query)

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func applySynchronizableReadPolicy(to query: inout [String: Any]) {
        guard synchronizesAcrossDevices else { return }
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
    }

    private func applySynchronizableWritePolicy(to query: inout [String: Any]) {
        guard synchronizesAcrossDevices else { return }
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
    }
}

nonisolated struct CredentialVault {
    static var supportedKeys: [String] {
        CredentialDefinition.supportedKeys
    }

    static var removableKeys: [String] {
        supportedKeys + CredentialDefinition.retiredKeys
    }

    var store: SecretStoring = KeychainSecretStore()

    func loadValues() -> [String: String] {
        guard let storedData = try? store.data(for: Self.supportedKeys) else {
            return [:]
        }

        return storedData.reduce(into: [String: String]()) { values, item in
            let key = item.key
            guard
                let value = String(data: item.value, encoding: .utf8),
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return
            }
            values[key] = value
        }
    }

    func storedKeys() -> Set<String> {
        Set(loadValues().keys)
    }

    func storeValue(_ value: String, for key: String) throws {
        guard Self.supportedKeys.contains(key) else {
            throw CredentialVaultError.unsupportedKey(key)
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw CredentialVaultError.emptyValue(key)
        }

        try store.save(Data(trimmedValue.utf8), for: key)
    }

    func storeValues(_ values: [String: String]) throws -> CredentialImportResult {
        var normalizedValues: [String: String] = [:]
        var ignoredKeys: [String] = []

        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.supportedKeys.contains(key), !trimmedValue.isEmpty else {
                ignoredKeys.append(key)
                continue
            }
            normalizedValues[key] = trimmedValue
        }

        guard !normalizedValues.isEmpty else {
            throw CredentialVaultError.noImportableValues
        }

        let storedValues = normalizedValues.sorted(by: { $0.key < $1.key })
        for (key, value) in storedValues {
            try store.save(Data(value.utf8), for: key)
        }

        return CredentialImportResult(
            storedKeys: storedValues.map { $0.key },
            ignoredKeys: ignoredKeys
        )
    }

    func deleteValue(for key: String) throws {
        guard Self.supportedKeys.contains(key) else {
            throw CredentialVaultError.unsupportedKey(key)
        }

        try store.delete(key)
    }

    func clearStoredCredentials() throws {
        for key in Self.removableKeys {
            try store.delete(key)
        }
    }
}

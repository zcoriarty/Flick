//
//  SecretStore.swift
//  Flick
//

import Foundation
import Security

protocol SecretStoring {
    func data(for key: String) throws -> Data?
    func save(_ data: Data, for key: String) throws
    func delete(_ key: String) throws
}

enum SecretStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status):
            "Keychain returned status \(status)."
        }
    }
}

enum CredentialVaultError: LocalizedError {
    case emptyValue(String)
    case unsupportedKey(String)

    var errorDescription: String? {
        switch self {
        case let .emptyValue(key):
            "\(key) cannot be stored with an empty value."
        case let .unsupportedKey(key):
            "\(key) is not a supported credential."
        }
    }
}

struct KeychainSecretStore: SecretStoring {
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

struct CredentialVault {
    static var supportedKeys: [String] {
        CredentialDefinition.supportedKeys
    }

    var store: SecretStoring = KeychainSecretStore()

    func loadValues() -> [String: String] {
        Self.supportedKeys.reduce(into: [String: String]()) { values, key in
            guard
                let data = try? store.data(for: key),
                let value = String(data: data, encoding: .utf8),
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

    func deleteValue(for key: String) throws {
        guard Self.supportedKeys.contains(key) else {
            throw CredentialVaultError.unsupportedKey(key)
        }

        try store.delete(key)
    }

    func clearStoredCredentials() throws {
        for key in Self.supportedKeys {
            try store.delete(key)
        }
    }
}

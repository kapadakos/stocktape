//
//  Keychain.swift
//  StockTape
//
//  Thin wrapper over the Security framework. All items are stored as generic
//  passwords under the single service name `com.stocktape.app` and use
//  kSecAttrAccessibleAfterFirstUnlock so the app can refresh tokens in the
//  background after the user has logged in once.
//

import Foundation
import Security

enum Keychain {

    /// Stable account labels used for each stored value.
    enum Key: String {
        case clientID = "schwab_client_id"
        case clientSecret = "schwab_client_secret"
        case accessToken = "schwab_access_token"
        case refreshToken = "schwab_refresh_token"
        case tokenExpiry = "schwab_token_expiry"              // ISO8601 string
        case refreshTokenExpiry = "schwab_refresh_token_expiry" // ISO8601 string
    }

    // MARK: - Read / write / delete

    @discardableResult
    static func set(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Remove any existing item first so we always do a clean insert.
        SecItemDelete(baseQuery(for: key) as CFDictionary)

        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.shared.error("Keychain write failed for \(key.rawValue): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func get(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status != errSecSuccess && status != errSecItemNotFound {
            if status == errSecUserCanceled {
                Logger.shared.warn("Keychain read denied for \(key.rawValue) — user clicked Deny on the access dialog.")
            } else {
                Logger.shared.error("Keychain read failed for \(key.rawValue): OSStatus \(status)")
            }
        }

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Wipe every StockTape item from the keychain.
    static func deleteAll() {
        [Key.clientID, .clientSecret, .accessToken, .refreshToken, .tokenExpiry, .refreshTokenExpiry]
            .forEach { delete($0) }
    }

    // MARK: - Convenience

    static func has(_ key: Key) -> Bool {
        guard let value = get(key) else { return false }
        return !value.isEmpty
    }

    // MARK: - Private

    private static func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}

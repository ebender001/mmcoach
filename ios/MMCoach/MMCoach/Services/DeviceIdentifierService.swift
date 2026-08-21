//
//  DeviceIdentifierService.swift
//  MMCoach
//
//  A stable per-device identifier, persisted in the Keychain rather than
//  UserDefaults so it survives the app being deleted and reinstalled. It
//  exists solely so the backend can recognize "this device already
//  redeemed its free case preparation" even under a brand-new account --
//  see PaywallViewModel and backend/cloud/repositories/
//  deviceRedemptionRepository.js. It identifies a device, not a person: a
//  random UUID, never linked to account data, and not personal
//  information in itself.
//

import Foundation
import Security

enum DeviceIdentifierService {
    private static let service = "dev.benderapps.MMCoach.deviceIdentifier"
    private static let account = "deviceIdentifier"

    /// Reads the existing identifier if one is already stored, otherwise
    /// generates and persists a new one. Deliberately not cached in a
    /// static var -- Keychain reads are fast and local, and this keeps
    /// every call honest about where the value actually lives.
    static func current() -> String {
        if let existing = read() {
            return existing
        }
        let generated = UUID().uuidString
        save(generated)
        return generated
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Clear any prior value first -- SecItemAdd fails with
        // errSecDuplicateItem if one already exists for this
        // service/account pair, and this path only runs when `read()`
        // just reported nothing usable there.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

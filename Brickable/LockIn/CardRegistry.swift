//
//  CardRegistry.swift
//  Brickable
//
//  Remembers that a lock card exists, in a place that survives reinstalling the
//  app.
//
//  This used to live in the App Group's UserDefaults, which iOS deletes along
//  with the app — so a reinstall made a perfectly good card look unprovisioned
//  and pushed you back through *Set Up Card*. Keychain items outlive app
//  deletion, so the flag belongs there.
//
//  Only the main app cares about this, so the item is app-scoped: no keychain
//  access group, nothing for the extensions to share.
//

import Foundation
import Security

enum CardRegistry {

    private static let service = "com.agomezi.brickable.lockcard"
    private static let account = "provisioned"

    /// True once any card has had the identifier written to it.
    ///
    /// The card itself is the real source of truth — a tap is verified by reading
    /// the identifier off it — so this only drives wording on the Lock In screen.
    /// Being wrong is cosmetic, which is why a plain read failure is treated as
    /// "no card" rather than surfaced as an error.
    static var isProvisioned: Bool {
        get {
            if readKeychainFlag() { return true }

            // Anyone upgrading from the UserDefaults version still has their
            // answer there. Move it across once, so the next reinstall keeps it.
            if SharedLockStore.cardProvisioned {
                writeKeychainFlag()
                return true
            }

            return false
        }
        set {
            guard newValue else {
                deleteKeychainFlag()
                SharedLockStore.cardProvisioned = false
                return
            }
            writeKeychainFlag()

            // Kept in step so a downgrade, or anything still reading the old
            // key, doesn't disagree with the keychain.
            SharedLockStore.cardProvisioned = true
        }
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readKeychainFlag() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    private static func writeKeychainFlag() {
        deleteKeychainFlag()

        var query = baseQuery
        query[kSecValueData as String] = Data([1])
        // The app only reads this while someone is using it, and the lock itself
        // needs an unlocked device anyway.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteKeychainFlag() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

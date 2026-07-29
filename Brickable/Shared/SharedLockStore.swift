//
//  SharedLockStore.swift
//  Brickable
//
//  The single source of truth for "am I locked right now, and what is blocked".
//  Lives in the App Group container so the main app, the shield extensions and
//  the DeviceActivity monitor all agree without talking to each other directly.
//

import Foundation
import FamilyControls

/// A snapshot of the lock, cheap to pass around and compare.
struct LockState: Codable, Equatable {
    var isLocked: Bool
    var lockedAt: Date?
    var autoUnlockAt: Date?

    static let unlocked = LockState(isLocked: false, lockedAt: nil, autoUnlockAt: nil)

    /// Seconds left on the auto-unlock timeout, or `nil` when not locked.
    /// Clamped at zero so a fired-but-not-yet-processed timeout reads as 0.
    var remainingTime: TimeInterval? {
        guard isLocked, let autoUnlockAt else { return nil }
        return max(0, autoUnlockAt.timeIntervalSinceNow)
    }

    /// True when the timeout has elapsed but the shield is somehow still up —
    /// the app uses this to self-heal if the monitor extension never ran.
    var isExpired: Bool {
        guard isLocked, let autoUnlockAt else { return false }
        return autoUnlockAt <= Date()
    }
}

enum SharedLockStore {
    private enum Key {
        static let isLocked = "brickable.lock.isLocked"
        static let lockedAt = "brickable.lock.lockedAt"
        static let autoUnlockAt = "brickable.lock.autoUnlockAt"
        static let autoUnlockMinutes = "brickable.lock.autoUnlockMinutes"
        static let selection = "brickable.lock.selection"
        static let cardProvisioned = "brickable.lock.cardProvisioned"
    }

    private static var defaults: UserDefaults { AppGroup.defaults }

    // MARK: - Lock state

    static var lockState: LockState {
        get {
            LockState(
                isLocked: defaults.bool(forKey: Key.isLocked),
                lockedAt: defaults.object(forKey: Key.lockedAt) as? Date,
                autoUnlockAt: defaults.object(forKey: Key.autoUnlockAt) as? Date
            )
        }
        set {
            defaults.set(newValue.isLocked, forKey: Key.isLocked)
            defaults.set(newValue.lockedAt, forKey: Key.lockedAt)
            defaults.set(newValue.autoUnlockAt, forKey: Key.autoUnlockAt)
        }
    }

    // MARK: - Auto-unlock timeout

    /// Configurable fallback timeout, in minutes. Always within DeviceActivity's
    /// legal range so a stale or hand-edited value can't produce a schedule the
    /// system will reject.
    static var autoUnlockMinutes: Int {
        get {
            let stored = defaults.integer(forKey: Key.autoUnlockMinutes)
            guard stored > 0 else { return AutoUnlock.defaultMinutes }
            return min(max(stored, AutoUnlock.minimumMinutes), AutoUnlock.maximumMinutes)
        }
        set {
            let clamped = min(max(newValue, AutoUnlock.minimumMinutes), AutoUnlock.maximumMinutes)
            defaults.set(clamped, forKey: Key.autoUnlockMinutes)
        }
    }

    // MARK: - What gets blocked

    /// The apps/categories chosen in `FamilyActivityPicker`.
    ///
    /// The tokens inside are opaque and only meaningful to the system, but the
    /// selection as a whole is `Codable`, so it round-trips through the shared
    /// container fine.
    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: Key.selection),
                  let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.selection)
        }
    }

    // MARK: - NFC card

    /// Set once the identifier has been written to a physical card.
    ///
    /// Superseded by `CardRegistry`, which keeps the same answer in the keychain
    /// so it survives reinstalling the app. Still written to so the two agree,
    /// and still read once to migrate anyone upgrading.
    static var cardProvisioned: Bool {
        get { defaults.bool(forKey: Key.cardProvisioned) }
        set { defaults.set(newValue, forKey: Key.cardProvisioned) }
    }
}

extension FamilyActivitySelection {
    /// Nothing picked means there is nothing to shield.
    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    var blockedItemCount: Int {
        applicationTokens.count + categoryTokens.count + webDomainTokens.count
    }
}

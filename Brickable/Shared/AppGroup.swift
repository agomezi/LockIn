//
//  AppGroup.swift
//  Brickable
//
//  Constants shared by the main app and all three extensions. Compiled into
//  every target, so it must stay free of app-only dependencies.
//

import Foundation

enum AppGroup {
    /// Must match the App Groups entitlement on all four targets.
    static let identifier = "group.com.agomezi.brickable"

    /// Shared container the app and extensions both read/write.
    ///
    /// `UserDefaults(suiteName:)` only returns `nil` for a structurally invalid
    /// suite name, but falling back to `.standard` means a mis-provisioned app
    /// group degrades to "the app still works, extensions just don't see the
    /// state" instead of crashing.
    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}

enum LockCard {
    /// Written to the NFC card once during provisioning, then matched on every
    /// later tap. Any card carrying this exact payload acts as the lock card.
    static let identifier = "brickable-lock-card-v1"
}

enum AutoUnlock {
    /// DeviceActivity refuses schedules shorter than 15 minutes, so the
    /// configurable timeout is clamped to this floor.
    static let minimumMinutes = 15
    static let maximumMinutes = 480
    static let defaultMinutes = 60
}

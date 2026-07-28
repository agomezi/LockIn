//
//  ShieldController.swift
//  Brickable
//
//  Applies and clears the actual block. Shared with the DeviceActivity monitor
//  extension so the timeout path clears exactly the same store the app set.
//

import Foundation
import FamilyControls
import ManagedSettings

extension ManagedSettingsStore.Name {
    /// A named store keeps Brickable's restrictions separate from anything else
    /// (including Screen Time itself) and lets the extensions address the very
    /// same store the app wrote to.
    static let brickable = Self("brickable")
}

enum ShieldController {
    static let store = ManagedSettingsStore(named: .brickable)

    /// Raise the shield over everything in `selection`.
    static func applyShield(for selection: FamilyActivitySelection) {
        let applications = selection.applicationTokens
        store.shield.applications = applications.isEmpty ? nil : applications

        let categories = selection.categoryTokens
        store.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: Set())
    }

    /// Drop the shield. Safe to call when nothing is shielded.
    static func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}

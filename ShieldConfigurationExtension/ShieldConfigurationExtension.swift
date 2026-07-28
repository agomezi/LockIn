//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//
//  Draws the block screen. Every shielded surface gets the same treatment:
//  "Locked In" / "Tap your card to unlock", and a single button that only
//  dismisses. Nothing here can lift the block.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.brickableShield
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        Self.brickableShield
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.brickableShield
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        Self.brickableShield
    }

    /// One shield, used everywhere — the block screen shouldn't editorialise or
    /// offer a way around itself, it just says what to do next.
    private static let brickableShield = ShieldConfiguration(
        backgroundBlurStyle: .systemUltraThinMaterialDark,
        backgroundColor: UIColor.black.withAlphaComponent(0.35),
        icon: UIImage(systemName: "lock.fill"),
        title: ShieldConfiguration.Label(
            text: "Locked In",
            color: .white
        ),
        subtitle: ShieldConfiguration.Label(
            text: "Tap your card to unlock",
            color: UIColor.white.withAlphaComponent(0.75)
        ),
        primaryButtonLabel: ShieldConfiguration.Label(
            text: "Close",
            color: .black
        ),
        primaryButtonBackgroundColor: .white
    )
}

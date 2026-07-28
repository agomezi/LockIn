//
//  ShieldActionExtension.swift
//  ShieldActionExtension
//
//  Handles taps on the block screen's buttons.
//
//  Deliberately limited: the only outcomes are "close the app" and "leave the
//  shield up". Unlocking is the card's job, so there is no path from here that
//  touches ShieldController or LockCoordinator.
//

import ManagedSettings

class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.response(for: action))
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.response(for: action))
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(Self.response(for: action))
    }

    private static func response(for action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            // "Close" — send the user back out of the blocked app.
            return .close
        default:
            // Everything else — the unused secondary button, and the submenu
            // actions newer iOS versions can surface — leaves the shield
            // exactly where it is. Nothing here lifts the block.
            return .defer
        }
    }
}

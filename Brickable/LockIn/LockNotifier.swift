//
//  LockNotifier.swift
//  Brickable
//
//  Local notifications for lock changes that happen with no UI on screen.
//
//  A Shortcuts automation runs the App Intent silently — the intent's
//  `ProvidesDialog` text is only spoken/shown when Siri invoked it — so a card
//  tap outside the app has to announce itself with a real notification or it
//  gives no feedback at all.
//
//  Every post reuses one identifier, so the tray holds the current lock state
//  rather than a pile of stale taps.
//

import Foundation
import UserNotifications

enum LockNotifier {

    /// One slot in Notification Centre: a new post replaces whatever is there.
    private static let identifier = "brickable.lock.state"

    private static var center: UNUserNotificationCenter { .current() }

    // MARK: - Permission

    /// Ask once, the first time there's a card that could trigger a background
    /// tap. Calling this when the answer is already known does nothing, so it's
    /// safe on every foreground.
    static func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    // MARK: - Posts

    static func lockedIn(minutes: Int, until unlockAt: Date?) {
        guard let unlockAt else {
            post(title: "Locked in",
                 body: "The auto-unlock timer didn't arm, so your card is the only way out.")
            return
        }

        post(title: "Locked in for \(durationDescription(minutes))",
             body: "Unlocks at \(unlockAt.formatted(date: .omitted, time: .shortened)), or tap your card again.")
    }

    static func unlocked() {
        post(title: "Unlocked", body: "Your apps are available again.")
    }

    /// Drop the tray entry. Used when the lock changes with the app on screen,
    /// where the in-app banner is the feedback and a leftover "Locked in for 60
    /// minutes" from an earlier tap would just be wrong.
    static func clear() {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // `trigger: nil` delivers immediately.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - Formatting

    /// "45 minutes", "1 hour", "2 hours 30 min" — the timeout is clamped to
    /// 15...480 minutes, so those are the only shapes needed.
    static func durationDescription(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) minutes" }

        let hours = minutes / 60
        let remainder = minutes % 60
        let hoursDescription = hours == 1 ? "1 hour" : "\(hours) hours"

        return remainder == 0 ? hoursDescription : "\(hoursDescription) \(remainder) min"
    }
}

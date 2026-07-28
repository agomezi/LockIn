//
//  LockCoordinator.swift
//  Brickable
//
//  The one place the lock is turned on and off. Shared with the DeviceActivity
//  monitor extension so a timeout unlock takes exactly the same path as a card
//  tap — shield cleared, schedule cancelled, shared state updated.
//

import Foundation
import FamilyControls

enum LockError: LocalizedError {
    case nothingSelected

    var errorDescription: String? {
        switch self {
        case .nothingSelected:
            return "Choose at least one app or category to block first."
        }
    }
}

enum LockCoordinator {
    struct Outcome {
        let state: LockState
        /// False when the shield went up but DeviceActivity refused the
        /// timeout, which means the card is the only way back out.
        let timeoutScheduled: Bool
    }

    /// Raise the shield and arm the auto-unlock timeout.
    @discardableResult
    static func lock() throws -> Outcome {
        let selection = SharedLockStore.selection
        guard !selection.isEmpty else { throw LockError.nothingSelected }

        ShieldController.applyShield(for: selection)

        let now = Date()
        let unlockAt = now.addingTimeInterval(TimeInterval(SharedLockStore.autoUnlockMinutes) * 60)

        // The shield is already up at this point. If scheduling fails we keep
        // the lock rather than silently rolling it back, and report the missing
        // fallback to the caller instead of pretending it armed.
        var timeoutScheduled = true
        do {
            try AutoUnlockScheduler.schedule(unlockAt: unlockAt)
        } catch {
            timeoutScheduled = false
        }

        let state = LockState(isLocked: true, lockedAt: now, autoUnlockAt: timeoutScheduled ? unlockAt : nil)
        SharedLockStore.lockState = state
        return Outcome(state: state, timeoutScheduled: timeoutScheduled)
    }

    /// Drop the shield and cancel any pending timeout.
    static func unlock() {
        ShieldController.clearShield()
        AutoUnlockScheduler.stop()
        SharedLockStore.lockState = .unlocked
    }

    /// Flip the lock based on whatever the shared container currently says.
    /// This is what a card tap calls.
    @discardableResult
    static func toggle() throws -> Outcome {
        if SharedLockStore.lockState.isLocked {
            unlock()
            return Outcome(state: .unlocked, timeoutScheduled: false)
        }
        return try lock()
    }

    /// Self-heal on launch/foreground: if the timeout elapsed while the monitor
    /// extension was never given a chance to run, drop the shield now.
    static func reconcile() {
        let state = SharedLockStore.lockState
        guard state.isLocked else { return }

        if state.isExpired || SharedLockStore.selection.isEmpty {
            unlock()
        }
    }
}

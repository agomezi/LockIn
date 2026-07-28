//
//  LockManager.swift
//  Brickable
//
//  View model for the Lock In tab: Family Controls authorization, the picker
//  selection, the auto-unlock timeout setting, and the NFC tap that flips the
//  lock. Mutating the lock itself is delegated to LockCoordinator so the app
//  and the timeout extension can't drift apart.
//

import Foundation
import FamilyControls
import Observation

@MainActor
@Observable
final class LockManager {

    struct Banner: Identifiable, Equatable {
        enum Kind { case success, error }
        let id = UUID()
        let kind: Kind
        let text: String

        static func success(_ text: String) -> Banner { Banner(kind: .success, text: text) }
        static func error(_ text: String) -> Banner { Banner(kind: .error, text: text) }
    }

    private(set) var authorizationStatus: AuthorizationStatus
    private(set) var lockState: LockState
    private(set) var remaining: TimeInterval = 0
    private(set) var isScanning = false
    private(set) var cardProvisioned: Bool

    /// Bound to `FamilyActivityPicker`; call `persistSelection()` after changes.
    var selection: FamilyActivitySelection

    /// Bound to the timeout stepper; call `persistAutoUnlockMinutes()` after changes.
    var autoUnlockMinutes: Int

    var banner: Banner?
    var isPickerPresented = false

    private let nfc = NFCCardService()

    /// Only ever touched on the main actor apart from `deinit`, which is
    /// nonisolated and still has to be able to stop the run loop source.
    @ObservationIgnored private nonisolated(unsafe) var ticker: Timer?

    init() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        lockState = SharedLockStore.lockState
        selection = SharedLockStore.selection
        autoUnlockMinutes = SharedLockStore.autoUnlockMinutes
        cardProvisioned = SharedLockStore.cardProvisioned
    }

    deinit {
        ticker?.invalidate()
    }

    var isAuthorized: Bool { authorizationStatus == .approved }
    var nfcAvailable: Bool { nfc.isAvailable }

    var blockedItemCount: Int { selection.blockedItemCount }

    /// Countdown formatted for the header, e.g. "42:17".
    var remainingDescription: String? {
        guard lockState.isLocked, lockState.autoUnlockAt != nil else { return nil }
        let total = Int(remaining.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Lifecycle

    /// Called on appear and whenever the app comes back to the foreground.
    func refresh() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus

        // Drop the shield if the timeout elapsed while we weren't running.
        LockCoordinator.reconcile()

        lockState = SharedLockStore.lockState
        selection = SharedLockStore.selection
        autoUnlockMinutes = SharedLockStore.autoUnlockMinutes
        cardProvisioned = SharedLockStore.cardProvisioned

        updateRemaining()
        syncTicker()
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            if authorizationStatus == .approved {
                banner = .success("Screen Time access granted.")
            }
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            banner = .error("Screen Time access was declined. Grant it in Settings › Screen Time to use the lock.")
        }
    }

    // MARK: - Settings

    func persistSelection() {
        SharedLockStore.selection = selection

        // Editing the list while locked should take effect immediately rather
        // than waiting for the next tap.
        if lockState.isLocked {
            if selection.isEmpty {
                LockCoordinator.unlock()
                lockState = SharedLockStore.lockState
                syncTicker()
                banner = .error("Nothing left to block, so the lock was released.")
            } else {
                ShieldController.applyShield(for: selection)
            }
        }
    }

    func persistAutoUnlockMinutes() {
        SharedLockStore.autoUnlockMinutes = autoUnlockMinutes
        // Normalise back in case the value was clamped on the way in.
        autoUnlockMinutes = SharedLockStore.autoUnlockMinutes
    }

    // MARK: - The card

    /// One-time: write the identifier onto a blank card.
    func provisionCard() {
        guard !isScanning else { return }
        isScanning = true

        nfc.provisionCard { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isScanning = false

                switch result {
                case .success:
                    SharedLockStore.cardProvisioned = true
                    self.cardProvisioned = true
                    self.banner = .success("Card set up. Tap it to lock in.")
                case .failure(let error):
                    self.report(error)
                }
            }
        }
    }

    /// Every tap after that: confirm the card, then flip the lock.
    func tapCard() {
        guard !isScanning else { return }

        guard isAuthorized else {
            banner = .error("Grant Screen Time access first.")
            return
        }
        guard lockState.isLocked || !selection.isEmpty else {
            banner = .error(LockError.nothingSelected.localizedDescription)
            return
        }

        isScanning = true
        nfc.scanCard { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isScanning = false

                switch result {
                case .success:
                    self.toggleLock()
                case .failure(let error):
                    self.report(error)
                }
            }
        }
    }

    private func toggleLock() {
        do {
            let outcome = try LockCoordinator.toggle()
            lockState = outcome.state
            updateRemaining()
            syncTicker()

            if outcome.state.isLocked {
                banner = outcome.timeoutScheduled
                    ? .success("Locked in for \(autoUnlockMinutes) minutes.")
                    : .error("Locked in, but the auto-unlock timer couldn't be scheduled — your card is the only way out.")
            } else {
                banner = .success("Unlocked.")
            }
        } catch {
            banner = .error(error.localizedDescription)
        }
    }

    private func report(_ error: Error) {
        // Backing out of the system NFC sheet isn't worth a message.
        if let serviceError = error as? NFCCardService.ServiceError, serviceError == .cancelled {
            return
        }
        banner = .error(error.localizedDescription)
    }

    // MARK: - Countdown

    private func updateRemaining() {
        remaining = lockState.remainingTime ?? 0
    }

    /// Run a one-second ticker only while a timed lock is active.
    private func syncTicker() {
        let needsTicker = lockState.isLocked && lockState.autoUnlockAt != nil
        guard needsTicker else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateRemaining()

                // Foreground safety net: if the timeout passed and the monitor
                // extension hasn't cleared things, do it here.
                if self.remaining <= 0 {
                    LockCoordinator.reconcile()
                    self.lockState = SharedLockStore.lockState
                    if !self.lockState.isLocked {
                        self.banner = .success("Auto-unlock timer ran out. Unlocked.")
                    }
                    self.updateRemaining()
                    self.syncTicker()
                }
            }
        }
    }
}

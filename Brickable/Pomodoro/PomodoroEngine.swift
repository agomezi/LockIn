//
//  PomodoroEngine.swift
//  Brickable
//
//  The countdown and the focus → short break → long break cycle.
//
//  Time remaining is always derived from an end date rather than accumulated
//  tick-by-tick, so backgrounding the app doesn't cause drift — the tick just
//  recomputes, and `syncAfterForeground()` catches up a phase that finished
//  while the timer wasn't firing.
//

import Foundation
import Observation
import AudioToolbox
import UIKit

@MainActor
@Observable
final class PomodoroEngine {

    enum Phase: String, CaseIterable, Equatable {
        case focus
        case shortBreak
        case longBreak

        var title: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }

        var isBreak: Bool { self != .focus }
    }

    private(set) var phase: Phase = .focus
    private(set) var isRunning = false
    private(set) var remaining: TimeInterval

    /// Completed focus sessions, used to decide when a long break is due.
    private(set) var completedFocusSessions = 0

    private(set) var settings: PomodoroSettings

    /// Called with the focus length in minutes each time a focus phase runs to
    /// completion. The Pomodoro tab wires this to `DailyProgressStore`.
    var onFocusSessionCompleted: ((Int) -> Void)?

    private var endDate: Date?

    /// Only ever touched on the main actor apart from `deinit`, which is
    /// nonisolated and still has to be able to stop the run loop source.
    @ObservationIgnored private nonisolated(unsafe) var ticker: Timer?

    init(settings: PomodoroSettings = PomodoroSettings()) {
        self.settings = settings
        self.remaining = TimeInterval(settings.focusMinutes * 60)
    }

    deinit {
        ticker?.invalidate()
    }

    // MARK: - Derived state

    func duration(for phase: Phase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus: minutes = max(1, settings.focusMinutes)
        case .shortBreak: minutes = max(1, settings.shortBreakMinutes)
        case .longBreak: minutes = max(1, settings.longBreakMinutes)
        }
        return TimeInterval(minutes * 60)
    }

    /// 0 at the start of a phase, 1 at the end.
    var progress: Double {
        let total = duration(for: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - (remaining / total)))
    }

    /// "24:31"
    var remainingDescription: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Position in the current long-break cycle, e.g. 3 of 4.
    var cyclePosition: Int {
        let every = max(1, settings.longBreakEvery)
        return (completedFocusSessions % every) + 1
    }

    var sessionsUntilLongBreak: Int {
        let every = max(1, settings.longBreakEvery)
        return every - (completedFocusSessions % every)
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = duration(for: phase) }

        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        startTicker()
    }

    func pause() {
        guard isRunning else { return }
        // Freeze the exact remaining time so resuming picks up where it left off.
        remaining = max(0, endDate?.timeIntervalSinceNow ?? remaining)
        isRunning = false
        endDate = nil
        stopTicker()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Back to the start of the current phase.
    func reset() {
        stopTicker()
        isRunning = false
        endDate = nil
        remaining = duration(for: phase)
    }

    /// Jump to the next phase without finishing this one. A skipped focus
    /// session isn't logged and doesn't count towards the long-break cadence.
    func skip() {
        advance(completed: false)
    }

    /// Start the whole cycle over.
    func resetCycle() {
        stopTicker()
        isRunning = false
        endDate = nil
        completedFocusSessions = 0
        phase = .focus
        remaining = duration(for: .focus)
    }

    // MARK: - Settings

    func apply(_ newSettings: PomodoroSettings) {
        let previous = settings
        settings = newSettings

        // Re-length the current phase only when idle — changing the focus
        // length mid-session shouldn't yank time out from under a running timer.
        guard !isRunning else { return }
        if previous.focusMinutes != newSettings.focusMinutes
            || previous.shortBreakMinutes != newSettings.shortBreakMinutes
            || previous.longBreakMinutes != newSettings.longBreakMinutes {
            remaining = duration(for: phase)
        }
    }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            advance(completed: true)
        }
    }

    /// Called when the app returns to the foreground, in case the phase ended
    /// while timers were suspended.
    func syncAfterForeground() {
        tick()
    }

    // MARK: - Phase transitions

    /// Finish the current phase and move to the next one. `completed` is false
    /// for a manual skip, which suppresses logging, the chime and auto-start.
    /// Internal rather than private so tests can drive the cycle without
    /// waiting out real countdowns.
    func advance(completed: Bool) {
        stopTicker()
        isRunning = false
        endDate = nil

        let finishedPhase = phase

        if finishedPhase == .focus && completed {
            completedFocusSessions += 1
            onFocusSessionCompleted?(max(1, settings.focusMinutes))
        }

        if completed {
            signalPhaseEnd()
        }

        let next: Phase
        if finishedPhase == .focus {
            let every = max(1, settings.longBreakEvery)
            next = (completedFocusSessions > 0 && completedFocusSessions % every == 0)
                ? .longBreak
                : .shortBreak
        } else {
            next = .focus
        }

        phase = next
        remaining = duration(for: next)

        // Auto-start only follows a phase that actually ran out; skipping is a
        // deliberate action and shouldn't immediately launch the next timer.
        guard completed else { return }
        let shouldAutoStart = next.isBreak ? settings.autoStartBreak : settings.autoStartFocus
        if shouldAutoStart { start() }
    }

    private func signalPhaseEnd() {
        guard settings.soundEnabled else { return }
        AudioServicesPlaySystemSound(1005)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

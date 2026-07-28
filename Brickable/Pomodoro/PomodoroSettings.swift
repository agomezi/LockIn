//
//  PomodoroSettings.swift
//  Brickable
//
//  Mirrors the Django `UserSettings` model field-for-field (including defaults),
//  so syncing with the backend later is a networking layer rather than a
//  rewrite. The snake_case `CodingKeys` are what the Django REST serializer
//  emits, so the same struct decodes a `/api/settings/` response as-is.
//

import Foundation
import Observation

struct PomodoroSettings: Codable, Equatable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var longBreakEvery: Int = 4
    var dailyGoalSessions: Int = 8
    var soundEnabled: Bool = true
    var autoStartBreak: Bool = false
    var autoStartFocus: Bool = false

    enum CodingKeys: String, CodingKey {
        case focusMinutes = "focus_minutes"
        case shortBreakMinutes = "short_break_minutes"
        case longBreakMinutes = "long_break_minutes"
        case longBreakEvery = "long_break_every"
        case dailyGoalSessions = "daily_goal_sessions"
        case soundEnabled = "sound_enabled"
        case autoStartBreak = "auto_start_break"
        case autoStartFocus = "auto_start_focus"
    }

    init() {}

    /// Decode leniently: a payload missing a field falls back to that field's
    /// default rather than failing the whole decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PomodoroSettings()

        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? defaults.focusMinutes
        shortBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? defaults.shortBreakMinutes
        longBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? defaults.longBreakMinutes
        longBreakEvery = try container.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? defaults.longBreakEvery
        dailyGoalSessions = try container.decodeIfPresent(Int.self, forKey: .dailyGoalSessions) ?? defaults.dailyGoalSessions
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? defaults.soundEnabled
        autoStartBreak = try container.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? defaults.autoStartBreak
        autoStartFocus = try container.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? defaults.autoStartFocus
    }

    /// Ranges the settings form enforces. `PositiveSmallIntegerField` on the
    /// Django side tops out at 32767, but these are the sane human limits.
    enum Limits {
        static let focusMinutes = 1...120
        static let shortBreakMinutes = 1...60
        static let longBreakMinutes = 1...60
        static let longBreakEvery = 1...12
        static let dailyGoalSessions = 1...24
    }
}

/// Loads and saves `PomodoroSettings` in `UserDefaults`.
@MainActor
@Observable
final class PomodoroSettingsStore {
    private static let key = "brickable.pomodoro.settings"

    var settings: PomodoroSettings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(PomodoroSettings.self, from: data) {
            settings = decoded
        } else {
            settings = PomodoroSettings()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func resetToDefaults() {
        settings = PomodoroSettings()
        save()
    }
}

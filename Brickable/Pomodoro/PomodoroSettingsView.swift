//
//  PomodoroSettingsView.swift
//  Brickable
//
//  A form over every field of `PomodoroSettings`. Changes are saved as they're
//  made and pushed straight into the engine.
//

import SwiftUI

struct PomodoroSettingsView: View {
    @Bindable var store: PomodoroSettingsStore
    let engine: PomodoroEngine

    var body: some View {
        Form {
            Section("Durations") {
                minuteStepper("Focus",
                              value: $store.settings.focusMinutes,
                              range: PomodoroSettings.Limits.focusMinutes)
                minuteStepper("Short break",
                              value: $store.settings.shortBreakMinutes,
                              range: PomodoroSettings.Limits.shortBreakMinutes)
                minuteStepper("Long break",
                              value: $store.settings.longBreakMinutes,
                              range: PomodoroSettings.Limits.longBreakMinutes)
            }

            Section {
                Stepper(value: $store.settings.longBreakEvery,
                        in: PomodoroSettings.Limits.longBreakEvery) {
                    LabeledContent("Long break every",
                                   value: "\(store.settings.longBreakEvery) session\(store.settings.longBreakEvery == 1 ? "" : "s")")
                }
            } footer: {
                Text("How many focus sessions to finish before the longer break.")
            }

            Section("Daily Goal") {
                Stepper(value: $store.settings.dailyGoalSessions,
                        in: PomodoroSettings.Limits.dailyGoalSessions) {
                    LabeledContent("Target",
                                   value: "\(store.settings.dailyGoalSessions) session\(store.settings.dailyGoalSessions == 1 ? "" : "s")")
                }
            }

            Section("Behaviour") {
                Toggle("Sound", isOn: $store.settings.soundEnabled)
                Toggle("Auto-start breaks", isOn: $store.settings.autoStartBreak)
                Toggle("Auto-start focus", isOn: $store.settings.autoStartFocus)
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    store.resetToDefaults()
                }
            } footer: {
                Text("Focus 25 · Short break 5 · Long break 15 · Long break every 4 · Goal 8 sessions.")
            }
        }
        .scrollContentBackground(.hidden)
        .onChange(of: store.settings) { _, newValue in
            store.save()
            engine.apply(newValue)
        }
    }

    private func minuteStepper(_ title: String,
                               value: Binding<Int>,
                               range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title, value: "\(value.wrappedValue) min")
        }
    }
}

#Preview {
    PomodoroSettingsView(store: PomodoroSettingsStore(), engine: PomodoroEngine())
}

//
//  PomodoroRootView.swift
//  Brickable
//
//  The Pomodoro tab. A segmented control switches between the three screens —
//  nesting a second TabView inside the app's tab bar would stack two bars on
//  top of each other.
//

import SwiftUI
import SwiftData

struct PomodoroRootView: View {
    @Bindable var settingsStore: PomodoroSettingsStore
    let engine: PomodoroEngine

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var screen: Screen = .timer

    enum Screen: String, CaseIterable, Identifiable {
        case timer = "Timer"
        case progress = "Progress"
        case settings = "Settings"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Screen", selection: $screen) {
                    ForEach(Screen.allCases) { screen in
                        Text(screen.rawValue).tag(screen)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                Group {
                    switch screen {
                    case .timer:
                        PomodoroTimerView(engine: engine,
                                          dailyGoalSessions: settingsStore.settings.dailyGoalSessions)
                    case .progress:
                        PomodoroStatsView(dailyGoalSessions: settingsStore.settings.dailyGoalSessions)
                    case .settings:
                        PomodoroSettingsView(store: settingsStore, engine: engine)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // Bring the engine in line with saved settings, and route completed
            // focus sessions into SwiftData.
            engine.apply(settingsStore.settings)
            engine.onFocusSessionCompleted = { minutes in
                DailyProgressStore.logSession(minutes: minutes, in: modelContext)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.syncAfterForeground() }
        }
    }
}

#Preview {
    PomodoroRootView(settingsStore: PomodoroSettingsStore(), engine: PomodoroEngine())
        .modelContainer(for: DailyProgress.self, inMemory: true)
}

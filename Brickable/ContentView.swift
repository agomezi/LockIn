//
//  ContentView.swift
//  Brickable
//
//  Root tab bar: the Brick-style lock on one side, Pomodoro on the other.
//

import SwiftUI

struct ContentView: View {
    let lockManager: LockManager
    let pomodoroSettings: PomodoroSettingsStore
    let pomodoroEngine: PomodoroEngine

    enum Tab: Hashable {
        case lockIn
        case pomodoro
    }

    @State private var selectedTab: Tab = .lockIn

    var body: some View {
        TabView(selection: $selectedTab) {
            LockInView(manager: lockManager)
                .tabItem {
                    Label("Lock In", systemImage: "lock.fill")
                }
                .tag(Tab.lockIn)

            PomodoroRootView(settingsStore: pomodoroSettings, engine: pomodoroEngine)
                .tabItem {
                    Label("Pomodoro", systemImage: "timer")
                }
                .tag(Tab.pomodoro)
        }
    }
}

#Preview {
    ContentView(lockManager: LockManager(),
                pomodoroSettings: PomodoroSettingsStore(),
                pomodoroEngine: PomodoroEngine())
        .modelContainer(for: DailyProgress.self, inMemory: true)
}

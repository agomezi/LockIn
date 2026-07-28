//
//  BrickableApp.swift
//  Brickable
//
//  App entry point. Owns the three long-lived objects — the lock manager, the
//  Pomodoro settings store and the timer engine — plus the SwiftData container
//  backing daily progress.
//

import SwiftUI
import SwiftData

@main
struct BrickableApp: App {
    @State private var lockManager = LockManager()
    @State private var pomodoroSettings = PomodoroSettingsStore()
    @State private var pomodoroEngine = PomodoroEngine()

    private let modelContainer: ModelContainer = {
        let schema = Schema([DailyProgress.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(lockManager: lockManager,
                        pomodoroSettings: pomodoroSettings,
                        pomodoroEngine: pomodoroEngine)
        }
        .modelContainer(modelContainer)
    }
}

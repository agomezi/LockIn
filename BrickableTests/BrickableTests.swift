//
//  BrickableTests.swift
//  BrickableTests
//
//  Covers the logic that has a right answer: the Django-equivalent stats port,
//  settings encoding, lock state, and the Pomodoro phase cycle.
//

import XCTest
import SwiftData
@testable import Brickable

final class PomodoroStatsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    /// Fixed reference day so tests never depend on when they run.
    private lazy var today: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 27
        return calendar.date(from: components)!
    }()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func record(_ offset: Int, sessions: Int, minutes: Int = 25) -> DayRecord {
        DayRecord(date: day(offset), focusSessionsCompleted: sessions, focusMinutesCompleted: minutes)
    }

    private func stats(_ records: [DayRecord]) -> PomodoroStats {
        PomodoroStats.compute(from: records, today: today, calendar: calendar)
    }

    // MARK: - Totals

    func testEmptyHistoryProducesZeroes() {
        XCTAssertEqual(stats([]), PomodoroStats.empty)
    }

    func testTotalsSumEveryDay() {
        let result = stats([
            record(-2, sessions: 2, minutes: 50),
            record(-1, sessions: 3, minutes: 75),
            record(0, sessions: 1, minutes: 25)
        ])

        XCTAssertEqual(result.totalSessions, 6)
        XCTAssertEqual(result.totalMinutes, 150)
    }

    func testTodayReadsFromTodaysRow() {
        let result = stats([
            record(-1, sessions: 9, minutes: 225),
            record(0, sessions: 4, minutes: 100)
        ])

        XCTAssertEqual(result.todaySessions, 4)
        XCTAssertEqual(result.todayMinutes, 100)
    }

    func testTodayIsZeroWhenThereIsNoRowForToday() {
        let result = stats([record(-1, sessions: 4)])

        XCTAssertEqual(result.todaySessions, 0)
        XCTAssertEqual(result.todayMinutes, 0)
    }

    // MARK: - Current streak

    func testCurrentStreakCountsConsecutiveDaysEndingToday() {
        let result = stats([
            record(-2, sessions: 1),
            record(-1, sessions: 2),
            record(0, sessions: 1)
        ])

        XCTAssertEqual(result.currentStreak, 3)
    }

    func testCurrentStreakStopsAtAGapInTheDays() {
        let result = stats([
            record(-5, sessions: 4),
            record(-4, sessions: 4),
            // days -3 and -2 missing entirely
            record(-1, sessions: 1),
            record(0, sessions: 1)
        ])

        XCTAssertEqual(result.currentStreak, 2)
    }

    func testCurrentStreakBreaksOnADayWithZeroSessions() {
        let result = stats([
            record(-2, sessions: 3),
            record(-1, sessions: 0, minutes: 0),
            record(0, sessions: 1)
        ])

        XCTAssertEqual(result.currentStreak, 1)
    }

    func testCurrentStreakIsZeroWhenTheLastActivityIsOlderThanYesterday() {
        let result = stats([
            record(-4, sessions: 5),
            record(-3, sessions: 5)
        ])

        XCTAssertEqual(result.currentStreak, 0)
    }

    /// Pinned quirk, not a bug in this port: the Django view starts its walk at
    /// *today*, so a run that ended yesterday reports 0 until a session is
    /// logged today. Reproduced here so local and server numbers match — if the
    /// backend ever changes, this test is the reminder to change both.
    func testCurrentStreakIsZeroUntilASessionIsLoggedToday() {
        let result = stats([
            record(-2, sessions: 3),
            record(-1, sessions: 3)
        ])

        XCTAssertEqual(result.currentStreak, 0)
        XCTAssertEqual(result.longestStreak, 2, "the run itself is still the best streak")
    }

    // MARK: - Longest streak

    func testLongestStreakFindsTheBestRunInHistory() {
        let result = stats([
            record(-10, sessions: 1),
            record(-9, sessions: 1),
            record(-8, sessions: 1),
            record(-7, sessions: 1),   // 4-day run
            record(-5, sessions: 1),
            record(-4, sessions: 1),   // 2-day run
            record(0, sessions: 1)     // today
        ])

        XCTAssertEqual(result.longestStreak, 4)
        XCTAssertEqual(result.currentStreak, 1)
    }

    func testLongestStreakTreatsAZeroSessionDayAsABreak() {
        let result = stats([
            record(-4, sessions: 2),
            record(-3, sessions: 2),
            record(-2, sessions: 0, minutes: 0),
            record(-1, sessions: 2),
            record(0, sessions: 2)
        ])

        XCTAssertEqual(result.longestStreak, 2)
        XCTAssertEqual(result.currentStreak, 2)
    }

    func testUnorderedInputIsSortedBeforeComputing() {
        let result = stats([
            record(0, sessions: 1),
            record(-2, sessions: 1),
            record(-1, sessions: 1)
        ])

        XCTAssertEqual(result.currentStreak, 3)
        XCTAssertEqual(result.longestStreak, 3)
    }

    func testTimestampsWithinADayAreNormalisedToThatDay() {
        // Same calendar day, different clock times — should be one day, not two.
        let midMorning = calendar.date(byAdding: .hour, value: 10, to: today)!
        let result = PomodoroStats.compute(
            from: [DayRecord(date: midMorning, focusSessionsCompleted: 2, focusMinutesCompleted: 50)],
            today: calendar.date(byAdding: .hour, value: 22, to: today)!,
            calendar: calendar
        )

        XCTAssertEqual(result.todaySessions, 2)
        XCTAssertEqual(result.currentStreak, 1)
    }
}

// MARK: -

final class PomodoroSettingsTests: XCTestCase {

    func testDefaultsMatchTheDjangoModel() {
        let settings = PomodoroSettings()

        XCTAssertEqual(settings.focusMinutes, 25)
        XCTAssertEqual(settings.shortBreakMinutes, 5)
        XCTAssertEqual(settings.longBreakMinutes, 15)
        XCTAssertEqual(settings.longBreakEvery, 4)
        XCTAssertEqual(settings.dailyGoalSessions, 8)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertFalse(settings.autoStartBreak)
        XCTAssertFalse(settings.autoStartFocus)
    }

    func testEncodesWithSnakeCaseKeysTheBackendExpects() throws {
        let data = try JSONEncoder().encode(PomodoroSettings())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["focus_minutes"] as? Int, 25)
        XCTAssertEqual(json["short_break_minutes"] as? Int, 5)
        XCTAssertEqual(json["long_break_minutes"] as? Int, 15)
        XCTAssertEqual(json["long_break_every"] as? Int, 4)
        XCTAssertEqual(json["daily_goal_sessions"] as? Int, 8)
        XCTAssertEqual(json["sound_enabled"] as? Bool, true)
        XCTAssertEqual(json["auto_start_break"] as? Bool, false)
        XCTAssertEqual(json["auto_start_focus"] as? Bool, false)
    }

    func testDecodesAServerPayload() throws {
        let json = """
        {
          "focus_minutes": 50,
          "short_break_minutes": 10,
          "long_break_minutes": 30,
          "long_break_every": 3,
          "daily_goal_sessions": 6,
          "sound_enabled": false,
          "auto_start_break": true,
          "auto_start_focus": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(PomodoroSettings.self, from: json)

        XCTAssertEqual(settings.focusMinutes, 50)
        XCTAssertEqual(settings.shortBreakMinutes, 10)
        XCTAssertEqual(settings.longBreakMinutes, 30)
        XCTAssertEqual(settings.longBreakEvery, 3)
        XCTAssertEqual(settings.dailyGoalSessions, 6)
        XCTAssertFalse(settings.soundEnabled)
        XCTAssertTrue(settings.autoStartBreak)
        XCTAssertTrue(settings.autoStartFocus)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let json = #"{"focus_minutes": 45}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(PomodoroSettings.self, from: json)

        XCTAssertEqual(settings.focusMinutes, 45)
        XCTAssertEqual(settings.shortBreakMinutes, 5)
        XCTAssertTrue(settings.soundEnabled)
    }

    func testStatsResponseDecodesTheBackendShape() throws {
        let json = """
        {"total_sessions": 12, "total_minutes": 300, "current_streak": 3, "longest_streak": 9}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NetworkManager.StatsResponse.self, from: json)

        XCTAssertEqual(response.totalSessions, 12)
        XCTAssertEqual(response.totalMinutes, 300)
        XCTAssertEqual(response.currentStreak, 3)
        XCTAssertEqual(response.longestStreak, 9)
    }
}

// MARK: -

@MainActor
final class PomodoroEngineTests: XCTestCase {

    private func makeEngine(_ mutate: (inout PomodoroSettings) -> Void = { _ in }) -> PomodoroEngine {
        var settings = PomodoroSettings()
        mutate(&settings)
        return PomodoroEngine(settings: settings)
    }

    func testStartsInFocusAtFullDuration() {
        let engine = makeEngine()

        XCTAssertEqual(engine.phase, .focus)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.remaining, 25 * 60)
        XCTAssertEqual(engine.remainingDescription, "25:00")
    }

    func testFocusIsFollowedByAShortBreak() {
        let engine = makeEngine()
        engine.advance(completed: true)

        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.remaining, 5 * 60)
        XCTAssertEqual(engine.completedFocusSessions, 1)
    }

    func testEveryFourthFocusEarnsALongBreak() {
        let engine = makeEngine()

        for session in 1...4 {
            engine.advance(completed: true)   // finish focus
            if session < 4 {
                XCTAssertEqual(engine.phase, .shortBreak, "session \(session)")
            } else {
                XCTAssertEqual(engine.phase, .longBreak, "session \(session)")
                XCTAssertEqual(engine.remaining, 15 * 60)
            }
            engine.advance(completed: true)   // finish the break
            XCTAssertEqual(engine.phase, .focus)
        }

        XCTAssertEqual(engine.completedFocusSessions, 4)
    }

    func testLongBreakEveryHonoursTheSetting() {
        let engine = makeEngine { $0.longBreakEvery = 2 }

        engine.advance(completed: true)
        XCTAssertEqual(engine.phase, .shortBreak)
        engine.advance(completed: true)

        engine.advance(completed: true)
        XCTAssertEqual(engine.phase, .longBreak)
    }

    func testCompletedFocusSessionIsLoggedWithTheFocusLength() {
        let engine = makeEngine { $0.focusMinutes = 30 }
        var logged: [Int] = []
        engine.onFocusSessionCompleted = { logged.append($0) }

        engine.advance(completed: true)   // focus done
        engine.advance(completed: true)   // break done — must not log

        XCTAssertEqual(logged, [30])
    }

    func testSkippingAFocusSessionLogsNothingAndDoesNotCount() {
        let engine = makeEngine()
        var logged: [Int] = []
        engine.onFocusSessionCompleted = { logged.append($0) }

        engine.skip()

        XCTAssertTrue(logged.isEmpty)
        XCTAssertEqual(engine.completedFocusSessions, 0)
        XCTAssertEqual(engine.phase, .shortBreak)
    }

    func testSkipNeverAutoStartsTheNextPhase() {
        let engine = makeEngine {
            $0.autoStartBreak = true
            $0.autoStartFocus = true
        }

        engine.skip()

        XCTAssertFalse(engine.isRunning)
    }

    func testAutoStartBreakStartsTheBreakAfterACompletedFocus() {
        let engine = makeEngine { $0.autoStartBreak = true }

        engine.advance(completed: true)

        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertTrue(engine.isRunning)
    }

    func testAutoStartFocusIsIndependentOfAutoStartBreak() {
        let engine = makeEngine { $0.autoStartFocus = true }

        engine.advance(completed: true)          // focus → break
        XCTAssertFalse(engine.isRunning, "autoStartBreak is off")

        engine.advance(completed: true)          // break → focus
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertTrue(engine.isRunning)
    }

    func testPauseKeepsTheRemainingTimeAndResetRestoresIt() {
        let engine = makeEngine()
        engine.start()
        XCTAssertTrue(engine.isRunning)

        engine.pause()
        XCTAssertFalse(engine.isRunning)
        XCTAssertGreaterThan(engine.remaining, 0)
        XCTAssertLessThanOrEqual(engine.remaining, 25 * 60)

        engine.reset()
        XCTAssertEqual(engine.remaining, 25 * 60)
        XCTAssertFalse(engine.isRunning)
    }

    func testProgressStartsAtZeroForEachFreshPhase() {
        let engine = makeEngine()
        XCTAssertEqual(engine.progress, 0, accuracy: 0.001)

        engine.advance(completed: true)  // fresh short break
        XCTAssertEqual(engine.progress, 0, accuracy: 0.001)
    }

    func testChangingDurationsWhileIdleRelengthsTheCurrentPhase() {
        let engine = makeEngine()

        var settings = PomodoroSettings()
        settings.focusMinutes = 40
        engine.apply(settings)

        XCTAssertEqual(engine.remaining, 40 * 60)
    }

    func testChangingDurationsWhileRunningLeavesTheCountdownAlone() {
        let engine = makeEngine()
        engine.start()
        let before = engine.remaining

        var settings = PomodoroSettings()
        settings.focusMinutes = 40
        engine.apply(settings)

        XCTAssertEqual(engine.remaining, before, accuracy: 1)
        XCTAssertTrue(engine.isRunning)
    }

    func testResetCycleReturnsToTheFirstFocusSession() {
        let engine = makeEngine()
        engine.advance(completed: true)
        engine.advance(completed: true)

        engine.resetCycle()

        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.completedFocusSessions, 0)
        XCTAssertEqual(engine.remaining, 25 * 60)
        XCTAssertFalse(engine.isRunning)
    }
}

// MARK: -

@MainActor
final class DailyProgressStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: DailyProgress.self, configurations: configuration)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testLoggingCreatesTodaysRow() throws {
        DailyProgressStore.logSession(minutes: 25, in: context)

        let records = DailyProgressStore.allRecords(in: context)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.focusSessionsCompleted, 1)
        XCTAssertEqual(records.first?.focusMinutesCompleted, 25)
    }

    func testLoggingTwiceInADayAccumulatesOnOneRow() throws {
        DailyProgressStore.logSession(minutes: 25, in: context)
        DailyProgressStore.logSession(minutes: 30, in: context)

        let records = DailyProgressStore.allRecords(in: context)
        XCTAssertEqual(records.count, 1, "one row per calendar day")
        XCTAssertEqual(records.first?.focusSessionsCompleted, 2)
        XCTAssertEqual(records.first?.focusMinutesCompleted, 55)
    }

    func testDifferentDaysGetTheirOwnRows() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        DailyProgressStore.logSession(minutes: 25, on: yesterday, in: context)
        DailyProgressStore.logSession(minutes: 25, in: context)

        XCTAssertEqual(DailyProgressStore.allRecords(in: context).count, 2)
    }

    func testZeroOrNegativeDurationsAreIgnored() throws {
        XCTAssertNil(DailyProgressStore.logSession(minutes: 0, in: context))
        XCTAssertNil(DailyProgressStore.logSession(minutes: -5, in: context))
        XCTAssertTrue(DailyProgressStore.allRecords(in: context).isEmpty)
    }

    func testStatsReadTheStoredRows() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        DailyProgressStore.logSession(minutes: 25, on: yesterday, in: context)
        DailyProgressStore.logSession(minutes: 25, in: context)
        DailyProgressStore.logSession(minutes: 25, in: context)

        let stats = PomodoroStats.compute(from: DailyProgressStore.allRecords(in: context))

        XCTAssertEqual(stats.totalSessions, 3)
        XCTAssertEqual(stats.totalMinutes, 75)
        XCTAssertEqual(stats.todaySessions, 2)
        XCTAssertEqual(stats.currentStreak, 2)
    }
}

// MARK: -

final class LockStateTests: XCTestCase {

    func testUnlockedStateHasNoRemainingTime() {
        XCTAssertNil(LockState.unlocked.remainingTime)
        XCTAssertFalse(LockState.unlocked.isExpired)
    }

    func testRemainingTimeCountsDownToTheUnlockDate() throws {
        let state = LockState(isLocked: true,
                              lockedAt: Date(),
                              autoUnlockAt: Date().addingTimeInterval(600))

        let remaining = try XCTUnwrap(state.remainingTime)
        XCTAssertEqual(remaining, 600, accuracy: 2)
        XCTAssertFalse(state.isExpired)
    }

    func testAPassedUnlockDateReadsAsExpiredAndZero() {
        let state = LockState(isLocked: true,
                              lockedAt: Date().addingTimeInterval(-3600),
                              autoUnlockAt: Date().addingTimeInterval(-60))

        XCTAssertTrue(state.isExpired)
        XCTAssertEqual(state.remainingTime, 0)
    }

    func testLockedWithoutATimeoutNeverExpires() {
        let state = LockState(isLocked: true, lockedAt: Date(), autoUnlockAt: nil)

        XCTAssertNil(state.remainingTime)
        XCTAssertFalse(state.isExpired)
    }

    func testLockStateSurvivesACodableRoundTrip() throws {
        let state = LockState(isLocked: true,
                              lockedAt: Date(timeIntervalSince1970: 1_780_000_000),
                              autoUnlockAt: Date(timeIntervalSince1970: 1_780_003_600))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LockState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    func testAutoUnlockMinutesAreClampedToTheSchedulableRange() {
        XCTAssertEqual(AutoUnlock.minimumMinutes, 15, "DeviceActivity's shortest interval")
        XCTAssertLessThan(AutoUnlock.minimumMinutes, AutoUnlock.defaultMinutes)
        XCTAssertLessThanOrEqual(AutoUnlock.defaultMinutes, AutoUnlock.maximumMinutes)
    }
}

// MARK: - Tap notification wording

/// The "Locked in for …" notification is the only feedback a card tap gives when
/// the app isn't on screen, so the phrasing is worth pinning.
final class LockNotifierTests: XCTestCase {

    func testMinutesUnderAnHourReadAsMinutes() {
        XCTAssertEqual(LockNotifier.durationDescription(15), "15 minutes")
        XCTAssertEqual(LockNotifier.durationDescription(45), "45 minutes")
    }

    func testWholeHoursDropTheMinutes() {
        XCTAssertEqual(LockNotifier.durationDescription(60), "1 hour")
        XCTAssertEqual(LockNotifier.durationDescription(120), "2 hours")
    }

    func testMixedDurationsKeepBothParts() {
        XCTAssertEqual(LockNotifier.durationDescription(90), "1 hour 30 min")
        XCTAssertEqual(LockNotifier.durationDescription(185), "3 hours 5 min")
    }

    func testTheWholeSchedulableRangeProducesSomething() {
        for minutes in AutoUnlock.minimumMinutes...AutoUnlock.maximumMinutes {
            XCTAssertFalse(LockNotifier.durationDescription(minutes).isEmpty)
        }
    }
}

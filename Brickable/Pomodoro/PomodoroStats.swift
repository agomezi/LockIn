//
//  PomodoroStats.swift
//  Brickable
//
//  Port of the Django `user_stats` view. Kept deliberately faithful — including
//  its edge-case behaviour — so local numbers and server numbers agree once the
//  backend is wired up. See the note on `currentStreak` below.
//

import Foundation

/// A single day's totals, decoupled from SwiftData so the streak maths can be
/// exercised directly in tests.
struct DayRecord: Equatable {
    var date: Date
    var focusSessionsCompleted: Int
    var focusMinutesCompleted: Int

    init(date: Date, focusSessionsCompleted: Int, focusMinutesCompleted: Int) {
        self.date = date
        self.focusSessionsCompleted = focusSessionsCompleted
        self.focusMinutesCompleted = focusMinutesCompleted
    }

    init(_ progress: DailyProgress) {
        self.init(date: progress.date,
                  focusSessionsCompleted: progress.focusSessionsCompleted,
                  focusMinutesCompleted: progress.focusMinutesCompleted)
    }
}

struct PomodoroStats: Equatable {
    var totalSessions = 0
    var totalMinutes = 0
    var currentStreak = 0
    var longestStreak = 0
    var todaySessions = 0
    var todayMinutes = 0

    static let empty = PomodoroStats()

    static func compute(from records: [DailyProgress],
                        today: Date = Date(),
                        calendar: Calendar = .current) -> PomodoroStats {
        compute(from: records.map(DayRecord.init), today: today, calendar: calendar)
    }

    static func compute(from records: [DayRecord],
                        today: Date = Date(),
                        calendar: Calendar = .current) -> PomodoroStats {
        var stats = PomodoroStats()

        let todayDay = calendar.startOfDay(for: today)
        let sorted = records
            .map {
                DayRecord(date: calendar.startOfDay(for: $0.date),
                          focusSessionsCompleted: $0.focusSessionsCompleted,
                          focusMinutesCompleted: $0.focusMinutesCompleted)
            }
            .sorted { $0.date < $1.date }

        stats.totalSessions = sorted.reduce(0) { $0 + $1.focusSessionsCompleted }
        stats.totalMinutes = sorted.reduce(0) { $0 + $1.focusMinutesCompleted }

        if let todayRecord = sorted.last(where: { $0.date == todayDay }) {
            stats.todaySessions = todayRecord.focusSessionsCompleted
            stats.todayMinutes = todayRecord.focusMinutesCompleted
        }

        guard let latest = sorted.last else { return stats }

        stats.currentStreak = currentStreak(sorted: sorted,
                                            latest: latest,
                                            todayDay: todayDay,
                                            calendar: calendar)
        stats.longestStreak = longestStreak(sorted: sorted, calendar: calendar)

        return stats
    }

    // MARK: - Streaks

    /// Walks backwards from today, counting consecutive days that have at least
    /// one completed focus session; a day with zero sessions breaks the run.
    ///
    /// Note this mirrors the Django view exactly, which means the count only
    /// starts from *today*: if the most recent activity was yesterday, the
    /// current streak reads 0 until a session is logged today. That's the
    /// server's behaviour, so it's reproduced here rather than "fixed" locally —
    /// changing it should happen on both sides at once.
    private static func currentStreak(sorted: [DayRecord],
                                      latest: DayRecord,
                                      todayDay: Date,
                                      calendar: Calendar) -> Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayDay) else { return 0 }
        guard latest.date == todayDay || latest.date == yesterday else { return 0 }

        var streak = 0
        var cursor = todayDay

        for record in sorted.reversed() {
            if record.date == cursor && record.focusSessionsCompleted > 0 {
                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            } else if record.date < cursor {
                break
            }
        }

        return streak
    }

    /// Longest run of consecutive days with at least one completed session.
    private static func longestStreak(sorted: [DayRecord], calendar: Calendar) -> Int {
        var longest = 0
        var running = 0
        var previousDate: Date?

        for record in sorted {
            guard record.focusSessionsCompleted > 0 else {
                previousDate = nil
                running = 0
                continue
            }

            if let previous = previousDate,
               let dayAfterPrevious = calendar.date(byAdding: .day, value: 1, to: previous),
               record.date == dayAfterPrevious {
                running += 1
            } else {
                running = 1
            }

            longest = max(longest, running)
            previousDate = record.date
        }

        return longest
    }
}

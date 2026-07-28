//
//  DailyProgress.swift
//  Brickable
//
//  One row per calendar day, matching the Django `DailyProgress` model.
//

import Foundation
import SwiftData

@Model
final class DailyProgress {
    /// Normalised to the start of the day so it behaves like Django's `DateField`
    /// and can be compared with `==`.
    @Attribute(.unique) var date: Date
    var focusSessionsCompleted: Int
    var focusMinutesCompleted: Int

    init(date: Date, focusSessionsCompleted: Int = 0, focusMinutesCompleted: Int = 0) {
        self.date = date
        self.focusSessionsCompleted = focusSessionsCompleted
        self.focusMinutesCompleted = focusMinutesCompleted
    }
}

enum DailyProgressStore {
    /// Increment today's row, creating it if needed — the local equivalent of
    /// the backend's `log_session` endpoint.
    @discardableResult
    static func logSession(minutes: Int,
                           on day: Date = Date(),
                           calendar: Calendar = .current,
                           in context: ModelContext) -> DailyProgress? {
        guard minutes > 0 else { return nil }
        let normalised = calendar.startOfDay(for: day)

        let record: DailyProgress
        if let existing = fetch(day: normalised, in: context) {
            record = existing
        } else {
            record = DailyProgress(date: normalised)
            context.insert(record)
        }

        record.focusSessionsCompleted += 1
        record.focusMinutesCompleted += minutes

        try? context.save()
        return record
    }

    static func fetch(day: Date, in context: ModelContext) -> DailyProgress? {
        let descriptor = FetchDescriptor<DailyProgress>(
            predicate: #Predicate { $0.date == day }
        )
        return try? context.fetch(descriptor).first
    }

    static func allRecords(in context: ModelContext) -> [DailyProgress] {
        let descriptor = FetchDescriptor<DailyProgress>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

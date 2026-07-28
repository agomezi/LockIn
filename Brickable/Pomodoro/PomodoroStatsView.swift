//
//  PomodoroStatsView.swift
//  Brickable
//
//  Totals, streaks and today's numbers, all derived from the SwiftData rows via
//  the Django-equivalent stats calculation.
//

import SwiftUI
import SwiftData

struct PomodoroStatsView: View {
    let dailyGoalSessions: Int

    @Query(sort: \DailyProgress.date, order: .forward) private var records: [DailyProgress]

    private var stats: PomodoroStats {
        PomodoroStats.compute(from: records)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard
                streakCard
                totalsCard

                if !records.isEmpty {
                    recentDaysCard
                }
            }
            .padding()
        }
    }

    // MARK: - Today

    private var todayCard: some View {
        let goal = max(1, dailyGoalSessions)

        return StatsCard(title: "Today") {
            HStack(spacing: 12) {
                StatTile(value: "\(stats.todaySessions)",
                         label: stats.todaySessions == 1 ? "session" : "sessions",
                         tint: .accentColor)
                StatTile(value: "\(stats.todayMinutes)",
                         label: "minutes",
                         tint: .accentColor)
            }

            VStack(spacing: 6) {
                ProgressView(value: Double(min(stats.todaySessions, goal)), total: Double(goal))
                    .tint(stats.todaySessions >= goal ? .green : .accentColor)
                HStack {
                    Text("Daily goal")
                    Spacer()
                    Text("\(stats.todaySessions) / \(goal)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Streaks

    private var streakCard: some View {
        StatsCard(title: "Streaks") {
            HStack(spacing: 12) {
                StatTile(value: "\(stats.currentStreak)",
                         label: stats.currentStreak == 1 ? "day current" : "days current",
                         tint: .orange)
                StatTile(value: "\(stats.longestStreak)",
                         label: stats.longestStreak == 1 ? "day best" : "days best",
                         tint: .pink)
            }

            if stats.currentStreak == 0 && stats.totalSessions > 0 {
                Text("Finish a focus session today to start a new streak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        StatsCard(title: "All Time") {
            HStack(spacing: 12) {
                StatTile(value: "\(stats.totalSessions)",
                         label: stats.totalSessions == 1 ? "session" : "sessions",
                         tint: .indigo)
                StatTile(value: formattedTotalTime,
                         label: "focused",
                         tint: .indigo)
            }
        }
    }

    private var formattedTotalTime: String {
        let hours = stats.totalMinutes / 60
        let minutes = stats.totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    // MARK: - Recent

    private var recentDaysCard: some View {
        StatsCard(title: "Recent Days") {
            VStack(spacing: 0) {
                ForEach(Array(records.suffix(7).reversed()), id: \.persistentModelID) { record in
                    HStack {
                        Text(record.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.subheadline)
                        Spacer()
                        Text("\(record.focusSessionsCompleted) × · \(record.focusMinutesCompleted) min")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    if record.persistentModelID != records.suffix(7).reversed().last?.persistentModelID {
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct StatsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    PomodoroStatsView(dailyGoalSessions: 8)
        .modelContainer(for: DailyProgress.self, inMemory: true)
}

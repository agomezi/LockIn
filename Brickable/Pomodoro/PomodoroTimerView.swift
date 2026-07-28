//
//  PomodoroTimerView.swift
//  Brickable
//
//  Circular countdown, phase label, and the start/pause/reset/skip controls.
//

import SwiftUI
import SwiftData

struct PomodoroTimerView: View {
    let engine: PomodoroEngine
    let dailyGoalSessions: Int

    @Query(sort: \DailyProgress.date, order: .forward) private var records: [DailyProgress]

    private var todaySessions: Int {
        PomodoroStats.compute(from: records).todaySessions
    }

    private var phaseColor: Color {
        switch engine.phase {
        case .focus: return .accentColor
        case .shortBreak: return .green
        case .longBreak: return .teal
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                phaseHeader
                dial
                controls
                todayFooter
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var phaseHeader: some View {
        VStack(spacing: 6) {
            Text(engine.phase.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(phaseColor)

            Text(engine.phase == .focus
                 ? "Session \(engine.cyclePosition) of \(max(1, engine.settings.longBreakEvery))"
                 : "\(engine.sessionsUntilLongBreak) session\(engine.sessionsUntilLongBreak == 1 ? "" : "s") until a long break")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Dial

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 16)

            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(phaseColor,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: engine.isRunning ? 1 : 0.2), value: engine.progress)

            VStack(spacing: 4) {
                Text(engine.remainingDescription)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))

                Text(engine.isRunning ? "Running" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 260, height: 260)
        .animation(.default, value: engine.phase)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 16) {
            Button {
                engine.toggle()
            } label: {
                Label(engine.isRunning ? "Pause" : "Start",
                      systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(phaseColor)

            HStack(spacing: 12) {
                Button {
                    engine.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

                Button {
                    engine.skip()
                } label: {
                    Label("Skip", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Footer

    private var todayFooter: some View {
        let goal = max(1, dailyGoalSessions)
        let done = todaySessions

        return VStack(spacing: 8) {
            HStack {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(done) / \(goal) sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            ProgressView(value: Double(min(done, goal)), total: Double(goal))
                .tint(done >= goal ? .green : phaseColor)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    PomodoroTimerView(engine: PomodoroEngine(), dailyGoalSessions: 8)
        .modelContainer(for: DailyProgress.self, inMemory: true)
}

//
//  AutoUnlockScheduler.swift
//  Brickable
//
//  Wraps DeviceActivity so the timeout is scheduled and cancelled under one
//  activity name that both the app and the monitor extension recognise.
//

import Foundation
import DeviceActivity

extension DeviceActivityName {
    /// The monitor extension matches on this to know a Brickable timeout fired.
    static let autoUnlock = Self("brickable.autoUnlock")
}

enum AutoUnlockScheduler {
    private static let center = DeviceActivityCenter()

    /// Monitor a one-shot window running from now until `unlockAt`.
    ///
    /// DeviceActivity works in wall-clock `DateComponents` rather than
    /// durations, so the timeout is expressed as an interval whose *end* is the
    /// moment we want the block dropped — `intervalDidEnd` in the monitor
    /// extension is what actually unlocks. A start time of "now" makes the
    /// interval active immediately.
    static func schedule(unlockAt: Date) throws {
        stop()

        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: Date()),
            intervalEnd: calendar.dateComponents(components, from: unlockAt),
            repeats: false
        )

        try center.startMonitoring(.autoUnlock, during: schedule)
    }

    /// Cancel a pending timeout. No-op when nothing is scheduled.
    static func stop() {
        center.stopMonitoring([.autoUnlock])
    }

    static var isScheduled: Bool {
        center.activities.contains(.autoUnlock)
    }
}

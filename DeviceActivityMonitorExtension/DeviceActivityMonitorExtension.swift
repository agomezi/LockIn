//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//
//  The auto-unlock fallback. When the scheduled interval ends, this runs even
//  if the app was never opened, and clears the block through the same
//  LockCoordinator path a card tap uses.
//

import DeviceActivity

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // The shield is applied by the app at tap time; nothing to do here.
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard activity == .autoUnlock else { return }
        LockCoordinator.unlock()
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }
}

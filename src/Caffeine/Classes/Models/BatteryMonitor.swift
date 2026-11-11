//
//  BatteryMonitor.swift
//  Caffeine
//

import Foundation
import IOKit.ps

/// Watches the power source and reports when the Mac is running on a low battery.
/// Used to switch Super Caffeine off before a closed-lid Mac drains its battery.
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    /// Default battery percentage at or below which Super Caffeine is turned off while on battery power
    static let defaultLowBatteryThreshold = 20

    /// User-configured threshold in percent; 0 disables the battery guard
    static var lowBatteryThreshold: Int {
        UserDefaults.standard.object(forKey: PreferenceKeys.superBatteryThreshold) as? Int
            ?? Self.defaultLowBatteryThreshold
    }

    private var runLoopSource: CFRunLoopSource?
    private var onChange: (() -> Void)?

    private init() {}

    // MARK: - Public Methods

    /// Whether the Mac is on battery power with a charge at or below `lowBatteryThreshold`
    var isLowOnBattery: Bool {
        let threshold = Self.lowBatteryThreshold
        guard
            threshold > 0,
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int,
                max > 0 else { continue }

            return current * 100 / max <= threshold
        }
        return false
    }

    /// Calls `handler` on the main run loop whenever the power source or charge changes
    func startMonitoring(_ handler: @escaping () -> Void) {
        self.stopMonitoring()
        self.onChange = handler

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let source = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
                // The source is added to the main run loop
                MainActor.assumeIsolated {
                    monitor.onChange?()
                }
            }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.runLoopSource = source
    }

    func stopMonitoring() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        self.runLoopSource = nil
        self.onChange = nil
    }
}

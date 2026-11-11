//
//  CaffeineViewModel.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import ApplicationServices
import Combine
import SwiftUI

/// Main view model for the Caffeine application
@MainActor
class CaffeineViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isActive = false
    /// Super Caffeine: also keeps the Mac awake with the lid closed (`pmset disablesleep 1`)
    @Published var isSuperActive = false {
        didSet {
            guard self.isSuperActive != oldValue else { return }
            self.updateBatteryMonitoring()
        }
    }
    @Published var timeRemaining: TimeInterval?
    @Published var showPreferences = false

    // MARK: - Private Properties

    private var timeoutTimer: Timer?
    private var displayTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        // Explicitly ensure we start inactive
        self.isActive = false
        self.timeRemaining = nil

        self.setupObservers()

        // Reflect a lid-closed sleep override left over from a previous session (or set manually)
        if LidSleepManager.shared.isSleepDisabled() {
            self.activate(withTimeout: 0)
            self.isSuperActive = true
        } else if UserDefaults.standard.bool(forKey: PreferenceKeys.activateAtLaunch) {
            // Check if we should activate at launch
            self.activate()
        }

        // Show preferences on first launch
        if !UserDefaults.standard.bool(forKey: PreferenceKeys.suppressLaunchMessage) {
            self.showPreferences = true
        }
    }

    // MARK: - Public Methods

    /// Cycles through the states: inactive → active → super active → inactive
    func toggleActive() {
        if !self.isActive {
            self.activate()
        } else if !self.isSuperActive {
            // If the password prompt is cancelled, continue the cycle to inactive
            if !self.activateSuper() {
                self.deactivate()
            }
        } else {
            self.deactivate()
        }
    }

    /// Switches between normal and super mode while staying active
    func toggleSuper() {
        if self.isSuperActive {
            self.deactivateSuper()
        } else {
            if !self.isActive {
                self.activate()
            }
            self.activateSuper()
        }
    }

    /// Enables sleep prevention with the lid closed. Returns `true` on success.
    @discardableResult
    func activateSuper() -> Bool {
        // Don't keep a closed-lid Mac awake on a nearly empty battery
        guard
            !BatteryMonitor.shared.isLowOnBattery,
            LidSleepManager.shared.setSleepDisabled(true) else { return false }
        self.isSuperActive = true
        return true
    }

    /// Restores normal lid-closed sleep. Returns `true` on success.
    @discardableResult
    func deactivateSuper() -> Bool {
        guard self.isSuperActive else { return true }
        guard LidSleepManager.shared.setSleepDisabled(false) else { return false }
        self.isSuperActive = false
        return true
    }

    /// Activates Caffeine with optional timeout
    func activate(withTimeout timeout: TimeInterval? = nil) {
        // Use default duration if no timeout specified
        let duration: TimeInterval?
        if let timeout {
            duration = timeout > 0 ? timeout : nil
        } else {
            let defaultMinutes = UserDefaults.standard.integer(forKey: PreferenceKeys.defaultDuration)
            duration = defaultMinutes > 0 ? TimeInterval(defaultMinutes * 60) : nil
        }

        // Cancel existing timers
        self.cancelTimers()

        // Set up timeout timer if duration specified
        if let duration {
            self.timeRemaining = duration

            self.timeoutTimer = Timer.scheduledTimer(
                withTimeInterval: duration,
                repeats: false
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.deactivate()
                }
            }

            // Update display every second
            self.displayTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    guard
                        let self,
                        let timeoutTimer = self.timeoutTimer else
                    {
                        self?.displayTimer?.invalidate()
                        return
                    }

                    self.timeRemaining = max(0, timeoutTimer.fireDate.timeIntervalSinceNow)
                    if self.timeRemaining ?? 0 <= 0 {
                        self.displayTimer?.invalidate()
                        self.displayTimer = nil
                    }
                }
            }
        } else {
            self.timeRemaining = nil
        }

        self.isActive = true
        SleepPreventionManager.shared.preventSleep()

        if UserDefaults.standard.bool(forKey: PreferenceKeys.keepAppsActive) {
            ActivitySimulator.shared.startMonitoring()
        }
    }

    /// Deactivates Caffeine
    func deactivate() {
        // Stay active if the system flag could not be restored, so the UI matches reality
        guard self.deactivateSuper() else { return }

        self.cancelTimers()
        self.timeRemaining = nil
        self.isActive = false
        SleepPreventionManager.shared.allowSleep()
        ActivitySimulator.shared.stopMonitoring()
    }

    /// Updates activity simulation based on preference
    func updateActivitySimulation(enabled: Bool) {
        if enabled {
            // Trigger the Accessibility permission prompt by posting a no-op event
            // This prompts for "Events" permission which CGEvent.post requires
            ActivitySimulator.shared.requestPermission()
        }

        if enabled, self.isActive {
            ActivitySimulator.shared.startMonitoring()
        } else {
            ActivitySimulator.shared.stopMonitoring()
        }
    }

    /// Returns a formatted string for the remaining time
    func formattedTimeRemaining() -> String? {
        // Only return a status if actually active
        guard self.isActive else {
            return nil
        }

        // If there's time remaining, format it
        if let remaining = timeRemaining, remaining > 0 {
            let seconds = Int(remaining)

            if seconds >= 3600 {
                let hours = seconds / 3600
                let minutes = (seconds % 3600) / 60
                return String(format: "%02d:%02d", hours, minutes)
            } else if seconds > 60 {
                let minutes = seconds / 60
                let format = String(localized: "%d minutes", comment: "Time remaining in minutes")
                return String.localizedStringWithFormat(format, minutes)
            } else {
                let format = String(localized: "%d seconds", comment: "Time remaining in seconds")
                return String.localizedStringWithFormat(format, seconds)
            }
        }

        // Active with no timer (indefinite)
        if self.isSuperActive {
            return String(localized: "Super Caffeine is active (lid can be closed)")
        }
        return String(localized: "Caffeine is active")
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Observe workspace sleep notification
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    if UserDefaults.standard.bool(forKey: PreferenceKeys.deactivateOnManualSleep) {
                        self?.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)

        // Run-loop timers don't advance during sleep, so on wake check whether
        // the activation period elapsed and deactivate if so
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let timeoutTimer = self.timeoutTimer else { return }
                    if timeoutTimer.fireDate.timeIntervalSinceNow <= 0 {
                        self.deactivate()
                    }
                }
            }
            .store(in: &self.cancellables)
    }

    /// Watches the battery only while Super Caffeine is on
    private func updateBatteryMonitoring() {
        guard self.isSuperActive else {
            BatteryMonitor.shared.stopMonitoring()
            return
        }

        BatteryMonitor.shared.startMonitoring { [weak self] in
            self?.turnOffSuperIfBatteryLow()
        }
        self.turnOffSuperIfBatteryLow()
    }

    /// Drops back to normal Caffeine (lid-closed sleep allowed) when the battery runs low
    private func turnOffSuperIfBatteryLow() {
        guard self.isSuperActive, BatteryMonitor.shared.isLowOnBattery else { return }
        self.deactivateSuper()
    }

    private func cancelTimers() {
        self.timeoutTimer?.invalidate()
        self.timeoutTimer = nil
        self.displayTimer?.invalidate()
        self.displayTimer = nil
    }
}

// MARK: - Preference Keys

enum PreferenceKeys {
    static let activateAtLaunch = "CAActivateAtLaunch"
    static let defaultDuration = "CADefaultDuration"
    static let suppressLaunchMessage = "CASuppressLaunchMessage"
    static let deactivateOnManualSleep = "CADeactivateOnManualSleep"
    static let keepAppsActive = "CAKeepAppsActive"
}

//
//  MenuBarController.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import Cocoa
import Combine
import SwiftUI

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var viewModel: CaffeineViewModel
    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?

    override init() {
        self.viewModel = CaffeineViewModel()
        super.init()
        self.setupMenuBar()
        self.setupObservers()

        // Ensure icon reflects the current state after full initialization
        // This is important because ViewModel.init() might activate if "activate at launch" is enabled
        self.updateIcon()
    }

    func cleanup() {
        self.viewModel.deactivate()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func setupMenuBar() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Set up button actions (icon will be set after observers are configured)
        button.action = #selector(self.statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        self.appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            // Appearance changes are delivered on the main thread
            MainActor.assumeIsolated {
                self?.updateIcon()
            }
        }

        button.setAccessibilityLabel("Caffeine")
        button.setAccessibilityIdentifier("MenuBarController.statusItem.button")
    }

    private func setupObservers() {
        self.viewModel.$isActive
            .combineLatest(self.viewModel.$isSuperActive)
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.updateIcon()
                }
            }
            .store(in: &self.cancellables)

        self.viewModel.$superFailure
            .compactMap(\.self)
            .sink { [weak self] failure in
                // Show after the current click/menu action has finished
                DispatchQueue.main.async {
                    self?.showSuperFailureAlert(failure)
                }
            }
            .store(in: &self.cancellables)

        self.viewModel.$showPreferences
            .sink { [weak self] show in
                if show {
                    self?.showPreferencesWindow()
                }
            }
            .store(in: &self.cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        if self.viewModel.isSuperActive {
            button.image = Self.makeSuperActiveImage(for: button.effectiveAppearance)
        } else {
            let imageName = self.viewModel.isActive ? "active" : "inactive"
            if let image = NSImage(named: NSImage.Name(imageName)) {
                button.image = image
            }
        }

        if self.viewModel.isSuperActive {
            button.setAccessibilityValue(NSLocalizedString(
                "Super active, sleep prevented even with the lid closed",
                tableName: "Accessibility",
                comment: "Accessibility value announced when Super Caffeine is preventing lid-closed sleep"
            ))
        } else if self.viewModel.isActive {
            button.setAccessibilityValue(NSLocalizedString(
                "Active, sleep prevented",
                tableName: "Accessibility",
                comment: "Accessibility value announced when Caffeine is preventing sleep"
            ))
        } else {
            button.setAccessibilityValue(NSLocalizedString(
                "Inactive, sleep allowed",
                tableName: "Accessibility",
                comment: "Accessibility value announced when Caffeine is not preventing sleep"
            ))
        }
    }

    /// Full coffee cup with yellow coffee, used for Super Caffeine.
    /// The cup outline uses the label color resolved for `appearance`, while the coffee stays yellow
    /// (a template image would turn it monochrome). A new image is built for every appearance change
    /// so AppKit never reuses a representation drawn for the old appearance.
    private static func makeSuperActiveImage(for appearance: NSAppearance) -> NSImage? {
        var outlineColor = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            outlineColor = NSColor(cgColor: NSColor.labelColor.cgColor) ?? .labelColor
        }

        guard
            let outline = NSImage(named: NSImage.Name("superActiveOutline")),
            let fill = NSImage(named: NSImage.Name("superActiveFill")) else { return nil }

        func tinted(_ mask: NSImage, _ color: NSColor, in rect: NSRect) {
            let layer = NSImage(size: rect.size, flipped: false) { bounds in
                mask.draw(in: bounds)
                color.setFill()
                bounds.fill(using: .sourceAtop)
                return true
            }
            layer.draw(in: rect)
        }

        let image = NSImage(size: outline.size, flipped: false) { bounds in
            tinted(outline, outlineColor, in: bounds)
            tinted(fill, .systemYellow, in: bounds)
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc
    private func statusItemClicked(_: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            self.showContextMenu()
        } else {
            self.viewModel.toggleActive()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Status info (only show if active)
        if self.viewModel.isActive, let timeString = viewModel.formattedTimeRemaining() {
            let infoItem = NSMenuItem(title: timeString, action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            infoItem.setAccessibilityIdentifier("MenuBarController.statusMenuItem")
            menu.addItem(infoItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Duration options in submenu
        let activateForItem = NSMenuItem(
            title: String(localized: "Activate for"),
            action: nil,
            keyEquivalent: ""
        )
        activateForItem.setAccessibilityIdentifier("MenuBarController.activateForMenuItem")
        let submenu = NSMenu()

        var durations: [(String, Int)] = [
            (String(localized: "Indefinitely"), 0),
            (String(localized: "5 minutes"), 5),
            (String(localized: "10 minutes"), 10),
            (String(localized: "15 minutes"), 15),
            (String(localized: "30 minutes"), 30),
            (String(localized: "1 hour"), 60),
            (String(localized: "2 hours"), 120),
            (String(localized: "5 hours"), 300),
        ]

        #if DEBUG
        durations.insert((String(localized: "1 minute"), 1), at: 1)
        #endif

        for (title, minutes) in durations {
            let item = NSMenuItem(
                title: title,
                action: #selector(activateWithDuration(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = minutes
            item.setAccessibilityLabel(String(
                format: NSLocalizedString(
                    "Activate: %@",
                    tableName: "Accessibility",
                    comment: "Accessibility label for a duration menu item, %@ is the duration"
                ),
                title
            ))
            item.setAccessibilityIdentifier("MenuBarController.durationMenuItem.\(minutes)")
            submenu.addItem(item)
        }

        activateForItem.submenu = submenu
        menu.addItem(activateForItem)

        // Super Caffeine (keeps the Mac awake with the lid closed)
        let superItem = NSMenuItem(
            title: String(localized: "Super Caffeine (lid can be closed)"),
            action: #selector(toggleSuper(_:)),
            keyEquivalent: ""
        )
        superItem.target = self
        superItem.state = self.viewModel.isSuperActive ? .on : .off
        superItem.setAccessibilityIdentifier("MenuBarController.superCaffeineMenuItem")
        menu.addItem(superItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: String(localized: "Preferences..."),
            action: #selector(showPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        prefsItem.setAccessibilityIdentifier("MenuBarController.preferencesMenuItem")
        menu.addItem(prefsItem)

        // About
        let aboutItem = NSMenuItem(
            title: String(localized: "About Caffeine"),
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.setAccessibilityIdentifier("MenuBarController.aboutMenuItem")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: String(localized: "Quit"),
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.setAccessibilityIdentifier("MenuBarController.quitMenuItem")
        menu.addItem(quitItem)

        self.statusItem?.menu = menu
        self.statusItem?.button?.performClick(nil)
        self.statusItem?.menu = nil
    }

    @objc
    private func activateWithDuration(_ sender: NSMenuItem) {
        let minutes = sender.tag
        let seconds = minutes > 0 ? TimeInterval(minutes * 60) : 0
        self.viewModel.activate(withTimeout: seconds)
    }

    @objc
    private func toggleSuper(_: NSMenuItem) {
        self.viewModel.toggleSuper()
    }

    private func showSuperFailureAlert(_ failure: SuperCaffeineFailure) {
        self.viewModel.superFailure = nil
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = String(localized: "Super Caffeine is unavailable")

        switch failure {
        case let .lowBattery(threshold):
            alert.informativeText = String(
                format: String(
                    localized: "The battery is at or below %d%%. Connect a power adapter or change the battery level in Preferences."
                ),
                threshold
            )
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()

        case .notAuthorized:
            let command = LidSleepManager.shared.sudoersSetupCommand
            alert.informativeText = String(
                localized: "Caffeine needs permission to run pmset without a password. Run this command once in Terminal, then try again:"
            ) + "\n\n" + command
            alert.addButton(withTitle: String(localized: "Copy Command"))
            alert.addButton(withTitle: String(localized: "OK"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        }
    }

    @objc
    private func showPreferences(_: Any?) {
        self.showPreferencesWindow()
    }

    private func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if self.preferencesWindow == nil {
            let contentView = PreferencesView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = String(localized: "Welcome to Caffeine")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 640, height: 420))
            window.center()

            self.preferencesWindow = window
        }

        self.preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc
    private func showAbout(_: Any?) {
        NSApp.activate(ignoringOtherApps: true)

        let credits =
            String(
                localized: "© 2006 Tomas Franzén\n© 2018 Michael Jones\n© 2022 Dominic Rodemer\n\nSource code:\nhttps://github.caffeine-app.net"
            )

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits),
        ])
    }

    @objc
    private func quit(_: Any?) {
        NSApp.terminate(nil)
    }
}

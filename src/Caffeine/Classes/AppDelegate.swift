//
//  AppDelegate.swift
//  Caffeine
//
//  Created by Dominic Rodemer on 11.11.25.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_: Notification) {
        // Create the menu bar controller
        self.menuBarController = MenuBarController()

        // Hide the dock icon - this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_: Notification) {
        // Clean up
        self.menuBarController?.cleanup()
    }
}

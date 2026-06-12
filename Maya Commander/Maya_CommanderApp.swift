//
//  Maya_CommanderApp.swift
//  Maya Commander
//
//  Created by Altan Duman on 8.06.2026.
//

import SwiftUI

@main
struct Maya_CommanderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No window group – the app runs purely in the menu bar
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hidMonitor: LamzuHIDMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent the app from activating / stealing focus
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()
        hidMonitor = LamzuHIDMonitor()

        hidMonitor?.onBatteryUpdate = { [weak self] level, charging in
            self?.statusBarController?.updateBattery(level: level, charging: charging)
        }
        hidMonitor?.onDeviceConnected = { [weak self] in
            self?.statusBarController?.setConnected(true)
        }
        hidMonitor?.onDeviceDisconnected = { [weak self] in
            self?.statusBarController?.setConnected(false)
        }

        hidMonitor?.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hidMonitor?.stopMonitoring()
    }
}

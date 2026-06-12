//
//  StatusBarController.swift
//  Maya Commander
//
//  Created by Altan Duman on 8.06.2026.
//

import Cocoa

/// Manages the macOS menu-bar (NSStatusItem) that displays mouse icon + battery level.
class StatusBarController {
    // MARK: - Properties

    private let statusItem: NSStatusItem
    private var isConnected = false
    private var isCharging = false
    private var batteryLevel: Int = 0

    // MARK: - Lifecycle

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        statusItem.menu = buildMenu()
        updateDisplay()
    }

    // MARK: - Configuration

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        // Use the SF Symbol for a mouse
        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Mouse")
            button.image?.isTemplate = true // adapts to light/dark menu bar
        } else {
            button.title = "🖱"
        }

        button.target = self
        button.action = #selector(statusItemClicked)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Searching for Mouse...", action: nil, keyEquivalent: "")
        titleItem.tag = MenuTag.deviceStatus.rawValue
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Public API

    /// Called by the HID monitor when a battery value arrives.
    func updateBattery(level: Int, charging: Bool = false) {
        batteryLevel = max(0, min(100, level))
        isCharging = charging
        isConnected = true
        updateDisplay()
    }

    /// Called by the HID monitor when connection state changes.
    func setConnected(_ connected: Bool) {
        isConnected = connected
        batteryLevel = isConnected ? batteryLevel : 0
        updateDisplay()
    }

    // MARK: - UI Updates

    private func updateDisplay() {
        updateStatusItemButton()
        updateMenuTitle()
    }

    private func updateStatusItemButton() {
        guard let button = statusItem.button else { return }

        let batteryText: String
        let icon: String
        if isConnected {
            batteryText = "\(batteryLevel)%"
            icon = isCharging ? "⚡" : ""
        } else {
            batteryText = "--%"
            icon = ""
        }

        // macOS 11+ uses SF Symbols; fall back to emoji on older systems
        if #available(macOS 11.0, *) {
            // Keep the image from init, update the title with charging indicator
            button.title = " \(icon)\(batteryText)"
        } else {
            button.title = "🖱 \(icon)\(batteryText)"
        }
    }

    private func updateMenuTitle() {
        guard let menu = statusItem.menu,
              let item = menu.item(withTag: MenuTag.deviceStatus.rawValue)
        else { return }

        if isConnected {
            let chargingSuffix = isCharging ? " ⚡" : ""
            item.title = "Lamzu Maya Connected (\(batteryLevel)%)\(chargingSuffix)"
        } else {
            item.title = "🔍 Searching for Mouse..."
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        statusItem.button?.performClick(nil)
    }
}

// MARK: - Menu Item Tags

private enum MenuTag: Int {
    case deviceStatus = 100
}

//
//  LamzuHIDMonitor.swift
//  Maya Commander
//
//  Created by Altan Duman on 8.06.2026.
//

import Foundation
import IOKit.hid

/// Manages a read-only IOHIDManager connection to the Lamzu Maya 8K dongle
/// (Vendor ID: 0x373E) and polls battery level via HID feature report commands.
///
/// # Protocol
/// Battery is obtained via **Feature Reports** on the control interface (MI_02):
/// 1. Send a 64-byte Get Battery command (opcode 0x83)
/// 2. Read the response feature report
/// 3. Parse: [0] = Marker (0xA0‑0xAF), [5] = Opcode echo (0x83),
///           [6] = Charging status, [7] = Battery %
class LamzuHIDMonitor {
    // MARK: - Constants

    private let lamzuVendorID: Int = 0x373E
    private let reportLength = 64
    /// How often to poll the battery (seconds).
    private let pollingInterval: TimeInterval = 60.0

    // MARK: - Callbacks

    var onBatteryUpdate: ((_ level: Int, _ charging: Bool) -> Void)?
    var onDeviceConnected: (() -> Void)?
    var onDeviceDisconnected: (() -> Void)?

    // MARK: - Private Properties

    private var manager: IOHIDManager?
    /// All detected Lamzu HID interfaces.
    private var allDevices: [IOHIDDevice] = []
    /// The control interface (MI_02 / vendor-specific) that responds to feature‑report commands.
    private var controlDevice: IOHIDDevice?
    /// Timer for periodic battery polling (runs on a background queue).
    private var pollingTimer: DispatchSourceTimer?
    private let pollingQueue = DispatchQueue(label: "com.maya.battery-polling", qos: .background)

    // MARK: - Public API

    /// Start listening for Lamzu device events and begin battery polling.
    func startMonitoring() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        // Match Lamzu's vendor ID and the vendor-specific usage page (0xFFFF)
        // to avoid matching generic input/pointer interfaces (which triggers macOS's
        // Input Monitoring permission dialog).
        let matchDict: CFDictionary = [
            kIOHIDVendorIDKey as String: lamzuVendorID,
            kIOHIDDeviceUsagePageKey as String: 0xFFFF
        ] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, matchDict)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovalCallback, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("[LamzuHIDMonitor] IOHIDManagerOpen failed: \(openResult)")
            return
        }

        print("[LamzuHIDMonitor] Started – listening for Lamzu devices (VID: 0x\(String(lamzuVendorID, radix: 16)))")

        // Process any already-connected devices.
        checkForAlreadyConnectedDevices()
    }

    /// Tear down the HID manager and stop polling.
    func stopMonitoring() {
        stopPolling()
        guard let manager = manager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = nil
        allDevices.removeAll()
        controlDevice = nil
        print("[LamzuHIDMonitor] Stopped")
    }

    // MARK: - Device Lifecycle

    fileprivate func deviceConnected(_ device: IOHIDDevice) {
        // Avoid duplicates.
        guard !allDevices.contains(where: { $0 === device }) else { return }

        allDevices.append(device)
        print("[LamzuHIDMonitor] Device connected: \(deviceDescription(device))")

        // If we haven't found a control interface yet, try to find one.
        if controlDevice == nil {
            findControlInterface()
        }
    }

    fileprivate func deviceDisconnected(_ device: IOHIDDevice) {
        allDevices.removeAll { $0 === device }

        if controlDevice === device {
            controlDevice = nil
            stopPolling()
            print("[LamzuHIDMonitor] Control interface disconnected")

            // Attempt to find another control interface.
            if !allDevices.isEmpty {
                findControlInterface()
            } else {
                onDeviceDisconnected?()
            }
        }
    }

    // MARK: - Control Interface Detection

    /// Iterates all connected devices and tries to send a feature-report command.
    /// The first device that responds with a valid marker is the control interface.
    /// Falls back to targeting the vendor-specific interface (usagePage: 0xffff) if probing fails.
    private func findControlInterface() {
        // Strategy 1: Probe each device with Get Profile to find the control interface.
        for device in allDevices {
            if verifyControlInterface(device) {
                controlDevice = device
                print("[LamzuHIDMonitor] Control interface found: \(deviceDescription(device))")
                onDeviceConnected?()
                startPolling()
                pollingQueue.async { [weak self] in
                    self?.pollBattery()
                }
                return
            }
        }

        // Strategy 2: Fall back to the vendor-specific interface (usagePage: 0xffff) directly.
        if let vendorDevice = allDevices.first(where: {
            let page = IOHIDDeviceGetProperty($0, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            return page == 0xffff
        }) {
            print("[LamzuHIDMonitor] Falling back to vendor-specific interface (usagePage: 0xffff)")
            controlDevice = vendorDevice
            onDeviceConnected?()
            startPolling()
            pollingQueue.async { [weak self] in
                self?.pollBattery()
            }
            return
        }

        print("[LamzuHIDMonitor] No control interface found yet – will retry when more devices connect")
    }

    /// Probe a device by sending a Get Profile command and checking for a valid response.
    private func verifyControlInterface(_ device: IOHIDDevice) -> Bool {
        // Build a "Get Profile" command.
        // IOKit strips the Report ID byte, so the 64-byte buffer maps directly:
        //   [0-1] = reserved/zero
        //   [2]   = Device ID (0x02 = mouse)
        //   [3]   = Payload length
        //   [4]   = Category (0x00 = general)
        //   [5]   = Opcode (0x85 = Get Profile)
        var cmd = [UInt8](repeating: 0, count: reportLength)
        cmd[2] = 0x02 // Device ID: mouse
        cmd[3] = 0x01 // Payload length
        cmd[4] = 0x00 // Category: general
        cmd[5] = 0x85 // Opcode: Get Profile

        let sendResult = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, cmd, reportLength)
        guard sendResult == kIOReturnSuccess else {
            print("[LamzuHIDMonitor]   -> send failed, result=\(sendResult)")
            return false
        }

        // Give the device time to process.
        usleep(15000) // 15 ms

        var response = [UInt8](repeating: 0, count: reportLength)
        var responseLen = response.count
        let getResult = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &response, &responseLen)
        guard getResult == kIOReturnSuccess else {
            print("[LamzuHIDMonitor]   -> get report failed, result=\(getResult)")
            return false
        }
        guard responseLen > 6 else { return false }

        // Response in IOKit (no Report ID prefix):
        // [0] = Marker (0xA0-0xAF = success)
        // [5] = Opcode echo (0x85)
        // [6] = Profile (1-5)
        let marker = response[0]
        guard (0xA0...0xAF).contains(marker) else { return false }
        guard response[5] == 0x85 else { return false }
        let profile = response[6]
        guard profile > 0 else { return false }
        return true
    }

    // MARK: - Battery Polling

    private func startPolling() {
        guard pollingTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(deadline: .now() + pollingInterval, repeating: pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.pollBattery()
        }
        timer.resume()
        pollingTimer = timer
    }

    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    /// Send the Get Battery command and parse the response.
    private func pollBattery() {
        guard let device = controlDevice else { return }

        // Build Get Battery command.
        var cmd = [UInt8](repeating: 0, count: reportLength)
        cmd[2] = 0x02 // Device ID: mouse
        cmd[3] = 0x02 // Payload length
        cmd[4] = 0x00 // Category: general
        cmd[5] = 0x83 // Opcode: Get Battery

        let sendResult = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, cmd, reportLength)
        guard sendResult == kIOReturnSuccess else {
            print("[LamzuHIDMonitor] pollBattery: send failed (result=\(sendResult))")
            return
        }

        usleep(15000) // 15 ms

        var response = [UInt8](repeating: 0, count: reportLength)
        var responseLen = response.count
        let getResult = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &response, &responseLen)
        guard getResult == kIOReturnSuccess else {
            print("[LamzuHIDMonitor] pollBattery: get report failed (result=\(getResult))")
            return
        }
        guard responseLen > 8 else { return }

        // Parse response (IOKit format, no ReportID prefix):
        // [0] = Marker (0xA0-0xAF)
        // [5] = Opcode echo (0x83)
        // [6] = Charging status (0=not charging, 1=charging)
        // [7] = Battery percentage (0-100)
        let marker = response[0]
        guard (0xA0...0xAF).contains(marker) else { return }
        guard response[5] == 0x83 else { return }

        let battery = Int(response[7])
        let charging = response[6] != 0
        guard (0...100).contains(battery) else { return }

        print("[LamzuHIDMonitor] Battery: \(battery)%\(charging ? " (charging)" : "")")
        DispatchQueue.main.async {
            self.onBatteryUpdate?(battery, charging)
        }
    }

    // MARK: - Helpers

    /// Enumerate any already-connected Lamzu devices after the manager opens.
    private func checkForAlreadyConnectedDevices() {
        guard let manager = manager,
              let devicesSet = IOHIDManagerCopyDevices(manager)
        else { return }

        let nsSet = devicesSet as NSSet
        for case let device as IOHIDDevice in nsSet {
            deviceConnected(device)
        }
    }

    private func deviceDescription(_ device: IOHIDDevice) -> String {
        let vendor  = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let name    = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        // Try to get usage page / usage to distinguish interfaces.
        let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage     = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0

        return "\(name) (VID: 0x\(String(vendor, radix: 16)), PID: 0x\(String(product, radix: 16)), usagePage: 0x\(String(usagePage, radix: 16)), usage: 0x\(String(usage, radix: 16)))"
    }
}

// MARK: - C Callbacks

private let deviceMatchingCallback: IOHIDDeviceCallback = { context, result, _, device in
    guard result == kIOReturnSuccess, let context = context else { return }
    let monitor = Unmanaged<LamzuHIDMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deviceConnected(device)
}

private let deviceRemovalCallback: IOHIDDeviceCallback = { context, result, _, device in
    guard let context = context else { return }
    let monitor = Unmanaged<LamzuHIDMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deviceDisconnected(device)
}

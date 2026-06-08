# Maya Commander

**A lightweight macOS menu-bar battery monitor for the Lamzu Maya X 8K wireless mouse.**

![App Icon](Maya%20Commander/Assets.xcassets/AppIcon.appiconset/icon_512x512.png)

Maya Commander runs as a background agent (no Dock icon) and displays your mouse's battery percentage directly in the macOS menu bar. It communicates with the Lamzu 8K dongle via HID feature reports to read battery status, polling every 60 seconds.

## Features

- **Menu bar display** — Shows mouse icon + battery percentage (e.g. `🐭 85%`)
- **Charging indicator** — Displays a ⚡ icon next to the percentage when the mouse is charging
- **Dropdown menu** — Shows connection status with battery level and a Quit option
- **Background agent** — No Dock icon, no main window, runs quietly in the menu bar
- **Efficient polling** — Queries battery every 60 seconds via HID Feature Reports
- **Apple Silicon native** — Built exclusively for arm64

## Requirements

- **macOS 26.5+** (Apple Sequoia or later)
- **Apple Silicon (M1/M2/M3/M4) Mac**
- **Lamzu Maya X 8K wireless mouse** with its proprietary 8K dongle
- Xcode 26.5+ (to build from source)

## Installation

### Download a Pre-built Release

> *(Coming soon — grab the latest `.app` from the Releases page)*

### Build from Source

1. **Clone or open the project:**
   ```bash
   cd Maya\ Commander
   ```

2. **Build with Xcode:**
   ```bash
   open Maya\ Commander.xcodeproj
   ```
   Then select **Product → Archive** or press `Cmd+B` to build.

3. **Or use the build script:**
   ```bash
   ./scripts/build.sh
   ```
   The built app will be at:
   ```
   build/Maya Commander.app
   ```

4. **Move to Applications:**
   ```bash
   cp -R build/Maya\ Commander.app /Applications/
   ```

## Usage

1. Launch **Maya Commander** from your Applications folder.
2. The app appears in the menu bar as a mouse icon with your battery percentage.
3. Click the menu bar icon to see the dropdown with connection status and a Quit option.
4. The app runs in the background — no windows or Dock icon to manage.

## How It Works

The app uses Apple's **IOHIDManager** framework to communicate with the Lamzu 8K dongle over the HID Feature Report protocol:

1. **Device discovery** — Scans for HID devices with Vendor ID `0x373E` (Lamzu)
2. **Control interface detection** — Finds the vendor-specific interface (MI_02, usagePage: `0xFFFF`) by sending a Get Profile command and validating the response
3. **Battery polling** — Sends a Get Battery command (opcode `0x83`) every 60 seconds and parses:
   - `response[0]` — Success marker (`0xA0-0xAF`)
   - `response[5]` — Opcode echo (`0x83`)
   - `response[6]` — Charging status
   - `response[7]` — Battery percentage (`0-100`)

## Project Structure

```
Maya Commander/
├── Maya Commander/             # Source code
│   ├── Maya_CommanderApp.swift # @main entry point, AppDelegate
│   ├── StatusBarController.swift # NSStatusItem menu-bar management
│   ├── LamzuHIDMonitor.swift   # IOHIDManager-based HID communication
│   ├── ContentView.swift       # Placeholder (unused in menu-bar mode)
│   ├── Assets.xcassets/        # App icon and assets
│   │   └── AppIcon.appiconset/ # Generated icon files at all sizes
│   └── Info.plist              # LSUIElement = YES (agent mode)
├── scripts/
│   └── build.sh                # ARM64-only release build script
├── Entitlements.plist          # Sandbox + USB entitlement
├── Icon-mac.png                # Source icon (1024x1024)
├── README.md                   # This file
└── Maya Commander.xcodeproj/   # Xcode project
```

## Troubleshooting

| Issue | Likely Cause | Solution |
|-------|-------------|----------|
| "No control interface found" | Mouse/dongle not connected | Ensure the dongle is plugged in and the mouse is powered on |
| Battery shows `--%` | Device disconnected | Check dongle connection, try re-pairing the mouse |
| App won't open | Gatekeeper | `xattr -dr com.apple.quarantine /Applications/Maya\ Commander.app` |
| "os/kern) failure (0x5)" | macOS system message | Harmless, can be ignored |

## Technical Details

- **Protocol:** CompX/OTD (used by many gaming mouse brands)
- **HID Framework:** IOKit (`IOHIDManager`)
- **Report Type:** Feature Reports (64 bytes, Report ID `0x00`)
- **Sandbox:** Enabled with `com.apple.security.device.usb` entitlement
- **Architecture:** `arm64` (Apple Silicon only)
- **Minimum macOS:** 26.5

## Credits

- Protocol reference: [lamzuctl](https://github.com/kalomaze/lamzuctl) by kalomaze

## License

MIT

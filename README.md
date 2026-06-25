# booBud ☕

The apps I found for the Bookoo scale were overcomplicated and awkward to use. I wanted something simple. So this is it — a straightforward iOS companion for your **Bookoo Mini Scale**: real-time weight, a brew timer, and tare controls over Bluetooth. Nothing more, nothing less.

## Features

- **BLE connection** to Bookoo Mini Scale (official protocol)
- **Live weight display** — grams or ounces, large readable digits
- **Brew timer** — start/stop/reset with 0.1s precision
- **Tare & Brew button** — one tap to zero the scale and start the timer
- **Stability indicator** — shows when weight settles
- **Battery level** from the scale

## Screenshots

<img src="Screenshot.png" alt="booBud weight display" width="320" />

## Requirements

- iOS 18.0+
- Xcode 16.0+
- A Bookoo Mini Scale (or compatible BLE scale)

## Install on Your iPhone (no App Store, no developer account)

1. Open `booBud.xcodeproj` in Xcode
2. Plug in your iPhone, select it from the device dropdown
3. Sign in with your Apple ID (Xcode → Settings → Accounts)
4. Press **⌘R** to build and install
5. On iPhone: Settings → General → VPN & Device Management → Trust your Apple ID

The app stays installed for 7 days — just rebuild to refresh.

## How It Works

booBud communicates with the Bookoo Mini Scale over Bluetooth Low Energy using the [official open-source protocol](https://github.com/BooKooCode/OpenSource):

- **Service UUID**: `0xFFE0`
- **Weight notifications**: characteristic `0xFF11` (20-byte packets with grams, flow rate, battery, timer)
- **Commands**: characteristic `0xFF12` (tare, timer start/stop/reset)

## Project Structure

```
booBud/
├── App/              # @main app entry
├── BLE/              # BookooProtocol + ScaleBLEController
├── Models/           # WeightReading, WeightUnit, BrewTimerState
├── ViewModels/       # ScaleViewModel (@Observable state)
├── Views/            # ContentView, WeightDisplay, BrewTimer, Controls, DeviceDiscovery
├── Resources/        # Info.plist (BLE permissions)
└── Assets.xcassets/  # App icon, accent color
```

## License

MIT

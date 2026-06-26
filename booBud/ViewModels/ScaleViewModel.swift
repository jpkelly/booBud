import SwiftUI
import Foundation
@preconcurrency import CoreBluetooth
import os

/// Central ViewModel — owns BLE controller, timer, and all UI-bound state.
@MainActor
@Observable
final class ScaleViewModel {

    // MARK: - Published State

    var currentReading: WeightReading?
    var displayUnit: WeightUnit = .grams
    var connectionState: ConnectionState = .disconnected
    var discoveredScales: [DiscoveredScale] = []
    var batteryPercent: Int = 0
    var brewTimer = BrewTimerState()
    var lastError: String?

    /// Weight data points recorded while timer is running: (elapsed seconds, weight in grams).
    var weightHistory: [(elapsed: Double, weight: Double)] = []

    /// Auto-stop timer settings — stored properties synced to UserDefaults.
    var autoStopEnabled: Bool = UserDefaults.standard.bool(forKey: "autoStopEnabled") {
        didSet { UserDefaults.standard.set(autoStopEnabled, forKey: "autoStopEnabled") }
    }
    var autoStopSeconds: Double = {
        let val = UserDefaults.standard.double(forKey: "autoStopSeconds")
        return val > 0 ? val : 30
    }() {
        didSet { UserDefaults.standard.set(autoStopSeconds, forKey: "autoStopSeconds") }
    }

    /// Auto-detect pour start and auto-start brew timer.
    var autoDetectPour: Bool = UserDefaults.standard.bool(forKey: "autoDetectPour") {
        didSet { UserDefaults.standard.set(autoDetectPour, forKey: "autoDetectPour") }
    }

    /// Scale operating mode — persisted to UserDefaults, sent to scale on change.
    var scaleMode: BookooProtocol.ScaleMode = {
        let raw = UserDefaults.standard.integer(forKey: "scaleMode")
        return BookooProtocol.ScaleMode(rawValue: UInt8(raw)) ?? .weight
    }() {
        didSet {
            UserDefaults.standard.set(Int(scaleMode.rawValue), forKey: "scaleMode")
            bleController.sendMode(scaleMode)
        }
    }

    /// Whether the graph should be visible.
    var showGraph: Bool {
        brewTimer.isRunning || weightHistory.count > 1
    }

    // MARK: - Computed

    var displayWeight: String {
        guard let reading = currentReading, reading.grams >= 0 else { return "0.0" }
        return reading.formatted(in: displayUnit)
    }

    var weightUnitSymbol: String {
        displayUnit.symbol
    }

    var isScaleReady: Bool {
        if case .connected = connectionState, currentReading != nil {
            return true
        }
        return false
    }

    var batteryIcon: String {
        switch batteryPercent {
        case 0...10:  return "battery.0"
        case 11...25: return "battery.25"
        case 26...50: return "battery.50"
        case 51...75: return "battery.75"
        default:      return "battery.100"
        }
    }

    // MARK: - Private

    private let bleController = ScaleBLEController()
    private let logger = Logger(subsystem: "com.boobud.viewmodel", category: "ScaleViewModel")
    private var lastAutoStartWeight: Double = 0
    private var connectedScaleName: String?

    /// Display-link style timer to advance the brew timer smoothly.
    private var displayTimer: Timer?

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting(String)    // scale name
        case connected(String)     // scale name
        case failed(String)        // error message
    }

    struct DiscoveredScale: Identifiable, Hashable {
        let id: UUID
        let peripheral: CBPeripheral
        let name: String
        let rssi: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: DiscoveredScale, rhs: DiscoveredScale) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Init

    init() {
        bleController.delegate = self
    }

    // MARK: - Actions

    func startScanning() {
        guard ScaleBLEController.isBluetoothAvailable else {
            connectionState = .connected("Simulator")
            return
        }
        discoveredScales.removeAll()
        connectionState = .scanning
        bleController.startScanning()
    }

    func stopScanning() {
        bleController.stopScanning()
    }

    func connect(to scale: DiscoveredScale) {
        connectedScaleName = scale.name
        connectionState = .connecting(scale.name)
        bleController.connect(to: scale.peripheral)
    }

    func disconnect() {
        connectedScaleName = nil
        bleController.disconnect()
        connectionState = .disconnected
        currentReading = nil
    }

    func tare() {
        bleController.sendTare()
        currentReading = nil
    }

    func tareAndStartTimer() {
        bleController.sendTareAndStartTimer()
        currentReading = nil
        brewTimer.reset()
        brewTimer.startOrResume()
        startDisplayTimer()
    }

    func toggleTimer() {
        if brewTimer.isRunning {
            brewTimer.stop()
            stopDisplayTimer()
            bleController.sendStopTimer()
        } else {
            brewTimer.startOrResume()
            startDisplayTimer()
            bleController.sendStartTimer()
        }
    }

    func resetTimer() {
        brewTimer.reset()
        weightHistory.removeAll()
        stopDisplayTimer()
        bleController.sendResetTimer()
    }

    func toggleUnit() {
        displayUnit = displayUnit == .grams ? .ounces : .grams
    }

    // MARK: - Display Timer

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.brewTimer.tick()
                // Sample current weight for graph
                if let reading = self.currentReading {
                    self.weightHistory.append((elapsed: self.brewTimer.elapsed, weight: reading.grams))
                } else {
                    self.weightHistory.append((elapsed: self.brewTimer.elapsed, weight: 0))
                }
                // Auto-stop check
                if self.autoStopEnabled && self.brewTimer.elapsed >= self.autoStopSeconds {
                    self.brewTimer.stop()
                    self.stopDisplayTimer()
                    self.bleController.sendStopTimer()
                }
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
}

// MARK: - ScaleBLEControllerDelegate

extension ScaleViewModel: ScaleBLEControllerDelegate {

    nonisolated func scaleController(
        _ controller: ScaleBLEController,
        didReceiveReading reading: BookooProtocol.WeightData
    ) {
        Task { @MainActor in
            let newReading = WeightReading(
                grams: reading.weightGrams,
                isStable: reading.isStable
            )
            self.currentReading = newReading

            // Auto-start timer when a pour is detected (if enabled)
            if self.autoDetectPour,
               !self.brewTimer.isRunning,
               !reading.isStable,
               newReading.grams > 0.5,
               self.lastAutoStartWeight < 0.5 {
                self.brewTimer.reset()
                self.brewTimer.startOrResume()
                self.startDisplayTimer()
            }
            self.lastAutoStartWeight = newReading.grams
        }
    }

    nonisolated func scaleController(
        _ controller: ScaleBLEController,
        didChangeConnectionState connected: Bool
    ) {
        Task { @MainActor in
            if connected {
                let name = self.connectedScaleName ?? self.bleController.connectedPeripheral?.name ?? "Scale"
                self.connectionState = .connected(name)
            } else {
                self.connectionState = .disconnected
                self.currentReading = nil
                self.brewTimer.reset()
            }
        }
    }

    nonisolated func scaleController(
        _ controller: ScaleBLEController,
        didDiscoverScale peripheral: CBPeripheral,
        localName: String,
        rssi: NSNumber
    ) {
        Task { @MainActor in
            let scale = DiscoveredScale(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: localName,
                rssi: rssi.intValue
            )
            // Upsert — avoid duplicates
            self.discoveredScales.removeAll { $0.id == scale.id }
            self.discoveredScales.append(scale)
            self.discoveredScales.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated func scaleController(
        _ controller: ScaleBLEController,
        didUpdateBattery percent: Int
    ) {
        Task { @MainActor in
            self.batteryPercent = percent
        }
    }
}

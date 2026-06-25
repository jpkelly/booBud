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
    private let logger = Logger(subsystem: "com.beanbud.viewmodel", category: "ScaleViewModel")

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

        var signalBars: String {
            if rssi > -50 { return "📶📶📶" }
            if rssi > -65 { return "📶📶" }
            return "📶"
        }

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
        discoveredScales.removeAll()
        connectionState = .scanning
        bleController.startScanning()
    }

    func stopScanning() {
        bleController.stopScanning()
    }

    func connect(to scale: DiscoveredScale) {
        connectionState = .connecting(scale.name)
        bleController.connect(to: scale.peripheral)
    }

    func disconnect() {
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
        stopDisplayTimer()
        bleController.sendResetTimer()
    }

    func toggleUnit() {
        displayUnit = displayUnit == .grams ? .ounces : .grams
    }

    // MARK: - Display Timer

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.brewTimer.tick()
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
            self.currentReading = WeightReading(
                grams: reading.weightGrams,
                isStable: reading.isStable
            )
        }
    }

    nonisolated func scaleController(
        _ controller: ScaleBLEController,
        didChangeConnectionState connected: Bool
    ) {
        Task { @MainActor in
            if connected {
                let name = self.bleController.connectedPeripheral?.name ?? "Scale"
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
        rssi: NSNumber
    ) {
        Task { @MainActor in
            let scale = DiscoveredScale(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: peripheral.name ?? "Bookoo Scale",
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

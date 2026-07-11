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

    /// Flow rate data points recorded while timer is running: (elapsed seconds, flow rate in g/s).
    var flowRateHistory: [(elapsed: Double, flowRate: Double)] = []

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

    /// Saved brew selected as an underlay reference on the live graph.
    /// When non-nil, the graph renders the saved brew's weight & flow lines
    /// as dimmed dashed ghost lines behind the live data. Persisted to UserDefaults.
    var underlayBrew: SavedBrew? {
        didSet {
            if let id = underlayBrew?.id {
                UserDefaults.standard.set(id.uuidString, forKey: "underlayBrewID")
            } else {
                UserDefaults.standard.removeObject(forKey: "underlayBrewID")
            }
        }
    }

    /// Restore the persisted underlay brew from the BrewStore after app launch.
    func restoreUnderlay(from store: BrewStore) {
        guard let idString = UserDefaults.standard.string(forKey: "underlayBrewID"),
              let id = UUID(uuidString: idString) else { return }
        underlayBrew = store.brews.first { $0.id == id }
    }

    /// Whether the underlay reference chip is hidden (× dismissed).
    /// Ghost lines still render — only the banner is hidden. Persisted to UserDefaults.
    var hideUnderlayChip: Bool = UserDefaults.standard.bool(forKey: "hideUnderlayChip") {
        didSet { UserDefaults.standard.set(hideUnderlayChip, forKey: "hideUnderlayChip") }
    }

    /// Weight threshold in grams that triggers auto-start when crossed.
    var pourTriggerGrams: Double = {
        let val = UserDefaults.standard.double(forKey: "pourTriggerGrams")
        return val > 0 ? val : 0.5
    }() {
        didSet { UserDefaults.standard.set(pourTriggerGrams, forKey: "pourTriggerGrams") }
    }

    /// Whether the flow rate Y-axis should auto-scale. When off, uses `flowMax` as the fixed maximum.
    /// On by default — persisted to UserDefaults.
    var flowAutoRange: Bool = {
        if UserDefaults.standard.object(forKey: "flowAutoRange") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "flowAutoRange")
    }() {
        didSet { UserDefaults.standard.set(flowAutoRange, forKey: "flowAutoRange") }
    }

    /// Fixed maximum for the flow rate Y-axis when `flowAutoRange` is off.
    var flowMax: Double = {
        let val = UserDefaults.standard.double(forKey: "flowMax")
        return val > 0 ? val : 5.0
    }() {
        didSet { UserDefaults.standard.set(flowMax, forKey: "flowMax") }
    }

    /// Last-used bean dose weight (grams), retained across brews. Persisted to UserDefaults.
    var lastBeanWeight: Double = {
        let val = UserDefaults.standard.double(forKey: "lastBeanWeight")
        return val > 0 ? val : 18.0
    }() {
        didSet { UserDefaults.standard.set(lastBeanWeight, forKey: "lastBeanWeight") }
    }

    /// Last-used grinder setting, retained across brews. Persisted to UserDefaults.
    var lastGrindSetting: Double = {
        let val = UserDefaults.standard.double(forKey: "lastGrindSetting")
        return val > 0 ? val : 2.0
    }() {
        didSet { UserDefaults.standard.set(lastGrindSetting, forKey: "lastGrindSetting") }
    }

    /// Step increment for the grind setting stepper. Persisted to UserDefaults.
    var grindStep: Double = {
        let val = UserDefaults.standard.double(forKey: "grindStep")
        return val > 0 ? val : 0.05
    }() {
        didSet { UserDefaults.standard.set(grindStep, forKey: "grindStep") }
    }

    /// Flow-stop detection — persisted toggle.
    var flowStopDetectionEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "flowStopDetectionEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "flowStopDetectionEnabled")
    }() {
        didSet { UserDefaults.standard.set(flowStopDetectionEnabled, forKey: "flowStopDetectionEnabled") }
    }

    /// Flow rate below which flow is considered "stopped" (g/s).
    var flowStopThreshold: Double = {
        let val = UserDefaults.standard.double(forKey: "flowStopThreshold")
        return val > 0 ? val : 0.3
    }() {
        didSet { UserDefaults.standard.set(flowStopThreshold, forKey: "flowStopThreshold") }
    }

    /// Brew-elapsed time when flow was confirmed stopped; nil until detection fires.
    var flowStoppedAt: Double?

    /// Whether the flow-stop status chip has been dismissed by the user.
    var hideFlowStopChip: Bool = false

    /// Internal: brew-elapsed time when flow first dropped below threshold (debounce start).
    private var flowBelowThresholdSince: Double?
    /// Internal: whether flow has peaked above 0.5 g/s this session (pour has actually started).
    private var flowHasBeenActive: Bool = false

    /// Scale operating mode — persisted to UserDefaults for reference.
    var scaleMode: BookooProtocol.ScaleMode = {
        let raw = UserDefaults.standard.integer(forKey: "scaleMode")
        return BookooProtocol.ScaleMode(rawValue: UInt8(raw)) ?? .weight
    }() {
        didSet { UserDefaults.standard.set(Int(scaleMode.rawValue), forKey: "scaleMode") }
    }

    /// Whether the graph should be visible.
    var showGraph: Bool {
        brewTimer.isRunning || weightHistory.count > 1
    }

    /// Whether there is enough recorded data to save a brew.
    var canSaveBrew: Bool {
        weightHistory.count > 1
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

    /// Whether a scale is remembered (stored UUID) but not currently connected.
    var hasRememberedScale: Bool {
        if case .connected = connectionState { return false }
        return UserDefaults.standard.string(forKey: "lastPeripheralUUID") != nil
    }

    /// The name of the remembered scale, if any.
    var rememberedScaleName: String {
        UserDefaults.standard.string(forKey: "lastPeripheralName") ?? "Unknown Scale"
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

        if let uuidString = UserDefaults.standard.string(forKey: "lastPeripheralUUID"),
           let uuid = UUID(uuidString: uuidString) {
            connectedScaleName = UserDefaults.standard.string(forKey: "lastPeripheralName")
            connectionState = .connecting(connectedScaleName ?? "Scale")
            bleController.reconnectToLastDevice(uuid: uuid)
            return
        }

        connectionState = .scanning
        bleController.startScanning()
    }

    func stopScanning() {
        bleController.stopScanning()
    }

    func connect(to scale: DiscoveredScale) {
        connectedScaleName = scale.name
        connectionState = .connecting(scale.name)
        UserDefaults.standard.set(scale.peripheral.identifier.uuidString, forKey: "lastPeripheralUUID")
        UserDefaults.standard.set(scale.name, forKey: "lastPeripheralName")
        bleController.connect(to: scale.peripheral)
    }

    func disconnect() {
        connectedScaleName = nil
        bleController.disconnect()
        connectionState = .disconnected
        currentReading = nil
    }

    /// Clear the stored peripheral so the next scan discovers fresh devices
    /// instead of trying to reconnect to a previous scale.
    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: "lastPeripheralUUID")
        UserDefaults.standard.removeObject(forKey: "lastPeripheralName")
        // Ensure the view updates even if we weren't connected
        if case .connected = connectionState {
            // disconnect() already handles state transition
        } else {
            connectionState = .disconnected
        }
        logger.info("Forgotten stored device — next scan will be a fresh discovery")
    }

    func tare() {
        bleController.sendTare()
        currentReading = nil
    }

    func tareAndStartTimer() {
        bleController.sendTareAndStartTimer()
        currentReading = nil
        brewTimer.reset()
        flowStoppedAt = nil
        flowBelowThresholdSince = nil
        flowHasBeenActive = false
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

    /// Clear the local live-session state (history, timer, flow-stop tracking)
    /// without sending a reset command to the scale. Used after saving a brew
    /// so the live buffers don't linger in a stale, unrecoverable state.
    func clearSession() {
        brewTimer.reset()
        weightHistory.removeAll()
        flowRateHistory.removeAll()
        flowStoppedAt = nil
        hideFlowStopChip = false
        flowBelowThresholdSince = nil
        flowHasBeenActive = false
        stopDisplayTimer()
    }

    func resetTimer() {
        clearSession()
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
                // Sample current weight and flow rate for graph
                if let reading = self.currentReading {
                    self.weightHistory.append((elapsed: self.brewTimer.elapsed, weight: reading.grams))
                    self.flowRateHistory.append((elapsed: self.brewTimer.elapsed, flowRate: reading.flowRate))
                } else {
                    self.weightHistory.append((elapsed: self.brewTimer.elapsed, weight: 0))
                    self.flowRateHistory.append((elapsed: self.brewTimer.elapsed, flowRate: 0))
                }
                // Auto-stop check
                if self.autoStopEnabled && self.brewTimer.elapsed >= self.autoStopSeconds {
                    self.brewTimer.stop()
                    self.stopDisplayTimer()
                    self.bleController.sendStopTimer()
                }

                // Flow-stop detection (only fire once per brew, after weight > 5g and flow has been active)
                if self.flowStopDetectionEnabled && self.flowStoppedAt == nil {
                    let maxWeight = self.weightHistory.map(\.weight).max() ?? 0
                    if maxWeight > 5.0 {
                        let currentFlow = self.currentReading?.flowRate ?? 0
                        // Gate: require flow has peaked above 0.5 g/s (pour has actually started)
                        if currentFlow > 0.5 { self.flowHasBeenActive = true }
                        if self.flowHasBeenActive {
                            if currentFlow < self.flowStopThreshold {
                                if let since = self.flowBelowThresholdSince {
                                    if self.brewTimer.elapsed - since >= 1.0 {
                                        self.flowStoppedAt = since
                                    }
                                } else {
                                    self.flowBelowThresholdSince = self.brewTimer.elapsed
                                }
                            } else {
                                self.flowBelowThresholdSince = nil
                            }
                        }
                    }
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
                flowRate: reading.flowRate,
                isStable: reading.isStable
            )
            self.currentReading = newReading

            // Auto-start timer when weight crosses threshold (if enabled)
            let threshold = self.pourTriggerGrams
            if self.autoDetectPour,
               !self.brewTimer.isRunning,
               newReading.grams >= threshold,
               self.lastAutoStartWeight < threshold {
                self.brewTimer.reset()
                self.flowStoppedAt = nil
                self.flowBelowThresholdSince = nil
                self.flowHasBeenActive = false
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
                // If we were trying to reconnect (connecting state) and it failed,
                // clear the stale UUID and fall back to scanning.
                if case .connecting = self.connectionState {
                    logger.info("Reconnect failed — clearing stored UUID and scanning for new devices")
                    UserDefaults.standard.removeObject(forKey: "lastPeripheralUUID")
                    UserDefaults.standard.removeObject(forKey: "lastPeripheralName")
                    self.connectedScaleName = nil
                    self.connectionState = .scanning
                    self.bleController.startScanning()
                    return
                }
                self.connectionState = .disconnected
                self.currentReading = nil
                self.batteryPercent = 0
                self.brewTimer.reset()
                self.flowStoppedAt = nil
                self.flowBelowThresholdSince = nil
                self.flowHasBeenActive = false
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

    nonisolated func scaleController(
        _ controller: ScaleBLEController,
        didReceiveScaleName name: String
    ) {
        Task { @MainActor in
            self.connectedScaleName = name
            // Update connection state header if already connected
            if case .connected = self.connectionState {
                self.connectionState = .connected(name)
            }
            // Also update connecting state if still in that phase
            if case .connecting = self.connectionState {
                self.connectionState = .connecting(name)
            }
            // Persist the name for auto-reconnect
            UserDefaults.standard.set(name, forKey: "lastPeripheralName")
        }
    }
}

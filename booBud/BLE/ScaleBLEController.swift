@preconcurrency import CoreBluetooth
import Foundation
import os

/// Delegate protocol for receiving scale events from the BLE controller.
protocol ScaleBLEControllerDelegate: AnyObject {
    func scaleController(_ controller: ScaleBLEController, didReceiveReading reading: BookooProtocol.WeightData)
    func scaleController(_ controller: ScaleBLEController, didChangeConnectionState connected: Bool)
    func scaleController(_ controller: ScaleBLEController, didDiscoverScale peripheral: CBPeripheral, localName: String, rssi: NSNumber)
    func scaleController(_ controller: ScaleBLEController, didUpdateBattery percent: Int)
    func scaleController(_ controller: ScaleBLEController, didReceiveScaleName name: String)
}

/// Manages all BLE communication with the Bookoo Mini Scale.
final class ScaleBLEController: NSObject, @unchecked Sendable {

    // MARK: - Public Properties

    weak var delegate: ScaleBLEControllerDelegate?

    private(set) var isConnected = false
    private(set) var isScanning = false
    private(set) var connectedPeripheral: CBPeripheral?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var commandCharacteristic: CBCharacteristic?
    private let logger = Logger(subsystem: "com.boobud.ble", category: "ScaleBLEController")

    /// Minimum RSSI threshold to filter out distant devices.
    private let rssiThreshold: NSNumber = -80

    /// Whether scanning was requested before Bluetooth was ready.
    private var pendingScan = false

    /// Per-identifier cached display name, so we never downgrade to peripheral.name
    /// after a good LocalName is received from a scan-response packet.
    private var discoveredNames: [UUID: String] = [:]

    /// Last connected peripheral UUID — used for auto-reconnect on disconnect.
    private var lastConnectedUUID: UUID?

    /// Strong reference to a peripheral during connection attempt.
    /// Prevents the "Did you forget to keep a reference?" API misuse warning.
    private var connectingPeripheral: CBPeripheral?

    /// Prevent reconnect storms — only auto-reconnect once per unexpected disconnect.
    private var autoReconnectAttempted = false

    /// Distinguish user-initiated disconnect from unexpected drops.
    private var userInitiatedDisconnect = false

    // MARK: - Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    /// Whether Bluetooth LE is available on this device (always false on simulator).
    static var isBluetoothAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    // MARK: - Public API

    /// Start scanning for Bookoo scales. Defers until Bluetooth is powered on if needed.
    func startScanning() {
        guard ScaleBLEController.isBluetoothAvailable else {
            logger.info("Simulator detected — BLE not available, skipping scan")
            return
        }
        guard centralManager.state == .poweredOn else {
            logger.info("Bluetooth not ready (state: \(String(describing: self.centralManager.state))), will scan when powered on")
            pendingScan = true
            return
        }
        guard !isScanning else { return }

        isScanning = true
        pendingScan = false
        autoReconnectAttempted = false  // fresh scan resets reconnect gate
        logger.info("Scanning for Bookoo scales…")

        // Allow duplicates so scan-response packets (carrying the local name)
        // are delivered even when the primary ADV already matched withServices.
        discoveredNames.removeAll()
        centralManager.scanForPeripherals(
            withServices: [BookooProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    /// Stop scanning.
    func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        discoveredNames.removeAll()
        centralManager.stopScan()
        logger.info("Stopped scanning")
    }

    /// Connect to a discovered peripheral.
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        logger.info("Connecting to \(peripheral.name ?? "unknown")")
        centralManager.connect(peripheral, options: nil)
    }

    /// Reconnect to a known peripheral by UUID without scanning.
    func reconnectToLastDevice(uuid: UUID) {
        guard ScaleBLEController.isBluetoothAvailable else { return }
        guard centralManager.state == .poweredOn else {
            pendingReconnectUUID = uuid
            return
        }

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else {
            startScanning()
            return
        }
        logger.info("Auto-reconnecting to \(peripheral.name ?? "unknown")")
        connectingPeripheral = peripheral  // keep alive until didConnect/didFailToConnect
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    private var pendingReconnectUUID: UUID?

    /// Disconnect from the current peripheral.
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        userInitiatedDisconnect = true
        logger.info("Disconnecting from \(peripheral.name ?? "unknown")")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    // MARK: - Commands

    /// Send a command packet to the connected scale.
    private func sendCommand(_ data: Data) {
        guard let peripheral = connectedPeripheral,
              let characteristic = commandCharacteristic else {
            logger.warning("Cannot send command — not connected or characteristic not discovered")
            return
        }

        logger.debug("Sending command: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func sendTare() {
        sendCommand(BookooProtocol.tareCommand())
    }

    func sendTareAndStartTimer() {
        sendCommand(BookooProtocol.tareAndStartTimerCommand())
    }

    func sendStartTimer() {
        sendCommand(BookooProtocol.startTimerCommand())
    }

    func sendStopTimer() {
        sendCommand(BookooProtocol.stopTimerCommand())
    }

    func sendResetTimer() {
        sendCommand(BookooProtocol.resetTimerCommand())
    }

    func sendMode(_ mode: BookooProtocol.ScaleMode) {
        sendCommand(BookooProtocol.switchModeCommand(mode))
    }
}

// MARK: - CBCentralManagerDelegate

extension ScaleBLEController: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("Bluetooth state: \(String(describing: central.state.rawValue))")
        switch central.state {
        case .poweredOn:
            // Auto-start scanning if it was requested before Bluetooth was ready
            if pendingScan {
                logger.info("Bluetooth now powered on — starting deferred scan")
                startScanning()
            }
            if let uuid = pendingReconnectUUID {
                pendingReconnectUUID = nil
                reconnectToLastDevice(uuid: uuid)
            }
            // Auto-reconnect if we were previously connected
            if let peripheral = connectedPeripheral {
                connectingPeripheral = peripheral
                central.connect(peripheral, options: nil)
            }
        case .poweredOff, .resetting:
            isConnected = false
            isScanning = false
            delegate?.scaleController(self, didChangeConnectionState: false)
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rawPeripheralName = peripheral.name ?? ""
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""

        // Accumulate best name per peripheral:
        // — prefer a non-empty LocalName from ad data (scan-response)
        // — never downgrade from a known good name to peripheral.name (macOS hostname)
        let id = peripheral.identifier
        let freshName = localName.isEmpty ? nil : localName
        let cachedName = discoveredNames[id]
        let bestName: String
        if let fresh = freshName {
            bestName = fresh
            discoveredNames[id] = fresh
        } else if let cached = cachedName {
            bestName = cached
        } else {
            // First sighting with no localName — use peripheral.name as fallback
            bestName = rawPeripheralName
            discoveredNames[id] = rawPeripheralName
        }

        // Only show devices whose name starts with "BOOKOO"
        let matchesPrefix = bestName.hasPrefix(BookooProtocol.advertisedNamePrefix)
        guard matchesPrefix else { return }
        guard RSSI.compare(rssiThreshold) == .orderedDescending else { return }

        delegate?.scaleController(self, didDiscoverScale: peripheral, localName: bestName, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to \(peripheral.name ?? "unknown")")
        isConnected = true
        connectedPeripheral = peripheral
        connectingPeripheral = nil
        lastConnectedUUID = peripheral.identifier
        autoReconnectAttempted = false
        peripheral.delegate = self
        peripheral.discoverServices([BookooProtocol.serviceUUID])
        delegate?.scaleController(self, didChangeConnectionState: true)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        isConnected = false
        connectedPeripheral = nil
        connectingPeripheral = nil
        delegate?.scaleController(self, didChangeConnectionState: false)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let wasUserInitiated = userInitiatedDisconnect
        userInitiatedDisconnect = false

        logger.info("Disconnected: \(error?.localizedDescription ?? "clean disconnect")")
        isConnected = false
        commandCharacteristic = nil
        connectedPeripheral = nil
        delegate?.scaleController(self, didChangeConnectionState: false)

        // Auto-reconnect only for unexpected disconnects (sim powered off, out of range, etc.)
        if !wasUserInitiated, !autoReconnectAttempted, let uuid = lastConnectedUUID {
            autoReconnectAttempted = true
            logger.info("🔄 Auto-reconnect attempt for \(uuid.uuidString.prefix(8))…")
            // Brief delay to let the peripheral stabilize before reconnecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.reconnectToLastDevice(uuid: uuid)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ScaleBLEController: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logger.error("Service discovery failed: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            logger.warning("No services found")
            return
        }

        for service in services where service.uuid == BookooProtocol.serviceUUID {
            logger.info("Found Bookoo service, discovering characteristics…")
            peripheral.discoverCharacteristics(
                [BookooProtocol.weightCharUUID, BookooProtocol.commandCharUUID, BookooProtocol.nameCharUUID],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logger.error("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case BookooProtocol.weightCharUUID:
                logger.info("Found weight characteristic — subscribing to notifications")
                peripheral.setNotifyValue(true, for: characteristic)

            case BookooProtocol.commandCharUUID:
                logger.info("Found command characteristic")
                commandCharacteristic = characteristic

            case BookooProtocol.nameCharUUID:
                logger.info("Found name characteristic — reading authoritative name")
                peripheral.readValue(for: characteristic)

            default:
                logger.debug("Unknown characteristic: \(characteristic.uuid.uuidString)")
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            logger.error("Value update failed: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BookooProtocol.weightCharUUID:
            if let weightData = BookooProtocol.WeightData(data: data) {
                delegate?.scaleController(self, didReceiveReading: weightData)
                delegate?.scaleController(self, didUpdateBattery: weightData.batteryPercent)
            } else {
                logger.warning("Failed to parse weight data packet: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }

        case BookooProtocol.nameCharUUID:
            if let name = String(data: data, encoding: .utf8), !name.isEmpty {
                logger.info("📛 Authoritative scale name: '\(name)'")
                delegate?.scaleController(self, didReceiveScaleName: name)
            }

        default:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            logger.error("Write failed: \(error.localizedDescription)")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            logger.error("Notification state update failed: \(error.localizedDescription)")
        } else {
            logger.info("Notifications \(characteristic.isNotifying ? "enabled" : "disabled") for \(characteristic.uuid.uuidString)")
        }
    }

    /// Called when the peripheral's services are modified (e.g., sim calls removeAllServices).
    /// If our Bookoo service disappears, treat it as a disconnect — much faster than
    /// waiting for the BLE supervision timeout (~20s).
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        let bookooInvalidated = invalidatedServices.contains { $0.uuid == BookooProtocol.serviceUUID }
        logger.info("Services modified — Bookoo invalidated: \(bookooInvalidated)")
        if bookooInvalidated {
            // Force-disconnect; didDisconnectPeripheral will handle cleanup + auto-reconnect
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}

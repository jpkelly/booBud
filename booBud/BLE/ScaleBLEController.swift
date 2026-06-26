@preconcurrency import CoreBluetooth
import Foundation
import os

/// Delegate protocol for receiving scale events from the BLE controller.
protocol ScaleBLEControllerDelegate: AnyObject {
    func scaleController(_ controller: ScaleBLEController, didReceiveReading reading: BookooProtocol.WeightData)
    func scaleController(_ controller: ScaleBLEController, didChangeConnectionState connected: Bool)
    func scaleController(_ controller: ScaleBLEController, didDiscoverScale peripheral: CBPeripheral, localName: String, rssi: NSNumber)
    func scaleController(_ controller: ScaleBLEController, didUpdateBattery percent: Int)
}

/// Manages all BLE communication with the Bookoo Mini Scale.
final class ScaleBLEController: NSObject {

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
        logger.info("Scanning for Bookoo scales…")

        centralManager.scanForPeripherals(
            withServices: [BookooProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Stop scanning.
    func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        centralManager.stopScan()
        logger.info("Stopped scanning")
    }

    /// Connect to a discovered peripheral.
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        logger.info("Connecting to \(peripheral.name ?? "unknown")")
        centralManager.connect(peripheral, options: nil)
    }

    /// Try to reconnect to a previously saved peripheral by UUID.
    func reconnectToLastDevice(uuid: UUID) {
        guard ScaleBLEController.isBluetoothAvailable,
              centralManager.state == .poweredOn else {
            // Defer until Bluetooth is ready
            pendingReconnectUUID = uuid
            return
        }

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = peripherals.first {
            logger.info("Reconnecting to last device: \(peripheral.name ?? "unknown")")
            centralManager.connect(peripheral, options: nil)
        } else {
            logger.info("Last device not in cache, falling back to scan")
            pendingReconnectUUID = nil
            startScanning()
        }
    }

    private var pendingReconnectUUID: UUID?

    /// Disconnect from the current peripheral.
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
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
            // Try pending reconnect
            if let uuid = pendingReconnectUUID {
                pendingReconnectUUID = nil
                reconnectToLastDevice(uuid: uuid)
            }
            // Auto-reconnect if we were previously connected
            if connectedPeripheral != nil {
                central.connect(connectedPeripheral!, options: nil)
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
        let name = peripheral.name ?? ""
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let displayName = localName.isEmpty ? name : localName

        // Only show devices whose name starts with "BOOKOO"
        let matchesPrefix = displayName.hasPrefix(BookooProtocol.advertisedNamePrefix)
        guard matchesPrefix else { return }
        guard RSSI.compare(rssiThreshold) == .orderedDescending else { return }

        logger.info("🔍 \(displayName) RSSI=\(RSSI)")
        delegate?.scaleController(self, didDiscoverScale: peripheral, localName: displayName, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to \(peripheral.name ?? "unknown")")
        isConnected = true
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([BookooProtocol.serviceUUID])
        delegate?.scaleController(self, didChangeConnectionState: true)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        isConnected = false
        connectedPeripheral = nil
        delegate?.scaleController(self, didChangeConnectionState: false)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("Disconnected: \(error?.localizedDescription ?? "clean disconnect")")
        isConnected = false
        commandCharacteristic = nil
        connectedPeripheral = nil
        delegate?.scaleController(self, didChangeConnectionState: false)
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
                [BookooProtocol.weightCharUUID, BookooProtocol.commandCharUUID],
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

        guard characteristic.uuid == BookooProtocol.weightCharUUID,
              let data = characteristic.value else { return }

        if let weightData = BookooProtocol.WeightData(data: data) {
            delegate?.scaleController(self, didReceiveReading: weightData)
            delegate?.scaleController(self, didUpdateBattery: weightData.batteryPercent)
        } else {
            logger.warning("Failed to parse weight data packet: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
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
}

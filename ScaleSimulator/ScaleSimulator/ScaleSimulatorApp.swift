import SwiftUI
import CoreBluetooth
import os

// MARK: - App Entry

@main
struct ScaleSimulatorApp: App {
    @State private var model = SimulatorModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - BLE Identifiers (mirrors booBud's BookooProtocol)

enum BookooBLE {
    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "FFE0")
    nonisolated(unsafe) static let commandCharUUID = CBUUID(string: "FF12")
    nonisolated(unsafe) static let weightCharUUID = CBUUID(string: "FF11")
    static let fullServiceUUID = "0000FFE0-0000-1000-8000-00805F9B34FB"
    static let advertisedName = "BOOKOO Mini Sim"

    // Packet constants
    static let productNumber: UInt8 = 0x03
    static let commandType: UInt8 = 0x0A
    static let weightDataType: UInt8 = 0x0B

    // Command IDs
    enum Command: UInt8, CustomStringConvertible {
        case tare = 0x01
        case beep = 0x02
        case autoOff = 0x03
        case startTimer = 0x04
        case stopTimer = 0x05
        case resetTimer = 0x06
        case tareAndStartTimer = 0x07
        case flowSmoothing = 0x08
        case calibration = 0x09
        case switchMode = 0x0A
        case stopCondition = 0x0B

        var description: String {
            switch self {
            case .tare:              return "Tare"
            case .beep:              return "Beep"
            case .autoOff:           return "Auto-Off"
            case .startTimer:        return "Start Timer"
            case .stopTimer:         return "Stop Timer"
            case .resetTimer:        return "Reset Timer"
            case .tareAndStartTimer: return "Tare + Start Timer"
            case .flowSmoothing:     return "Flow Smoothing"
            case .calibration:       return "Calibration"
            case .switchMode:        return "Switch Mode"
            case .stopCondition:     return "Stop Condition"
            }
        }
    }

    enum ScaleMode: UInt8, CaseIterable, CustomStringConvertible {
        case weight = 0x00
        case timing = 0x01
        case ratio = 0x02
        case automatic = 0x03

        var description: String {
            switch self {
            case .weight:    return "Weight"
            case .timing:    return "Timer"
            case .ratio:     return "Ratio"
            case .automatic: return "Auto"
            }
        }
    }

    /// Build a 20-byte weight data packet matching BookooProtocol.WeightData format.
    static func buildWeightPacket(
        milliseconds: UInt32,
        weightGrams: Double,
        flowRate: Double,
        batteryPercent: UInt8,
        unit: UInt8 = 0x01
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)

        // Byte 0: Product number
        bytes[0] = productNumber
        // Byte 1: Data type
        bytes[1] = weightDataType

        // Bytes 2-4: Elapsed milliseconds (3-byte big-endian)
        bytes[2] = UInt8((milliseconds >> 16) & 0xFF)
        bytes[3] = UInt8((milliseconds >> 8) & 0xFF)
        bytes[4] = UInt8(milliseconds & 0xFF)

        // Byte 5: Unit (0x01 = grams)
        bytes[5] = unit

        // Byte 6: Weight sign (0x00 = positive, 0x01 = negative)
        let weightSign: UInt8 = weightGrams < 0 ? 0x01 : 0x00
        bytes[6] = weightSign

        // Bytes 7-9: Weight × 100 (3-byte big-endian)
        let absWeight = UInt32(abs(weightGrams) * 100).clamped(to: 0...0xFFFFFF)
        bytes[7] = UInt8((absWeight >> 16) & 0xFF)
        bytes[8] = UInt8((absWeight >> 8) & 0xFF)
        bytes[9] = UInt8(absWeight & 0xFF)

        // Byte 10: Flow rate sign
        let flowSign: UInt8 = flowRate < 0 ? 0x01 : 0x00
        bytes[10] = flowSign

        // Bytes 11-12: Flow rate × 100 (2-byte big-endian)
        let absFlow = UInt16(abs(flowRate) * 100).clamped(to: 0...0xFFFF)
        bytes[11] = UInt8((absFlow >> 8) & 0xFF)
        bytes[12] = UInt8(absFlow & 0xFF)

        // Byte 13: Battery percentage
        bytes[13] = batteryPercent

        // Bytes 14-18: Reserved (0x00)

        // Byte 19: XOR checksum of bytes 0-18
        bytes[19] = bytes[0..<19].reduce(0, ^)

        return Data(bytes)
    }

    /// Parse a 6-byte command packet and return the command + data bytes.
    static func parseCommand(_ data: Data) -> (command: Command, data1: UInt8, data2: UInt8)? {
        guard data.count >= 6 else { return nil }
        guard data[0] == productNumber else { return nil }
        guard data[1] == commandType else { return nil }

        let checksum = data[0..<5].reduce(0, ^)
        guard data[5] == checksum else { return nil }

        guard let cmd = Command(rawValue: data[2]) else { return nil }
        return (cmd, data[3], data[4])
    }
}

extension UInt32 {
    func clamped(to range: ClosedRange<UInt32>) -> UInt32 {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension UInt16 {
    func clamped(to range: ClosedRange<UInt16>) -> UInt16 {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Simulator Model

@Observable
final class SimulatorModel: NSObject, @unchecked Sendable {
    // State
    var isAdvertising = false
    var isConnected = false
    var connectedCentral: String?
    var peripheralManager: CBPeripheralManager!

    // Simulated scale state
    var weightGrams: Double = 0.0 {
        didSet {
            if weightGrams != oldValue {
                if !isPouring {
                    flowRate = 0.6  // signal measuring on iPhone
                    scheduleStableReset()
                }
                sendWeightNotification()
            }
        }
    }

    private var stableResetWorkItem: DispatchWorkItem?

    private func scheduleStableReset() {
        stableResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.flowRate = 0
            }
        }
        stableResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    var flowRate: Double = 0.0 {
        didSet { if flowRate != oldValue { sendWeightNotification() } }
    }
    var batteryPercent: Double = 85
    var unit: WeightUnit = .grams
    var mode: BookooBLE.ScaleMode = .weight
    var timerRunning = false
    var timerElapsed: TimeInterval = 0

    // Pour simulation
    var isPouring = false
    private var pourTimer: Timer?
    private var pourStartTime: Date = Date()
    private var pourStartWeight: Double = 0
    private let pourTarget: Double = 40
    private let pourDuration: TimeInterval = 30
    private var pourCurve: PourCurve = .linear

    enum PourCurve: String, CaseIterable {
        case linear
        case easeIn    // slow start, fast finish
        case easeOut   // fast start, slow finish

        func progress(_ t: Double) -> Double {
            switch self {
            case .linear:  return t
            case .easeIn:  return t * t * t
            case .easeOut: return 1.0 - pow(1.0 - t, 3)
            }
        }

        var label: String {
            switch self {
            case .linear:  return "Linear"
            case .easeIn:  return "Slow → Fast"
            case .easeOut: return "Fast → Slow"
            }
        }
    }

    func startPour(curve: PourCurve) {
        stopPour()
        pourCurve = curve
        weightGrams = 0     // tare
        flowRate = 0.6      // signal measuring
        pourStartWeight = 0
        pourStartTime = Date()
        isPouring = true
        timerRunning = true
        timerElapsed = 0
        timerStartDate = Date()
        startDisplayTimer()
        log("☕ Pour started: \(curve.label)")
        pourTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pourTick()
            }
        }
    }

    func stopPour() {
        pourTimer?.invalidate()
        pourTimer = nil
        isPouring = false
        timerRunning = false
        stopDisplayTimer()
    }

    private func pourTick() {
        let elapsed = Date().timeIntervalSince(pourStartTime)
        let t = min(elapsed / pourDuration, 1.0)
        let amount = pourCurve.progress(t) * pourTarget

        // Set flow first — ensure minimum 0.6 so iPhone shows orange dot during pour
        let rawFlow = t < 1.0 ? (pourTarget / pourDuration) * (pourCurve.progress(t + 0.05) - pourCurve.progress(t)) / 0.05 : 0
        flowRate = t < 1.0 ? max(rawFlow, 0.6) : 0
        weightGrams = pourStartWeight + amount

        if t >= 1.0 {
            stopPour()
            flowRate = 0
            log("☕ Pour complete: \(String(format: "%.0f", weightGrams))g")
        }
    }

    // UI controls
    var logMessages: [LogEntry] = []
    var notificationInterval: Double = 0.05  // 50ms

    // Presets
    var presetWeights: [Preset] = [
        Preset(name: "Empty", weight: 0),
        Preset(name: "250g", weight: 250),
        Preset(name: "500g", weight: 500),
        Preset(name: "1kg", weight: 1000),
    ]

    // Services & characteristics
    private var service: CBMutableService!
    private var weightCharacteristic: CBMutableCharacteristic!
    private var commandCharacteristic: CBMutableCharacteristic!

    // Timer
    private var dataTimer: Timer?
    private var displayTimer: Timer?
    private var timerStartDate: Date?
    private var failCount = 0
    // Logger
    private let logger = Logger(subsystem: "com.boobud.simulator", category: "Simulator")

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    // MARK: - BLE Setup

    private func setupService() {
        let fullServiceUUID = CBUUID(string: BookooBLE.fullServiceUUID)

        // Weight data characteristic (notify)
        weightCharacteristic = CBMutableCharacteristic(
            type: BookooBLE.weightCharUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )

        // Command characteristic (write without response)
        commandCharacteristic = CBMutableCharacteristic(
            type: BookooBLE.commandCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        service = CBMutableService(type: fullServiceUUID, primary: true)
        service.characteristics = [weightCharacteristic, commandCharacteristic]

        peripheralManager.add(service)
        log("Service registered: \(BookooBLE.fullServiceUUID)")
    }

    func toggleAdvertising() {
        if isAdvertising {
            stopAdvertising()
        } else {
            startAdvertising()
        }
    }

    private func startAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            log("⚠️ Bluetooth not powered on — state: \(peripheralManager.state.rawValue)")
            return
        }

        setupService()

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: BookooBLE.advertisedName,
            CBAdvertisementDataServiceUUIDsKey: [BookooBLE.serviceUUID],
        ])

        isAdvertising = true
        log("📡 Started advertising as \"\(BookooBLE.advertisedName)\"")
    }

    private func stopAdvertising() {
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        isAdvertising = false
        isConnected = false
        connectedCentral = nil
        stopDataTimer()
        stopPour()
        log("🛑 Stopped advertising")
    }

    // MARK: - Data Sending

    func startDataTimer() {
        stopDataTimer()
        dataTimer = Timer.scheduledTimer(withTimeInterval: notificationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendWeightNotification()
            }
        }
    }

    func stopDataTimer() {
        dataTimer?.invalidate()
        dataTimer = nil
    }

    private func sendWeightNotification() {
        guard isConnected, connectedCentral != nil else { return }

        let ms = UInt32(timerElapsed * 1000)
        let packet = BookooBLE.buildWeightPacket(
            milliseconds: ms,
            weightGrams: weightGrams,
            flowRate: flowRate,
            batteryPercent: UInt8(batteryPercent),
            unit: unit == .grams ? 0x01 : 0x02
        )

        if !peripheralManager.updateValue(packet, for: weightCharacteristic, onSubscribedCentrals: nil) {
            failCount += 1
            if failCount <= 5 { NSLog("[BLE] queue full (fail #\(failCount))") }
        }
    }

    // MARK: - Command Handling

    private func handleCommand(_ cmd: BookooBLE.Command, data1: UInt8, data2: UInt8) {
        switch cmd {
        case .tare:
            weightGrams = 0
            log("⬅️ Tare → weight = 0")

        case .beep:
            log("⬅️ Beep")

        case .autoOff:
            log("⬅️ Auto-Off (data: \(data1), \(data2))")

        case .startTimer:
            timerRunning = true
            timerStartDate = Date()
            startDisplayTimer()
            log("⬅️ Start Timer")

        case .stopTimer:
            timerRunning = false
            stopDisplayTimer()
            log("⬅️ Stop Timer @ \(String(format: "%.1f", timerElapsed))s")

        case .resetTimer:
            timerRunning = false
            timerElapsed = 0
            timerStartDate = nil
            stopDisplayTimer()
            log("⬅️ Reset Timer")

        case .tareAndStartTimer:
            weightGrams = 0
            flowRate = 0
            timerRunning = true
            timerElapsed = 0
            timerStartDate = Date()
            startDisplayTimer()
            log("⬅️ Tare + Start Timer")

        case .flowSmoothing:
            log("⬅️ Flow Smoothing (data: \(data1), \(data2))")

        case .calibration:
            log("⬅️ Calibration (data: \(data1), \(data2))")

        case .switchMode:
            if let newMode = BookooBLE.ScaleMode(rawValue: data1) {
                mode = newMode
                log("⬅️ Switch Mode → \(newMode.description)")
            } else {
                log("⬅️ Switch Mode → unknown 0x\(String(data1, radix: 16))")
            }

        case .stopCondition:
            log("⬅️ Stop Condition (data: \(data1), \(data2))")
        }
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.timerStartDate else { return }
                self.timerElapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Logging

    func log(_ message: String) {
        let entry = LogEntry(timestamp: Date(), message: message)
        logMessages.append(entry)
        // Keep last 100 entries
        if logMessages.count > 100 {
            logMessages.removeFirst(logMessages.count - 100)
        }
        logger.info("\(message)")
    }

    func clearLog() {
        logMessages.removeAll()
    }
}

// MARK: - CBPeripheralManagerDelegate

extension SimulatorModel: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let stateStr: String = {
            switch peripheral.state {
            case .unknown:      return "Unknown"
            case .resetting:    return "Resetting"
            case .unsupported:  return "Unsupported"
            case .unauthorized: return "Unauthorized (check System Settings → Privacy → Bluetooth)"
            case .poweredOff:   return "Powered Off"
            case .poweredOn:    return "Powered On ✓"
            @unknown default:   return "Unknown state"
            }
        }()
        log("Bluetooth: \(stateStr)")
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            log("⚠️ Failed to add service: \(error.localizedDescription)")
        } else {
            log("✅ Service added: \(service.uuid)")
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            log("⚠️ Advertising failed: \(error.localizedDescription)")
            isAdvertising = false
        } else {
            log("✅ Advertising started successfully")
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            guard request.characteristic.uuid == BookooBLE.commandCharUUID,
                  let data = request.value else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }

            if let (cmd, d1, d2) = BookooBLE.parseCommand(data) {
                handleCommand(cmd, data1: d1, data2: d2)
                peripheral.respond(to: request, withResult: .success)
            } else {
                log("⚠️ Invalid command packet: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            }
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        if characteristic.uuid == BookooBLE.weightCharUUID {
            isConnected = true
            connectedCentral = central.identifier.uuidString
            startDataTimer()
            log("🔗 Connected: \(central.identifier.uuidString.prefix(8))… (subscribed to weight)")
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        if characteristic.uuid == BookooBLE.weightCharUUID {
            isConnected = false
            connectedCentral = nil
            stopDataTimer()
            log("🔌 Disconnected: \(central.identifier.uuidString.prefix(8))…")
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {}
}

// MARK: - Types

enum WeightUnit: String, CaseIterable {
    case grams
    case ounces

    var symbol: String {
        switch self {
        case .grams:  return "g"
        case .ounces: return "oz"
        }
    }

    var rawByte: UInt8 {
        switch self {
        case .grams:  return 0x01
        case .ounces: return 0x02
        }
    }
}

struct Preset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let weight: Double
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

// MARK: - Content View

struct ContentView: View {
    @Bindable var model: SimulatorModel

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left panel: Controls
                controlPanel
                    .frame(width: geometry.size.width * 0.55)
                    .padding()

                Divider()

                // Right panel: Log
                logPanel
                    .frame(width: geometry.size.width * 0.45)
            }
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection

            actionsSection

            weightSection

            // Pour simulation buttons
            VStack(alignment: .leading, spacing: 6) {
                Label("Simulate Pour", systemImage: "water.waves")
                    .font(.subheadline)

                HStack(spacing: 6) {
                    ForEach(SimulatorModel.PourCurve.allCases, id: \.rawValue) { curve in
                        Button {
                            model.startPour(curve: curve)
                        } label: {
                            Text(curve.label)
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.isPouring)
                    }
                }

                if model.isPouring {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Pouring… \(String(format: "%.0f", model.weightGrams))g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") {
                            model.stopPour()
                            model.flowRate = 0
                            model.log("☕ Pour cancelled")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection

                    Divider()

                    modeSection
                }
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "scalemass.fill")
                    .font(.title)
                Text("BOOKOO Scale Simulator")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            HStack(spacing: 12) {
                statusBadge
                if model.isConnected {
                    Label("Connected", systemImage: "link")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(model.isAdvertising ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(model.isAdvertising ? "Advertising" : "Stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(model.isAdvertising ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
        )
    }

    // MARK: Weight Section

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Weight", systemImage: "scalemass")
                .font(.headline)

            HStack {
                Slider(value: $model.weightGrams, in: -10...50)
                    .controlSize(.small)


                TextField("Weight", value: $model.weightGrams, format: .number.precision(.fractionLength(1)))
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())

                Text(model.unit.symbol)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Battery
                VStack(alignment: .leading, spacing: 4) {
                    Label("Battery", systemImage: batteryIcon)
                        .font(.subheadline)

                    Slider(value: $model.batteryPercent, in: 0...100, step: 1)
                        .controlSize(.small)
                        .frame(width: 100)

                    Text("\(Int(model.batteryPercent))%")
                        .font(.caption)
                        .monospacedDigit()
                }

                Spacer()

                // Timer
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Timer", systemImage: "timer")
                        .font(.subheadline)

                    Text(formatTime(model.timerElapsed))
                        .font(.title2)
                        .monospacedDigit()
                        .foregroundStyle(model.timerRunning ? .orange : .secondary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.timerRunning ? Color.orange : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(model.timerRunning ? "Running" : "Stopped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Notification interval
            HStack(spacing: 8) {
                Text("BLE update rate:")
                    .font(.caption)
                Picker("", selection: $model.notificationInterval) {
                    Text("50ms").tag(0.05)
                    Text("100ms").tag(0.1)
                    Text("200ms").tag(0.2)
                    Text("500ms").tag(0.5)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .onChange(of: model.notificationInterval) {
                    if model.isConnected {
                        model.stopDataTimer()
                    }
                }
            }
        }
    }

    private var batteryIcon: String {
        switch model.batteryPercent {
        case 0...10:  return "battery.0"
        case 11...25: return "battery.25"
        case 26...50: return "battery.50"
        case 51...75: return "battery.75"
        default:      return "battery.100"
        }
    }

    // MARK: Mode Section

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mode", systemImage: "square.grid.3x3")
                .font(.headline)

            Picker("Mode", selection: $model.mode) {
                ForEach(BookooBLE.ScaleMode.allCases, id: \.rawValue) { mode in
                    Text(mode.description).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Actions

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button {
                model.toggleAdvertising()
            } label: {
                Label(
                    model.isAdvertising ? "Stop Advertising" : "Start Advertising",
                    systemImage: model.isAdvertising ? "stop.circle.fill" : "play.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.isAdvertising ? .red : .green)

            Button {
                model.weightGrams = 0
                model.log("🎯 Manual Tare")
            } label: {
                Label("Tare", systemImage: "arrow.down.to.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Log Panel

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Command Log", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    model.clearLog()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                List(model.logMessages) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Text(entry.message)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .id(entry.id)
                }
                .listStyle(.plain)
                .onChange(of: model.logMessages.count) {
                    if let last = model.logMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Helpers

    private func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((interval - Double(totalSeconds)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, tenths)
    }
}

import Foundation
@preconcurrency import CoreBluetooth

/// Complete Bookoo Mini Scale BLE protocol implementation.
/// Based on official protocol docs: https://github.com/BooKooCode/OpenSource
enum BookooProtocol {

    // MARK: - BLE Identifiers

    /// 128-bit Service UUID: 0000FFE0-0000-1000-8000-00805F9B34FB
    static let serviceUUID = CBUUID(string: "FFE0")

    /// Command characteristic — write commands to the scale
    static let commandCharUUID = CBUUID(string: "FF12")

    /// Weight data characteristic — receives weight/time/battery notifications
    static let weightCharUUID = CBUUID(string: "FF11")

    /// Device Name characteristic — read to get authoritative display name
    static let nameCharUUID = CBUUID(string: "FF1E")

    /// Scale advertises with this local name prefix
    static let advertisedNamePrefix = "BOOKOO"

    // MARK: - Packet Structure

    static let productNumber: UInt8 = 0x03
    static let commandType: UInt8 = 0x0A
    static let weightDataType: UInt8 = 0x0B

    // MARK: - Command IDs

    enum Command: UInt8 {
        case tare             = 0x01
        case beep             = 0x02
        case autoOff          = 0x03
        case startTimer       = 0x04
        case stopTimer        = 0x05
        case resetTimer       = 0x06
        case tareAndStartTimer = 0x07
        case flowSmoothing    = 0x08
        case calibration      = 0x09
        case switchMode       = 0x0A
        case stopCondition    = 0x0B
    }

    // MARK: - Scale Modes

    /// Operating modes of the Bookoo scale (Ultra series).
    /// Inferred from protocol notes — command 0x0A is the mode switch.
    enum ScaleMode: UInt8, CaseIterable {
        case weight    = 0x00  /// Basic weighing
        case timing    = 0x01  /// Brew timer
        case ratio     = 0x02  /// Brew ratio
        case automatic = 0x03  /// Auto-stop detection

        var label: String {
            switch self {
            case .weight:    return "Weight"
            case .timing:    return "Timer"
            case .ratio:     return "Ratio"
            case .automatic: return "Auto"
            }
        }
    }

    // MARK: - Checksum

    /// XOR all bytes to produce the checksum byte.
    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(0, ^)
    }

    /// Verify the last byte of a packet is the correct XOR checksum of all preceding bytes.
    static func verifyChecksum(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let payload = data.prefix(data.count - 1)
        let expected = data.last!
        return checksum(Array(payload)) == expected
    }

    // MARK: - Command Encoding

    /// Build a 6-byte command packet.
    /// Format: [ProductNumber, CommandType, CommandID, Data1, Data2, Checksum]
    static func buildCommand(_ cmd: Command, data1: UInt8 = 0x00, data2: UInt8 = 0x00) -> Data {
        var bytes: [UInt8] = [
            productNumber,
            commandType,
            cmd.rawValue,
            data1,
            data2,
        ]
        bytes.append(checksum(bytes))
        return Data(bytes)
    }

    /// Convenience: Tare (zero the scale).
    static func tareCommand() -> Data {
        buildCommand(.tare)
    }

    /// Convenience: Tare + start timer (recommended for brewing).
    static func tareAndStartTimerCommand() -> Data {
        buildCommand(.tareAndStartTimer)
    }

    /// Convenience: Start the brew timer.
    static func startTimerCommand() -> Data {
        buildCommand(.startTimer)
    }

    /// Convenience: Stop the brew timer.
    static func stopTimerCommand() -> Data {
        buildCommand(.stopTimer)
    }

    /// Convenience: Reset the brew timer to zero.
    static func resetTimerCommand() -> Data {
        buildCommand(.resetTimer)
    }

    /// Convenience: Switch the scale's operating mode.
    static func switchModeCommand(_ mode: ScaleMode) -> Data {
        buildCommand(.switchMode, data1: mode.rawValue)
    }

    // MARK: - Weight Data Decoding

    /// Parsed weight data packet from the scale.
    struct WeightData {
        /// Elapsed time in seconds (milliseconds from scale / 1000).
        let elapsedSeconds: Double
        /// Weight in grams.
        let weightGrams: Double
        /// Flow rate in grams per second.
        let flowRate: Double
        /// Battery percentage (0–100).
        let batteryPercent: Int
        /// Whether the scale is currently stable / not in motion.
        let isStable: Bool
        /// Raw packet for debugging.
        let rawData: Data

        init?(data: Data) {
            guard data.count == 20 else { return nil }
            guard data[0] == BookooProtocol.productNumber else { return nil }
            guard data[1] == BookooProtocol.weightDataType else { return nil }
            guard BookooProtocol.verifyChecksum(data) else { return nil }

            // Bytes 2-4: Milliseconds (3-byte unsigned integer)
            let ms: UInt32 = (UInt32(data[2]) << 16) | (UInt32(data[3]) << 8) | UInt32(data[4])
            elapsedSeconds = Double(ms) / 1000.0

            // Byte 5: Unit (0x01 = grams; we only support grams per protocol doc)
            // Byte 6: Weight sign (0x00 = positive, 0x01 = negative)
            let weightSign: Double = (data[6] == 0x01) ? -1.0 : 1.0

            // Bytes 7-9: Grams weight × 100 (3-byte unsigned integer)
            let rawWeight: UInt32 = (UInt32(data[7]) << 16) | (UInt32(data[8]) << 8) | UInt32(data[9])
            weightGrams = weightSign * Double(rawWeight) / 100.0

            // Byte 10: Flow rate sign
            let flowSign: Double = (data[10] == 0x01) ? -1.0 : 1.0

            // Bytes 11-12: Flow rate × 100 (2-byte unsigned integer)
            let rawFlow: UInt16 = (UInt16(data[11]) << 8) | UInt16(data[12])
            flowRate = flowSign * Double(rawFlow) / 100.0

            // Byte 13: Battery percentage
            batteryPercent = Int(data[13])

            // The scale sends weight continuously — considering it "stable" if
            // flow rate is very low and weight is non-negative above a threshold.
            isStable = abs(flowRate) < 0.5 && weightGrams > -0.01

            rawData = data
        }
    }
}

import Foundation

/// Minimal protobuf wire-format reader for Antigravity's local conversation
/// databases. Only the fields aimeter needs are read; unknown fields are kept
/// as raw values so schema additions never break parsing.
struct ProtobufMessage {
    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case bytes(Data)
    }

    private(set) var fields: [(number: Int, value: Value)] = []

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            guard let key = Self.readVarint(bytes, &index) else { return nil }
            let number = Int(key >> 3)
            guard number > 0 else { return nil }
            switch key & 7 {
            case 0:
                guard let value = Self.readVarint(bytes, &index) else { return nil }
                fields.append((number, .varint(value)))
            case 1:
                guard index + 8 <= bytes.count else { return nil }
                var value: UInt64 = 0
                for shift in 0..<8 { value |= UInt64(bytes[index + shift]) << (8 * UInt64(shift)) }
                index += 8
                fields.append((number, .fixed64(value)))
            case 2:
                guard let length = Self.readVarint(bytes, &index),
                      length <= UInt64(bytes.count - index) else { return nil }
                let end = index + Int(length)
                fields.append((number, .bytes(Data(bytes[index..<end]))))
                index = end
            case 5:
                guard index + 4 <= bytes.count else { return nil }
                var value: UInt32 = 0
                for shift in 0..<4 { value |= UInt32(bytes[index + shift]) << (8 * UInt32(shift)) }
                index += 4
                fields.append((number, .fixed32(value)))
            default:
                return nil
            }
        }
    }

    func varint(_ number: Int) -> UInt64? {
        for field in fields where field.number == number {
            if case .varint(let value) = field.value { return value }
        }
        return nil
    }

    func int(_ number: Int) -> Int {
        varint(number).map { Int(clamping: $0) } ?? 0
    }

    func bytes(_ number: Int) -> Data? {
        allBytes(number).first
    }

    func allBytes(_ number: Int) -> [Data] {
        fields.compactMap { field in
            guard field.number == number, case .bytes(let data) = field.value else { return nil }
            return data
        }
    }

    func message(_ number: Int) -> ProtobufMessage? {
        bytes(number).flatMap(ProtobufMessage.init)
    }

    func allMessages(_ number: Int) -> [ProtobufMessage] {
        allBytes(number).compactMap(ProtobufMessage.init)
    }

    func string(_ number: Int) -> String? {
        bytes(number).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Repeated scalar fields may be packed (one length-delimited blob) or
    /// unpacked (one varint per element); accept both encodings.
    func packedVarints(_ number: Int) -> [UInt64] {
        var values: [UInt64] = []
        for field in fields where field.number == number {
            switch field.value {
            case .varint(let value):
                values.append(value)
            case .bytes(let data):
                let bytes = [UInt8](data)
                var index = 0
                while index < bytes.count, let value = Self.readVarint(bytes, &index) {
                    values.append(value)
                }
            default:
                continue
            }
        }
        return values
    }

    /// google.protobuf.Timestamp { int64 seconds = 1; int32 nanos = 2; }
    func timestamp(_ number: Int) -> Date? {
        guard let message = message(number), let seconds = message.varint(1), seconds > 0 else {
            return nil
        }
        let nanos = Double(message.varint(2) ?? 0) / 1_000_000_000
        return Date(timeIntervalSince1970: Double(seconds) + nanos)
    }

    private static func readVarint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte < 0x80 { return value }
            shift += 7
        }
        return nil
    }
}

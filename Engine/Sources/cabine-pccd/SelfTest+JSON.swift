import Foundation
import CabinePCCKit

/// A JSON document as the self-test reads it for itself, with none of the kit and none of Foundation's
/// JSON in it. A number is the `Double` its own digits spell, so that two documents can be compared to
/// the last bit of every number: it is how the test knows that a line's source leaves the PCC as it came.
enum Parsed {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Parsed])
    case object([String: Parsed])

    /// Reads a whole document; nil if it is not JSON.
    init?(_ data: Data) {
        var reader = Reader(bytes: [UInt8](data))
        guard let value = reader.value(), reader.atEnd() else { return nil }
        self = value
    }

    init?(_ text: String) { self.init(Data(text.utf8)) }

    subscript(key: String) -> Parsed? {
        if case let .object(fields) = self { fields[key] } else { nil }
    }

    /// How many numbers there are in it.
    var numberCount: Int {
        switch self {
        case .number: 1
        case let .array(items): items.reduce(0) { $0 + $1.numberCount }
        case let .object(fields): fields.values.reduce(0) { $0 + $1.numberCount }
        default: 0
        }
    }

    /// True when both are the same document: the same keys, the same strings, and numbers that are the
    /// same `Double` bit for bit.
    func same(as other: Parsed) -> Bool {
        switch (self, other) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.number(a), .number(b)): return a.bitPattern == b.bitPattern
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)):
            guard a.count == b.count else { return false }
            for index in a.indices where !a[index].same(as: b[index]) { return false }
            return true
        case let (.object(a), .object(b)):
            guard a.count == b.count else { return false }
            for (key, value) in a {
                guard let match = b[key], value.same(as: match) else { return false }
            }
            return true
        default: return false
        }
    }

    /// True when a value the kit read is this document, numbers bit for bit.
    func matches(_ value: CabineWire.JSONValue) -> Bool {
        switch (self, value) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.number(a), .number(b)): return a.bitPattern == b.bitPattern
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)):
            guard a.count == b.count else { return false }
            for index in a.indices where !a[index].matches(b[index]) { return false }
            return true
        case let (.object(a), .object(b)):
            guard a.count == b.count else { return false }
            for (key, item) in a {
                guard let match = b[key], item.matches(match) else { return false }
            }
            return true
        default: return false
        }
    }

    /// True when every field of this object is in `other` with the same value, and so on down: `other`
    /// may have fields this one has not.
    func isWithin(_ other: Parsed) -> Bool {
        switch (self, other) {
        case let (.object(a), .object(b)):
            for (key, value) in a {
                guard let match = b[key], value.isWithin(match) else { return false }
            }
            return true
        case let (.array(a), .array(b)):
            guard a.count == b.count else { return false }
            for index in a.indices where !a[index].isWithin(b[index]) { return false }
            return true
        default: return same(as: other)
        }
    }

    /// The bytes of a document, read from the first to the last.
    private struct Reader {
        let bytes: [UInt8]
        var at = 0

        mutating func atEnd() -> Bool {
            skipSpace()
            return at == bytes.count
        }

        private mutating func skipSpace() {
            while at < bytes.count, bytes[at] == 0x20 || bytes[at] == 0x0A || bytes[at] == 0x0D || bytes[at] == 0x09 { at += 1 }
        }

        private mutating func take(_ byte: UInt8) -> Bool {
            skipSpace()
            guard at < bytes.count, bytes[at] == byte else { return false }
            at += 1
            return true
        }

        mutating func value() -> Parsed? {
            skipSpace()
            guard at < bytes.count else { return nil }
            switch bytes[at] {
            case UInt8(ascii: "{"): return object()
            case UInt8(ascii: "["): return array()
            case UInt8(ascii: "\""): return string().map(Parsed.string)
            case UInt8(ascii: "t"): return word("true", .bool(true))
            case UInt8(ascii: "f"): return word("false", .bool(false))
            case UInt8(ascii: "n"): return word("null", .null)
            default: return number()
            }
        }

        private mutating func word(_ word: String, _ value: Parsed) -> Parsed? {
            let letters = Array(word.utf8)
            guard at + letters.count <= bytes.count, Array(bytes[at..<(at + letters.count)]) == letters else { return nil }
            at += letters.count
            return value
        }

        private mutating func number() -> Parsed? {
            let start = at
            while at < bytes.count, "+-.eE0123456789".utf8.contains(bytes[at]) { at += 1 }
            guard at > start, let number = Double(String(decoding: bytes[start..<at], as: UTF8.self)) else { return nil }
            return .number(number)
        }

        private mutating func array() -> Parsed? {
            at += 1
            var items: [Parsed] = []
            if take(UInt8(ascii: "]")) { return .array(items) }
            while true {
                guard let item = value() else { return nil }
                items.append(item)
                if take(UInt8(ascii: ",")) { continue }
                return take(UInt8(ascii: "]")) ? .array(items) : nil
            }
        }

        private mutating func object() -> Parsed? {
            at += 1
            var fields: [String: Parsed] = [:]
            if take(UInt8(ascii: "}")) { return .object(fields) }
            while true {
                skipSpace()
                guard at < bytes.count, bytes[at] == UInt8(ascii: "\""), let key = string(), take(UInt8(ascii: ":")),
                      let item = value() else { return nil }
                fields[key] = item
                if take(UInt8(ascii: ",")) { continue }
                return take(UInt8(ascii: "}")) ? .object(fields) : nil
            }
        }

        /// Four hexadecimal digits, after `\u`.
        private mutating func unit() -> UInt32? {
            guard at + 4 <= bytes.count, let unit = UInt32(String(decoding: bytes[at..<(at + 4)], as: UTF8.self), radix: 16) else { return nil }
            at += 4
            return unit
        }

        private mutating func string() -> String? {
            at += 1
            var text: [UInt8] = []
            while at < bytes.count {
                let byte = bytes[at]
                at += 1
                if byte == UInt8(ascii: "\"") { return String(decoding: text, as: UTF8.self) }
                guard byte == UInt8(ascii: "\\") else {
                    text.append(byte)
                    continue
                }
                guard at < bytes.count else { return nil }
                let escaped = bytes[at]
                at += 1
                switch escaped {
                case UInt8(ascii: "n"): text.append(0x0A)
                case UInt8(ascii: "r"): text.append(0x0D)
                case UInt8(ascii: "t"): text.append(0x09)
                case UInt8(ascii: "b"): text.append(0x08)
                case UInt8(ascii: "f"): text.append(0x0C)
                case UInt8(ascii: "u"):
                    guard var scalar = unit() else { return nil }
                    // A character beyond the first plane is written as two units.
                    if (0xD800..<0xDC00).contains(scalar) {
                        guard at + 2 <= bytes.count, bytes[at] == UInt8(ascii: "\\"), bytes[at + 1] == UInt8(ascii: "u") else { return nil }
                        at += 2
                        guard let low = unit(), (0xDC00..<0xE000).contains(low) else { return nil }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let character = Unicode.Scalar(scalar) else { return nil }
                    text.append(contentsOf: Array(String(Character(character)).utf8))
                default: text.append(escaped)
                }
            }
            return nil
        }
    }
}

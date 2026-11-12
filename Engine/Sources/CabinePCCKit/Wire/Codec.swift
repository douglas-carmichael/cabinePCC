import Foundation

extension CabineWire {

    /// Why a line could not be read as a message.
    public struct DecodeFailure: Error, Equatable, Sendable, CustomStringConvertible {
        public enum Kind: Equatable, Sendable {
            /// Not one JSON object with a string `type`: the stream itself is wrong.
            case malformed
            /// A message of a known type whose fields are missing or of the wrong kind.
            case fields
        }

        public var kind: Kind
        /// The message's `type` and `id`, when they could be read.
        public var type: String?
        public var id: MessageID?
        /// The field at fault, as a path from the top of the message; empty when there is none to name.
        public var path: [String]
        public var reason: String

        public var description: String { reason }
    }

    /// Newline-delimited JSON: one object a line, its `type` written first and the other keys in
    /// alphabetical order, optional fields left out rather than null.
    public enum Codec {

        // MARK: Writing

        /// A message as one line, without its line feed.
        public static func encode(_ message: PCCMessage) -> Data {
            switch message {
            case let .hello(body): compose(message.type, body)
            case let .result(body): compose(message.type, body)
            case let .line(body): compose(message.type, body)
            case let .traffic(body): compose(message.type, body)
            case let .authority(body): compose(message.type, body)
            case let .info(body): compose(message.type, body)
            case let .ping(body): compose(message.type, body)
            case let .pong(body): compose(message.type, body)
            case let .command(body): compose(message.type, body)
            case let .event(body): compose(message.type, body)
            case let .error(body): compose(message.type, body)
            case let .unknown(_, id): compose(message.type, Bare(id: id))
            }
        }

        public static func encode(_ message: CabMessage) -> Data {
            switch message {
            case let .hello(body): compose(message.type, body)
            case let .lineRequest(body): compose(message.type, body)
            case let .join(body): compose(message.type, body)
            case let .position(body): compose(message.type, body)
            case let .status(body): compose(message.type, body)
            case let .event(body): compose(message.type, body)
            case let .leave(body): compose(message.type, body)
            case let .pong(body): compose(message.type, body)
            case let .ping(body): compose(message.type, body)
            case let .result(body): compose(message.type, body)
            case let .unknown(_, id): compose(message.type, Bare(id: id))
            }
        }

        /// A message as it goes down a connection: the line and its line feed.
        public static func framed(_ message: PCCMessage) -> Data {
            var line = encode(message)
            line.append(0x0A)
            return line
        }

        public static func framed(_ message: CabMessage) -> Data {
            var line = encode(message)
            line.append(0x0A)
            return line
        }

        /// An object whose first key is `type` and whose others are those of `body`.
        private static func compose<Body: Encodable>(_ type: String, _ body: Body) -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var line = Data("{\"type\":".utf8)
            line.append((try? encoder.encode(type)) ?? Data("\"\"".utf8))
            // The body is an object of its own: what follows its opening brace follows the type.
            if let fields = try? encoder.encode(body), fields.count > 2, fields.first == UInt8(ascii: "{") {
                line.append(UInt8(ascii: ","))
                line.append(fields.dropFirst())
            } else {
                line.append(UInt8(ascii: "}"))
            }
            return line
        }

        // MARK: Reading

        /// Reads one line a cab sent. A `type` this version does not know is not a failure: it comes back
        /// as `.unknown`.
        public static func decodeCabMessage(_ line: Data) throws -> CabMessage {
            let head = try probe(line)
            do {
                switch head.type {
                case "hello": return .hello(try body(line))
                case "lineRequest": return .lineRequest(try body(line))
                case "join": return .join(try body(line))
                case "position": return .position(try body(line))
                case "status": return .status(try body(line))
                case "event": return .event(try body(line))
                case "leave": return .leave(try body(line))
                case "pong": return .pong(try body(line))
                case "ping": return .ping(try body(line))
                case "result": return .result(try body(line))
                default: return .unknown(type: head.type, id: head.id)
                }
            } catch {
                throw fieldFailure(error, head)
            }
        }

        /// Reads one line a PCC sent.
        public static func decodePCCMessage(_ line: Data) throws -> PCCMessage {
            let head = try probe(line)
            do {
                switch head.type {
                case "hello": return .hello(try body(line))
                case "result": return .result(try body(line))
                case "line": return .line(try body(line))
                case "traffic": return .traffic(try body(line))
                case "authority": return .authority(try body(line))
                case "info": return .info(try body(line))
                case "ping": return .ping(try body(line))
                case "pong": return .pong(try body(line))
                case "command": return .command(try body(line))
                case "event": return .event(try body(line))
                case "error": return .error(try body(line))
                default: return .unknown(type: head.type, id: head.id)
                }
            } catch {
                throw fieldFailure(error, head)
            }
        }

        /// What every message has: its `type`, and the `id` it may carry.
        private struct Head {
            var type: String
            var id: MessageID?
        }

        private struct Probe: Decodable {
            var type: String?
            var id: MessageID?

            enum CodingKeys: String, CodingKey { case type, id }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // Either may be of a kind it should not be: that is for the caller to say, not a reason
                // to give up on the line here.
                type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
                id = (try? container.decodeIfPresent(MessageID.self, forKey: .id)) ?? nil
            }
        }

        /// A message that is nothing but its type and perhaps an id.
        private struct Bare: Encodable {
            var id: MessageID?
        }

        private static func probe(_ line: Data) throws -> Head {
            let read: Probe
            do {
                read = try JSONDecoder().decode(Probe.self, from: line)
            } catch DecodingError.typeMismatch {
                throw DecodeFailure(kind: .malformed, type: nil, id: nil, path: [], reason: "a message is one JSON object")
            } catch {
                throw DecodeFailure(kind: .malformed, type: nil, id: nil, path: [], reason: "not JSON")
            }
            guard let type = read.type, !type.isEmpty else {
                throw DecodeFailure(kind: .malformed, type: nil, id: read.id, path: [], reason: "a message has a string type")
            }
            return Head(type: type, id: read.id)
        }

        private static func body<Body: Decodable>(_ line: Data) throws -> Body {
            try JSONDecoder().decode(Body.self, from: line)
        }

        private static func fieldFailure(_ error: Error, _ head: Head) -> DecodeFailure {
            let (path, reason) = describe(error)
            return DecodeFailure(kind: .fields, type: head.type, id: head.id, path: path, reason: reason)
        }

        /// A decoding error in a few words that name the field: "uM is missing", "track should be a number".
        static func describe(_ error: Error) -> (path: [String], reason: String) {
            func keys(_ path: [CodingKey]) -> [String] {
                path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            }
            func name(_ path: [String]) -> String {
                var text = ""
                for key in path {
                    if !key.hasPrefix("[") && !text.isEmpty { text += "." }
                    text += key
                }
                return text
            }
            guard let error = error as? DecodingError else { return ([], "could not be read") }
            switch error {
            case let .keyNotFound(key, context):
                let path = keys(context.codingPath + [key])
                return (path, "\(name(path)) is missing")
            case let .valueNotFound(_, context):
                let path = keys(context.codingPath)
                return (path, "\(name(path)) is missing")
            case let .typeMismatch(type, context):
                let path = keys(context.codingPath)
                return (path, "\(name(path)) should be \(kind(type))")
            case let .dataCorrupted(context):
                let path = keys(context.codingPath)
                return (path, path.isEmpty ? "could not be read" : "\(name(path)) should be a whole number")
            @unknown default:
                return ([], "could not be read")
            }
        }

        private static func kind(_ type: Any.Type) -> String {
            if type == String.self { return "a string" }
            if type == Bool.self { return "true or false" }
            if type == Int.self { return "a whole number" }
            if type == Double.self { return "a number" }
            if type == MessageID.self { return "a string or a number" }
            if type == CommandValue.self { return "true or false, a string or a number" }
            let name = String(describing: type)
            if name.hasPrefix("Array") { return "a list" }
            return "an object"
        }
    }

    /// Splits what a connection delivers into lines. A line feed ends a line; a carriage return before
    /// it is dropped, and so is a blank line. A line longer than the limit is an error: the framer gives
    /// back the lines that came before it, says so in `lineTooLong`, and reads no further, for the
    /// connection is then to be closed.
    public struct Framer: Sendable {
        public let maxLineBytes: Int
        /// True once a line longer than the limit has come.
        public private(set) var lineTooLong = false
        private var pending = Data()

        public init(maxLineBytes: Int = CabineWire.maxLineBytes) {
            self.maxLineBytes = maxLineBytes
        }

        /// Takes in the next bytes received and gives back the lines they complete, without their line ends.
        public mutating func append(_ data: Data) -> [Data] {
            guard !lineTooLong else { return [] }
            pending.append(data)
            var lines: [Data] = []
            var start = pending.startIndex
            while let feed = pending[start...].firstIndex(of: 0x0A) {
                var end = feed
                if end > start, pending[end - 1] == 0x0D { end -= 1 }
                if end - start > maxLineBytes {
                    overflow()
                    return lines
                }
                if end > start { lines.append(Data(pending[start..<end])) }
                start = feed + 1
            }
            // Data keeps its indices when its front is cut off: start afresh from what is left.
            pending = Data(pending[start...])
            // One byte more than a line may be is still in order: it may be the carriage return of its end.
            if pending.count > maxLineBytes + 1 { overflow() }
            return lines
        }

        private mutating func overflow() {
            lineTooLong = true
            pending.removeAll()
        }
    }
}

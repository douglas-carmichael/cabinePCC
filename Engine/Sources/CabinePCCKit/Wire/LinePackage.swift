import Foundation

extension CabineWire {

    /// Any JSON value. It is what a line's source goes through the PCC as: the PCC keeps it and hands it
    /// on without reading it, so it must come out as it went in.
    ///
    /// A number is kept as the `Double` it reads as, and written back in the shortest form that reads as
    /// that same `Double`: `13224.5` comes out `13224.5`, and a whole number written `103.0` comes out
    /// `103`. An object's keys come out in alphabetical order.
    public enum JSONValue: Codable, Sendable, Equatable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            // Numbers first: a source is thousands of them, and a kind that is tried in vain costs a throw.
            if container.decodeNil() {
                self = .null
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let text = try? container.decode(String.self) {
                self = .string(text)
            } else if let flag = try? container.decode(Bool.self) {
                self = .bool(flag)
            } else if let items = try? container.decode([JSONValue].self) {
                self = .array(items)
            } else {
                self = .object(try container.decode([String: JSONValue].self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case let .bool(flag): try container.encode(flag)
            case let .number(number): try container.encode(number)
            case let .string(text): try container.encode(text)
            case let .array(items): try container.encode(items)
            case let .object(fields): try container.encode(fields)
            }
        }

        /// The value under a key, of an object.
        public subscript(key: String) -> JSONValue? {
            if case let .object(fields) = self { fields[key] } else { nil }
        }

        /// The value at a place, of an array.
        public subscript(index: Int) -> JSONValue? {
            if case let .array(items) = self, items.indices.contains(index) { items[index] } else { nil }
        }

        public var string: String? { if case let .string(text) = self { text } else { nil } }
        public var number: Double? { if case let .number(number) = self { number } else { nil } }
        public var bool: Bool? { if case let .bool(flag) = self { flag } else { nil } }
        public var array: [JSONValue]? { if case let .array(items) = self { items } else { nil } }
        public var object: [String: JSONValue]? { if case let .object(fields) = self { fields } else { nil } }
    }

    /// A line of the PCC's library: the description the PCC runs it on, and the source a Cabine builds
    /// it from. It is also the format of a `.line.json` file.
    public struct LinePackage: Codable, Sendable, Equatable {
        /// The format this version writes and reads.
        public static let currentFormat = 1

        public var format: Int
        /// The line as the PCC runs it.
        public var description: LineDescription
        /// The line as a Cabine builds it: the data of Cabine's own line file, as it came. Absent for a
        /// line that every Cabine has built in under that id.
        public var source: JSONValue?

        public init(format: Int = LinePackage.currentFormat, description: LineDescription, source: JSONValue? = nil) {
            self.format = format
            self.description = description
            self.source = source
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            format = try container.decodeIfPresent(Int.self, forKey: .format) ?? LinePackage.currentFormat
            description = try container.decode(LineDescription.self, forKey: .description)
            source = try container.decodeIfPresent(JSONValue.self, forKey: .source)
        }

        public var identity: LineIdentity { description.identity }

        // MARK: Files

        /// Reads a package from a `.line.json` file. See `decode(file:)` for what the file may hold.
        public static func decode(file url: URL) throws -> LinePackage {
            try decode(file: try Data(contentsOf: url))
        }

        /// Reads a package from the bytes of a `.line.json` file: a package; a bare description, which is
        /// then a package with no source; or a whole `line` message with the package inside it. Throws a
        /// `DecodeFailure` that names what is missing or of the wrong kind.
        public static func decode(file data: Data) throws -> LinePackage {
            /// Which of the three the file is, by the keys it has.
            struct Shape: Decodable {
                var hasDescription: Bool
                var hasPackage: Bool

                enum CodingKeys: String, CodingKey { case description, package }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    hasDescription = container.contains(.description)
                    hasPackage = container.contains(.package)
                }
            }
            struct Message: Decodable { let package: LinePackage }

            let decoder = JSONDecoder()
            guard let shape = try? decoder.decode(Shape.self, from: data) else {
                throw DecodeFailure(kind: .malformed, type: "line", id: nil, path: [], reason: "not a line package")
            }
            do {
                if shape.hasPackage { return try decoder.decode(Message.self, from: data).package }
                if shape.hasDescription { return try decoder.decode(LinePackage.self, from: data) }
                return LinePackage(description: try decoder.decode(LineDescription.self, from: data))
            } catch {
                let (path, reason) = Codec.describe(error)
                throw DecodeFailure(kind: path.isEmpty ? .malformed : .fields, type: "line", id: nil, path: path,
                                    reason: path.isEmpty ? "not a line package" : reason)
            }
        }

        /// The package as the bytes of a `.line.json` file: on one line, its keys in alphabetical order,
        /// ended by a line feed. A source of thousands of numbers is not laid out to be read.
        public func encodedForFile() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(self) + Data([0x0A])
        }
    }
}

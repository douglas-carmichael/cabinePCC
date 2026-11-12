import Foundation

/// The wire of the Cabine link, protocol version 1, as docs/cabine-link.md specifies it: its constants,
/// the words its string fields take, and one Codable type for each message.
///
/// Nothing in the Wire folder knows of the engine or of sockets, so the same files can serve the other
/// end of the link.
public enum CabineWire {
    /// The version both `hello`s and the Bonjour TXT record declare.
    public static let protocolVersion = 1
    /// The port a PCC listens on by preference.
    public static let preferredPort: UInt16 = 5289
    public static let bonjourServiceType = "_cabinepcc._tcp"
    public static let bonjourDomain = "local."
    /// The longest line either end accepts, in bytes, its line feed excluded.
    public static let maxLineBytes = 1 << 20
    /// Connections a PCC serves at once.
    public static let maxSessions = 16
    /// The longest text a `message` command carries, in characters.
    public static let maxMessageCharacters = 120
    /// The numbers a rame may bear, and those of the fleet the automatic rames are numbered from.
    public static let rameNumbers = 1...99
    public static let fleetNumbers = 1...52

    /// A value as it goes on the wire: rounded to so many decimal places, with -0 and anything that is
    /// not a number folded into 0 (JSON has no way to write the latter).
    public static func rounded(_ value: Double, _ places: Int = 3) -> Double {
        guard value.isFinite else { return 0 }
        let scale = pow(10, Double(places))
        let r = (value * scale).rounded() / scale
        return r == 0 ? 0 : r
    }
}

/// One of the words a string field of the wire takes. It keeps a word it does not know, so that a
/// message from a newer end still decodes; the words of this version are the static members.
public protocol CabineWireName: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible,
                                ExpressibleByStringLiteral where RawValue == String {
    init(rawValue: String)
}

extension CabineWireName {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }
}

extension CabineWire {

    /// The `error` of a `result` or of an `error` message.
    public struct ErrorCode: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let badMessage: ErrorCode = "badMessage"
        public static let unknownType: ErrorCode = "unknownType"
        public static let unsupportedProtocol: ErrorCode = "unsupportedProtocol"
        /// The PCC is on no line, and none was named.
        public static let noLine: ErrorCode = "noLine"
        /// The PCC holds no line of that id and revision.
        public static let noSuchLine: ErrorCode = "noSuchLine"
        public static let notOnLine: ErrorCode = "notOnLine"
        public static let notInService: ErrorCode = "notInService"
        public static let badValue: ErrorCode = "badValue"
        public static let tooManySessions: ErrorCode = "tooManySessions"
        public static let lineTooLong: ErrorCode = "lineTooLong"
    }

    /// Who drives a train of the fleet picture.
    public struct TrainKind: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// A rame the PCC drives.
        public static let auto: TrainKind = "auto"
        /// A Cabine's.
        public static let cab: TrainKind = "cab"
    }

    /// What a train of the fleet picture is doing.
    public struct TrainPhase: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let running: TrainPhase = "running"
        /// At a platform with its doors open or opening.
        public static let dwelling: TrainPhase = "dwelling"
        /// Doors closing or just closed.
        public static let departing: TrainPhase = "departing"
        /// Kept at a platform.
        public static let held: TrainPhase = "held"
        /// Braked.
        public static let emergency: TrainPhase = "emergency"
        /// Turning back beyond a terminus: it occupies the tail and is not to be drawn.
        public static let tail: TrainPhase = "tail"
    }

    /// What ends a movement authority.
    public struct AuthorityReason: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let train: AuthorityReason = "train"
        public static let horizon: AuthorityReason = "horizon"
        public static let end: AuthorityReason = "end"
        public static let hold: AuthorityReason = "hold"
        public static let service: AuthorityReason = "service"
        public static let emergency: AuthorityReason = "emergency"
    }

    /// The state of the line, in `info`.
    public struct LineMode: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let normal: LineMode = "normal"
        /// The line is not in service.
        public static let stopped: LineMode = "stopped"
        public static let emergency: LineMode = "emergency"
    }

    /// An order from the PCC's operator to a cab.
    public struct CommandName: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let emergencyBrake: CommandName = "emergencyBrake"
        public static let hold: CommandName = "hold"
        public static let message: CommandName = "message"
        public static let call: CommandName = "call"
    }

    /// The name of an `event`, from either end.
    public struct EventName: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        // From a cab.
        public static let report: EventName = "report"
        public static let call: EventName = "call"
        public static let acknowledge: EventName = "acknowledge"
        public static let emergencyBrake: EventName = "emergencyBrake"
        // From the PCC.
        public static let line: EventName = "line"
        public static let peer: EventName = "peer"
        public static let closing: EventName = "closing"
    }

    /// What became of another cab, in a `peer` event.
    public struct PeerState: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let joined: PeerState = "joined"
        public static let left: PeerState = "left"
    }

    /// A cab's doors, in its `status`.
    public struct DoorPhase: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let closed: DoorPhase = "closed"
        public static let opening: DoorPhase = "opening"
        public static let open: DoorPhase = "open"
        public static let warning: DoorPhase = "warning"
        public static let closing: DoorPhase = "closing"
    }

    /// A cab's CONDUITE selector, in its `status`.
    public struct DrivingMode: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// By hand.
        public static let manual: DrivingMode = "CM"
        public static let pa: DrivingMode = "PA"
        public static let ca: DrivingMode = "CA"
    }

    /// Why a cab's service is over, in `leave`.
    public struct LeaveReason: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// It reached its terminus.
        public static let finished: LeaveReason = "finished"
        /// The player ended it.
        public static let ended: LeaveReason = "ended"
        public static let quit: LeaveReason = "quit"
    }

    /// One of the driver's coded radio reports.
    public struct ReportCode: CabineWireName {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let radioCheck: ReportCode = "radioCheck"
        public static let readyToDepart: ReportCode = "readyToDepart"
        public static let stoppedAtSignal: ReportCode = "stoppedAtSignal"
        public static let passengerIll: ReportCode = "passengerIll"
        public static let technicalFault: ReportCode = "technicalFault"
        public static let incidentOver: ReportCode = "incidentOver"
        public static let requestCall: ReportCode = "requestCall"
    }

    /// The `id` a request carries and its `result` echoes: a string or a number, sent back as it came.
    public enum MessageID: Hashable, Sendable, Codable, CustomStringConvertible,
                           ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
        case string(String)
        case integer(Int)
        case number(Double)

        public init(stringLiteral value: String) { self = .string(value) }
        public init(integerLiteral value: Int) { self = .integer(value) }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .string(text)
            } else if let whole = try? container.decode(Int.self) {
                self = .integer(whole)
            } else if let real = try? container.decode(Double.self) {
                self = .number(real)
            } else {
                throw DecodingError.typeMismatch(MessageID.self, .init(codingPath: decoder.codingPath,
                                                                       debugDescription: "an id is a string or a number"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(text): try container.encode(text)
            case let .integer(whole): try container.encode(whole)
            case let .number(real): try container.encode(real)
            }
        }

        public var description: String {
            switch self {
            case let .string(text): text
            case let .integer(whole): String(whole)
            case let .number(real): String(real)
            }
        }
    }

    /// The `value` of a `command`: true or false, words, or a number.
    public enum CommandValue: Hashable, Sendable, Codable {
        case bool(Bool)
        case string(String)
        case number(Double)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .bool(flag)
            } else if let text = try? container.decode(String.self) {
                self = .string(text)
            } else if let real = try? container.decode(Double.self) {
                self = .number(real)
            } else {
                throw DecodingError.typeMismatch(CommandValue.self, .init(codingPath: decoder.codingPath,
                                                                          debugDescription: "a value is true or false, a string or a number"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .bool(flag): try container.encode(flag)
            case let .string(text): try container.encode(text)
            case let .number(real): try container.encode(real)
            }
        }

        public var bool: Bool? { if case let .bool(flag) = self { flag } else { nil } }
        public var string: String? { if case let .string(text) = self { text } else { nil } }
    }

    /// Which line, and which revision of its geometry. Two identities with the same `id` and `rev` mean
    /// the same line to the metre; the name is for displays.
    public struct LineIdentity: Codable, Hashable, Sendable, CustomStringConvertible {
        public var id: String
        public var rev: String
        public var name: String

        public init(id: String, rev: String, name: String) {
            self.id = id
            self.rev = rev
            self.name = name
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            rev = try container.decode(String.self, forKey: .rev)
            // A line that is given no name goes by its id.
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        }

        /// True when both mean the same line: equal `id` and equal `rev`.
        public func isSameLine(as other: LineIdentity) -> Bool { id == other.id && rev == other.rev }

        public var description: String { "\(name) (\(id), \(rev))" }
    }
}

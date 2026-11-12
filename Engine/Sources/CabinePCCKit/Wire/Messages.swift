import Foundation

// One type for each message of the specification, named after its `type`. The `type` itself is not a
// field: the codec writes and reads it (Codec.swift). A field the specification allows to be absent is
// an optional here, and an optional that is nil is left out of the line, never written as null.

extension CabineWire {

    // MARK: - From the cab

    /// `hello`, from a cab: who it is and which line it holds.
    public struct CabHello: Codable, Equatable, Sendable {
        /// The version it speaks; taken to be this one when it does not say.
        public var `protocol`: Int?
        public var app: String?
        public var appVersion: String?
        public var cab: Cab?
        /// The line the cab holds at that moment; left out by a cab that holds none.
        public var line: LineIdentity?

        public struct Cab: Codable, Equatable, Sendable {
            /// Stays the same from one launch of that Cabine to the next.
            public var id: String
            /// For the PCC's displays.
            public var name: String?

            public init(id: String, name: String? = nil) {
                self.id = id
                self.name = name
            }
        }

        public init(protocol version: Int? = CabineWire.protocolVersion, app: String? = nil, appVersion: String? = nil,
                    cab: Cab? = nil, line: LineIdentity? = nil) {
            self.protocol = version
            self.app = app
            self.appVersion = appVersion
            self.cab = cab
            self.line = line
        }
    }

    /// `lineRequest`: the cab asks for a line of the PCC's library.
    public struct LineRequest: Codable, Equatable, Sendable {
        public var id: MessageID?
        /// The line asked for; the one the PCC is on when left out.
        public var line: LineIdentity?

        public init(id: MessageID? = nil, line: LineIdentity? = nil) {
            self.id = id
            self.line = line
        }
    }

    /// `join`: the cab's train enters service where it stands.
    public struct Join: Codable, Equatable, Sendable {
        public var id: MessageID?
        public var track: Int
        /// Its nose.
        public var uM: Double
        /// Index, in that track's order of travel, of the station it stands at or runs to next.
        public var station: Int?
        /// The number it would like.
        public var rame: Int?

        public init(id: MessageID? = nil, track: Int, uM: Double, station: Int? = nil, rame: Int? = nil) {
            self.id = id
            self.track = track
            self.uM = uM
            self.station = station
            self.rame = rame
        }
    }

    /// `position`, five times a second.
    public struct Position: Codable, Equatable, Sendable {
        public var seq: Int?
        public var tS: Double?
        public var track: Int
        public var uM: Double
        public var speedMS: Double?
        public var accelerationMS2: Double?

        public init(seq: Int? = nil, tS: Double? = nil, track: Int, uM: Double, speedMS: Double? = nil,
                    accelerationMS2: Double? = nil) {
            self.seq = seq
            self.tS = tS
            self.track = track
            self.uM = uM
            self.speedMS = speedMS
            self.accelerationMS2 = accelerationMS2
        }
    }

    /// `status`, about three times a second.
    public struct Status: Codable, Equatable, Sendable {
        public var seq: Int?
        public var tS: Double?
        /// The cab's CONDUITE selector.
        public var mode: DrivingMode?
        /// True while the automatic driver has the train.
        public var automatic: Bool?
        public var doors: Doors?
        public var emergencyBrake: EmergencyBrake?
        public var passengers: Int?
        public var station: StationState?
        /// Seconds late (positive) or early on its timetable.
        public var deviationS: Double?
        /// The train is kept at its platform.
        public var held: Bool?
        /// The player has paused the game: the train stands.
        public var paused: Bool?
        /// The train holds a movement authority and runs on it.
        public var underControl: Bool?

        public struct Doors: Codable, Equatable, Sendable {
            public var phase: DoorPhase?
            /// `right` or `left`.
            public var side: String?
            /// 0 shut to 1 open.
            public var open: Double?

            public init(phase: DoorPhase? = nil, side: String? = nil, open: Double? = nil) {
                self.phase = phase
                self.side = side
                self.open = open
            }
        }

        public struct EmergencyBrake: Codable, Equatable, Sendable {
            public var applied: Bool
            /// In Cabine's words.
            public var cause: String?

            public init(applied: Bool, cause: String? = nil) {
                self.applied = applied
                self.cause = cause
            }
        }

        public struct StationState: Codable, Equatable, Sendable {
            /// The station it is at or runs to, in its track's order.
            public var index: Int?
            public var atPlatform: Bool?

            public init(index: Int? = nil, atPlatform: Bool? = nil) {
                self.index = index
                self.atPlatform = atPlatform
            }
        }

        public init(seq: Int? = nil, tS: Double? = nil, mode: DrivingMode? = nil, automatic: Bool? = nil,
                    doors: Doors? = nil, emergencyBrake: EmergencyBrake? = nil, passengers: Int? = nil,
                    station: StationState? = nil, deviationS: Double? = nil, held: Bool? = nil, paused: Bool? = nil,
                    underControl: Bool? = nil) {
            self.seq = seq
            self.tS = tS
            self.mode = mode
            self.automatic = automatic
            self.doors = doors
            self.emergencyBrake = emergencyBrake
            self.passengers = passengers
            self.station = station
            self.deviationS = deviationS
            self.held = held
            self.paused = paused
            self.underControl = underControl
        }
    }

    /// `event`, from a cab: a coded report, a call, an acknowledgement, or its emergency brake.
    public struct CabEvent: Codable, Equatable, Sendable {
        public var event: EventName
        /// Of a `report`.
        public var code: ReportCode?
        public var text: String?
        /// Of an `emergencyBrake`.
        public var applied: Bool?
        public var cause: String?

        public init(event: EventName, code: ReportCode? = nil, text: String? = nil, applied: Bool? = nil,
                    cause: String? = nil) {
            self.event = event
            self.code = code
            self.text = text
            self.applied = applied
            self.cause = cause
        }
    }

    /// `leave`: the cab's service is over.
    public struct Leave: Codable, Equatable, Sendable {
        public var id: MessageID?
        public var reason: LeaveReason?

        public init(id: MessageID? = nil, reason: LeaveReason? = nil) {
            self.id = id
            self.reason = reason
        }
    }

    // MARK: - Either way

    /// `ping`, and the `pong` that answers it with the same `id` and `tS`.
    public struct Ping: Codable, Equatable, Sendable {
        public var id: MessageID?
        public var tS: Double?

        public init(id: MessageID? = nil, tS: Double? = nil) {
            self.id = id
            self.tS = tS
        }
    }

    /// `result`: the answer to a request, with the request's `id`.
    public struct ResultMessage: Codable, Equatable, Sendable {
        public var id: MessageID?
        public var ok: Bool
        public var error: ErrorCode?
        public var message: String?
        /// The number a `join` was given.
        public var rame: Int?

        public init(id: MessageID? = nil, ok: Bool, error: ErrorCode? = nil, message: String? = nil, rame: Int? = nil) {
            self.id = id
            self.ok = ok
            self.error = error
            self.message = message
            self.rame = rame
        }
    }

    // MARK: - From the PCC

    /// `hello`, from the PCC: who it is, the line it is on, and how the cab stands to it.
    public struct PCCHello: Codable, Equatable, Sendable {
        public var `protocol`: Int
        public var app: String
        public var name: String
        public var pcc: PCC?
        /// The line the PCC is on; absent while it is on none.
        public var line: LineIdentity?
        /// The line the cab named is the PCC's: the cab is on the line.
        public var onLine: Bool
        public var link: LinkTimings

        public struct PCC: Codable, Equatable, Sendable {
            public var id: String

            public init(id: String) { self.id = id }
        }

        public init(protocol version: Int = CabineWire.protocolVersion, app: String, name: String, pcc: PCC? = nil,
                    line: LineIdentity? = nil, onLine: Bool, link: LinkTimings = LinkTimings()) {
            self.protocol = version
            self.app = app
            self.name = name
            self.pcc = pcc
            self.line = line
            self.onLine = onLine
            self.link = link
        }
    }

    /// The periods the PCC sends at and would like to be sent at, and the two times that matter when
    /// things go wrong.
    public struct LinkTimings: Codable, Equatable, Sendable {
        public var positionPeriodS: Double
        public var statusPeriodS: Double
        public var trafficPeriodS: Double
        public var authorityPeriodS: Double
        public var infoPeriodS: Double
        public var pingPeriodS: Double
        /// Silence after which the other end is taken to be gone.
        public var timeoutS: Double
        /// How long the PCC holds a silent cab's train as an obstacle before handing it back to automation.
        public var staleHoldS: Double

        public init(positionPeriodS: Double = 0.2, statusPeriodS: Double = 0.3, trafficPeriodS: Double = 0.2,
                    authorityPeriodS: Double = 0.6, infoPeriodS: Double = 0.4, pingPeriodS: Double = 0.5,
                    timeoutS: Double = 3, staleHoldS: Double = 30) {
            self.positionPeriodS = positionPeriodS
            self.statusPeriodS = statusPeriodS
            self.trafficPeriodS = trafficPeriodS
            self.authorityPeriodS = authorityPeriodS
            self.infoPeriodS = infoPeriodS
            self.pingPeriodS = pingPeriodS
            self.timeoutS = timeoutS
            self.staleHoldS = staleHoldS
        }
    }

    /// `line`: a line of the library, in answer to `lineRequest`, with the request's `id`.
    public struct LineMessage: Codable, Equatable, Sendable {
        public var id: MessageID?
        public var package: LinePackage

        public init(id: MessageID? = nil, package: LinePackage) {
            self.id = id
            self.package = package
        }
    }

    /// `traffic`, five times a second: every rame of the line but the recipient's own.
    public struct Traffic: Codable, Equatable, Sendable {
        public var tS: Double
        public var trains: [TrafficTrain]

        public init(tS: Double, trains: [TrafficTrain]) {
            self.tS = tS
            self.trains = trains
        }
    }

    public struct TrafficTrain: Codable, Equatable, Sendable {
        public var rame: Int
        public var kind: TrainKind
        /// For a cab, its name.
        public var name: String?
        public var track: Int
        /// Where its nose is.
        public var uM: Double
        public var speedMS: Double
        public var accelerationMS2: Double?
        /// 0 shut to 1 open.
        public var doors: Double
        public var phase: TrainPhase
        /// Index, in its track's order of travel, of the station it stands at or runs to next; absent in
        /// the tail.
        public var station: Int?
        public var lengthM: Double

        public init(rame: Int, kind: TrainKind, name: String? = nil, track: Int, uM: Double, speedMS: Double,
                    accelerationMS2: Double? = nil, doors: Double, phase: TrainPhase, station: Int? = nil,
                    lengthM: Double) {
            self.rame = rame
            self.kind = kind
            self.name = name
            self.track = track
            self.uM = uM
            self.speedMS = speedMS
            self.accelerationMS2 = accelerationMS2
            self.doors = doors
            self.phase = phase
            self.station = station
            self.lengthM = lengthM
        }
    }

    /// `authority`: leave to run as far as `endM` on the cab's track, and no further.
    public struct Authority: Codable, Equatable, Sendable {
        public var seq: Int
        public var tS: Double
        public var track: Int
        public var endM: Double
        public var reason: AuthorityReason
        /// With `train`: the number of the train ahead, and the metres from the cab's nose to its rear.
        public var rame: Int?
        public var gapM: Double?
        /// How long it stands without being renewed.
        public var validS: Double

        public init(seq: Int, tS: Double, track: Int, endM: Double, reason: AuthorityReason, rame: Int? = nil,
                    gapM: Double? = nil, validS: Double) {
            self.seq = seq
            self.tS = tS
            self.track = track
            self.endM = endM
            self.reason = reason
            self.rame = rame
            self.gapM = gapM
            self.validS = validS
        }
    }

    /// `info`, every 0.4 s: the line's clock and state, and the numbers in use.
    public struct Info: Codable, Equatable, Sendable {
        public var tS: Double
        /// The line's time of day, seconds since midnight.
        public var clockS: Double
        public var mode: LineMode
        /// The trains of the line, and those of them that are cabs.
        public var rames: Int
        public var cabs: Int
        public var numbers: [Int]

        public init(tS: Double, clockS: Double, mode: LineMode, rames: Int, cabs: Int, numbers: [Int]) {
            self.tS = tS
            self.clockS = clockS
            self.mode = mode
            self.rames = rames
            self.cabs = cabs
            self.numbers = numbers
        }
    }

    /// `command`: an order from the PCC's operator, which the cab answers with `result`.
    public struct Command: Codable, Equatable, Sendable {
        public var id: MessageID?
        public var command: CommandName
        public var value: CommandValue?

        public init(id: MessageID? = nil, command: CommandName, value: CommandValue? = nil) {
            self.id = id
            self.command = command
            self.value = value
        }
    }

    /// `event`, from the PCC: the line it is now on, another cab entering or leaving service, or its closing.
    public struct PCCEvent: Codable, Equatable, Sendable {
        public var event: EventName
        /// Of `line`: the line the PCC is now on; left out when it is now on none.
        public var line: LineIdentity?
        /// Of `peer`.
        public var rame: Int?
        public var name: String?
        public var state: PeerState?
        /// Of `closing`: in how many seconds.
        public var inS: Double?

        public init(event: EventName, line: LineIdentity? = nil, rame: Int? = nil, name: String? = nil,
                    state: PeerState? = nil, inS: Double? = nil) {
            self.event = event
            self.line = line
            self.rame = rame
            self.name = name
            self.state = state
            self.inS = inS
        }
    }

    /// `error`: something wrong with the stream itself.
    public struct StreamError: Codable, Equatable, Sendable {
        public var error: ErrorCode
        public var message: String?

        public init(error: ErrorCode, message: String? = nil) {
            self.error = error
            self.message = message
        }
    }

    // MARK: - The two directions

    /// A message a cab sends.
    public enum CabMessage: Equatable, Sendable {
        case hello(CabHello)
        case lineRequest(LineRequest)
        case join(Join)
        case position(Position)
        case status(Status)
        case event(CabEvent)
        case leave(Leave)
        case pong(Ping)
        case ping(Ping)
        /// Its answer to a `command`.
        case result(ResultMessage)
        /// A `type` this version does not know, kept with its `id` so that it can be answered.
        case unknown(type: String, id: MessageID?)

        public var type: String {
            switch self {
            case .hello: "hello"
            case .lineRequest: "lineRequest"
            case .join: "join"
            case .position: "position"
            case .status: "status"
            case .event: "event"
            case .leave: "leave"
            case .pong: "pong"
            case .ping: "ping"
            case .result: "result"
            case let .unknown(type, _): type
            }
        }
    }

    /// A message the PCC sends.
    public enum PCCMessage: Equatable, Sendable {
        case hello(PCCHello)
        case result(ResultMessage)
        /// A line of the library, in answer to `lineRequest`.
        case line(LineMessage)
        case traffic(Traffic)
        case authority(Authority)
        case info(Info)
        case ping(Ping)
        case pong(Ping)
        case command(Command)
        case event(PCCEvent)
        case error(StreamError)
        /// A `type` this version does not know.
        case unknown(type: String, id: MessageID?)

        public var type: String {
            switch self {
            case .hello: "hello"
            case .result: "result"
            case .line: "line"
            case .traffic: "traffic"
            case .authority: "authority"
            case .info: "info"
            case .ping: "ping"
            case .pong: "pong"
            case .command: "command"
            case .event: "event"
            case .error: "error"
            case let .unknown(type, _): type
            }
        }

        /// True for the messages that are sent again and again, each replacing the last: one of them may
        /// be skipped for a reader that has fallen behind, where an answer or an order may not.
        public var isPeriodic: Bool {
            switch self {
            case .traffic, .authority, .info, .ping: true
            default: false
            }
        }
    }
}

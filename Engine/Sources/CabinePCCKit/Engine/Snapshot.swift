import Foundation

// What a host reads from the engine to supervise the line: a picture of it at one moment, and the things
// that happened since it last asked.

extension CabinePCC {

    /// The line and everything on it at one moment.
    public struct Snapshot: Sendable {
        /// Seconds the engine has run for: the `tS` of what it sends.
        public var timeS: Double
        /// The line the PCC is on, if it is on one.
        public var line: Line?
        /// The line's time of day, seconds since midnight.
        public var clockS: Double
        public var mode: CabineWire.LineMode
        /// Line service is on.
        public var inService: Bool
        /// A general emergency stop is on.
        public var emergencyStop: Bool
        /// Seconds between trains each way that the fleet is sized for.
        public var headwayS: Double
        /// Trains on the line, cabs included, when the operator has fixed their number.
        public var fleetSize: Int?
        /// The time one rame alone takes to go round the loop, measured when the line was taken up.
        public var lapTimeS: Double
        /// How many automatic rames the PCC means to have on the line at present.
        public var automaticTarget: Int
        /// Every train of the line.
        public var rames: [Rame]
        /// Every connection.
        public var sessions: [Session]
        /// The lines of the library, in the order they were kept.
        public var library: [HeldLine]

        public var cabs: [Rame] { rames.filter { $0.cab != nil } }

        public func rame(numbered number: Int) -> Rame? { rames.first { $0.number == number } }
    }

    /// A line of the library, in a few words: enough to list it and to choose it.
    public struct HeldLine: Sendable, Identifiable, Equatable {
        public var identity: CabineWire.LineIdentity
        public var stationCount: Int
        /// Length of each track, tail tracks included.
        public var lengthM: Double
        /// The package has the line's source, to hand to a cab that has not built that line in.
        public var hasSource: Bool
        /// The line's two ends, as track 1 runs.
        public var firstStation: String
        public var lastStation: String

        /// A line of the library is known by its id and its revision.
        public var id: CabineWire.LineIdentity { identity }

        public init(identity: CabineWire.LineIdentity, stationCount: Int, lengthM: Double, hasSource: Bool,
                    firstStation: String, lastStation: String) {
            self.identity = identity
            self.stationCount = stationCount
            self.lengthM = lengthM
            self.hasSource = hasSource
            self.firstStation = firstStation
            self.lastStation = lastStation
        }
    }

    /// One train of the line.
    public struct Rame: Sendable, Identifiable {
        /// Stays the same for as long as the train is on the line, whatever becomes of its number or of
        /// who drives it.
        public var id: Int
        public var number: Int
        public var kind: CabineWire.TrainKind
        public var track: Int
        /// Where its nose is.
        public var uM: Double
        public var speedMS: Double
        public var accelerationMS2: Double
        public var phase: CabineWire.TrainPhase
        /// 0 shut to 1 open.
        public var doors: Double
        /// Index, in its track's order of travel, of the station it stands at or runs to next; nil in the
        /// tail and beyond the last stop.
        public var station: Int?
        public var stationName: String?
        public var lengthM: Double
        /// The operator is holding it at a platform, or will at the next it reaches.
        public var held: Bool
        /// The operator has applied its emergency brake.
        public var braked: Bool
        /// For a cab's train, the cab.
        public var cab: Cab?
    }

    /// The cab that drives a train.
    public struct Cab: Sendable {
        public var cabID: String
        public var name: String
        /// Its connection; nil once that has gone.
        public var session: SessionID?
        public var link: LinkState
        /// Seconds since anything was heard from it.
        public var linkAgeS: Double
        /// The last round trip of a ping, when the host measures it.
        public var roundTripS: Double?
        /// What its last `status` said.
        public var status: CabineWire.Status?
        public var emergencyBrake: Bool
        public var emergencyCause: String?
        /// The last movement authority sent to it.
        public var authority: CabineWire.Authority?
        /// The last coded report its driver sent.
        public var lastReport: Report?

        public var mode: CabineWire.DrivingMode? { status?.mode }
        public var automatic: Bool? { status?.automatic }
    }

    public enum LinkState: String, Sendable {
        /// Heard from within the link's timeout.
        case live
        /// Silent: its train is held where it was last seen, as an obstacle.
        case silent
    }

    /// A coded radio report from a driver.
    public struct Report: Sendable, Equatable {
        public var code: CabineWire.ReportCode?
        public var text: String?
        /// The line's time of day when it came.
        public var clockS: Double
    }

    /// One connection.
    public struct Session: Sendable, Identifiable {
        public var id: SessionID
        /// Where it comes from, as its host put it.
        public var peer: String
        public var standing: Standing
        public var cabID: String?
        public var name: String?
        public var app: String?
        public var appVersion: String?
        /// The line it says it holds; nil if it holds none, or has not said.
        public var line: CabineWire.LineIdentity?
        /// The number of its train, while it is in service.
        public var rame: Int?
        /// Seconds since anything was heard from it.
        public var linkAgeS: Double
        public var roundTripS: Double?
    }

    /// How a connection stands to the PCC.
    public enum Standing: String, Sendable {
        /// Open, and has not said `hello`.
        case opened
        /// Connected, but not on the PCC's line.
        case connected
        case onLine
        case inService
    }

    /// Something that happened, for an operator's journal.
    public struct JournalEntry: Sendable, Equatable, CustomStringConvertible {
        /// The engine's time and the line's time of day when it happened.
        public var timeS: Double
        public var clockS: Double
        public var event: Event

        public enum Event: Sendable, Equatable {
            /// The PCC is now on this line, with so many automatic rames.
            case lineTakenUp(line: CabineWire.LineIdentity, rames: Int)
            /// A cab said `hello` for the first time on its connection, naming the line it holds, or none.
            case cabConnected(name: String, cabID: String, line: CabineWire.LineIdentity?)
            /// A cab has named the PCC's line: it is on the line.
            case cabOnLine(name: String)
            /// A cab asked for a line that the library does not hold.
            case lineRefused(name: String, error: CabineWire.ErrorCode, reason: String)
            /// A cab asked for a line of the library and was sent its package.
            case lineHandedOver(name: String, line: CabineWire.LineIdentity)
            /// A cab entered service; `withdrawn` are the automatic rames whose place it took.
            case cabJoined(name: String, rame: Int, track: Int, uM: Double, withdrawn: [Int])
            case cabLeft(name: String, rame: Int, reason: String)
            /// A cab in service fell silent: its train is held as an obstacle.
            case cabSilent(name: String, rame: Int)
            case cabHeardAgain(name: String, rame: Int)
            /// A cab's train went back to automation, as the automatic rame of this number.
            case cabHandedBack(name: String, rame: Int, number: Int)
            case cabDisconnected(name: String)
            case cabEmergencyBrake(name: String, rame: Int?, applied: Bool, cause: String?)
            case cabReport(name: String, rame: Int?, code: CabineWire.ReportCode?, text: String?)
            case cabCall(name: String, rame: Int?)
            case cabAcknowledge(name: String, rame: Int?)
            /// A cab answered a command with a refusal.
            case commandRefused(name: String, rame: Int?, command: CabineWire.CommandName, error: String?)
        }

        public var description: String {
            func rame(_ number: Int?) -> String { number.map { String(format: " (rame %02d)", $0) } ?? "" }
            switch event {
            case let .lineTakenUp(line, rames):
                return "line taken up: \(line.name), id \(line.id), rev \(line.rev), \(rames) automatic rames"
            case let .cabConnected(name, _, line):
                guard let line else { return "cab \(name) connected, holding no line" }
                return "cab \(name) connected, holding \(line.name) (\(line.id), \(line.rev))"
            case let .cabOnLine(name):
                return "cab \(name) is on the line"
            case let .lineRefused(name, error, reason):
                return "cab \(name) asked for a line and was refused: \(error), \(reason)"
            case let .lineHandedOver(name, line):
                return "\(line.name) (\(line.id), \(line.rev)) handed to cab \(name)"
            case let .cabJoined(name, number, track, uM, withdrawn):
                let taken = withdrawn.isEmpty ? "" : ", in place of " + withdrawn.map { String(format: "%02d", $0) }.joined(separator: ", ")
                return String(format: "cab %@ joined as rame %02d on track %d at %.1f m%@", name, number, track, uM, taken)
            case let .cabLeft(name, number, reason):
                return String(format: "cab %@ left service (%@), rame %02d", name, reason, number)
            case let .cabSilent(name, number):
                return String(format: "cab %@ is silent: rame %02d held as an obstacle", name, number)
            case let .cabHeardAgain(name, number):
                return String(format: "cab %@ is heard again, rame %02d", name, number)
            case let .cabHandedBack(name, number, automatic):
                return String(format: "rame %02d of cab %@ handed back to automation as rame %02d", number, name, automatic)
            case let .cabDisconnected(name):
                return "cab \(name) disconnected"
            case let .cabEmergencyBrake(name, number, applied, cause):
                return "cab \(name)\(rame(number)): emergency brake \(applied ? "applied" : "released")" + (cause.map { ", \($0)" } ?? "")
            case let .cabReport(name, number, code, text):
                return "cab \(name)\(rame(number)) reports: \(code?.rawValue ?? "?")" + (text.map { ", \($0)" } ?? "")
            case let .cabCall(name, number):
                return "cab \(name)\(rame(number)) calls the centre"
            case let .cabAcknowledge(name, number):
                return "cab \(name)\(rame(number)) acknowledges"
            case let .commandRefused(name, number, command, error):
                return "cab \(name)\(rame(number)) refused \(command)" + (error.map { ": \($0)" } ?? "")
            }
        }
    }

    /// A message the engine has for a connection.
    public struct Outbound: Sendable, Equatable {
        public var session: SessionID
        public var message: CabineWire.PCCMessage
        /// The connection is to be closed once this has gone.
        public var thenClose: Bool
    }
}

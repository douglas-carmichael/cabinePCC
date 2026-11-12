import Foundation

/// The PCC end of the Cabine link: the engine that keeps the lines and runs one of them for the cabs
/// connected to it (`CabinePCC.Engine`), and the server that puts that engine on the network
/// (`CabinePCC.Server`). The wire they speak is `CabineWire`.
public enum CabinePCC {

    /// One connection, as its host names it. The engine never looks inside.
    public struct SessionID: Hashable, Sendable, CustomStringConvertible {
        public let value: Int

        public init(_ value: Int) { self.value = value }

        public var description: String { "#\(value)" }
    }

    /// What a PCC is set up with. Everything about a line comes with its package; these are the PCC's own.
    public struct Settings: Sendable {
        /// The PCC's name, for the cabs' displays and for Bonjour.
        public var name = "PCC"
        /// The `app` of its `hello`.
        public var app = "CabinePCC"
        /// The `pcc.id` of its `hello`.
        public var pccID = UUID().uuidString
        /// Seconds between trains each way that the fleet is sized for.
        public var headwayS = 150.0
        /// Trains on the line, cabs included, when the operator fixes their number; nil sizes the fleet
        /// from the headway.
        public var fleetSize: Int?
        /// Seconds a rame spends out of sight beyond a terminus before it comes out on the other track.
        public var turnBackS = 60.0
        /// The line's time of day when a line is taken up: 08:42:00.
        public var clockStartS = 8.0 * 3_600 + 42 * 60
        /// Whether a line is in service as soon as it is taken up.
        public var serviceOnAtTakeUp = true
        /// The periods and timeouts of the link, as the PCC's `hello` states them.
        public var link = CabineWire.LinkTimings()
        /// How long an authority stands without being renewed.
        public var authorityValidS = 3.0
        /// How many lines the library holds at most.
        public var libraryLimit = 64

        public init() {}

        /// The headways an operator may ask for, in seconds, and the fleet sizes.
        public static let headwayRange = 30.0...3_600.0
        public static let fleetRange = 2...CabineWire.fleetNumbers.upperBound
    }

    /// Why an operator's order was not carried out.
    public enum OrderError: Error, Equatable, Sendable, CustomStringConvertible {
        case noLine
        case noSuchRame(Int)
        case notACab(Int)
        /// The cab's train is on the line, but its connection is gone.
        case cabNotConnected(Int)
        case badValue(String)
        /// A cab is in service on the present line.
        case lineInUse
        /// The description of a line fails the PCC's checks; the reason says where.
        case badLine(String)
        /// The library holds no line of that id and revision.
        case noSuchLine

        public var description: String {
            switch self {
            case .noLine: "the PCC is on no line"
            case let .noSuchRame(number): "no rame \(number) on the line"
            case let .notACab(number): "rame \(number) is not a cab"
            case let .cabNotConnected(number): "the cab of rame \(number) is not connected"
            case let .badValue(reason): reason
            case .lineInUse: "a cab is in service on the present line"
            case let .badLine(reason): "bad line: \(reason)"
            case .noSuchLine: "the library holds no such line"
            }
        }
    }
}

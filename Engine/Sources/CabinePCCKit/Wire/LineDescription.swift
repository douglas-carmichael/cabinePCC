import Foundation

extension CabineWire {

    /// The description of a line: the line as the PCC runs it. Its two tracks, where trains stop on each,
    /// the speed limits, the beacons, and the figures of its stock and its moving block. It is one of the
    /// two things in a `LinePackage`, and the PCC's engine works on nothing else. Positions are `uM`,
    /// metres along a track from the buffer stops it starts at.
    ///
    /// Only what the specification requires is required here. `train`, `cbtc`, `dwell` and each of their
    /// fields may be left out, and then take the values the specification shows (`defaultTrain` and the
    /// others below). Whether the figures make a line a PCC can run is for the PCC to say: see
    /// `CabinePCC.Line`.
    public struct LineDescription: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// A revision of the geometry, an opaque string that Cabine makes.
        public var rev: String
        /// Length of each track, tail tracks included.
        public var lengthM: Double
        /// The line's roundel, RRGGBB.
        public var colour: String?
        public var textColour: String?
        /// The limit outside every zone; `train.maxSpeedMS` when left out.
        public var lineSpeedMS: Double?
        public var train: Train?
        public var cbtc: CBTC?
        public var dwell: Dwell?
        /// How far short of the end of a track a train stops before it turns back.
        public var endBufferM: Double?
        /// The stations, in the order track 1 meets them.
        public var stations: [Station]
        /// Exactly two: `track` 1 and `track` 2.
        public var tracks: [Track]

        public init(id: String, name: String, rev: String, lengthM: Double, colour: String? = nil,
                    textColour: String? = nil, lineSpeedMS: Double? = nil, train: Train? = nil, cbtc: CBTC? = nil,
                    dwell: Dwell? = nil, endBufferM: Double? = nil, stations: [Station], tracks: [Track]) {
            self.id = id
            self.name = name
            self.rev = rev
            self.lengthM = lengthM
            self.colour = colour
            self.textColour = textColour
            self.lineSpeedMS = lineSpeedMS
            self.train = train
            self.cbtc = cbtc
            self.dwell = dwell
            self.endBufferM = endBufferM
            self.stations = stations
            self.tracks = tracks
        }

        /// The stock of the line, which the automatic rames are made of.
        public struct Train: Codable, Equatable, Sendable {
            public var lengthM: Double?
            public var maxSpeedMS: Double?
            public var accelerationMS2: Double?
            public var serviceBrakeMS2: Double?
            public var emergencyBrakeMS2: Double?
            /// The deceleration its automatic driver comes down to a limit or a stop with.
            public var approachDecelMS2: Double?
            /// How far under a limit it settles.
            public var marginMS: Double?
            public var capacity: Int?

            public init(lengthM: Double? = nil, maxSpeedMS: Double? = nil, accelerationMS2: Double? = nil,
                        serviceBrakeMS2: Double? = nil, emergencyBrakeMS2: Double? = nil,
                        approachDecelMS2: Double? = nil, marginMS: Double? = nil, capacity: Int? = nil) {
                self.lengthM = lengthM
                self.maxSpeedMS = maxSpeedMS
                self.accelerationMS2 = accelerationMS2
                self.serviceBrakeMS2 = serviceBrakeMS2
                self.emergencyBrakeMS2 = emergencyBrakeMS2
                self.approachDecelMS2 = approachDecelMS2
                self.marginMS = marginMS
                self.capacity = capacity
            }
        }

        /// The figures of the moving block, as Cabine applies them.
        public struct CBTC: Codable, Equatable, Sendable {
            /// The margin kept behind the train ahead.
            public var safetyMarginM: Double?
            /// How far short of the end of its authority an automatic driver stops.
            public var stoppingShortM: Double?
            /// How far an authority reaches at most.
            public var horizonM: Double?
            /// The room a train needs ahead of it to leave a platform.
            public var departureRoomM: Double?
            /// What a train's report of its position may be out by: a base, more for every metre run since
            /// its last beacon, and a ceiling.
            public var uncertaintyBaseM: Double?
            public var uncertaintyPerM: Double?
            public var uncertaintyMaxM: Double?

            public init(safetyMarginM: Double? = nil, stoppingShortM: Double? = nil, horizonM: Double? = nil,
                        departureRoomM: Double? = nil, uncertaintyBaseM: Double? = nil, uncertaintyPerM: Double? = nil,
                        uncertaintyMaxM: Double? = nil) {
                self.safetyMarginM = safetyMarginM
                self.stoppingShortM = stoppingShortM
                self.horizonM = horizonM
                self.departureRoomM = departureRoomM
                self.uncertaintyBaseM = uncertaintyBaseM
                self.uncertaintyPerM = uncertaintyPerM
                self.uncertaintyMaxM = uncertaintyMaxM
            }
        }

        /// A station stop of an automatic rame.
        public struct Dwell: Codable, Equatable, Sendable {
            /// The range its doors stay open.
            public var minS: Double?
            public var maxS: Double?
            /// The stop at the last station of a track.
            public var terminusS: Double?
            public var doorsOpenS: Double?
            public var doorsCloseS: Double?
            /// From the doors beginning to close to the rame moving off.
            public var departS: Double?

            public init(minS: Double? = nil, maxS: Double? = nil, terminusS: Double? = nil, doorsOpenS: Double? = nil,
                        doorsCloseS: Double? = nil, departS: Double? = nil) {
                self.minS = minS
                self.maxS = maxS
                self.terminusS = terminusS
                self.doorsOpenS = doorsOpenS
                self.doorsCloseS = doorsCloseS
                self.departS = departS
            }
        }

        public struct Station: Codable, Equatable, Sendable {
            public var name: String

            public init(name: String) { self.name = name }
        }

        public struct Track: Codable, Equatable, Sendable {
            /// 1, the forward direction, or 2, the way back.
            public var track: Int
            /// Where the nose of a train comes to rest at each station, in the order of travel.
            public var stopsM: [Double]
            public var zones: [Zone]?
            /// Where a train sets its position right.
            public var beaconsM: [Double]?

            public init(track: Int, stopsM: [Double], zones: [Zone]? = nil, beaconsM: [Double]? = nil) {
                self.track = track
                self.stopsM = stopsM
                self.zones = zones
                self.beaconsM = beaconsM
            }
        }

        /// A speed limit lower than the line's, from `fromM` to `toM` on its track. It holds while any part
        /// of a train is inside.
        public struct Zone: Codable, Equatable, Sendable {
            public var fromM: Double
            public var toM: Double
            public var limitMS: Double

            public init(fromM: Double, toM: Double, limitMS: Double) {
                self.fromM = fromM
                self.toM = toM
                self.limitMS = limitMS
            }
        }

        public var identity: LineIdentity { LineIdentity(id: id, rev: rev, name: name) }

        // MARK: The values the specification shows

        public static let defaultTrain = Train(lengthM: 75, maxSpeedMS: 19.444, accelerationMS2: 1.25, serviceBrakeMS2: 1.25,
                                               emergencyBrakeMS2: 1.78, approachDecelMS2: 0.6, marginMS: 1.3, capacity: 560)
        public static let defaultCBTC = CBTC(safetyMarginM: 25, stoppingShortM: 6, horizonM: 1_500, departureRoomM: 40,
                                             uncertaintyBaseM: 1.5, uncertaintyPerM: 0.02, uncertaintyMaxM: 8)
        public static let defaultDwell = Dwell(minS: 17, maxS: 27, terminusS: 30, doorsOpenS: 2.2, doorsCloseS: 2.4, departS: 4.2)
        public static let defaultEndBufferM = 28.0

        // MARK: Files

        /// Reads the description out of the bytes of a `.line.json` file, whatever `LinePackage.decode(file:)`
        /// reads: a package, or a bare description. Throws a `DecodeFailure` that names what is missing or
        /// of the wrong kind.
        public static func decode(file data: Data) throws -> LineDescription {
            try LinePackage.decode(file: data).description
        }

        /// The bare description as the bytes of a file, laid out to be read. A `.line.json` file is a
        /// package: see `LinePackage.encodedForFile()`.
        public func encodedForFile() -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(self)) ?? Data("{}".utf8)
        }
    }
}

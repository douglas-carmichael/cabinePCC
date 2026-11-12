import Foundation

extension CabinePCC {

    /// Why a line description was not taken up.
    public struct LineRefusal: Error, Equatable, Sendable, CustomStringConvertible {
        public let reason: String

        public init(reason: String) { self.reason = reason }

        public var description: String { reason }
    }

    /// A line the PCC can run: a description that has passed the PCC's checks, with every figure it left
    /// out settled and its two tracks put in order.
    ///
    /// The PCC lays the two tracks end to end as one loop, track 1 from 0 to `lengthM` and then track 2.
    /// A train on track 2 at `uM` is at `lengthM + uM` round the loop, and the loop is `2 × lengthM` long.
    public struct Line: Sendable {
        public let description: CabineWire.LineDescription
        public let identity: CabineWire.LineIdentity
        /// Length of each track, tail tracks included.
        public let lengthM: Double
        /// The stations, in the order track 1 meets them.
        public let stationNames: [String]
        /// The limit outside every zone, and never more than the stock can do.
        public let lineSpeedMS: Double
        public let train: Train
        public let cbtc: CBTC
        public let dwell: Dwell
        public let endBufferM: Double
        /// `tracks[0]` is track 1 and `tracks[1]` track 2.
        public let tracks: [Track]

        public struct Train: Sendable, Equatable {
            public let lengthM: Double
            public let maxSpeedMS: Double
            public let accelerationMS2: Double
            public let serviceBrakeMS2: Double
            public let emergencyBrakeMS2: Double
            public let approachDecelMS2: Double
            public let marginMS: Double
            public let capacity: Int
        }

        public struct CBTC: Sendable, Equatable {
            public let safetyMarginM: Double
            public let stoppingShortM: Double
            public let horizonM: Double
            public let departureRoomM: Double
            public let uncertaintyBaseM: Double
            public let uncertaintyPerM: Double
            public let uncertaintyMaxM: Double
        }

        public struct Dwell: Sendable, Equatable {
            public let minS: Double
            public let maxS: Double
            public let terminusS: Double
            public let doorsOpenS: Double
            public let doorsCloseS: Double
            public let departS: Double
        }

        public struct Zone: Sendable, Equatable {
            public let fromM: Double
            public let toM: Double
            public let limitMS: Double
        }

        public struct Track: Sendable, Equatable {
            /// 1 or 2.
            public let number: Int
            /// Where the nose of a train comes to rest at each station, in the order of travel.
            public let stopsM: [Double]
            /// In the order a train meets them.
            public let zones: [Zone]
            public let beaconsM: [Double]
        }

        // MARK: Geometry

        public var stationCount: Int { stationNames.count }

        /// Where a rame stops before it turns back, and where a cab's authority ends at the latest.
        public var endOfTrackM: Double { lengthM - endBufferM }

        /// Where the nose of a rame is when it comes out of the tail: its rear `endBufferM` clear of the
        /// buffer stops.
        public var tailExitM: Double { train.lengthM + endBufferM }

        public var loopLengthM: Double { 2 * lengthM }

        /// What an automatic rame keeps between its nose and the rear of the train ahead when it stops
        /// behind it: the safety margin, and the little it stops short of the end of its leave.
        public var followingDistanceM: Double { cbtc.safetyMarginM + cbtc.stoppingShortM }

        public func track(_ number: Int) -> Track { tracks[number == 2 ? 1 : 0] }

        public func otherTrack(_ number: Int) -> Int { number == 2 ? 1 : 2 }

        /// A position round the loop the two tracks make.
        public func loopPosition(track: Int, uM: Double) -> Double { track == 2 ? lengthM + uM : uM }

        /// Index into `stationNames` of a stop of a track, counted in that track's order of travel.
        public func stationIndex(track: Int, stop: Int) -> Int { track == 2 ? stationCount - 1 - stop : stop }

        public func stationName(track: Int, stop: Int) -> String? {
            let index = stationIndex(track: track, stop: stop)
            return stationNames.indices.contains(index) ? stationNames[index] : nil
        }

        /// The lowest limit anywhere under a train whose nose is at `noseM`: a zone's limit holds while
        /// any part of the train is inside it.
        public func speedLimit(track: Int, noseM: Double) -> Double {
            let tail = noseM - train.lengthM
            var limit = lineSpeedMS
            for zone in self.track(track).zones {
                if zone.fromM > noseM { break }
                if zone.toM >= tail { limit = min(limit, zone.limitMS) }
            }
            return limit
        }

        /// What a train's report of its position may be out by, with its nose at `noseM`: a base, more
        /// for every metre run since the last beacon it passed, and a ceiling.
        public func uncertainty(track: Int, noseM: Double) -> Double {
            let beacons = self.track(track).beaconsM
            // The last beacon at or behind the nose; a train that has passed none counts from the buffers.
            var low = 0, high = beacons.count
            while low < high {
                let middle = (low + high) / 2
                if beacons[middle] <= noseM { low = middle + 1 } else { high = middle }
            }
            let beacon = low > 0 ? beacons[low - 1] : 0
            return min(cbtc.uncertaintyBaseM + cbtc.uncertaintyPerM * max(noseM - beacon, 0), cbtc.uncertaintyMaxM)
        }

        /// Index of the stop of a track at which a train whose nose is at `noseM` stands, within
        /// `tolerance` metres either way.
        public func stop(track: Int, near noseM: Double, tolerance: Double) -> Int? {
            let stops = self.track(track).stopsM
            var best: Int?
            for (index, stop) in stops.enumerated() where abs(stop - noseM) <= tolerance {
                if best == nil || abs(stop - noseM) < abs(stops[best!] - noseM) { best = index }
            }
            return best
        }

        // MARK: Checks

        /// Checks a description and settles what it left out. Throws a `LineRefusal` that says what is
        /// wrong with it.
        public init(_ description: CabineWire.LineDescription) throws {
            typealias Description = CabineWire.LineDescription

            func number(_ value: Double) -> String {
                value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
            }
            func within(_ value: Double, _ name: String, _ range: ClosedRange<Double>) throws -> Double {
                guard value.isFinite, range.contains(value) else {
                    throw LineRefusal(reason: "\(name) must lie between \(number(range.lowerBound)) and \(number(range.upperBound))")
                }
                return value
            }
            func named(_ text: String, _ name: String, limit: Int) throws {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw LineRefusal(reason: "\(name) is empty") }
                guard text.count <= limit else { throw LineRefusal(reason: "\(name) is longer than \(limit) characters") }
            }
            func colour(_ text: String?, _ name: String) throws {
                guard let text else { return }
                guard text.count == 6, text.allSatisfy(\.isHexDigit) else {
                    throw LineRefusal(reason: "\(name) must be six hexadecimal digits, RRGGBB")
                }
            }

            try named(description.id, "id", limit: 64)
            try named(description.name, "name", limit: 128)
            try named(description.rev, "rev", limit: 128)
            try colour(description.colour, "colour")
            try colour(description.textColour, "textColour")
            let length = try within(description.lengthM, "lengthM", 100...100_000)

            guard (2...128).contains(description.stations.count) else {
                throw LineRefusal(reason: "stations must number 2 to 128")
            }
            for (index, station) in description.stations.enumerated() {
                try named(station.name, "stations[\(index)].name", limit: 128)
            }

            // The stock, the moving block and the station stop: what is given, or else what the
            // specification shows.
            let t = description.train ?? Description.Train(), td = Description.defaultTrain
            let serviceBrake = try within(t.serviceBrakeMS2 ?? td.serviceBrakeMS2!, "train.serviceBrakeMS2", 0.1...5)
            let emergencyBrake = try within(t.emergencyBrakeMS2 ?? td.emergencyBrakeMS2!, "train.emergencyBrakeMS2", 0.1...10)
            let capacity = t.capacity ?? td.capacity!
            guard capacity >= 0 else { throw LineRefusal(reason: "train.capacity must not be negative") }
            let train = Train(
                lengthM: try within(t.lengthM ?? td.lengthM!, "train.lengthM", 10...500),
                maxSpeedMS: try within(t.maxSpeedMS ?? td.maxSpeedMS!, "train.maxSpeedMS", 2...100),
                accelerationMS2: try within(t.accelerationMS2 ?? td.accelerationMS2!, "train.accelerationMS2", 0.1...5),
                serviceBrakeMS2: serviceBrake,
                emergencyBrakeMS2: emergencyBrake,
                // The automatic driver must be able to hold the deceleration it plans on.
                approachDecelMS2: try within(t.approachDecelMS2 ?? td.approachDecelMS2!, "train.approachDecelMS2",
                                             0.05...min(serviceBrake, emergencyBrake)),
                marginMS: try within(t.marginMS ?? td.marginMS!, "train.marginMS", 0...10),
                capacity: capacity)

            let c = description.cbtc ?? Description.CBTC(), cd = Description.defaultCBTC
            let uncertaintyBase = try within(c.uncertaintyBaseM ?? cd.uncertaintyBaseM!, "cbtc.uncertaintyBaseM", 0...100)
            let cbtc = CBTC(
                safetyMarginM: try within(c.safetyMarginM ?? cd.safetyMarginM!, "cbtc.safetyMarginM", 1...1_000),
                stoppingShortM: try within(c.stoppingShortM ?? cd.stoppingShortM!, "cbtc.stoppingShortM", 0...100),
                horizonM: try within(c.horizonM ?? cd.horizonM!, "cbtc.horizonM", 10...1_000_000),
                departureRoomM: try within(c.departureRoomM ?? cd.departureRoomM!, "cbtc.departureRoomM", 0...10_000),
                uncertaintyBaseM: uncertaintyBase,
                uncertaintyPerM: try within(c.uncertaintyPerM ?? cd.uncertaintyPerM!, "cbtc.uncertaintyPerM", 0...1),
                uncertaintyMaxM: try within(c.uncertaintyMaxM ?? cd.uncertaintyMaxM!, "cbtc.uncertaintyMaxM", uncertaintyBase...1_000))

            let w = description.dwell ?? Description.Dwell(), wd = Description.defaultDwell
            let dwellMin = try within(w.minS ?? wd.minS!, "dwell.minS", 0...3_600)
            let dwell = Dwell(
                minS: dwellMin,
                maxS: try within(w.maxS ?? wd.maxS!, "dwell.maxS", dwellMin...3_600),
                terminusS: try within(w.terminusS ?? wd.terminusS!, "dwell.terminusS", 0...3_600),
                doorsOpenS: try within(w.doorsOpenS ?? wd.doorsOpenS!, "dwell.doorsOpenS", 0.1...60),
                doorsCloseS: try within(w.doorsCloseS ?? wd.doorsCloseS!, "dwell.doorsCloseS", 0.1...60),
                departS: try within(w.departS ?? wd.departS!, "dwell.departS", 0...600))

            let endBuffer = try within(description.endBufferM ?? Description.defaultEndBufferM, "endBufferM", 0...1_000)
            let lineSpeed = try within(description.lineSpeedMS ?? train.maxSpeedMS, "lineSpeedMS", 2...100)

            // A rame standing at the end of a track and one that has just come out at its start must both
            // fit, with the moving-block margin between them.
            let following = cbtc.safetyMarginM + cbtc.stoppingShortM
            let least = 2 * (train.lengthM + endBuffer) + following
            guard length >= least else {
                throw LineRefusal(reason: "lengthM is too short for the train: it must be at least \(number(least.rounded(.up)))")
            }

            guard description.tracks.count == 2,
                  let first = description.tracks.first(where: { $0.track == 1 }),
                  let second = description.tracks.first(where: { $0.track == 2 }) else {
                throw LineRefusal(reason: "tracks must be exactly two, track 1 and track 2")
            }

            var tracks: [Track] = []
            for given in [first, second] {
                let name = "track \(given.track)"
                guard given.stopsM.count == description.stations.count else {
                    throw LineRefusal(reason: "\(name): stopsM has \(given.stopsM.count) stops for \(description.stations.count) stations")
                }
                guard given.stopsM.allSatisfy(\.isFinite) else { throw LineRefusal(reason: "\(name): stopsM must be numbers") }
                for (index, stop) in given.stopsM.enumerated() where index > 0 {
                    guard stop > given.stopsM[index - 1] else { throw LineRefusal(reason: "\(name): stopsM must rise") }
                }
                // A rame comes out of the tail with its nose a train and a buffer from the start of the
                // track, and goes back into it a buffer short of the end: the stops lie between the two.
                guard given.stopsM[0] >= train.lengthM + endBuffer else {
                    throw LineRefusal(reason: "\(name): the first stop must be at least \(number(train.lengthM + endBuffer)) m from the start of the track")
                }
                guard given.stopsM[given.stopsM.count - 1] <= length - endBuffer else {
                    throw LineRefusal(reason: "\(name): the last stop must be at least \(number(endBuffer)) m from the end of the track")
                }

                let declared = given.zones ?? []
                guard declared.count <= 4_096 else { throw LineRefusal(reason: "\(name): more than 4096 zones") }
                var zones: [Zone] = []
                for (index, zone) in declared.enumerated() {
                    let zoneName = "\(name): zones[\(index)]"
                    guard zone.fromM.isFinite, zone.toM.isFinite, zone.fromM < zone.toM else {
                        throw LineRefusal(reason: "\(zoneName): fromM must be less than toM")
                    }
                    let limit = try within(zone.limitMS, "\(zoneName).limitMS", 1...100)
                    // What reaches beyond the ends of the track is cut off; a zone wholly outside it is dropped.
                    let from = max(zone.fromM, 0), to = min(zone.toM, length)
                    if from < to { zones.append(Zone(fromM: from, toM: to, limitMS: limit)) }
                }
                zones.sort { $0.fromM < $1.fromM }

                let beacons = given.beaconsM ?? []
                guard beacons.count <= 8_192 else { throw LineRefusal(reason: "\(name): more than 8192 beacons") }
                guard beacons.allSatisfy(\.isFinite) else { throw LineRefusal(reason: "\(name): beaconsM must be numbers") }
                for (index, beacon) in beacons.enumerated() where index > 0 {
                    guard beacon >= beacons[index - 1] else { throw LineRefusal(reason: "\(name): beaconsM must rise") }
                }

                tracks.append(Track(number: given.track, stopsM: given.stopsM, zones: zones,
                                    beaconsM: beacons.filter { $0 >= 0 && $0 <= length }))
            }

            self.description = description
            identity = description.identity
            lengthM = length
            stationNames = description.stations.map(\.name)
            lineSpeedMS = min(lineSpeed, train.maxSpeedMS)
            self.train = train
            self.cbtc = cbtc
            self.dwell = dwell
            endBufferM = endBuffer
            self.tracks = tracks
        }
    }
}

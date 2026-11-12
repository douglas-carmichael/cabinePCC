import Foundation

extension CabinePCC {

    /// The simulation behind the wire: the library of lines, the line the PCC is on, the automatic rames
    /// on it, the moving block that keeps every train apart, and what each cab is told.
    ///
    /// It has no sockets and no clock of its own. Its host steps it (`step`), hands it what each
    /// connection sends (`open`, `receive`, `close`), asks it for the messages that go out at a fixed rate
    /// (`broadcastTraffic`, `broadcastInfo`, `broadcastPing`) and takes what it has to send (`takeOutbox`).
    /// The same host, or its operator, reads `snapshot()` and `takeJournal()`, keeps the library and gives
    /// the orders of Engine+Host.swift.
    ///
    /// It is not safe to use from two threads at once: `Server` keeps it to one queue. Given the same seed
    /// and the same calls it does the same thing every time.
    public final class Engine {

        // MARK: Parts

        /// What an automatic rame is doing.
        enum Phase {
            case running
            /// At a platform, doors opening or open.
            case dwelling
            /// Doors closing, and the pause before it moves off.
            case departing
            /// Doors shut, kept at the platform until it may leave.
            case waiting
            /// Out of sight beyond a terminus, standing at the end of the track it has left.
            case tail
        }

        /// One train of the line.
        struct Train {
            let id: Int
            var number: Int
            var track: Int
            var body: Body
            var phase = Phase.running
            /// Index, in its track's order of travel, of the stop it stands at or runs to next; the number
            /// of stops once it has served the last.
            var stop: Int
            var timer = 0.0
            /// 0 shut to 1 open.
            var doors = 0.0
            /// The operator's orders for it.
            var holdOrdered = false
            var brakeOrdered = false
            /// Where it is to come to rest because line service went off while it ran.
            var serviceStop: Double?
            /// The first zone of its track that its driver still has to mind: those before it lie behind
            /// the train for good.
            var zoneCursor = 0
            /// The cab that drives it; nil for an automatic rame.
            var cab: CabLink?
        }

        /// What the engine knows of the cab that drives a train. A reference, so that a train stays
        /// light to copy: there is one of these for a cab's train and none for an automatic rame.
        final class CabLink {
            var cabID: String
            var name: String
            /// Its connection; nil once that has gone.
            var session: SessionID?
            var heardAt: Double
            /// Nothing has been heard from it for the link's timeout: its train is held as an obstacle.
            var silent = false
            /// Its last `position`: where, how fast, and when by the engine's time.
            var reportUM: Double
            var reportSpeed = 0.0
            var reportAcceleration = 0.0
            var reportAt: Double
            var status: CabineWire.Status?
            var emergency = false
            var emergencyCause: String?
            /// When its doors were last seen to have closed.
            var doorsShutAt: Double?
            /// The last authority sent to it, and when.
            var sent: CabineWire.Authority?
            var sentAt = -Double.infinity
            /// Where its authority is cut back to while the operator holds it, the line is out of service
            /// or a general emergency stop is on.
            var restrictedEnd: Double?
            /// The operator's hold has caught it standing at a platform.
            var holdLatched = false
            var lastReport: Report?

            init(cabID: String, name: String, session: SessionID?, heardAt: Double, reportUM: Double, reportAt: Double) {
                self.cabID = cabID
                self.name = name
                self.session = session
                self.heardAt = heardAt
                self.reportUM = reportUM
                self.reportAt = reportAt
            }
        }

        /// One connection.
        struct Link {
            let id: SessionID
            var peer: String
            var hello: CabineWire.CabHello?
            var cabID: String
            var name: String
            /// The line it says it holds; nil if it holds none.
            var line: CabineWire.LineIdentity?
            /// That line is the PCC's.
            var onLine = false
            var heardAt: Double
            var roundTripS: Double?
            var authoritySeq = 0
            /// When a report from it was last turned away, so that a cab that reports out of service is
            /// not answered five times a second.
            var refusedAt = -Double.infinity
        }

        /// A line of the library: the package as it was given, and the line made of its description.
        struct Held {
            var package: CabineWire.LinePackage
            var line: Line
        }

        // MARK: State

        public internal(set) var settings: Settings
        var random: SeededRandom
        /// Seconds the engine has been stepped for: the `tS` of what it sends.
        var time = 0.0
        /// The line's time of day.
        var clock: Double
        var line: Line?
        var stock: Stock?
        var driver: Driver?
        /// The lines the PCC holds, in the order they were kept. The line it is on is one of them.
        var library: [Held] = []
        var trains: [Train] = []
        var links: [Link] = []
        var outbox: [Outbound] = []
        var journal: [JournalEntry] = []
        /// Line service, and the general emergency stop: of the line the PCC is on, and off while it is
        /// on none.
        var inService = false
        var emergencyStop = false
        var lapTimeS = 0.0
        var nextTrainID = 1
        var pingCount = 0
        var commandCount = 0
        /// Commands sent to cabs and not yet answered.
        var pendingCommands: [(id: CabineWire.MessageID, session: SessionID, command: CabineWire.CommandName)] = []
        /// Seconds before another rame may be put on each track from its tail.
        var injectionWait = [0.0, 0.0]
        var injectOnTrack2 = false
        /// Set on the engine that measures a lap: where its one rame called, and when.
        var probe: [(track: Int, stop: Int, at: Double)]?

        // MARK: Figures of the engine's own

        /// The longest step the simulation takes at once, in seconds: a longer `dt` is cut up.
        static let longestStep = 0.05
        /// A rame has made its stop when it is at rest this near it, in metres.
        static let stopTolerance = 1.0
        /// A rame is taken into the tail when it is at rest this near the end of its track, in metres.
        static let tailTolerance = 2.0
        /// A stop is prolonged now and then: how often, and by how many seconds.
        static let dawdleChance = 0.14
        static let dawdleS = 15.0...32.0
        /// For how long after a cab's report its train is carried on at the speed it reported, in seconds.
        static let reckoningS = 0.5
        /// A train within this many metres of a stop, at rest, is taken to stand at its platform.
        static let platformReach = 5.0

        // MARK: Life

        /// - Parameters:
        ///   - settings: the PCC's own settings.
        ///   - seed: what its random draws come from: the same seed gives the same run.
        public init(settings: Settings = Settings(), seed: UInt64 = 1) {
            self.settings = settings
            random = SeededRandom(seed)
            clock = settings.clockStartS
        }

        // MARK: Stepping

        /// Advances the simulation by `dt` seconds.
        public func step(_ dt: Double) {
            guard dt.isFinite, dt > 0 else { return }
            let pieces = max(1, Int((dt / Engine.longestStep - 1e-9).rounded(.up)))
            let h = dt / Double(pieces)
            for _ in 0..<pieces { advance(h) }
        }

        private func advance(_ h: Double) {
            time += h
            guard let line else { return }
            clock += h
            if clock >= 86_400 { clock -= 86_400 }
            superviseCabs(line)
            regulateFleet(h, line)
            // Where every nose is round the loop, kept beside the trains while they are driven: each
            // rame looks for the train ahead of it at every step.
            var noses = [Double]()
            noses.reserveCapacity(trains.count)
            var index = 0
            while index < trains.count {
                noses.append(line.loopPosition(track: trains[index].track, uM: trains[index].body.position))
                index += 1
            }
            index = 0
            while index < trains.count {
                if trains[index].cab == nil, !drive(index, h, line, &noses) {
                    trains.remove(at: index)
                    noses.remove(at: index)
                } else {
                    index += 1
                }
            }
            sendAuthorities(h, line)
        }

        // MARK: The fleet

        var cabCount: Int {
            var count = 0, index = 0
            while index < trains.count {
                if trains[index].cab != nil { count += 1 }
                index += 1
            }
            return count
        }
        var automaticCount: Int { trains.count - cabCount }

        /// How many trains the line is to carry, cabs included: one every `headwayS` each way, which is
        /// the time of a lap divided by the headway, unless the operator has fixed their number.
        var fleetTarget: Int {
            guard let line, lapTimeS > 0 else { return 0 }
            let wanted = settings.fleetSize ?? Int((lapTimeS / settings.headwayS).rounded())
            // No more than the loop can hold and still move: a train for every three train-and-margin
            // lengths of it.
            let room = Int(line.loopLengthM / (3 * (line.train.lengthM + line.followingDistanceM)))
            return min(wanted, max(room, 2), CabineWire.fleetNumbers.upperBound)
        }

        /// How many of those are to be automatic rames: the rest of the fleet, at least 2, and never more
        /// than the fleet's numbers allow beside the cabs.
        var automaticTarget: Int { automaticTarget(beside: cabCount) }

        private func automaticTarget(beside cabs: Int) -> Int {
            max(min(max(fleetTarget - cabs, 2), CabineWire.fleetNumbers.upperBound - cabs), 0)
        }

        /// The lowest number of the fleet that no train bears; beyond the fleet if all of it is out.
        func freeNumber() -> Int {
            for number in CabineWire.rameNumbers where !trains.contains(where: { $0.number == number }) { return number }
            return 0
        }

        func newTrainID() -> Int {
            defer { nextTrainID += 1 }
            return nextTrainID
        }

        /// How long an automatic rame's doors stay open at a stop that is not the last of its track.
        func drawDwell(_ line: Line) -> Double {
            let mean = (line.dwell.minS + line.dwell.maxS) / 2
            // The lone rame that measures a lap takes the average stop.
            if probe != nil { return mean + Engine.dawdleChance * (Engine.dawdleS.lowerBound + Engine.dawdleS.upperBound) / 2 }
            var dwell = random.range(line.dwell.minS, line.dwell.maxS)
            if random.chance(Engine.dawdleChance) { dwell += random.range(Engine.dawdleS.lowerBound, Engine.dawdleS.upperBound) }
            return dwell
        }

        /// The metres from the nose of one train to the rear of the train next ahead of it round the
        /// loop, given where every nose is round it: less than nothing when the two overlap, and nil when
        /// it is alone on the line.
        private func rearGap(ahead index: Int, _ noses: [Double], _ line: Line) -> Double? {
            let loop = line.loopLengthM
            let nose = noses[index]
            var least = Double.infinity
            // A plain loop: this runs for every rame at every step, and an unoptimised build is slow
            // to iterate any other way.
            var other = 0
            let count = noses.count
            while other < count {
                if other != index {
                    var ahead = noses[other] - nose
                    if ahead < 0 { ahead += loop }
                    if ahead < least { least = ahead }
                }
                other += 1
            }
            return least.isFinite ? least - line.train.lengthM : nil
        }

        /// True when a rame may come out of the tail onto a track: the way to that track's first stop is
        /// clear of every train by the moving-block margin.
        private func wayOutClear(onto track: Int, _ line: Line) -> Bool {
            let clearBeyond = line.track(track).stopsM[0] + line.followingDistanceM
            let length = line.train.lengthM
            return !trains.contains {
                $0.track == track && ($0.cab != nil || $0.phase != .tail) && $0.body.position - length <= clearBeyond
            }
        }

        /// True when an automatic rame standing at a platform with its doors shut may leave it.
        private func mayLeave(_ index: Int, _ noses: [Double], _ line: Line) -> Bool {
            let train = trains[index]
            guard inService, !emergencyStop, !train.brakeOrdered, !train.holdOrdered else { return false }
            guard let gap = rearGap(ahead: index, noses, line) else { return true }
            return gap - line.cbtc.safetyMarginM >= line.cbtc.departureRoomM
        }

        /// Puts rames on the line from its tails while there are fewer than there should be. (When there
        /// are more, the next to reach a tail goes no further: see `drive`.)
        private func regulateFleet(_ h: Double, _ line: Line) {
            guard probe == nil else { return }
            injectionWait[0] = max(0, injectionWait[0] - h)
            injectionWait[1] = max(0, injectionWait[1] - h)
            guard inService, !emergencyStop else { return }
            let cabs = cabCount
            guard trains.count - cabs < automaticTarget(beside: cabs) else { return }
            for track in injectOnTrack2 ? [2, 1] : [1, 2] where injectionWait[track - 1] <= 0 {
                // A rame that is turning back onto that track comes out first.
                let turning = trains.contains { $0.cab == nil && $0.phase == .tail && line.otherTrack($0.track) == track }
                guard !turning, wayOutClear(onto: track, line) else { continue }
                trains.append(Train(id: newTrainID(), number: freeNumber(), track: track,
                                    body: Body(position: line.tailExitM), stop: 0))
                injectionWait[track - 1] = lapTimeS / Double(max(fleetTarget, 1))
                injectOnTrack2 = track == 1
                break
            }
        }

        /// Advances one automatic rame by `h`, and keeps its place among `noses` right. False when it has
        /// left the line.
        private func drive(_ index: Int, _ h: Double, _ line: Line, _ noses: inout [Double]) -> Bool {
            guard let stock, let driver else { return true }
            var train = trains[index]
            let track = line.track(train.track)
            let stops = track.stopsM
            let braked = emergencyStop || train.brakeOrdered

            switch train.phase {
            case .dwelling:
                train.doors = min(1, train.doors + h / line.dwell.doorsOpenS)
                train.timer -= h
                // Its stop is over when its time is up and its doors have opened: however short the stop
                // a line asks for, the doors open.
                if train.timer <= 0 && train.doors >= 1 {
                    if train.holdOrdered || !inService || braked {
                        // Kept at its platform with its doors open.
                        train.timer = 0
                    } else {
                        train.phase = .departing
                        train.timer = line.dwell.departS
                    }
                }
                trains[index] = train

            case .departing:
                train.doors = max(0, train.doors - h / line.dwell.doorsCloseS)
                train.timer -= h
                if train.timer <= 0 && train.doors <= 0 { train.phase = .waiting }
                trains[index] = train
                if train.phase == .waiting { leaveIfClear(index, noses, line) }

            case .waiting:
                leaveIfClear(index, noses, line)

            case .running:
                let nose = train.body.position
                let endOfTrack = line.endOfTrackM
                var target = train.stop < stops.count ? stops[train.stop] : endOfTrack
                // Its leave ends a margin short of the rear of the train ahead, and it stops a little
                // short of the end of its leave.
                if let gap = rearGap(ahead: index, noses, line) {
                    target = min(target, nose + gap - line.followingDistanceM)
                }
                if let serviceStop = train.serviceStop { target = min(target, serviceStop) }
                let command = driver.command(speed: train.body.speed, nose: nose, track: track, lineSpeed: line.lineSpeedMS,
                                             stopDistance: target - nose, cursor: &train.zoneCursor)
                train.body.step(dt: h, command: command, emergencyBrake: braked, stock: stock)

                if train.stop < stops.count, train.body.position > stops[train.stop] + Engine.stopTolerance {
                    // Past its stop, as only a train handed back at speed can be: on to the next.
                    train.stop += 1
                } else if train.body.isStopped {
                    if train.stop < stops.count {
                        if abs(train.body.position - stops[train.stop]) < Engine.stopTolerance {
                            // It has made its stop: it stands, and opens its doors.
                            train.phase = .dwelling
                            train.timer = train.stop == stops.count - 1 ? line.dwell.terminusS : drawDwell(line)
                            train.body.speed = 0
                            train.body.acceleration = 0
                            probe?.append((train.track, train.stop, time))
                        }
                    } else if train.body.position > endOfTrack - Engine.tailTolerance {
                        // Beyond the last platform, a buffer short of the end of the track: into the tail.
                        // That is where a rame the line has no more use for leaves it.
                        if probe == nil && automaticCount > automaticTarget { return false }
                        train.phase = .tail
                        train.timer = settings.turnBackS
                        train.body.speed = 0
                        train.body.acceleration = 0
                        train.body.effort = 0
                    }
                }
                trains[index] = train
                noses[index] = line.loopPosition(track: train.track, uM: train.body.position)

            case .tail:
                train.timer -= h
                if train.timer <= 0, inService, !braked {
                    let out = line.otherTrack(train.track)
                    if wayOutClear(onto: out, line) {
                        // It comes out on the other track, its rear a buffer clear of the buffer stops.
                        train.track = out
                        train.body = Body(position: line.tailExitM)
                        train.stop = 0
                        train.phase = .running
                        train.doors = 0
                        train.serviceStop = nil
                        train.zoneCursor = 0
                    }
                }
                trains[index] = train
                noses[index] = line.loopPosition(track: train.track, uM: train.body.position)
            }
            return true
        }

        private func leaveIfClear(_ index: Int, _ noses: [Double], _ line: Line) {
            guard mayLeave(index, noses, line) else { return }
            trains[index].stop += 1
            trains[index].phase = .running
        }

        // MARK: Taking up a line

        /// Puts the PCC on a line of its library: the automatic rames are withdrawn and seeded afresh on
        /// it, the clock starts again, a general emergency stop is cleared, and each connection is on the
        /// line or not by the line it named. The caller has made sure that no cab is in service, and says
        /// so to the cabs afterwards (`announceLine`).
        func takeUp(_ newLine: Line) {
            line = newLine
            let newStock = Stock(newLine.train)
            stock = newStock
            driver = Driver(stock: newStock)
            trains.removeAll()
            clock = settings.clockStartS
            inService = settings.serviceOnAtTakeUp
            emergencyStop = false
            injectionWait = [0, 0]

            let lap = Engine.measureLap(newLine, settings: settings)
            lapTimeS = lap.seconds
            seed(newLine, calls: lap.calls)

            for index in links.indices {
                let was = links[index].onLine
                links[index].onLine = links[index].line?.isSameLine(as: newLine.identity) ?? false
                if links[index].onLine && !was { note(.cabOnLine(name: links[index].name)) }
            }
            note(.lineTakenUp(line: newLine.identity, rames: trains.count))
        }

        /// Puts the PCC on no line: its rames are withdrawn, and no connection is on the line. The caller
        /// has made sure that no cab is in service, and says so to the cabs afterwards (`announceLine`).
        func leaveLine() {
            line = nil
            stock = nil
            driver = nil
            trains.removeAll()
            lapTimeS = 0
            clock = settings.clockStartS
            inService = false
            emergencyStop = false
            injectionWait = [0, 0]
            for index in links.indices { links[index].onLine = false }
        }

        /// The line of the library with an id and a revision, and where it is in it.
        func held(_ identity: CabineWire.LineIdentity) -> (index: Int, held: Held)? {
            guard let index = library.firstIndex(where: { $0.package.identity.isSameLine(as: identity) }) else { return nil }
            return (index, library[index])
        }

        /// The time one rame alone takes to go round the loop, stops and both turn-backs included, and
        /// when it calls at each stop on the way: found by running one, in simulated time.
        private static func measureLap(_ line: Line, settings: Settings) -> (seconds: Double, calls: [(track: Int, stop: Int, at: Double)]) {
            let lone = Engine(settings: settings)
            lone.line = line
            lone.inService = true
            let stock = Stock(line.train)
            lone.stock = stock
            lone.driver = Driver(stock: stock)
            lone.probe = [(1, 0, 0)]
            var train = Train(id: 1, number: 1, track: 1, body: Body(position: line.track(1).stopsM[0]), stop: 0)
            train.phase = .dwelling
            train.doors = 1
            train.timer = lone.drawDwell(line)
            lone.trains = [train]
            // It is back when it calls again where it began. A day is far more than any line needs.
            let stopsInALap = 2 * line.stationCount
            while lone.time < 86_400, (lone.probe?.count ?? 0) <= stopsInALap {
                lone.advance(Engine.longestStep)
            }
            let calls = lone.probe ?? []
            guard calls.count > stopsInALap else { return (lone.time, Array(calls.prefix(stopsInALap))) }
            return (calls[stopsInALap].at, Array(calls.prefix(stopsInALap)))
        }

        /// Seeds the automatic rames standing at platforms spread round the loop, part-way through their
        /// stops: as evenly in time as the platforms allow, the first at the first stop of track 1.
        private func seed(_ line: Line, calls: [(track: Int, stop: Int, at: Double)]) {
            let wanted = automaticTarget
            guard wanted > 0, lapTimeS > 0, !calls.isEmpty else { return }
            let loop = line.loopLengthM
            let apart = line.train.lengthM + line.followingDistanceM
            var free = calls
            for k in 0..<wanted {
                let due = lapTimeS * Double(k) / Double(wanted)
                // The nearest platform in time that is still free and clear of the rames already placed.
                func distance(_ at: Double) -> Double {
                    let d = abs(at - due)
                    return min(d, lapTimeS - d)
                }
                let choices = free.indices.sorted { distance(free[$0].at) < distance(free[$1].at) }
                guard let choice = choices.first(where: { candidate in
                    let nose = line.loopPosition(track: free[candidate].track, uM: line.track(free[candidate].track).stopsM[free[candidate].stop])
                    return !trains.contains { placed in
                        let d = abs(line.loopPosition(track: placed.track, uM: placed.body.position) - nose)
                        return min(d, loop - d) < apart
                    }
                }) else { break }
                let call = free.remove(at: choice)
                let stops = line.track(call.track).stopsM
                var train = Train(id: newTrainID(), number: freeNumber(), track: call.track,
                                  body: Body(position: stops[call.stop]), stop: call.stop)
                train.phase = .dwelling
                train.doors = 1
                let whole = call.stop == stops.count - 1 ? line.dwell.terminusS : (line.dwell.minS + line.dwell.maxS) / 2
                train.timer = max(1, whole * random.range(0.2, 1))
                trains.append(train)
            }
        }

        // MARK: Out

        func send(_ message: CabineWire.PCCMessage, to session: SessionID, thenClose: Bool = false) {
            outbox.append(Outbound(session: session, message: message, thenClose: thenClose))
        }

        func note(_ event: JournalEntry.Event) {
            guard probe == nil else { return }
            journal.append(JournalEntry(timeS: time, clockS: clock, event: event))
            // A journal nobody reads is not kept for ever.
            if journal.count > 2_000 { journal.removeFirst(journal.count - 2_000) }
        }

        /// The messages waiting to go out, in the order they were made; they are the host's from now on.
        public func takeOutbox() -> [Outbound] {
            defer { outbox.removeAll(keepingCapacity: true) }
            return outbox
        }

        /// What happened since this was last called, for an operator's journal.
        public func takeJournal() -> [JournalEntry] {
            defer { journal.removeAll() }
            return journal
        }
    }
}

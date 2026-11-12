import Foundation

// What the engine's host does with it besides stepping it: the messages that go out at a fixed rate,
// which the host's timers call for; the picture an operator supervises the line by; the library of
// lines and which of them the PCC is on; and the operator's orders.

extension CabinePCC.Engine {

    // MARK: What goes out at a fixed rate

    /// Queues the fleet picture for every cab on the line: every train of the line but its own.
    public func broadcastTraffic() {
        guard let line else { return }
        let stops = [line.track(1).stopsM.count, line.track(2).stopsM.count]
        let length = line.train.lengthM, departS = line.dwell.departS
        let picture = trains.map { pictured($0, stops: stops[$0.track == 2 ? 1 : 0], length: length, departS: departS) }
        let stamp = CabineWire.rounded(time)
        for link in links where link.onLine {
            var others = picture
            if let own = trainIndex(of: link.id) { others.remove(at: own) }
            send(.traffic(.init(tS: stamp, trains: others)), to: link.id)
        }
    }

    /// Queues the line's clock and state for every cab, on the line or not.
    public func broadcastInfo() {
        let info = CabineWire.Info(tS: CabineWire.rounded(time), clockS: CabineWire.rounded(clock, 1), mode: mode,
                                   rames: trains.count, cabs: cabCount, numbers: trains.map(\.number).sorted())
        for link in links where link.hello != nil { send(.info(info), to: link.id) }
    }

    /// Queues a `ping` for every cab on the line, and returns its `id`: a host that keeps the time can
    /// tell the round trip when the `pong` with that id comes back (`noteRoundTrip`).
    @discardableResult
    public func broadcastPing() -> Int {
        pingCount += 1
        let ping = CabineWire.Ping(id: .integer(pingCount), tS: CabineWire.rounded(time))
        for link in links where link.onLine { send(.ping(ping), to: link.id) }
        return pingCount
    }

    /// Tells every cab that the PCC is about to close the line or quit, in `inS` seconds.
    public func broadcastClosing(inS: Double) {
        for link in links where link.hello != nil {
            send(.event(.init(event: .closing, inS: CabineWire.rounded(max(inS, 0)))), to: link.id)
        }
    }

    /// Keeps the round trip a host has measured on a connection, for the snapshot. The engine has no
    /// clock fine enough to measure it itself.
    public func noteRoundTrip(_ seconds: Double, for session: CabinePCC.SessionID) {
        guard let index = linkIndex(session), seconds.isFinite, seconds >= 0 else { return }
        links[index].roundTripS = seconds
    }

    // MARK: The picture

    /// The line the PCC is on, if it is on one.
    public var lineIdentity: CabineWire.LineIdentity? { line?.identity }

    /// Seconds the engine has been stepped for.
    public var timeS: Double { time }

    var mode: CabineWire.LineMode {
        emergencyStop ? .emergency : (inService && line != nil ? .normal : .stopped)
    }

    /// What a train is doing, in the words of the wire. `departS` is the line's pause before a rame
    /// moves off: a cab whose doors have just closed is leaving for that long.
    func phase(of train: Train, departS: Double) -> CabineWire.TrainPhase {
        if let cab = train.cab {
            if cab.silent || cab.emergency { return .emergency }
            if cab.status?.held == true || cab.holdLatched { return .held }
            if let doors = cab.status?.doors?.phase {
                if doors == .opening || doors == .open { return .dwelling }
                if doors == .warning || doors == .closing { return .departing }
            }
            if let shut = cab.doorsShutAt, time - shut < departS, train.body.speed < 0.5 { return .departing }
            return .running
        }
        switch train.phase {
        case .tail: return .tail
        case .running: return emergencyStop || train.brakeOrdered ? .emergency : .running
        // Kept at its platform beyond its stop, doors open or shut.
        case .dwelling:
            let kept = train.timer <= 0 && train.doors >= 1 && (train.holdOrdered || train.brakeOrdered || emergencyStop || !inService)
            return kept ? .held : .dwelling
        case .departing: return .departing
        case .waiting: return .held
        }
    }

    /// The station a train stands at or runs to next, in its track's order, of the `stops` that track
    /// has; none in the tail or beyond the last stop.
    private func station(of train: Train, stops: Int) -> Int? {
        if train.cab == nil && train.phase == .tail { return nil }
        return train.stop < stops ? train.stop : nil
    }

    /// A train as the fleet picture shows it.
    private func pictured(_ train: Train, stops: Int, length: Double, departS: Double) -> CabineWire.TrafficTrain {
        CabineWire.TrafficTrain(rame: train.number, kind: train.cab == nil ? .auto : .cab, name: train.cab?.name,
                                track: train.track, uM: CabineWire.rounded(train.body.position),
                                speedMS: CabineWire.rounded(train.body.speed),
                                accelerationMS2: CabineWire.rounded(train.body.acceleration),
                                doors: CabineWire.rounded(train.doors, 2), phase: phase(of: train, departS: departS),
                                station: station(of: train, stops: stops), lengthM: length)
    }

    /// The line and everything on it at this moment.
    public func snapshot() -> CabinePCC.Snapshot {
        var rames: [CabinePCC.Rame] = []
        if let line {
            // What is wanted of the line for each train, taken once.
            let stops = [line.track(1).stopsM.count, line.track(2).stopsM.count]
            let names = line.stationNames
            let length = line.train.lengthM, departS = line.dwell.departS
            rames.reserveCapacity(trains.count)
            for train in trains {
                let onTrack2 = train.track == 2
                let next = station(of: train, stops: stops[onTrack2 ? 1 : 0])
                // A stop of track 2 is the station counted from the other end.
                let name = next.map { names[onTrack2 ? names.count - 1 - $0 : $0] }
                var cab: CabinePCC.Cab?
                if let link = train.cab {
                    cab = CabinePCC.Cab(cabID: link.cabID, name: link.name, session: link.session,
                                        link: link.silent ? .silent : .live, linkAgeS: time - link.heardAt,
                                        roundTripS: link.session.flatMap { linkIndex($0) }.flatMap { links[$0].roundTripS },
                                        status: link.status, emergencyBrake: link.emergency, emergencyCause: link.emergencyCause,
                                        authority: link.sent, lastReport: link.lastReport)
                }
                rames.append(CabinePCC.Rame(id: train.id, number: train.number, kind: train.cab == nil ? .auto : .cab,
                                            track: train.track, uM: train.body.position, speedMS: train.body.speed,
                                            accelerationMS2: train.body.acceleration, phase: phase(of: train, departS: departS),
                                            doors: train.doors, station: next, stationName: name, lengthM: length,
                                            held: train.holdOrdered, braked: train.brakeOrdered, cab: cab))
            }
        }
        let sessions = links.map { link -> CabinePCC.Session in
            let train = trainIndex(of: link.id)
            let standing: CabinePCC.Standing = link.hello == nil ? .opened : (train != nil ? .inService : (link.onLine ? .onLine : .connected))
            return CabinePCC.Session(id: link.id, peer: link.peer, standing: standing, cabID: link.hello == nil ? nil : link.cabID,
                                     name: link.hello == nil ? nil : link.name, app: link.hello?.app, appVersion: link.hello?.appVersion,
                                     line: link.line, rame: train.map { trains[$0].number }, linkAgeS: time - link.heardAt,
                                     roundTripS: link.roundTripS)
        }
        let held = library.map { held -> CabinePCC.HeldLine in
            let description = held.package.description
            return CabinePCC.HeldLine(identity: held.package.identity, stationCount: description.stations.count,
                                      lengthM: description.lengthM, hasSource: held.package.source != nil,
                                      firstStation: description.stations.first?.name ?? "",
                                      lastStation: description.stations.last?.name ?? "")
        }
        return CabinePCC.Snapshot(timeS: time, line: line, clockS: clock, mode: mode, inService: inService,
                                  emergencyStop: emergencyStop, headwayS: settings.headwayS,
                                  fleetSize: settings.fleetSize, lapTimeS: lapTimeS,
                                  automaticTarget: line == nil ? 0 : automaticTarget, rames: rames, sessions: sessions,
                                  library: held)
    }

    // MARK: The library, and the line the PCC is on

    /// Keeps a line in the library, without taking it up. Its description must pass the PCC's checks. A
    /// line already held under the same id and revision is replaced where it stands in the library;
    /// for the line the PCC is on, that gives it another source and nothing else.
    public func keep(_ package: CabineWire.LinePackage) throws {
        guard package.format == CabineWire.LinePackage.currentFormat else {
            throw CabinePCC.OrderError.badLine("a package of format \(package.format) is not one this PCC reads")
        }
        let made: CabinePCC.Line
        do {
            made = try CabinePCC.Line(package.description)
        } catch let refusal as CabinePCC.LineRefusal {
            throw CabinePCC.OrderError.badLine(refusal.reason)
        }
        // A package goes to a cab as one line of the wire, and a line has a limit: one that could not be
        // sent is not kept. The room left is for the `id` of the request it answers.
        let sent = CabineWire.Codec.encode(CabineWire.PCCMessage.line(.init(package: package))).count
        guard sent <= CabineWire.maxLineBytes - 1_024 else {
            throw CabinePCC.OrderError.badLine("the package is \(sent) bytes on the wire: a line may be 1 MiB at most")
        }
        if let found = held(package.identity) {
            // The line the PCC is on is the description it is running: that cannot change under it.
            if let line, line.identity.isSameLine(as: package.identity), line.description != package.description {
                throw CabinePCC.OrderError.badValue("the PCC is on line \(package.identity.id): its description cannot be changed while it runs")
            }
            library[found.index] = Held(package: package, line: made)
        } else {
            let limit = max(settings.libraryLimit, 1)
            guard library.count < limit else {
                throw CabinePCC.OrderError.badValue("the library is full: it holds \(limit) lines")
            }
            library.append(Held(package: package, line: made))
        }
    }

    /// A line of the library, as it was kept.
    public func heldPackage(_ identity: CabineWire.LineIdentity) -> CabineWire.LinePackage? {
        held(identity)?.held.package
    }

    /// Takes a line out of the library. Refused for the line the PCC is on, and when it holds no such line.
    public func forget(_ identity: CabineWire.LineIdentity) throws {
        guard let found = held(identity) else { throw CabinePCC.OrderError.noSuchLine }
        if let line, line.identity.isSameLine(as: identity) {
            throw CabinePCC.OrderError.badValue("the PCC is on line \(identity.id): it cannot be forgotten while it runs")
        }
        library.remove(at: found.index)
    }

    /// Puts the PCC on a line of its library, and says so to every cab. Refused while a cab is in
    /// service on the present line, and when it holds no such line.
    public func takeUp(held identity: CabineWire.LineIdentity) throws {
        guard let found = held(identity) else { throw CabinePCC.OrderError.noSuchLine }
        guard cabCount == 0 else { throw CabinePCC.OrderError.lineInUse }
        takeUp(found.held.line)
        announceLine()
    }

    /// Keeps a line, then puts the PCC on it.
    public func takeUp(_ package: CabineWire.LinePackage) throws {
        try keep(package)
        try takeUp(held: package.identity)
    }

    /// Puts the PCC on no line, and says so to every cab. Refused while a cab is in service.
    public func closeLine() throws {
        guard cabCount == 0 else { throw CabinePCC.OrderError.lineInUse }
        guard line != nil else { return }
        leaveLine()
        announceLine()
    }

    /// A bare description as a package: with the source the library already holds for that line, if it
    /// holds one, so that keeping a description does not lose it.
    private func packaged(_ description: CabineWire.LineDescription) -> CabineWire.LinePackage {
        CabineWire.LinePackage(description: description, source: heldPackage(description.identity)?.source)
    }

    /// Keeps a line of which there is only the description.
    public func keep(_ description: CabineWire.LineDescription) throws {
        try keep(packaged(description))
    }

    /// The description of a line of the library.
    public func heldDescription(_ identity: CabineWire.LineIdentity) -> CabineWire.LineDescription? {
        heldPackage(identity)?.description
    }

    /// Keeps a line of which there is only the description, then puts the PCC on it.
    public func takeUp(_ description: CabineWire.LineDescription) throws {
        try takeUp(packaged(description))
    }

    // MARK: The operator's orders

    /// Line service on or off. With it off no train has leave to move: one at a platform stays there,
    /// and one on the move comes to a stand where it can.
    public func setService(_ on: Bool) {
        // Service is the running line's: on no line there is none to give.
        guard let line, on != inService else { return }
        inService = on
        for index in trains.indices where trains[index].cab == nil {
            if on {
                trains[index].serviceStop = nil
            } else if trains[index].phase == .running {
                let v = trains[index].body.speed
                trains[index].serviceStop = trains[index].body.position + v * v / (2 * line.train.approachDecelMS2) + v
            }
        }
    }

    /// The general emergency stop, on or off: every automatic rame is braked to a stand, and every cab
    /// is ordered to brake. Releasing it leaves braked the cabs the operator has braked one by one.
    public func setEmergencyStop(_ on: Bool) {
        guard line != nil, on != emergencyStop else { return }
        emergencyStop = on
        for train in trains {
            guard let session = train.cab?.session else { continue }
            if on || !train.brakeOrdered { order(.emergencyBrake, .bool(on), to: session) }
        }
    }

    /// Keeps a rame at the platform it is at, or the next it reaches, until released.
    public func hold(rame number: Int, _ on: Bool) throws {
        let index = try index(ofRame: number)
        trains[index].holdOrdered = on
        if let session = trains[index].cab?.session { order(.hold, .bool(on), to: session) }
    }

    /// Brakes one rame to a stand, and releases it.
    public func emergencyBrake(rame number: Int, _ on: Bool) throws {
        let index = try index(ofRame: number)
        trains[index].brakeOrdered = on
        // While the general stop is on, a cab stays braked whatever becomes of its own order.
        if let session = trains[index].cab?.session, on || !emergencyStop { order(.emergencyBrake, .bool(on), to: session) }
    }

    /// Sends words from the operator to a cab's display.
    public func message(rame number: Int, _ text: String) throws {
        let session = try cabSession(ofRame: number)
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw CabinePCC.OrderError.badValue("a message needs words") }
        guard words.count <= CabineWire.maxMessageCharacters else {
            throw CabinePCC.OrderError.badValue("a message may be \(CabineWire.maxMessageCharacters) characters at most: this one is \(words.count)")
        }
        order(.message, .string(words), to: session)
    }

    /// Rings a cab's driver.
    public func call(rame number: Int) throws {
        order(.call, nil, to: try cabSession(ofRame: number))
    }

    /// Sizes the fleet for a train every `seconds` each way. The line comes to it as rames reach its
    /// tails: more come out of them, or those there are go no further.
    public func setHeadway(_ seconds: Double) throws {
        guard seconds.isFinite, CabinePCC.Settings.headwayRange.contains(seconds) else {
            let range = CabinePCC.Settings.headwayRange
            throw CabinePCC.OrderError.badValue("a headway lies between \(Int(range.lowerBound)) and \(Int(range.upperBound)) seconds")
        }
        settings.headwayS = seconds
    }

    /// Fixes the number of trains on the line, cabs included; nil goes back to sizing it from the headway.
    public func setFleetSize(_ size: Int?) throws {
        if let size, !CabinePCC.Settings.fleetRange.contains(size) {
            let range = CabinePCC.Settings.fleetRange
            throw CabinePCC.OrderError.badValue("a fleet is \(range.lowerBound) to \(range.upperBound) trains")
        }
        settings.fleetSize = size
    }

    private func index(ofRame number: Int) throws -> Int {
        guard line != nil else { throw CabinePCC.OrderError.noLine }
        guard let index = trains.firstIndex(where: { $0.number == number }) else { throw CabinePCC.OrderError.noSuchRame(number) }
        return index
    }

    private func cabSession(ofRame number: Int) throws -> CabinePCC.SessionID {
        let index = try index(ofRame: number)
        guard let cab = trains[index].cab else { throw CabinePCC.OrderError.notACab(number) }
        guard let session = cab.session else { throw CabinePCC.OrderError.cabNotConnected(number) }
        return session
    }
}

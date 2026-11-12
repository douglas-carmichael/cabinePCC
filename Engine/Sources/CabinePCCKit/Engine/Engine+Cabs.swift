import Foundation

// What the engine does with its connections and with what the cabs send it.

extension CabinePCC.Engine {
    typealias Wire = CabineWire
    typealias SessionID = CabinePCC.SessionID

    // MARK: Connections

    /// A connection has been accepted. `peer` says where it comes from, for displays.
    public func open(_ session: CabinePCC.SessionID, peer: String = "") {
        guard linkIndex(session) == nil else { return }
        links.append(Link(id: session, peer: peer, cabID: "", name: peer.isEmpty ? "\(session)" : peer, heardAt: time))
    }

    /// A connection has gone. If its cab was in service, its train stays where it was last seen, at a
    /// stand, as an obstacle, until the hold on a silent cab's train runs out.
    public func close(_ session: CabinePCC.SessionID) {
        guard let index = linkIndex(session) else { return }
        let link = links.remove(at: index)
        pendingCommands.removeAll { $0.session == session }
        if link.hello != nil { note(.cabDisconnected(name: link.name)) }
        if let train = trainIndex(of: session) {
            trains[train].cab?.session = nil
            silence(train)
        }
    }

    func linkIndex(_ session: SessionID) -> Int? { links.firstIndex { $0.id == session } }

    /// The train of the cab on a connection, while it is in service.
    func trainIndex(of session: SessionID) -> Int? { trains.firstIndex { $0.cab?.session == session } }

    // MARK: In

    /// Takes one line a connection sent, as it came off the wire without its line end. A line that
    /// cannot be read is answered as the specification says and does no other harm. Returns the message
    /// when it could be read.
    @discardableResult
    public func receive(line: Data, from session: CabinePCC.SessionID) -> CabineWire.CabMessage? {
        guard linkIndex(session) != nil else { return nil }
        do {
            let message = try Wire.Codec.decodeCabMessage(line)
            receive(message, from: session)
            return message
        } catch let failure as Wire.DecodeFailure {
            // Any line at all is a sign of life.
            heard(session)
            switch failure.kind {
            case .malformed:
                send(.error(.init(error: .badMessage, message: failure.reason)), to: session)
            case .fields:
                send(.result(.init(id: failure.id, ok: false, error: .badMessage,
                                   message: "\(failure.type ?? "message"): \(failure.reason)")), to: session)
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Takes one message a connection sent.
    public func receive(_ message: CabineWire.CabMessage, from session: CabinePCC.SessionID) {
        guard let index = linkIndex(session) else { return }
        heard(session)
        switch message {
        case let .hello(hello):
            handle(hello, index)
        case let .ping(ping):
            send(.pong(ping), to: session)
        case .pong:
            break
        case let .unknown(type, id):
            refuse(id, .unknownType, "unknown type \(type)", session)
        case let .lineRequest(request):
            guard saidHello(index, request.id, message) else { return }
            handle(request, index)
        case let .join(join):
            guard saidHello(index, join.id, message) else { return }
            handle(join, index)
        case let .position(report):
            guard saidHello(index, nil, message) else { return }
            handle(report, index)
        case let .status(status):
            guard saidHello(index, nil, message) else { return }
            handle(status, index)
        case let .event(event):
            guard saidHello(index, nil, message) else { return }
            handle(event, index)
        case let .leave(leave):
            guard saidHello(index, leave.id, message) else { return }
            handle(leave, index)
        case let .result(result):
            handle(result, index)
        }
    }

    /// A connection's first word is `hello`: anything else before it is turned away.
    private func saidHello(_ index: Int, _ id: Wire.MessageID?, _ message: Wire.CabMessage) -> Bool {
        if links[index].hello != nil { return true }
        refuse(id, .badMessage, "\(message.type): say hello first", links[index].id)
        return false
    }

    private func refuse(_ id: Wire.MessageID?, _ error: Wire.ErrorCode, _ reason: String, _ session: SessionID) {
        send(.result(.init(id: id, ok: false, error: error, message: reason)), to: session)
    }

    /// Turns away a report, which has no id to answer by: once a second at most, however often they come.
    private func refuseReport(_ index: Int, _ error: Wire.ErrorCode, _ reason: String) {
        guard time - links[index].refusedAt >= 1 else { return }
        links[index].refusedAt = time
        refuse(nil, error, reason, links[index].id)
    }

    /// Something has come from a connection: it is alive, and if its train was held for its silence it
    /// is a cab's train again.
    private func heard(_ session: SessionID) {
        guard let index = linkIndex(session) else { return }
        links[index].heardAt = time
        guard let train = trainIndex(of: session) else { return }
        trains[train].cab?.heardAt = time
        if trains[train].cab?.silent == true {
            trains[train].cab?.silent = false
            // Its next report says where it is; until then it stands where it was held.
            let held = trains[train].body.position
            trains[train].cab?.reportUM = held
            trains[train].cab?.reportSpeed = 0
            trains[train].cab?.reportAcceleration = 0
            note(.cabHeardAgain(name: links[index].name, rame: trains[train].number))
        }
    }

    // MARK: hello and lineRequest

    private func handle(_ hello: Wire.CabHello, _ index: Int) {
        let session = links[index].id
        if let version = hello.protocol, version != Wire.protocolVersion {
            send(.error(.init(error: .unsupportedProtocol, message: "this PCC speaks protocol \(Wire.protocolVersion)")),
                 to: session, thenClose: true)
            return
        }
        // The line the cab holds, if it holds one. A line is named by its id and its rev.
        let named = hello.line
        if let named, named.id.isEmpty || named.rev.isEmpty {
            refuse(nil, .badMessage, "hello: line must give an id and a rev", session)
            return
        }
        let first = links[index].hello == nil
        let cabID = hello.cab.map(\.id).flatMap { $0.isEmpty ? nil : String($0.prefix(64)) } ?? "session-\(session.value)"
        let name = hello.cab?.name.flatMap { $0.isEmpty ? nil : String($0.prefix(64)) }
            ?? (links[index].peer.isEmpty ? "cab \(session.value)" : links[index].peer)

        // A cab that says it is another cab, or holds another line or none, has left the service it was in.
        if let train = trainIndex(of: session) {
            let sameLine = named.map { links[index].line?.isSameLine(as: $0) ?? false } ?? false
            if cabID != links[index].cabID || !sameLine {
                handBack(train)
            } else {
                trains[train].cab?.name = name
            }
        }
        links[index].hello = hello
        links[index].cabID = cabID
        links[index].name = name
        links[index].line = named
        if first { note(.cabConnected(name: name, cabID: cabID, line: named)) }
        settle(index)

        send(.hello(.init(app: settings.app, name: settings.name, pcc: .init(id: settings.pccID), line: line?.identity,
                          onLine: links[index].onLine, link: settings.link)), to: session)
    }

    /// Works out whether a connection is on the PCC's line: it is when the line it named is that line,
    /// id and rev both.
    private func settle(_ index: Int) {
        let was = links[index].onLine
        if let line, let named = links[index].line {
            links[index].onLine = line.identity.isSameLine(as: named)
        } else {
            links[index].onLine = false
        }
        if links[index].onLine && !was { note(.cabOnLine(name: links[index].name)) }
    }

    /// A cab asks for a line of the library: the one the PCC is on, or the one it names.
    private func handle(_ request: Wire.LineRequest, _ index: Int) {
        let session = links[index].id
        guard let wanted = request.line ?? line?.identity else {
            refuse(request.id, .noLine, "the PCC is on no line", session)
            return
        }
        guard let found = held(wanted) else {
            // The library may hold that line in another revision: the cab is told so.
            let reason = library.contains { $0.package.identity.id == wanted.id }
                ? "no line \(wanted.id) of revision \(wanted.rev) in the library"
                : "no line \(wanted.id) in the library"
            note(.lineRefused(name: links[index].name, error: .noSuchLine, reason: reason))
            refuse(request.id, .noSuchLine, reason, session)
            return
        }
        send(.line(.init(id: request.id, package: found.held.package)), to: session)
        note(.lineHandedOver(name: links[index].name, line: found.held.package.identity))
    }

    /// Tells every cab which line the PCC is now on, or that it is on none.
    func announceLine() {
        for link in links where link.hello != nil {
            send(.event(.init(event: .line, line: line?.identity)), to: link.id)
        }
    }

    /// Tells the other cabs on the line that one has entered or left service.
    private func announcePeer(rame: Int, name: String, state: Wire.PeerState, except: SessionID?) {
        for link in links where link.onLine && link.id != except {
            send(.event(.init(event: .peer, rame: rame, name: name, state: state)), to: link.id)
        }
    }

    // MARK: join and leave

    private func handle(_ join: Wire.Join, _ index: Int) {
        let session = links[index].id
        guard let line, links[index].onLine else {
            refuse(join.id, .notOnLine, "join: not on the PCC's line", session)
            return
        }
        guard join.track == 1 || join.track == 2 else {
            refuse(join.id, .badValue, "join: track must be 1 or 2", session)
            return
        }
        guard join.uM.isFinite, join.uM >= 0, join.uM <= line.lengthM else {
            refuse(join.id, .badValue, "join: uM must lie between 0 and \(line.lengthM)", session)
            return
        }
        let stops = line.track(join.track).stopsM
        if let station = join.station, !stops.indices.contains(station) {
            refuse(join.id, .badValue, "join: station must lie between 0 and \(stops.count - 1)", session)
            return
        }
        if let wanted = join.rame, !Wire.rameNumbers.contains(wanted) {
            refuse(join.id, .badValue, "join: rame must lie between \(Wire.rameNumbers.lowerBound) and \(Wire.rameNumbers.upperBound)", session)
            return
        }
        let length = line.train.lengthM
        let rear = join.uM - length
        let cabID = links[index].cabID
        // Two cabs cannot have the same stretch of track.
        let taken = trains.contains { other in
            guard let cab = other.cab, cab.cabID != cabID, other.track == join.track else { return false }
            return other.body.position > rear && other.body.position - length < join.uM
        }
        guard !taken else {
            refuse(join.id, .badValue, "join: another cab's train stands there", session)
            return
        }

        // A cab is in service with one train. One it still has on the line, held there since its
        // connection dropped, is the very train it now says where to find: it is not left behind as a
        // rame of its own.
        var withdrawn: [Int] = []
        trains.removeAll { train in
            guard let cab = train.cab, cab.cabID == cabID || cab.session == session else { return false }
            withdrawn.append(train.number)
            return true
        }

        // The cab takes the place of the automatic rames that stand where its train is or within the
        // moving-block margin of it, and of one coming up behind that could no longer stop short of it.
        let reach = line.followingDistanceM
        trains.removeAll { rame in
            guard rame.cab == nil, rame.track == join.track else { return false }
            let nose = rame.body.position
            if nose + reach > rear && nose - length - reach < join.uM {
                withdrawn.append(rame.number)
                return true
            }
            if nose <= rear - reach, rame.phase == .running {
                let v = rame.body.speed
                if rear - reach - nose < v * v / (2 * line.train.serviceBrakeMS2) + 1.5 * v + 2 {
                    withdrawn.append(rame.number)
                    return true
                }
            }
            return false
        }

        // The number it asked for, unless another cab holds it; an automatic rame that holds it is
        // given another.
        var number = join.rame ?? 0
        if number == 0 || trains.contains(where: { $0.cab != nil && $0.number == number }) { number = freeNumber() }
        let holder = trains.firstIndex { $0.number == number }
        var train = Train(id: newTrainID(), number: number, track: join.track, body: CabinePCC.Body(position: join.uM),
                          stop: join.station ?? stops.firstIndex { $0 >= join.uM - CabinePCC.Engine.platformReach } ?? stops.count)
        train.cab = CabLink(cabID: cabID, name: links[index].name, session: session, heardAt: time,
                            reportUM: join.uM, reportAt: time)
        trains.append(train)
        if let holder { trains[holder].number = freeNumber() }

        // The fleet's numbers are all there are: a cab beyond them puts an automatic rame out.
        while trains.count > Wire.fleetNumbers.upperBound, let spare = spareAutomatic(line) {
            withdrawn.append(trains[spare].number)
            trains.remove(at: spare)
        }

        send(.result(.init(id: join.id, ok: true, rame: number)), to: session)
        note(.cabJoined(name: links[index].name, rame: number, track: join.track, uM: join.uM, withdrawn: withdrawn))
        announcePeer(rame: number, name: links[index].name, state: .joined, except: session)
        if emergencyStop { order(.emergencyBrake, .bool(true), to: session) }
        // Its first authority goes with the answer, and the cabs behind it learn at once of the train
        // that now stands ahead of them.
        sendAuthorities(0, line)
    }

    /// The automatic rame the line can best do without: one out of sight in a tail, or else the one
    /// farthest from every cab.
    private func spareAutomatic(_ line: CabinePCC.Line) -> Int? {
        if let hidden = trains.firstIndex(where: { $0.cab == nil && $0.phase == .tail }) { return hidden }
        let loop = line.loopLengthM
        var best: Int?
        var farthest = -1.0
        for (index, train) in trains.enumerated() where train.cab == nil {
            let nose = line.loopPosition(track: train.track, uM: train.body.position)
            var nearest = Double.infinity
            for other in trains where other.cab != nil {
                let d = abs(line.loopPosition(track: other.track, uM: other.body.position) - nose)
                nearest = min(nearest, d, loop - d)
            }
            if nearest > farthest {
                farthest = nearest
                best = index
            }
        }
        return best
    }

    private func handle(_ leave: Wire.Leave, _ index: Int) {
        let session = links[index].id
        guard let train = trainIndex(of: session) else {
            refuse(leave.id, .notInService, "leave: not in service", session)
            return
        }
        note(.cabLeft(name: links[index].name, rame: trains[train].number, reason: leave.reason?.rawValue ?? "left"))
        handBack(train)
        send(.result(.init(id: leave.id, ok: true)), to: session)
    }

    /// Hands a cab's train back to automation where it stands: it runs on as an automatic rame.
    func handBack(_ index: Int) {
        guard let line, let cab = trains[index].cab else { return }
        var train = trains[index]
        let was = train.number
        train.cab = nil
        // An automatic rame bears a number of the fleet.
        if !Wire.fleetNumbers.contains(train.number) { train.number = freeNumber() }
        train.body.acceleration = 0
        train.body.effort = 0
        train.body.emergency = 0
        train.serviceStop = nil
        train.zoneCursor = 0
        train.timer = 0

        let stops = line.track(train.track).stopsM
        let nose = train.body.position
        let standing = train.body.speed < 0.1
        if standing, let at = line.stop(track: train.track, near: nose, tolerance: CabinePCC.Engine.platformReach) {
            train.body.speed = 0
            train.stop = at
            if nose < stops[at] - CabinePCC.Engine.stopTolerance {
                // A little short of its stop: it draws up to it, once the line is in service.
                train.phase = .running
                train.doors = 0
                if !inService { train.serviceStop = nose }
            } else {
                // At its platform: it makes its stop there.
                train.phase = .dwelling
                train.timer = at == stops.count - 1 ? line.dwell.terminusS : drawDwell(line)
            }
        } else {
            // On the move, or at a stand between stations: it runs on to the first stop it can still make.
            let v = train.body.speed
            let needs = v * v / (2 * line.train.serviceBrakeMS2) + 1.5 * v + CabinePCC.Engine.stopTolerance
            train.stop = stops.firstIndex { $0 >= nose + needs } ?? stops.count
            train.phase = .running
            train.doors = 0
            if !inService { train.serviceStop = nose + v * v / (2 * line.train.approachDecelMS2) }
        }
        trains[index] = train

        note(.cabHandedBack(name: cab.name, rame: was, number: train.number))
        announcePeer(rame: was, name: cab.name, state: .left, except: cab.session)
    }

    // MARK: Reports

    private func handle(_ report: Wire.Position, _ index: Int) {
        let session = links[index].id
        guard let line, let train = trainIndex(of: session) else {
            refuseReport(index, .notInService, "position: not in service")
            return
        }
        guard report.track == 1 || report.track == 2 else {
            refuseReport(index, .badValue, "position: track must be 1 or 2")
            return
        }
        let speed = report.speedMS ?? 0, acceleration = report.accelerationMS2 ?? 0
        guard report.uM.isFinite, report.uM >= 0, report.uM <= line.lengthM, speed.isFinite, acceleration.isFinite else {
            refuseReport(index, .badValue, "position: uM must lie between 0 and \(line.lengthM)")
            return
        }
        let reportedSpeed = min(max(speed, 0), 100), reportedAcceleration = min(max(acceleration, -20), 20)
        trains[train].track = report.track
        trains[train].body.position = report.uM
        trains[train].body.speed = reportedSpeed
        trains[train].body.acceleration = reportedAcceleration
        trains[train].cab?.reportUM = report.uM
        trains[train].cab?.reportSpeed = reportedSpeed
        trains[train].cab?.reportAcceleration = reportedAcceleration
        trains[train].cab?.reportAt = time
    }

    private func handle(_ status: Wire.Status, _ index: Int) {
        let session = links[index].id
        guard let line, let train = trainIndex(of: session), let cab = trains[train].cab else {
            refuseReport(index, .notInService, "status: not in service")
            return
        }
        if status.doors?.phase == .closed, let before = cab.status?.doors?.phase, before != .closed { cab.doorsShutAt = time }
        cab.status = status
        if let doors = status.doors {
            trains[train].doors = min(max(doors.open ?? (doors.phase == .open ? 1 : 0), 0), 1)
        }
        if let station = status.station?.index, line.track(trains[train].track).stopsM.indices.contains(station) {
            trains[train].stop = station
        }
        if let brake = status.emergencyBrake { noteEmergencyBrake(of: train, applied: brake.applied, cause: brake.cause, index) }
    }

    /// Keeps what a cab says of its emergency brake, and puts a change of it in the journal.
    private func noteEmergencyBrake(of train: Int, applied: Bool, cause: String?, _ index: Int) {
        guard trains[train].cab?.emergency != applied else {
            if applied, let cause { trains[train].cab?.emergencyCause = cause }
            return
        }
        trains[train].cab?.emergency = applied
        trains[train].cab?.emergencyCause = applied ? cause : nil
        note(.cabEmergencyBrake(name: links[index].name, rame: trains[train].number, applied: applied, cause: cause))
    }

    private func handle(_ event: Wire.CabEvent, _ index: Int) {
        let name = links[index].name
        let train = trainIndex(of: links[index].id)
        let rame = train.map { trains[$0].number }
        switch event.event {
        case .report:
            if let train { trains[train].cab?.lastReport = CabinePCC.Report(code: event.code, text: event.text, clockS: clock) }
            note(.cabReport(name: name, rame: rame, code: event.code, text: event.text))
        case .call:
            note(.cabCall(name: name, rame: rame))
        case .acknowledge:
            note(.cabAcknowledge(name: name, rame: rame))
        case .emergencyBrake:
            guard let applied = event.applied else { return }
            if let train {
                noteEmergencyBrake(of: train, applied: applied, cause: event.cause, index)
            } else {
                note(.cabEmergencyBrake(name: name, rame: nil, applied: applied, cause: event.cause))
            }
        default:
            // An event this version does not know: ignored.
            break
        }
    }

    /// A cab's answer to a command: a refusal goes in the journal.
    private func handle(_ result: Wire.ResultMessage, _ index: Int) {
        let session = links[index].id
        guard let id = result.id, let waiting = pendingCommands.firstIndex(where: { $0.id == id && $0.session == session }) else { return }
        let pending = pendingCommands.remove(at: waiting)
        if !result.ok {
            note(.commandRefused(name: links[index].name, rame: trainIndex(of: session).map { trains[$0].number },
                                 command: pending.command, error: result.error?.rawValue ?? result.message))
        }
    }

    /// Sends a cab an order of the operator's, and remembers it until the cab answers.
    func order(_ command: Wire.CommandName, _ value: Wire.CommandValue?, to session: SessionID) {
        commandCount += 1
        let id = Wire.MessageID.string("c\(commandCount)")
        pendingCommands.append((id, session, command))
        if pendingCommands.count > 64 { pendingCommands.removeFirst(pendingCommands.count - 64) }
        send(.command(.init(id: id, command: command, value: value)), to: session)
    }

    // MARK: Silence

    /// Holds a cab's train where it was last seen, at a stand, as an obstacle.
    private func silence(_ train: Int) {
        guard let cab = trains[train].cab, !cab.silent else { return }
        trains[train].cab?.silent = true
        trains[train].body.speed = 0
        trains[train].body.acceleration = 0
        note(.cabSilent(name: cab.name, rame: trains[train].number))
    }

    /// Looks after the cabs' trains at each step: one whose cab has fallen silent is held, and handed
    /// back to automation if the silence lasts; the others are carried on from their last report.
    func superviseCabs(_ line: CabinePCC.Line) {
        var next = 0
        while next < trains.count {
            let index = next
            next += 1
            guard let cab = trains[index].cab else { continue }
            let quiet = time - cab.heardAt
            if !cab.silent && (cab.session == nil || quiet >= settings.link.timeoutS) { silence(index) }
            if trains[index].cab?.silent == true {
                if quiet >= settings.link.staleHoldS { handBack(index) }
                continue
            }
            // Between two reports a train is taken to move as it last said it did, for a short while:
            // five reports a second would otherwise show in the picture the other cabs are sent.
            let age = time - cab.reportAt
            if age <= CabinePCC.Engine.reckoningS {
                var t = age
                if cab.reportAcceleration < 0, cab.reportSpeed + cab.reportAcceleration * t < 0 {
                    t = cab.reportSpeed / -cab.reportAcceleration
                }
                trains[index].body.position = min(cab.reportUM + cab.reportSpeed * t + 0.5 * cab.reportAcceleration * t * t, line.lengthM)
                trains[index].body.speed = max(0, cab.reportSpeed + cab.reportAcceleration * t)
                trains[index].body.acceleration = trains[index].body.speed > 0 ? cab.reportAcceleration : 0
            } else {
                trains[index].body.speed = 0
                trains[index].body.acceleration = 0
            }
        }
    }
}

import Foundation
import CabinePCCKit

// 6. More of the engine, still without sockets: the library and which line the PCC is on, as its operator
// orders it and as the cabs follow; two cabs on one track; and the fleet brought to what the operator asks.

/// A few connections to an engine, and what each has been sent.
private final class Party {
    let engine: CabinePCC.Engine
    private(set) var sent: [CabinePCC.SessionID: [CabineWire.PCCMessage]] = [:]

    init(settings: CabinePCC.Settings = CabinePCC.Settings(), seed: UInt64) {
        engine = CabinePCC.Engine(settings: settings, seed: seed)
    }

    func open(_ number: Int) -> CabinePCC.SessionID {
        let session = CabinePCC.SessionID(number)
        engine.open(session, peer: "cab \(number)")
        return session
    }

    /// Sends a message as the line of JSON it is on the wire, and gathers what the engine answers to everyone.
    func say(_ message: CabineWire.CabMessage, from session: CabinePCC.SessionID) {
        engine.receive(line: CabineWire.Codec.encode(message), from: session)
        gather()
    }

    func step(_ seconds: Double = 0.05) {
        engine.step(seconds)
        gather()
    }

    func gather() {
        for outbound in engine.takeOutbox() { sent[outbound.session, default: []].append(outbound.message) }
    }

    /// Forgets what has been sent so far.
    func forget() { sent.removeAll() }

    /// How many messages a connection has been sent.
    func count(to session: CabinePCC.SessionID) -> Int { sent[session]?.count ?? 0 }

    func hello(to session: CabinePCC.SessionID) -> CabineWire.PCCHello? {
        for message in (sent[session] ?? []).reversed() { if case let .hello(hello) = message { return hello } }
        return nil
    }

    func result(to session: CabinePCC.SessionID) -> CabineWire.ResultMessage? {
        for message in (sent[session] ?? []).reversed() { if case let .result(result) = message { return result } }
        return nil
    }

    func authority(to session: CabinePCC.SessionID) -> CabineWire.Authority? {
        for message in (sent[session] ?? []).reversed() { if case let .authority(authority) = message { return authority } }
        return nil
    }

    func info(to session: CabinePCC.SessionID) -> CabineWire.Info? {
        for message in (sent[session] ?? []).reversed() { if case let .info(info) = message { return info } }
        return nil
    }

    /// The last line of the library a connection was sent.
    func line(to session: CabinePCC.SessionID) -> CabineWire.LineMessage? {
        for message in (sent[session] ?? []).reversed() { if case let .line(line) = message { return line } }
        return nil
    }

    /// The lines the PCC has said it is on, to a connection, in order: nil where it said it is on none.
    func lines(to session: CabinePCC.SessionID) -> [CabineWire.LineIdentity?] {
        var lines: [CabineWire.LineIdentity?] = []
        for message in sent[session] ?? [] {
            if case let .event(event) = message, event.event == .line { lines.append(event.line) }
        }
        return lines
    }

    func traffic(to session: CabinePCC.SessionID) -> Bool {
        (sent[session] ?? []).contains { if case .traffic = $0 { true } else { false } }
    }

    func pinged(_ session: CabinePCC.SessionID) -> Bool {
        (sent[session] ?? []).contains { if case .ping = $0 { true } else { false } }
    }

    func standing(_ session: CabinePCC.SessionID) -> CabinePCC.Standing? {
        engine.snapshot().sessions.first { $0.id == session }?.standing
    }
}

extension SelfTest {

    /// The lines are the PCC's: its operator fills the library and says which line it is on, and the
    /// cabs follow.
    func library() {
        typealias Package = CabineWire.LinePackage
        let first = CabinePCC.testLine
        var second = first
        second.id = "bis"
        second.name = "Ligne bis"
        second.rev = "0000000000000002"
        second.stations[0].name = "Porte Bis"
        let x = first.identity, y = second.identity
        guard let onePackage = try? Package.decode(file: Data(SelfTest.packageText(first, source: SelfTest.sampleSource).utf8)) else {
            check("the test's own package is read", false)
            return
        }
        let twoPackage = Package(description: second)
        let nowhere = CabineWire.LineIdentity(id: "nulle", rev: "0", name: "")

        let party = Party(seed: 9)
        let engine = party.engine
        // Three cabs, and a connection that never says hello.
        let a = party.open(1), b = party.open(2), c = party.open(3), mute = party.open(4)
        func hello(_ cab: String, on line: CabineWire.LineIdentity?, from session: CabinePCC.SessionID) {
            party.say(.hello(.init(app: "Cabine", cab: .init(id: cab, name: cab), line: line)), from: session)
        }

        // On no line, with nothing in the library.
        hello("A", on: nil, from: a)
        let alone = party.hello(to: a)
        check("a hello that names no line is a cab on no line, and a PCC on no line names none in its answer",
              alone != nil && alone?.onLine == false && alone?.line == nil && party.standing(a) == .connected
                && engine.snapshot().sessions.first?.line == nil && engine.snapshot().sessions.last?.standing == .opened)
        party.say(.lineRequest(.init(id: "l1")), from: a)
        let noLine = party.result(to: a)
        party.say(.lineRequest(.init(id: "l2", line: .init(id: "9", rev: "1", name: "9"))), from: a)
        let noSuch = party.result(to: a)
        party.say(.join(.init(id: "j0", track: 1, uM: 279.5)), from: a)
        let notOn = party.result(to: a)
        party.say(.lineRequest(.init(id: "l3")), from: mute)
        let early = party.result(to: mute)
        check("a lineRequest is refused with noLine when the PCC is on no line and none is named, and with noSuchLine when the library has not the line named",
              noLine?.ok == false && noLine?.error == .noLine && noLine?.id == "l1" && noSuch?.ok == false && noSuch?.error == .noSuchLine
                && noSuch?.id == "l2" && noSuch?.message == "no line 9 in the library" && notOn?.error == .notOnLine
                && early?.error == .badMessage && early?.id == "l3",
              "\(noLine?.message ?? "-"); \(noSuch?.message ?? "-")")
        party.forget()
        for _ in 0..<100 { party.step() }
        engine.broadcastInfo()
        engine.broadcastTraffic()
        engine.broadcastPing()
        party.gather()
        let idle = party.info(to: a)
        let unheld = refusal(of: { try engine.hold(rame: 1, true) })
        engine.setService(true)
        engine.setEmergencyStop(true)
        check("a PCC on no line says 08:42:00, stopped and no rames to every cab that has said hello, and sends no traffic and no ping",
              idle?.clockS == 31_320 && idle?.mode == .stopped && idle?.rames == 0 && idle?.cabs == 0 && idle?.numbers == []
                && party.count(to: a) == 1 && party.count(to: mute) == 0)
        check("on no line there is no service to give and no train to order",
              unheld == .noLine && !engine.snapshot().inService && !engine.snapshot().emergencyStop && engine.snapshot().mode == .stopped
                && engine.snapshot().rames.isEmpty && engine.snapshot().clockS == 31_320)

        // The operator fills the library and puts the PCC on a line. A cab that holds another line
        // already has said so.
        hello("C", on: y, from: c)
        party.forget()
        let filled = refusal(of: {
            try engine.keep(onePackage)
            try engine.keep(twoPackage)
            try engine.takeUp(held: x)
        })
        party.gather()
        let begun = engine.snapshot()
        check("the operator puts the PCC on a line of its library: every cab that has said hello is told with event line, and no other connection",
              filled == nil && party.lines(to: a) == [x] && party.lines(to: c) == [x] && party.count(to: mute) == 0
                && begun.line?.identity == x && begun.library.map(\.identity) == [x, y] && begun.clockS == 31_320 && begun.inService
                && begun.mode == .normal && begun.rames.count >= 2 && party.standing(a) == .connected && party.standing(c) == .connected,
              filled.map { "\($0)" } ?? "\(begun.rames.count) rames")

        // The cab follows: it asks, is sent the line, and says hello again once it holds it.
        party.forget()
        party.say(.lineRequest(.init(id: "l4")), from: a)
        let sent = party.line(to: a)
        hello("A", on: x, from: a)
        let onIt = party.hello(to: a)
        engine.broadcastTraffic()
        engine.broadcastPing()
        party.gather()
        check("a cab follows the PCC's line: it asks, is sent the package with its source, says hello again naming the line, and is on the line",
              sent?.id == "l4" && sent?.package == onePackage && sent?.package.source != nil && onIt?.onLine == true && onIt?.line == x
                && party.standing(a) == .onLine && party.traffic(to: a) && party.pinged(a) && !party.traffic(to: c) && !party.pinged(c))

        // The same id is not the same line: the rev counts.
        let stale = CabineWire.LineIdentity(id: x.id, rev: "autre", name: x.name)
        hello("B", on: stale, from: b)
        let offRev = party.hello(to: b)
        party.say(.lineRequest(.init(id: "l5", line: stale)), from: b)
        let noRev = party.result(to: b)
        party.say(.lineRequest(.init(id: "l6", line: .init(id: "bis", rev: "0000000000000002", name: "bis"))), from: b)
        let spare = party.line(to: b)
        check("a cab whose line has the PCC's id and another rev is not on the line; the host sees which line each cab holds",
              offRev?.onLine == false && offRev?.line == x && party.standing(b) == .connected
                && engine.snapshot().sessions.first { $0.id == b }?.line == stale
                && noRev?.error == .noSuchLine && noRev?.message == "no line \(x.id) of revision autre in the library",
              noRev?.message ?? "-")
        check("a cab may ask for a line the PCC is not on, by its id and its rev; one kept without a source is sent without one",
              spare?.id == "l6" && spare?.package == twoPackage && spare?.package.source == nil)

        // A cab in service keeps the PCC on its line.
        party.say(.join(.init(id: "j1", track: 1, uM: 279.5, rame: 30)), from: a)
        party.forget()
        let busy = [refusal(of: { try engine.takeUp(held: y) }), refusal(of: { try engine.takeUp(twoPackage) }),
                    refusal(of: { try engine.takeUp(second) }), refusal(of: { try engine.closeLine() })]
        let unknown = refusal(of: { try engine.takeUp(held: nowhere) })
        party.gather()
        check("while a cab is in service the operator can neither change line nor close it, and no cab is told of anything",
              busy == [.lineInUse, .lineInUse, .lineInUse, .lineInUse] && unknown == .noSuchLine && party.count(to: a) == 0
                && party.count(to: c) == 0 && engine.snapshot().line?.identity == x && engine.snapshot().cabs.count == 1)
        hello("A", on: x, from: a)
        check("a cab in service that says hello again, naming the same line, is answered as before and stays in service",
              party.hello(to: a)?.onLine == true && engine.snapshot().cabs.count == 1 && party.standing(a) == .inService
                && engine.snapshot().rame(numbered: 30)?.kind == .cab)
        hello("A", on: nil, from: a)
        check("a cab in service that says hello naming no line has left its service: its train goes back to automation",
              party.hello(to: a)?.onLine == false && engine.snapshot().cabs.isEmpty && party.standing(a) == .connected
                && engine.snapshot().rame(numbered: 30)?.kind == .auto)

        // No cab is in service: the operator changes line. Service is off and a general emergency stop
        // is on when it does.
        hello("A", on: x, from: a)
        engine.setService(false)
        engine.setEmergencyStop(true)
        for _ in 0..<40 { party.step() }
        let stopped = engine.snapshot()
        party.forget()
        let changed = refusal(of: { try engine.takeUp(held: y) })
        party.gather()
        engine.broadcastTraffic()
        party.gather()
        let now = engine.snapshot()
        check("with no cab in service the operator changes line, and every cab is told with event line",
              changed == nil && party.lines(to: a) == [y] && party.lines(to: b) == [y] && party.lines(to: c) == [y]
                && party.count(to: mute) == 0 && now.line?.identity == y && now.line?.stationNames.first == "Porte Bis")
        check("on the new line the rames are seeded afresh, the clock starts again, a general emergency stop is cleared and the line is in service",
              stopped.mode == .emergency && !stopped.inService && stopped.clockS > 31_321 && now.clockS == 31_320 && now.inService
                && !now.emergencyStop && now.mode == .normal && now.rames.count == now.automaticTarget && now.rames.count >= 2
                && now.rames.allSatisfy { $0.kind == .auto && $0.speedMS == 0 },
              "\(now.rames.count) rames")
        party.say(.join(.init(id: "j2", track: 1, uM: 279.5)), from: a)
        check("a cab that already held the new line is on the line at once; those that hold the old one are on it no more",
              party.standing(c) == .onLine && party.standing(a) == .connected && party.standing(b) == .connected
                && party.traffic(to: c) && !party.traffic(to: a) && party.result(to: a)?.error == .notOnLine)
        party.forget()
        party.say(.lineRequest(.init(id: "l7")), from: b)
        let next = party.line(to: b)
        hello("B", on: y, from: b)
        check("a cab that held the old line follows: its lineRequest that names none is answered with the new line",
              next?.id == "l7" && next?.package == twoPackage && party.hello(to: b)?.onLine == true && party.hello(to: b)?.line == y
                && party.standing(b) == .onLine)

        // The line the PCC is on, taken up again, starts afresh.
        for _ in 0..<20 { party.step() }
        let ran = engine.snapshot().clockS
        party.forget()
        let afresh = refusal(of: { try engine.takeUp(held: y) })
        party.gather()
        check("the line the PCC is on, taken up again, starts afresh and is announced again; the cabs that hold it stay on the line",
              afresh == nil && ran > 31_320.9 && engine.snapshot().clockS == 31_320 && party.lines(to: a) == [y] && party.lines(to: b) == [y]
                && party.standing(b) == .onLine && party.standing(c) == .onLine && party.standing(a) == .connected)

        // The operator closes the line.
        for _ in 0..<20 { party.step() }
        party.forget()
        let shut = refusal(of: { try engine.closeLine() })
        party.gather()
        let told = [party.lines(to: a), party.lines(to: b), party.lines(to: c)]
        engine.broadcastInfo()
        engine.broadcastTraffic()
        engine.broadcastPing()
        party.gather()
        let off = engine.snapshot()
        check("the operator closes the line: every cab is told with an event line that names none",
              shut == nil && told == [[nil], [nil], [nil]] && party.count(to: mute) == 0 && off.line == nil)
        check("the PCC is then on no line: no rames, no cab on the line, stopped, 08:42:00, and its library as it was",
              off.rames.isEmpty && off.mode == .stopped && !off.inService && off.clockS == 31_320 && off.lapTimeS == 0
                && off.automaticTarget == 0 && off.sessions.filter { $0.standing == .connected }.count == 3
                && !party.traffic(to: c) && !party.pinged(c) && party.info(to: c)?.mode == .stopped && party.info(to: c)?.rames == 0
                && off.library.map(\.identity) == [x, y])
        party.forget()
        hello("C", on: y, from: c)
        party.say(.lineRequest(.init(id: "l8")), from: c)
        let none = party.result(to: c)
        party.say(.lineRequest(.init(id: "l9", line: y)), from: c)
        let still = party.line(to: c)
        let twice = refusal(of: { try engine.closeLine() })
        party.gather()
        check("on no line a cab is on none, a lineRequest that names none is refused with noLine, the library still answers for a line that is named, and closing again does nothing",
              party.hello(to: c)?.line == nil && party.hello(to: c)?.onLine == false && none?.error == .noLine && none?.id == "l8"
                && still?.id == "l9" && still?.package == twoPackage && twice == nil && party.lines(to: c).isEmpty)

        // What the operator's journal has of all that.
        let journal = engine.takeJournal().map(\.event)
        let taken = journal.compactMap { event -> CabineWire.LineIdentity? in if case let .lineTakenUp(line, _) = event { line } else { nil } }
        let vain = journal.compactMap { event -> String? in if case let .lineRefused(_, .noSuchLine, reason) = event { reason } else { nil } }
        let handed = journal.compactMap { event -> String? in if case let .lineHandedOver(name, line) = event { "\(name) \(line.id) \(line.rev)" } else { nil } }
        check("the journal has each line handed to a cab, with the cab it went to, in the order they were asked for",
              handed == ["A \(x.id) \(x.rev)", "B \(y.id) \(y.rev)", "B \(y.id) \(y.rev)", "C \(y.id) \(y.rev)"],
              handed.joined(separator: "; "))
        check("the journal has each cab as it connected with the line it held, each line taken up, the cabs as they came on the line, and the lines asked for in vain",
              journal.contains(.cabConnected(name: "A", cabID: "A", line: nil)) && journal.contains(.cabConnected(name: "C", cabID: "C", line: y))
                && journal.contains(.cabConnected(name: "B", cabID: "B", line: stale)) && taken == [x, y, y]
                && journal.contains(.cabOnLine(name: "A")) && journal.contains(.cabOnLine(name: "B")) && journal.contains(.cabOnLine(name: "C"))
                && vain == ["no line 9 in the library", "no line \(x.id) of revision autre in the library"],
              "\(taken.count) lines taken up, \(vain.count) asked for in vain")

        // The library's own rules, on a PCC whose library holds three lines at most.
        var settings = CabinePCC.Settings()
        settings.libraryLimit = 3
        let shelf = CabinePCC.Engine(settings: settings, seed: 10)
        var third = first
        third.id = "ter"
        third.name = "Ligne ter"
        third.rev = "0000000000000003"
        var fourth = first
        fourth.id = "quater"
        fourth.name = "Ligne quater"
        fourth.rev = "0000000000000004"
        let three = refusal(of: {
            try shelf.keep(onePackage)
            try shelf.keep(twoPackage)
            try shelf.keep(third)
        })
        let full = refusal(of: { try shelf.keep(Package(description: fourth)) })
        check("the library holds as many lines as its limit, in the order they were kept, and refuses one more",
              three == nil && full == .badValue("the library is full: it holds 3 lines")
                && shelf.snapshot().library.map(\.identity.id) == [x.id, "bis", "ter"] && CabinePCC.Settings().libraryLimit == 64,
              full.map { "\($0)" } ?? "it was kept")
        var sourced = twoPackage
        sourced.source = .object(["note": .string("ajoutée")])
        let replaced = refusal(of: { try shelf.keep(sourced) })
        let listed = shelf.snapshot().library
        let bare = refusal(of: { try shelf.keep(second) })
        check("a line kept again under the same id and rev takes the place of the first where it stood; a bare description kept over it keeps its source",
              replaced == nil && listed.map(\.identity.id) == [x.id, "bis", "ter"] && listed.map(\.hasSource) == [true, true, false]
                && bare == nil && shelf.heldPackage(y) == sourced && shelf.heldDescription(y) == second && shelf.heldDescription(nowhere) == nil
                && shelf.heldPackage(nowhere) == nil)
        let up = refusal(of: { try shelf.takeUp(third) })
        var renamed = third
        renamed.stations[0].name = "Autre nom"
        let running = [refusal(of: { try shelf.forget(third.identity) }), refusal(of: { try shelf.keep(renamed) })]
        let resourced = refusal(of: { try shelf.keep(Package(description: third, source: .string("ajoutée"))) })
        let forgotten = [refusal(of: { try shelf.forget(y) }), refusal(of: { try shelf.forget(y) })]
        let room = refusal(of: { try shelf.keep(Package(description: fourth)) })
        check("the line the PCC is on can neither be forgotten nor given another description, though its source may be replaced",
              up == nil && shelf.snapshot().line?.identity == third.identity
                && running == [.badValue("the PCC is on line ter: it cannot be forgotten while it runs"),
                               .badValue("the PCC is on line ter: its description cannot be changed while it runs")]
                && resourced == nil && shelf.heldPackage(third.identity)?.source == CabineWire.JSONValue.string("ajoutée")
                && shelf.heldDescription(third.identity) == third)
        check("a line the PCC is not on is forgotten once, and leaves room for another",
              forgotten == [nil, .noSuchLine] && shelf.heldPackage(y) == nil && room == nil
                && shelf.snapshot().library.map(\.identity.id) == [x.id, "ter", "quater"])
    }

    func twoCabs() {
        let party = Party(seed: 12)
        let engine = party.engine
        do { try engine.takeUp(CabinePCC.testLine) } catch { check("the engine takes up the built-in line", false, "\(error)"); return }
        guard let line = engine.snapshot().line else { return }
        let a = party.open(1), b = party.open(2)
        party.say(.hello(.init(app: "Cabine", cab: .init(id: "A", name: "Devant"), line: line.identity)), from: a)
        party.say(.hello(.init(app: "Cabine", cab: .init(id: "B", name: "Derrière"), line: line.identity)), from: b)
        let length = line.train.lengthM
        let ahead = line.track(1).stopsM[2]
        let behind = ahead - 300

        /// What a train's position may be out by, from the description's own beacons.
        func uncertainty(at nose: Double) -> Double {
            let beacon = (CabinePCC.testLine.tracks[0].beaconsM ?? []).last { $0 <= nose } ?? 0
            return min(1.5 + 0.02 * (nose - beacon), 8)
        }

        // The first joins; the second asks for the same number, and for a place the first is in.
        party.say(.join(.init(id: "j1", track: 1, uM: ahead, station: 2, rame: 7)), from: a)
        party.say(.join(.init(id: "j2", track: 1, uM: ahead - 40, rame: 7)), from: b)
        let inTheWay = party.result(to: b)
        party.say(.join(.init(id: "j3", track: 1, uM: behind, rame: 7)), from: b)
        let second = party.result(to: b)
        let snapshot = engine.snapshot()
        check("a cab that joins where another cab's train stands is refused with badValue",
              inTheWay?.error == .badValue && inTheWay?.id == "j2")
        check("a cab that asks for a number another cab holds is given another",
              party.result(to: a)?.rame == 7 && second?.ok == true && second?.rame != nil && second?.rame != 7 && snapshot.cabs.count == 2
                && Set(snapshot.rames.map(\.number)).count == snapshot.rames.count, "rame \(second?.rame ?? 0)")

        // The second's authority ends behind the first: its rear, less what its position may be out by,
        // less the margin.
        func expected(_ nose: Double) -> Double { nose - length - uncertainty(at: nose) - 25 }
        let authority = party.authority(to: b)
        check("the second cab's authority ends at the first's rear, less its uncertainty, less the margin",
              authority?.reason == .train && authority?.rame == 7 && abs((authority?.gapM ?? 0) - (300 - length)) < 0.001
                && abs((authority?.endM ?? 0) - expected(ahead)) < 0.002,
              String(format: "to %.3f m, %.2f m of uncertainty", authority?.endM ?? 0, uncertainty(at: ahead)))

        // The first moves on: the second's authority follows, and is short by more the further the first
        // has run from a beacon, until it passes the next one.
        var followed = true
        var widest = 0.0, narrowest = Double.infinity
        var nose = ahead
        for step in 1...240 {
            nose += 1.5
            party.say(.position(.init(seq: step, tS: Double(step) * 0.2, track: 1, uM: nose, speedMS: 0, accelerationMS2: 0)), from: a)
            party.say(.position(.init(seq: step, tS: Double(step) * 0.2, track: 1, uM: behind, speedMS: 0, accelerationMS2: 0)), from: b)
            // Long enough for the authority to have been renewed since: one that grows is not sent at once.
            for _ in 0..<13 { party.step() }
            guard let now = party.authority(to: b) else { followed = false; break }
            if now.reason != .train || now.rame != 7 || abs(now.endM - expected(nose)) > 0.002 { followed = false }
            widest = max(widest, uncertainty(at: nose))
            narrowest = min(narrowest, uncertainty(at: nose))
        }
        check("as the first runs on, the authority follows its rear, short by its uncertainty since its last beacon",
              followed && narrowest < 2 && widest > 4, String(format: "uncertainty from %.2f to %.2f m over 360 m", narrowest, widest))

        // The first leaves: its train is an automatic rame, still ahead of the second.
        party.say(.leave(.init(id: "v1", reason: .ended)), from: a)
        party.step()
        let after = party.authority(to: b)
        check("when the first leaves, its train is still the train ahead of the second",
              after?.reason == .train && after?.rame == 7 && engine.snapshot().cabs.count == 1 && engine.snapshot().rame(numbered: 7)?.kind == .auto)

        // The second's connection drops, and it dials again: the train it had on the line is the very one
        // it now says where to find, 150 m further on. It is not left behind as a rame of its own.
        engine.close(b)
        party.step()
        let held = engine.snapshot().cabs.first
        let again = party.open(3)
        party.say(.hello(.init(app: "Cabine", cab: .init(id: "B", name: "Derrière"), line: line.identity)), from: again)
        party.say(.join(.init(id: "j4", track: 1, uM: behind + 150, rame: second?.rame)), from: again)
        let back = party.result(to: again)
        let rames = engine.snapshot().rames
        let cabs = rames.filter { $0.kind == .cab }
        check("a cab that dials again while its train is held takes it up where it now is: none is left where it was",
              held?.cab?.link == .silent && back?.ok == true && back?.rame == second?.rame && cabs.count == 1
                && abs((cabs.first?.uM ?? 0) - (behind + 150)) < 0.001 && cabs.first?.cab?.link == .live
                && !rames.contains { $0.kind == .auto && $0.track == 1 && abs($0.uM - behind) < 100 },
              "\(cabs.count) cab at \(cabs.first?.uM ?? 0) m, held before: \(held?.cab?.link.rawValue ?? "no")")
    }

    /// The fleet is brought to what is asked of it through the tails: a rame too many goes no further than
    /// the next tail it reaches, and one too few comes out of one.
    func fleetOrders() {
        let party = Party(seed: 31)
        let engine = party.engine
        do { try engine.takeUp(CabinePCC.testLine) } catch { check("the engine takes up the built-in line", false, "\(error)"); return }
        guard let line = engine.snapshot().line else { return }
        let watch = LineWatch(line)
        let lap = engine.snapshot().lapTimeS
        let fleet = engine.snapshot().rames.count

        /// Runs the line until it carries `count` trains, for two laps at most. True if it came to.
        func settles(at count: Int) -> Bool {
            for _ in 0..<Int(2 * lap / 0.05) {
                party.step()
                let snapshot = engine.snapshot()
                watch.observe(snapshot)
                if snapshot.rames.count == count { return true }
            }
            return false
        }

        // A cab joins between two stations, where no automatic rame is, and leaves at once: its train is
        // an automatic rame too many, until one reaches a tail.
        let a = party.open(1)
        party.say(.hello(.init(app: "Cabine", cab: .init(id: "A", name: "Passage"), line: line.identity)), from: a)
        let between = (line.track(1).stopsM[1] + line.track(1).stopsM[2]) / 2
        party.say(.join(.init(id: "j1", track: 1, uM: between)), from: a)
        let withCab = engine.snapshot()
        party.say(.leave(.init(id: "v1", reason: .ended)), from: a)
        let tooMany = engine.snapshot().rames.count
        let shed = settles(at: fleet)
        check("a train that a cab leaves on the line beside a whole fleet is one too many, and the next rame to reach a tail goes no further",
              withCab.rames.count == fleet + 1 && withCab.automaticTarget == fleet - 1 && tooMany == fleet + 1 && shed
                && engine.snapshot().automaticTarget == fleet,
              "\(tooMany) trains, then \(engine.snapshot().rames.count) after \(Int(engine.snapshot().timeS)) s")

        // The operator asks for a train every 300 s, then for 8 trains whatever the headway, then for the
        // headway again.
        var ordered = true
        do { try engine.setHeadway(300) } catch { ordered = false }
        let fewer = SelfTest.fleet(lap: lap, headway: 300, line)
        let thinned = settles(at: fewer)
        check("a longer headway thins the fleet at the tails", ordered && fewer < fleet && thinned && engine.snapshot().automaticTarget == fewer,
              "\(fewer) trains for a train every 300 s")
        do { try engine.setFleetSize(8) } catch { ordered = false }
        let fixed = settles(at: 8)
        check("a fleet size fixed by the operator is reached, more rames coming out of the tails", ordered && fixed && engine.snapshot().fleetSize == 8)
        do {
            try engine.setFleetSize(nil)
            try engine.setHeadway(150)
        } catch { ordered = false }
        let restored = settles(at: fleet)
        var refused = 0
        do { try engine.setHeadway(5) } catch { refused += 1 }
        do { try engine.setFleetSize(1) } catch { refused += 1 }
        do { try engine.setFleetSize(53) } catch { refused += 1 }
        check("and the headway asked for again brings the fleet back; a headway or a fleet size out of range is refused",
              ordered && restored && refused == 3 && engine.snapshot().headwayS == 150 && engine.snapshot().fleetSize == nil)
        check("through all of it: no two trains nearer than the safety margin, every call in order and within 1 m, no rame over its limit",
              watch.faultless, watch.faultless ? String(format: "%.0f min, %d calls, least %.2f m between trains", engine.snapshot().timeS / 60, watch.calls, watch.leastGap) : describe(watch))
    }
}

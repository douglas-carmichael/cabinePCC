import Foundation
import CabinePCCKit

// 4. A cab, still without sockets: a train the test drives down the line, reporting as a Cabine does,
// and what the engine does about it.

/// The train of a cab played by the test. It drives itself down its track, stops at each stop, never
/// runs beyond the authority it was last sent, and says where it is as a Cabine does.
private struct ScriptedCab {
    var track: Int
    /// Its nose, its speed and its acceleration.
    var u: Double
    var v = 0.0
    var a = 0.0
    /// The stop it stands at or runs to next.
    var stop: Int
    var doors = 0.0
    /// Seconds its doors still stay open, when it stands at a stop.
    var dwellLeft = 0.0
    /// How long it stops at a station, in seconds.
    var dwell = 12.0
    /// The stops it has made since it entered service.
    private(set) var calls = 0
    private var positions = 0
    private var statuses = 0

    init(track: Int, u: Double, stop: Int) {
        self.track = track
        self.u = u
        self.stop = stop
    }

    /// Keeps it standing where it is, doors open, until `leave()`.
    mutating func stay() {
        doors = 1
        dwellLeft = .infinity
    }

    mutating func leave() {
        dwellLeft = 0.01
    }

    /// Moves it on by `dt`.
    /// - Parameters:
    ///   - authorityEnd: where the authority it holds ends; it stops `stoppingShort` before that.
    ///   - limit: the lowest limit under a train whose nose is at a place.
    mutating func drive(_ dt: Double, stops: [Double], zones: [CabineWire.LineDescription.Zone], endOfTrack: Double,
                        stoppingShort: Double, authorityEnd: Double?, limit: (Double) -> Double) {
        if dwellLeft > 0 {
            dwellLeft -= dt
            v = 0
            a = 0
            if dwellLeft <= 0 {
                doors = 0
                stop += 1
            }
            return
        }
        let goal = stop < stops.count ? stops[stop] : endOfTrack
        let room = min(goal, (authorityEnd ?? u) - stoppingShort) - u
        // As fast as the limit under it allows, a lower limit ahead allows, and stopping in the room it
        // has allows, braking at 0.8 m/s².
        var allowed = min(limit(u) - 0.3, (2 * 0.8 * max(room, 0)).squareRoot())
        for zone in zones where zone.fromM > u {
            let ahead = zone.fromM - u - 5, entry = zone.limitMS - 0.3
            allowed = min(allowed, ahead <= 0 ? entry : (entry * entry + 2 * 0.8 * ahead).squareRoot())
        }
        var speed = v + min(max(allowed - v, -1.1 * dt), 0.9 * dt)
        if room <= 0.25 && speed < 0.6 { speed = 0 }
        speed = max(speed, 0)
        a = (speed - v) / dt
        u += (v + speed) / 2 * dt
        v = speed
        if v == 0, stop < stops.count, abs(u - stops[stop]) < 0.5 {
            doors = 1
            dwellLeft = dwell
            calls += 1
        }
    }

    mutating func position(at time: Double) -> CabineWire.CabMessage {
        positions += 1
        return .position(.init(seq: positions, tS: CabineWire.rounded(time), track: track, uM: CabineWire.rounded(u),
                               speedMS: CabineWire.rounded(v), accelerationMS2: CabineWire.rounded(a)))
    }

    mutating func status(at time: Double, stops: Int) -> CabineWire.CabMessage {
        statuses += 1
        return .status(.init(seq: statuses, tS: CabineWire.rounded(time), mode: .pa, automatic: true,
                             doors: .init(phase: doors > 0 ? .open : .closed, side: "right", open: doors),
                             emergencyBrake: .init(applied: false), passengers: 180,
                             station: .init(index: min(stop, stops - 1), atPlatform: doors > 0), deviationS: 0,
                             held: false, paused: false, underControl: true))
    }
}

/// The line, a cab on it and a second connection that only watches, stepped together.
private final class CabRun {
    static let dt = 0.05

    let engine: CabinePCC.Engine
    let line: CabinePCC.Line
    let watch: LineWatch
    /// The cab's connection, and the watcher's.
    let session = CabinePCC.SessionID(1)
    let monitor = CabinePCC.SessionID(2)
    var cab: ScriptedCab?
    /// True while the cab says nothing.
    var silent = false
    private(set) var snapshot: CabinePCC.Snapshot
    private var ticks = 0

    // What came back to the cab.
    var hellos: [CabineWire.PCCHello] = []
    var results: [CabineWire.ResultMessage] = []
    var commands: [CabineWire.Command] = []
    var events: [CabineWire.PCCEvent] = []
    var traffic: CabineWire.Traffic?
    var info: CabineWire.Info?
    var authority: CabineWire.Authority?
    private(set) var authorities = 0
    private(set) var longestWait = 0.0
    private(set) var faults: [String] = []
    // What came to the watcher.
    var monitorHellos: [CabineWire.PCCHello] = []
    var monitorResults: [CabineWire.ResultMessage] = []
    var monitorEvents: [CabineWire.PCCEvent] = []
    var monitorTraffic: CabineWire.Traffic?

    init(engine: CabinePCC.Engine, line: CabinePCC.Line) {
        self.engine = engine
        self.line = line
        watch = LineWatch(line)
        snapshot = engine.snapshot()
        watch.observe(snapshot)
    }

    var time: Double { snapshot.timeS }

    /// The cab's train as the PCC has it.
    var rame: CabinePCC.Rame? { snapshot.rames.first { $0.cab?.session == session } }

    /// Sends the engine what the cab says, as the line of JSON it would be on the wire.
    func say(_ message: CabineWire.CabMessage, from sender: CabinePCC.SessionID? = nil) {
        engine.receive(line: CabineWire.Codec.encode(message), from: sender ?? session)
        snapshot = engine.snapshot()
        collect()
    }

    /// Looks at the line again after an order has been given, and takes what the order sent.
    func look() {
        snapshot = engine.snapshot()
        collect()
    }

    /// One step: the cab drives and reports, the engine advances, and what it sends is judged.
    func step() {
        ticks += 1
        if var driven = cab, !silent {
            let on = driven.track
            let track = line.track(on)
            let zones = line.description.tracks.first { $0.track == on }?.zones ?? []
            driven.drive(CabRun.dt, stops: track.stopsM, zones: zones, endOfTrack: line.endOfTrackM,
                         stoppingShort: line.cbtc.stoppingShortM, authorityEnd: authority?.endM) { [watch] nose in
                watch.limit(track: on, nose: nose)
            }
            // Five positions and about three statuses a second.
            let position = ticks % 4 == 0 ? driven.position(at: time) : nil
            let status = ticks % 6 == 0 ? driven.status(at: time, stops: track.stopsM.count) : nil
            cab = driven
            if let position { engine.receive(line: CabineWire.Codec.encode(position), from: session) }
            if let status { engine.receive(line: CabineWire.Codec.encode(status), from: session) }
        }
        engine.step(CabRun.dt)
        if ticks % 4 == 0 { engine.broadcastTraffic() }
        if ticks % 8 == 0 { engine.broadcastInfo() }
        snapshot = engine.snapshot()
        watch.observe(snapshot)
        collect()
    }

    /// Runs for up to `seconds`, and stops as soon as `done` holds. True if it came to hold (or there
    /// was nothing to wait for).
    @discardableResult
    func run(for seconds: Double, until done: (() -> Bool)? = nil) -> Bool {
        for _ in 0..<Int((seconds / CabRun.dt).rounded()) {
            step()
            if let done, done() { return true }
        }
        return done == nil
    }

    private func collect() {
        for outbound in engine.takeOutbox() {
            if outbound.session == session {
                switch outbound.message {
                case let .authority(sent): judge(sent)
                case let .result(result): results.append(result)
                case let .command(command):
                    commands.append(command)
                    // A cab answers a command.
                    if !silent { engine.receive(.result(.init(id: command.id, ok: true)), from: session) }
                case let .event(event): events.append(event)
                case let .traffic(picture): traffic = picture
                case let .info(sent): info = sent
                case let .hello(hello): hellos.append(hello)
                default: break
                }
            } else if outbound.session == monitor {
                switch outbound.message {
                case let .event(event): monitorEvents.append(event)
                case let .traffic(picture): monitorTraffic = picture
                case let .hello(hello): monitorHellos.append(hello)
                case let .result(result): monitorResults.append(result)
                default: break
                }
            }
        }
    }

    /// Forgets the last authority, when the cab's service ends: the next is the first of a new one.
    func endService() {
        cab = nil
        authority = nil
    }

    /// Holds an authority to what the specification says of it.
    private func judge(_ sent: CabineWire.Authority) {
        authorities += 1
        func fault(_ what: String) {
            if faults.count < 6 { faults.append(String(format: "at %.2f s (seq %d, %@, to %.3f): ", sent.tS, sent.seq, sent.reason.rawValue, sent.endM) + what) }
        }
        guard let cab, let mine = rame else {
            fault("sent to a cab that is not in service")
            return
        }
        let length = line.train.lengthM
        if sent.track != cab.track { fault("on track \(sent.track)") }
        if sent.validS != 3 { fault("valid for \(sent.validS) s") }
        // It lies ahead of the nose. (The cab reports its nose to the millimetre.)
        if sent.endM < cab.u - 0.001 { fault(String(format: "behind the nose at %.3f", cab.u)) }
        // It never reaches beyond the rear of the train ahead less the margin, nor the end of the track.
        var ahead: CabinePCC.Rame?
        for other in snapshot.rames where other.id != mine.id && other.track == mine.track && other.uM > mine.uM {
            if ahead == nil || other.uM < ahead!.uM { ahead = other }
        }
        if let ahead, sent.endM > ahead.uM - length - line.cbtc.safetyMarginM + 0.001 {
            fault(String(format: "beyond the rear of rame %02d at %.3f less the margin", ahead.number, ahead.uM - length))
        }
        if sent.endM > line.endOfTrackM + 0.001 { fault("beyond the end of the track") }
        switch sent.reason {
        case .train:
            if let ahead {
                let rear = ahead.uM - length
                if sent.rame != ahead.number { fault("names rame \(sent.rame ?? 0), not \(ahead.number)") }
                if abs((sent.gapM ?? -1) - (rear - mine.uM)) > 0.01 { fault(String(format: "gap %.3f, not %.3f", sent.gapM ?? -1, rear - mine.uM)) }
                // Less what the train ahead's position may be out by, too: a metre and a half at least.
                if sent.endM > rear - line.cbtc.safetyMarginM - line.cbtc.uncertaintyBaseM + 0.001 { fault("without the uncertainty of the train ahead") }
                if sent.endM < rear - line.cbtc.safetyMarginM - line.cbtc.uncertaintyMaxM - 0.001 { fault("further back than the margin and the uncertainty ask") }
            } else {
                fault("no train is ahead")
            }
        case .horizon:
            if abs(sent.endM - (mine.uM + line.cbtc.horizonM)) > 0.01 { fault("not the horizon") }
        case .end:
            if abs(sent.endM - line.endOfTrackM) > 0.01 { fault("not the end of the track") }
        case .hold, .service, .emergency:
            if sent.rame != nil || sent.gapM != nil { fault("names a train") }
        default:
            fault("unknown reason")
        }
        // It is renewed at least every 0.6 s, each with the next number.
        if let last = authority {
            let wait = sent.tS - last.tS
            if wait > longestWait { longestWait = wait }
            if wait > 0.6 + 1e-6 { fault(String(format: "%.3f s after the last", wait)) }
            if sent.seq != last.seq + 1 { fault("after seq \(last.seq)") }
        }
        authority = sent
    }
}

extension SelfTest {

    func cab(_ name: String, _ description: CabineWire.LineDescription) {
        let engine = CabinePCC.Engine(seed: 4)
        do {
            try engine.takeUp(description)
        } catch {
            check("the engine takes up the \(name)", false, "\(error)")
            return
        }
        guard let line = engine.snapshot().line else { return }
        let run = CabRun(engine: engine, line: line)
        let length = line.train.lengthM
        let stops1 = line.track(1).stopsM
        engine.open(run.session, peer: "cab A")
        engine.open(run.monitor, peer: "cab B")
        _ = engine.takeJournal()

        // Both say hello on the PCC's line: both are on the line at once.
        run.say(.hello(.init(app: "Cabine", appVersion: "selftest", cab: .init(id: "CAB-A", name: "Essai A"), line: line.identity)))
        run.say(.hello(.init(app: "Cabine", appVersion: "selftest", cab: .init(id: "CAB-B", name: "Essai B"), line: line.identity)), from: run.monitor)
        let hello = run.hellos.first
        check("a cab on the PCC's line is on the line at once",
              hello?.onLine == true && hello?.line == line.identity && hello?.protocol == 1 && hello?.app == "CabinePCC"
                && hello?.link == CabineWire.LinkTimings() && run.monitorHellos.first?.onLine == true)
        run.say(.position(.init(track: 1, uM: 300)))
        check("a report from a cab that is not in service is answered notInService", run.results.last?.error == .notInService)

        // It joins at the first stop of track 1 where an automatic rame stands, asking for the number of
        // another automatic rame: the one is withdrawn, the other renumbered.
        let before = run.snapshot
        guard let standing = before.rames.filter({ $0.track == 1 && $0.cab == nil && $0.phase == .dwelling && $0.station != nil }).min(by: { $0.uM < $1.uM }),
              let station = standing.station, let other = before.rames.first(where: { $0.cab == nil && $0.id != standing.id }) else {
            check("an automatic rame stands at a stop of track 1 for the cab to take the place of", false)
            return
        }
        let number = other.number
        run.cab = ScriptedCab(track: 1, u: stops1[station], stop: station)
        run.cab?.doors = 1
        run.cab?.dwellLeft = 12
        run.say(.join(.init(id: "j1", track: 1, uM: stops1[station], station: station, rame: number)))
        let joined = run.results.last
        let after = run.snapshot
        let mine = run.rame
        check("the cab joins at stop \(station) of track 1 and is given the number it asked for",
              joined?.ok == true && joined?.id == "j1" && joined?.rame == number && mine?.number == number && mine?.kind == .cab
                && mine?.track == 1 && mine?.uM == stops1[station] && mine?.cab?.name == "Essai A" && mine?.cab?.link == .live,
              "rame \(String(format: "%02d", number))")
        check("the automatic rame that stood there is withdrawn: the cab has taken its place",
              !after.rames.contains { $0.id == standing.id } && after.rames.count == before.rames.count)
        let renumbered = after.rames.first { $0.id == other.id }
        check("the automatic rame that held the number is given another",
              renumbered != nil && renumbered?.number != number && Set(after.rames.map(\.number)).count == after.rames.count,
              "now rame \(String(format: "%02d", renumbered?.number ?? 0))")
        check("its first authority comes with the answer", run.authority != nil && run.authorities == 1)
        check("the other cab is told of it", run.monitorEvents.contains { $0.event == .peer && $0.rame == number && $0.name == "Essai A" && $0.state == .joined })
        run.say(.join(.init(id: "j2", track: 3, uM: 300)))
        let badTrack = run.results.last
        run.say(.join(.init(id: "j3", track: 1, uM: line.lengthM + 10)), from: run.monitor)
        check("a join with a track or a place that does not exist is refused with badValue",
              badTrack?.error == .badValue && badTrack?.id == "j2" && run.monitorResults.last?.error == .badValue
                && run.monitorResults.last?.id == "j3" && run.snapshot.cabs.count == 1)

        // It drives down the line, stopping at each stop, as far as a stop where it then waits. The
        // authority is judged every time one comes (CabRun.judge).
        let waitAt = min(station + 2, stops1.count - (stops1.count > 2 ? 2 : 1))
        let arrived = run.run(for: 1_800) { run.cab?.stop == waitAt && (run.cab?.dwellLeft ?? 0) > 0 }
        run.cab?.stay()
        check("the cab drives to stop \(waitAt), calling at each stop on the way",
              arrived && abs((run.cab?.u ?? 0) - stops1[waitAt]) < 0.5 && run.cab?.calls == waitAt - station,
              String(format: "there after %.0f s, %d authorities", run.time, run.authorities))
        run.run(for: 1)
        run.engine.broadcastTraffic()
        run.look()
        let seen = run.monitorTraffic?.trains.first { $0.rame == number }
        check("the fleet picture shows the cab to the other cab, and not to itself",
              seen?.kind == .cab && seen?.name == "Essai A" && seen?.track == 1 && abs((seen?.uM ?? 0) - stops1[waitAt]) < 0.5
                && seen?.doors == 1 && seen?.phase == .dwelling && seen?.station == waitAt && seen?.lengthM == length
                && run.traffic?.trains.contains { $0.rame == number } == false
                && run.traffic?.trains.count == run.snapshot.rames.count - 1 && run.monitorTraffic?.trains.count == run.snapshot.rames.count,
              "\(seen.map { "rame \($0.rame) \($0.kind) at \($0.uM), doors \($0.doors), \($0.phase), station \($0.station ?? -1)" } ?? "not in it")")

        // The automatic rames behind it stop short of it.
        func follower() -> CabinePCC.Rame? {
            guard let mine = run.rame else { return nil }
            return run.snapshot.rames.first {
                $0.cab == nil && $0.track == 1 && $0.uM < mine.uM && $0.speedMS == 0 && $0.phase == .running
                    && mine.uM - length - $0.uM < line.followingDistanceM + 2
            }
        }
        let caughtUp = run.run(for: 2_400) { follower() != nil }
        var stoodOff = false
        var gap = 0.0
        if caughtUp, let behind = follower() {
            // Once it has settled, it stays where it is.
            run.run(for: 15)
            let settledAt = run.snapshot.rames.first { $0.id == behind.id }
            run.run(for: 10)
            if let still = run.snapshot.rames.first(where: { $0.id == behind.id }), let mine = run.rame {
                gap = mine.uM - length - still.uM
                stoodOff = gap >= line.cbtc.safetyMarginM && gap <= line.followingDistanceM + 0.6 && still.uM == settledAt?.uM && still.speedMS == 0
            }
        }
        check("an automatic rame comes up behind the cab and stops short of it", stoodOff,
              caughtUp ? String(format: "%.2f m behind its rear, after %.0f s", gap, run.time) : "none came within \(Int(run.time)) s")

        /// The automatic rames that stand between stations with the way clear ahead of them, now and for
        /// the next ten seconds: none should, once nothing holds the line. (One that queues behind the
        /// train ahead, or waits in a tail or at a platform, is where it should be.)
        func stranded() -> [Int] {
            func standing() -> Set<Int> {
                let rames = run.snapshot.rames
                let loop = 2 * line.lengthM
                return Set(rames.filter { rame in
                    guard rame.cab == nil, rame.phase == .running, rame.speedMS == 0, rame.uM < line.endOfTrackM - 3 else { return false }
                    let nose = line.loopPosition(track: rame.track, uM: rame.uM)
                    var least = Double.infinity
                    for other in rames where other.id != rame.id {
                        var ahead = line.loopPosition(track: other.track, uM: other.uM) - nose
                        if ahead < 0 { ahead += loop }
                        least = min(least, ahead)
                    }
                    return least - length > line.followingDistanceM + 10
                }.map(\.number))
            }
            var still = standing()
            for _ in 0..<200 where !still.isEmpty {
                run.step()
                still.formIntersection(standing())
            }
            return still.sorted()
        }

        // The operator holds it: its authority is pulled back to where it stands.
        func nose() -> Double { run.cab?.u ?? -1 }
        func settled(_ reason: CabineWire.AuthorityReason) -> Bool {
            run.authority?.reason == reason && abs((run.authority?.endM ?? -1) - nose()) < 0.001
        }
        try? engine.hold(rame: number, true)
        run.look()
        let holdOrder = run.commands.last
        run.step()
        let heldAtOnce = settled(.hold)
        run.run(for: 3)
        check("hold: the cab is ordered to hold, and its authority ends where it stands, at once",
              holdOrder?.command == .hold && holdOrder?.value == .bool(true) && heldAtOnce && settled(.hold)
                && run.rame?.held == true && run.rame?.phase == .held,
              String(format: "authority to %.3f m (%@), nose at %.3f m", run.authority?.endM ?? 0, run.authority?.reason.rawValue ?? "-", nose()))
        try? engine.hold(rame: number, false)
        run.look()
        let releaseOrder = run.commands.last
        run.run(for: 0.7)
        check("release: the hold is lifted and the authority reaches ahead again",
              releaseOrder?.command == .hold && releaseOrder?.value == .bool(false) && run.authority?.reason != .hold
                && (run.authority?.endM ?? 0) > nose() + 1 && run.rame?.held == false)

        // The general emergency stop: the same, for every train.
        engine.setEmergencyStop(true)
        run.look()
        let brakeOrder = run.commands.last
        run.step()
        let stoppedAtOnce = settled(.emergency)
        run.run(for: 25)
        run.engine.broadcastInfo()
        run.look()
        let allStopped = run.snapshot.rames.allSatisfy { $0.speedMS == 0 }
        let betweenStations = run.snapshot.rames.filter { $0.cab == nil && $0.phase == .emergency }.count
        /// How the cab's authority and the line stand, in words, for a check that fails.
        func asItStands() -> String {
            let moving = run.snapshot.rames.filter { $0.speedMS != 0 }.map { String(format: "%02d", $0.number) }
            return "authority to \(run.authority?.endM ?? 0) (\(run.authority?.reason.rawValue ?? "-")), nose at \(nose()), "
                + "still moving: \(moving.isEmpty ? "none" : moving.joined(separator: " ")), mode \(run.info?.mode.rawValue ?? "-")"
        }
        let allBraked = brakeOrder?.command == .emergencyBrake && brakeOrder?.value == .bool(true) && stoppedAtOnce && settled(.emergency)
            && allStopped && run.info?.mode == .emergency && run.snapshot.mode == .emergency
        check("general emergency stop: the cab is ordered to brake, its authority ends where it stands, and every rame comes to a stand",
              allBraked, allBraked ? "\(betweenStations) automatic rames braked between stations" : asItStands())
        engine.setEmergencyStop(false)
        run.look()
        let unbrakeOrder = run.commands.last
        run.run(for: 40)
        var idle = stranded()
        run.engine.broadcastInfo()
        run.look()
        check("its release: the cab's brake is released, the authority reaches ahead and the rames run again",
              unbrakeOrder?.command == .emergencyBrake && unbrakeOrder?.value == .bool(false) && run.authority?.reason != .emergency
                && (run.authority?.endM ?? 0) > nose() + 1 && run.info?.mode == .normal
                && !run.snapshot.rames.contains { $0.cab == nil && $0.phase == .emergency } && idle.isEmpty,
              idle.isEmpty ? "\(run.snapshot.rames.filter { $0.cab == nil && $0.speedMS > 1 }.count) automatic rames on the move" : "left standing: \(idle)")

        // Line service off: no train has leave to move.
        engine.setService(false)
        run.step()
        let outAtOnce = settled(.service)
        run.run(for: 60)
        run.engine.broadcastInfo()
        run.look()
        let out = outAtOnce && settled(.service) && run.snapshot.rames.allSatisfy { $0.speedMS == 0 } && run.info?.mode == .stopped
        check("line service off: the authority ends where the cab stands and every rame comes to a stand", out, out ? "" : asItStands())
        engine.setService(true)
        run.run(for: 40)
        idle = stranded()
        check("line service on again: the rames run again",
              run.authority?.reason != .service && (run.authority?.endM ?? 0) > nose() + 1 && run.snapshot.mode == .normal && idle.isEmpty,
              idle.isEmpty ? "\(run.snapshot.rames.filter { $0.cab == nil && $0.speedMS > 1 }.count) automatic rames on the move" : "left standing: \(idle)")

        // The operator's words and call reach the cab; too many words do not leave.
        try? engine.message(rame: number, "REPRENEZ LA MARCHE NORMALE")
        try? engine.call(rame: number)
        run.look()
        let orders = run.commands.suffix(2)
        var tooLong = false
        do { try engine.message(rame: number, String(repeating: "A", count: 121)) } catch { tooLong = true }
        var notACab = false
        if let automatic = run.snapshot.rames.first(where: { $0.cab == nil }) {
            do { try engine.call(rame: automatic.number) } catch { notACab = error as? CabinePCC.OrderError == .notACab(automatic.number) }
        }
        check("a message and a call are sent to the cab as commands; 121 characters, or a call to an automatic rame, are refused",
              orders.count == 2 && orders.first?.command == .message && orders.first?.value == .string("REPRENEZ LA MARCHE NORMALE")
                && orders.last?.command == .call && orders.last?.value == nil && orders.first?.id != orders.last?.id && tooLong && notACab)

        // The driver's reports, calls and brake reach the operator's journal.
        _ = engine.takeJournal()
        run.say(.event(.init(event: .report, code: .passengerIll, text: "MALAISE VOYAGEUR")))
        run.say(.event(.init(event: .call)))
        run.say(.event(.init(event: .acknowledge)))
        run.say(.event(.init(event: .emergencyBrake, applied: true, cause: "FREINAGE D'URGENCE CONDUCTEUR")))
        let braked = run.rame
        run.say(.event(.init(event: .emergencyBrake, applied: false)))
        let journal = engine.takeJournal().map(\.event)
        check("a driver's report, call, acknowledgement and emergency brake are put before the operator",
              journal == [.cabReport(name: "Essai A", rame: number, code: .passengerIll, text: "MALAISE VOYAGEUR"),
                          .cabCall(name: "Essai A", rame: number), .cabAcknowledge(name: "Essai A", rame: number),
                          .cabEmergencyBrake(name: "Essai A", rame: number, applied: true, cause: "FREINAGE D'URGENCE CONDUCTEUR"),
                          .cabEmergencyBrake(name: "Essai A", rame: number, applied: false, cause: nil)]
                && braked?.cab?.emergencyBrake == true && braked?.phase == .emergency && run.rame?.cab?.emergencyBrake == false
                && run.rame?.cab?.lastReport?.code == .passengerIll && run.rame?.cab?.mode == .pa && run.rame?.cab?.automatic == true)

        // It runs on, and falls silent on the move: its train is held where it was last seen, at a
        // stand, as an obstacle.
        run.cab?.leave()
        let moving = run.run(for: 600) { (run.cab?.v ?? 0) > 8 }
        run.run(for: 1)
        let lastSeen = run.rame
        let heardAt = run.time
        let cabRame = lastSeen?.id ?? -1
        run.silent = true
        run.run(for: 2.5)
        let stillLive = run.rame?.cab?.link == .live
        run.run(for: 1)
        let held = run.rame
        let reckoned = (lastSeen?.uM ?? 0) + 0.5 * (lastSeen?.speedMS ?? 0) + 1
        check("a cab that falls silent for 3 s is held where it was last seen, at a stand, as an obstacle",
              moving && stillLive && held?.kind == .cab && held?.cab?.link == .silent && held?.speedMS == 0
                && (held?.uM ?? 0) >= (lastSeen?.uM ?? 0) && (held?.uM ?? 0) <= reckoned && held?.phase == .emergency,
              String(format: "last seen at %.1f m at %.1f m/s, held at %.1f m", lastSeen?.uM ?? 0, lastSeen?.speedMS ?? 0, held?.uM ?? 0))
        run.run(for: 25.5)
        let stillHeld = run.snapshot.rames.first { $0.id == cabRame }
        run.run(for: 31.5 - (run.time - heardAt))
        let handed = run.snapshot.rames.first { $0.id == cabRame }
        run.endService()
        let handBack = engine.takeJournal().map(\.event)
        check("after 30 s of silence its train is handed back to automation",
              stillHeld?.kind == .cab && stillHeld?.uM == held?.uM && handed?.kind == .auto && handed?.cab == nil
                && handed?.number == number && run.snapshot.cabs.isEmpty
                && handBack.contains(.cabSilent(name: "Essai A", rame: number)) && handBack.contains(.cabHandedBack(name: "Essai A", rame: number, number: number))
                && run.monitorEvents.contains { $0.event == .peer && $0.rame == number && $0.state == .left })
        run.silent = false
        run.say(.position(.init(track: 1, uM: handed?.uM ?? 0, speedMS: 0)))
        check("the cab is then no longer in service: its report is answered notInService", run.results.last?.error == .notInService)
        let ranOn = run.run(for: 900) {
            guard let now = run.snapshot.rames.first(where: { $0.id == cabRame }), let handed else { return false }
            return now.cab == nil && now.phase == .dwelling && now.doors == 1 && (now.track != handed.track || now.uM > handed.uM + 1)
        }
        let called = run.snapshot.rames.first { $0.id == cabRame }
        check("and it runs on as an automatic rame: it calls at the next stop", ranOn,
              "stop \(called?.station ?? -1) of track \(called?.track ?? 0)")

        // It joins again, on track 2, where an automatic rame stands, asking for no number; drives off;
        // and leaves on the move: its train is handed back at once.
        let stops2 = line.track(2).stopsM
        func standingOn2() -> CabinePCC.Rame? {
            run.snapshot.rames.filter { $0.track == 2 && $0.cab == nil && $0.phase == .dwelling && $0.doors == 1 && $0.station != nil }.min { $0.uM < $1.uM }
        }
        guard run.run(for: 900, until: { standingOn2() != nil }), let place = standingOn2(), let stop2 = place.station else {
            check("an automatic rame stands at a stop of track 2 for the cab to take the place of", false)
            return
        }
        run.monitorEvents.removeAll()
        run.cab = ScriptedCab(track: 2, u: stops2[stop2], stop: stop2)
        run.cab?.doors = 1
        run.cab?.dwellLeft = 3
        run.say(.join(.init(id: "j4", track: 2, uM: stops2[stop2], station: stop2)))
        let again = run.results.last
        let second = run.rame
        check("the cab joins again on track 2 with no number asked for: it is given a free one of the fleet",
              again?.ok == true && again?.id == "j4" && second != nil && second?.number == again?.rame && (1...52).contains(again?.rame ?? 0)
                && !run.snapshot.rames.contains { $0.id == place.id } && Set(run.snapshot.rames.map(\.number)).count == run.snapshot.rames.count,
              "rame \(String(format: "%02d", again?.rame ?? 0))")
        let farthest = min(stop2 + 3, stops2.count - 1)
        let further = run.run(for: 3_600) { run.cab?.stop == farthest && (run.cab?.dwellLeft ?? 0) > 0 }
        check("on track 2 it drives on to stop \(farthest), calling at each stop on the way, inside its authority all the way",
              further && abs((run.cab?.u ?? 0) - stops2[farthest]) < 0.5 && run.cab?.calls == farthest - stop2 && run.faults.isEmpty,
              run.faults.isEmpty ? "\(run.authorities) authorities so far" : run.faults.joined(separator: "; "))
        let offAgain = run.run(for: 300) { (run.cab?.v ?? 0) > 5 }
        run.run(for: 1)
        let leaving = run.rame
        run.say(.leave(.init(id: "v1", reason: .ended)))
        let left = run.results.last
        let atOnce = run.snapshot.rames.first { $0.id == leaving?.id }
        run.endService()
        check("leave hands its train back at once, where it is and as it runs",
              offAgain && left?.ok == true && left?.id == "v1" && atOnce?.kind == .auto && atOnce?.uM == leaving?.uM
                && (atOnce?.speedMS ?? 0) > 5 && run.snapshot.cabs.isEmpty
                && run.monitorEvents.contains { $0.event == .peer && $0.state == .left && $0.rame == leaving?.number },
              String(format: "at %.1f m, %.1f m/s", atOnce?.uM ?? 0, atOnce?.speedMS ?? 0))
        run.say(.leave(.init(id: "v2", reason: .quit)))
        check("a leave from a cab that is not in service is answered notInService", run.results.last?.error == .notInService && run.results.last?.id == "v2")
        let onward = run.run(for: 900) {
            guard let now = run.snapshot.rames.first(where: { $0.id == leaving?.id }), let leaving else { return false }
            return now.cab == nil && now.phase == .dwelling && now.doors == 1 && (now.track != leaving.track || now.uM > leaving.uM + 1)
        }
        check("and that train too runs on as an automatic rame", onward)

        // What held all the way through.
        check("its authority was renewed at least every 0.6 s, and was all the specification says of it", run.faults.isEmpty && run.longestWait <= 0.6 + 1e-6,
              run.faults.isEmpty ? String(format: "%d authorities, %.2f s apart at most", run.authorities, run.longestWait) : run.faults.joined(separator: "; "))
        let watch = run.watch
        check("with a cab on the line: no two trains ever nearer than the safety margin, no automatic rame over its limit", watch.count(.gap) == 0 && watch.count(.speed) == 0,
              watch.count(.gap) + watch.count(.speed) == 0
                ? String(format: "least %.2f m from a nose to the rear ahead, nearest %.2f m/s under a limit, over %.0f min", watch.leastGap, -watch.nearestToLimit, run.time / 60)
                : describe(watch))
        check("with a cab on the line: the automatic rames still call at every stop in order, within 1 m, doors open, and turn back as they should",
              watch.count(.order) + watch.count(.stop) + watch.count(.doors) + watch.count(.turn) == 0,
              watch.faultless ? "\(watch.calls) calls" : describe(watch))
        let target = SelfTest.fleet(lap: run.snapshot.lapTimeS, headway: run.snapshot.headwayS, line)
        let whole = run.run(for: 1_200) { run.snapshot.rames.count == target }
        check("the fleet is whole again once the cab has gone", whole && run.snapshot.automaticTarget == target && run.snapshot.cabs.isEmpty,
              "\(run.snapshot.rames.count) rames")
    }
}

import Foundation
import Combine
import CabinePCCKit

// PCC LINK -- this node as the PCC of Cabine cabs.
//
// Cabine is a metro driving simulator seen from the cab. In its PCC mode it
// no longer works out the other trains of its line, nor its own movement
// authority: it dials a PCC that speaks the wire of docs/cabine-link.md, and
// that PCC is the simulation engine behind every Cabine connected to it. The
// engine is the package in Engine/ (CabinePCCKit): it keeps a library of
// lines, runs the one its operator puts it on, drives the automatic rames,
// keeps every train apart in moving block, gives each cab its movement
// authority and takes the operator's orders. This class is its host and its
// operator's desk:
//
//   * THE SERVER -- one CabinePCC.Server, started with the node unless the
//     operator has disabled the PCC. It listens on every interface and
//     advertises `_cabinepcc._tcp` (LAN on), or on loopback only (LAN off).
//     It runs the engine on a queue of its own, and keeps the process out of
//     App Nap for as long as it runs.
//   * THE LIBRARY -- the lines the program was built with and the operator's
//     own (LineLibrary.swift), kept in the engine at each start; then the
//     line the PCC was last on is taken up.
//   * THE PICTURE -- four times a second the server's snapshot, how its
//     listener stands and what its journal has gathered are published, for
//     the PCC Dispatcher and the DCL verbs, monitors and forms.
//   * THE ORDERS -- which line; service, the general emergency stop, headway
//     and fleet size; and for one rame hold, emergency brake, message and
//     call. Each returns an Outcome that the caller puts in the operator's
//     words (PCCText.swift).
//   * SCADA -- the general emergency stop, a cab that has fallen silent, an
//     emergency brake, a listener that failed and a cab that holds another
//     revision of the line are process-driven points; a driver's coded
//     report or call and a line file that was refused are events the
//     operator acknowledges and clears.
//   * SETTINGS -- enabled, LAN, headway, the PCC's name and the line it was
//     last on, kept in the node's settings under `pcc.`.
//
// None of the simulation is done here. A dispatch desk talking to a cab
// simulator -- not a safety controller.
@MainActor
final class PCCLink: ObservableObject {

    /// How the listener stands.
    enum Listener: Equatable {
        /// The operator has disabled the PCC.
        case disabled
        case starting
        case listening(port: UInt16)
        /// In the system's words.
        case failed(String)
    }

    /// One line of the journal, numbered as it came.
    struct JournalLine: Identifiable, Equatable {
        let id: Int
        /// The line's time of day when it happened; nil while the PCC was
        /// on no line.
        let clockS: Double?
        let event: Event

        enum Event: Equatable {
            /// Something the engine noted.
            case engine(CabinePCC.JournalEntry.Event)
            /// The library was read: so many lines are held.
            case libraryRead(held: Int)
            /// A line file is not a good package, and was skipped.
            case lineFileRefused(file: String, fault: LineFileFault)
            /// The line the PCC was last on is not in the library.
            case lineNotHeld(id: String)
            /// The operator put the PCC on no line.
            case lineClosed
        }
    }

    /// What became of an operator's order.
    enum Outcome: Equatable {
        case done
        case refused(Refusal)
    }

    /// Why an order was not carried out. `PCCText.refusal` puts it in the
    /// operator's words.
    enum Refusal: Equatable {
        /// The PCC is disabled, or its listener has yet to start.
        case notRunning
        case noLine
        case noSuchRame(Int)
        case notACab(Int)
        /// The cab's train is on the line, but its connection is gone.
        case cabNotConnected(Int)
        case headwayOutOfRange
        case fleetOutOfRange
        case emptyMessage
        /// With the length of the message that was refused.
        case messageTooLong(Int)
        case emptyName
        /// A cab is in service on the present line.
        case lineInUse
        /// The library holds no line of that id.
        case noSuchLine(String)
        /// What the engine said, when it is none of the above.
        case other(String)
    }

    @Published private(set) var listener: Listener
    /// True when the listener has been starting for longer than one takes.
    /// On the LAN that is what a Mac does that has refused the program the
    /// local network, or has yet to be asked.
    @Published private(set) var isSlowToStart = false
    /// The line and everything on it; nil while the PCC is not running.
    @Published private(set) var snapshot: CabinePCC.Snapshot?
    /// The last `journalLimit` things that happened, the newest last.
    @Published private(set) var journal: [JournalLine] = []
    /// Where the data of each line of the library came from; none for a
    /// line whose package has no source.
    @Published private(set) var credits: [CabineWire.LineIdentity: LineCredits] = [:]
    @Published private(set) var isEnabled: Bool
    /// Listening on every interface and advertised by Bonjour; off, on
    /// loopback only and not advertised.
    @Published private(set) var isLAN: Bool
    /// Seconds between trains each way that the fleet is sized for.
    @Published private(set) var headwayS: Double
    /// The PCC's name, for the cabs' displays and for Bonjour.
    @Published private(set) var name: String

    static let journalLimit = 200
    private static let scanInterval: TimeInterval = 0.25
    /// How long a listener may take to start before the operator is told.
    private static let slowStart: TimeInterval = 5

    private let world: PCCWorld
    private let environment: PCCEnvironment
    private var settings: PCCSettingsStore { environment.settings }
    private var server: CabinePCC.Server?
    private var timer: Timer?
    private var started = false
    private var startedAt = Date.distantPast
    /// Servers that have been closed and whose listeners have yet to let go
    /// of the port: one started before that would find the port taken and
    /// settle on another, where no cab would look for it.
    private var closing = 0
    /// The id of the line the PCC is to be on when its server starts; nil
    /// once its operator has put it on none.
    private var wantedLine: String?
    private var journalCount = 0
    /// The process-driven points raised and not yet returned to normal.
    private var standing: Set<Point> = []
    private var idle: Idle?

    /// A SCADA point.
    private struct Point: Hashable {
        let source: String
        let point: String
    }

    /// What a PCC with no line and no connection shows of itself. While it
    /// stays the same nothing is published, so that a window left open on an
    /// idle PCC is not drawn again four times a second.
    private struct Idle: Equatable {
        let headwayS: Double
        let fleetSize: Int?
        let library: [CabinePCC.HeldLine]
    }

    init(world: PCCWorld, environment: PCCEnvironment) {
        self.world = world
        self.environment = environment
        let settings = environment.settings
        let enabled = settings.bool(PCCSettingKey.enabled) ?? true
        isEnabled = enabled
        isLAN = settings.bool(PCCSettingKey.lan) ?? true
        headwayS = settings.double(PCCSettingKey.headway).flatMap { CabinePCC.Settings.headwayRange.contains($0) ? $0 : nil }
            ?? CabinePCC.Settings().headwayS
        name = Self.cleanName(settings.string(PCCSettingKey.name)) ?? "PCC \(world.label)"
        wantedLine = Self.cleanName(settings.string(PCCSettingKey.line)) ?? environment.firstLine
        listener = enabled ? .starting : .disabled
    }

    // MARK: -- lifecycle

    /// Called once when the node starts: starts the server, unless the
    /// operator has disabled it, and the scan that publishes its picture.
    func start() {
        guard !started else { return }
        started = true
        // The folder an operator puts lines of his own in is there to be found.
        try? FileManager.default.createDirectory(at: environment.linesFolder, withIntermediateDirectories: true)
        startServer()
        let t = Timer(timeInterval: Self.scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func startServer() {
        // While a server is closing this waits: it is asked again when the
        // port is free.
        guard started, server == nil, isEnabled, closing == 0 else { return }
        var settings = CabinePCC.Settings()
        settings.name = name
        settings.pccID = world.nodeId
        settings.headwayS = headwayS
        var configuration = CabinePCC.Server.Configuration()
        configuration.port = environment.pccPort
        configuration.fallsBackToAnyPort = environment.pccFallsBackToAnyPort
        configuration.loopbackOnly = !isLAN
        configuration.bonjour = isLAN
        // The dwell of each automatic rame is drawn from the seed: another
        // at each start, so that no two days on a line are the same.
        let fresh = CabinePCC.Server(settings: settings, configuration: configuration,
                                     seed: UInt64.random(in: 1...UInt64.max))
        fresh.start()
        server = fresh
        startedAt = Date()
        // The lines first, then the one the PCC was last on.
        readLibrary(into: fresh)
        if let wanted = wantedLine {
            if let held = Self.line(wanted, in: fresh.snapshot().library) {
                try? fresh.takeUp(held: held.identity)
            } else {
                note(.lineNotHeld(id: wanted))
                world.raiseAlarm(source: "PCC", point: "LIGNE", severity: .minor,
                                 message: Strings.lookup("alarm.msg.pcc.linenotheld", lang: .en))
            }
        }
        refresh()
    }

    /// Closes the PCC: the cabs are told, then their connections and the
    /// listener are closed. The line goes with the engine.
    private func stopServer() {
        guard let old = server else { return }
        server = nil
        closing += 1
        old.stop { [weak self] in
            // The port is free. A PCC that is to run starts now; asking does
            // no harm to one that is disabled, or already started.
            Task { @MainActor in
                guard let self else { return }
                self.closing -= 1
                self.startServer()
            }
        }
        refresh()
    }

    /// How the server listens, and the name it gives, are fixed when it is
    /// made: a change to either takes a new one.
    private func restartServer() {
        guard server != nil else { return }
        stopServer()
        startServer()
    }

    /// Tells the cabs the PCC is closing and closes it, for the end of the
    /// program. It waits a moment for the word to leave: the process ends
    /// whether it has left or not, and the cabs see the connection close.
    func closeForQuit() {
        timer?.invalidate()
        timer = nil
        // Nothing starts again behind it.
        started = false
        guard let old = server else { return }
        server = nil
        let gone = DispatchSemaphore(value: 0)
        old.stop { gone.signal() }
        _ = gone.wait(timeout: .now() + 0.3)
    }

    /// When the PCC began to listen, for as long as it has.
    var listeningSince: Date? {
        if case .listening = listener { return startedAt }
        return nil
    }

    // MARK: -- the library

    /// Keeps in the engine every line the program was built with, then
    /// every one of the operator's. A file that is not a good package is
    /// reported in the journal and the alarm log, and skipped.
    private func readLibrary(into server: CabinePCC.Server) {
        var refused = 0
        var known = credits
        for file in LineLibrary.files(bundled: environment.bundledLines, own: environment.linesFolder) {
            do {
                let package = try CabineWire.LinePackage.decode(file: file)
                try server.keep(package)
                known[package.identity] = LineCredits(package)
            } catch {
                refused += 1
                note(.lineFileRefused(file: file.lastPathComponent, fault: LineLibrary.fault(error)))
            }
        }
        let held = server.snapshot().library
        // A line that is no longer held has no credits to show.
        known = known.filter { entry in held.contains { $0.identity == entry.key } }
        if known != credits { credits = known }
        note(.libraryRead(held: held.count))
        if refused > 0 {
            // A new word takes the place of the last, and is put in front
            // of the operator again.
            world.clearAlarm(source: "PCC", point: "FICHIER")
            world.raiseAlarm(source: "PCC", point: "FICHIER", severity: .minor,
                             message: Strings.lookup("alarm.msg.pcc.linefile", lang: .en))
        }
    }

    /// The line of a library that an operator means by an id: the one kept
    /// last under it, which is the operator's own when the program was
    /// built with another revision.
    static func line(_ id: String, in library: [CabinePCC.HeldLine]) -> CabinePCC.HeldLine? {
        let wanted = id.trimmingCharacters(in: .whitespaces).lowercased()
        return library.last { $0.identity.id.lowercased() == wanted }
    }

    /// A line of the library as it was kept: its description, and its
    /// source if it has one.
    func package(_ identity: CabineWire.LineIdentity) -> CabineWire.LinePackage? {
        server?.heldPackage(identity)
    }

    /// Reads the lines again: what is new or changed in the operator's
    /// folder is kept without the PCC being closed.
    @discardableResult
    func rereadLibrary() -> Outcome {
        guard let server else { return .refused(.notRunning) }
        readLibrary(into: server)
        refresh()
        return .done
    }

    // MARK: -- the picture

    /// Reads the server's picture and its journal, publishes what has
    /// changed and samples the SCADA points. The scan calls it four times a
    /// second; an order calls it at once, so that what it changed shows.
    func refresh() {
        let fresh = server?.snapshot()
        if let entries = server?.takeJournal(), !entries.isEmpty { keep(entries) }

        let now: Listener
        switch server?.state {
        case nil: now = isEnabled ? .starting : .disabled
        case .idle?, .starting?, .stopped?: now = .starting
        case let .listening(port)?: now = .listening(port: port)
        case let .failed(reason)?: now = .failed(reason)
        }
        if now != listener { listener = now }
        let slow = now == .starting && server != nil && Date().timeIntervalSince(startedAt) > Self.slowStart
        if slow != isSlowToStart { isSlowToStart = slow }

        publish(fresh)
        sampleAlarms(fresh)
    }

    private func publish(_ fresh: CabinePCC.Snapshot?) {
        guard let fresh else {
            idle = nil
            if snapshot != nil { snapshot = nil }
            return
        }
        if fresh.line == nil, fresh.sessions.isEmpty {
            let quiet = Idle(headwayS: fresh.headwayS, fleetSize: fresh.fleetSize, library: fresh.library)
            if quiet == idle, snapshot != nil { return }
            idle = quiet
        } else {
            idle = nil
        }
        snapshot = fresh
    }

    private func keep(_ entries: [CabinePCC.JournalEntry]) {
        var lines = journal
        for entry in entries {
            journalCount += 1
            lines.append(JournalLine(id: journalCount, clockS: entry.clockS, event: .engine(entry.event)))
            annunciate(entry)
        }
        if lines.count > Self.journalLimit { lines.removeFirst(lines.count - Self.journalLimit) }
        journal = lines
    }

    /// Puts in the journal something this desk did, or found.
    private func note(_ event: JournalLine.Event) {
        journalCount += 1
        var lines = journal
        lines.append(JournalLine(id: journalCount, clockS: snapshot?.line == nil ? nil : snapshot?.clockS, event: event))
        if lines.count > Self.journalLimit { lines.removeFirst(lines.count - Self.journalLimit) }
        journal = lines
    }

    /// The host and port to give a Cabine: this Mac's name on the network,
    /// or localhost while the PCC listens on loopback only.
    var address: (host: String, port: UInt16)? {
        guard case let .listening(port) = listener else { return nil }
        return (isLAN ? Self.hostName : "localhost", port)
    }

    private static let hostName: String = {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&buffer, Int(MAXHOSTNAMELEN)) == 0 else { return "localhost" }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? "localhost" : name
    }()

    // MARK: -- SCADA

    /// The source of a cab's points: CABINE and its rame's number, or CABINE
    /// alone for a cab that is not in service.
    private static func source(cab rame: Int?) -> String {
        rame.map { String(format: "CABINE %02d", $0) } ?? "CABINE"
    }

    /// The process-driven points: raised while the condition holds,
    /// returned to normal when it clears -- or when the train is no longer
    /// on the line, or the PCC has closed.
    private func sampleAlarms(_ snapshot: CabinePCC.Snapshot?) {
        var holding: Set<Point> = []
        func hold(_ source: String, _ point: String, _ severity: AlarmSeverity, _ messageKey: String) {
            world.raiseAlarm(source: source, point: point, severity: severity,
                             message: Strings.lookup(messageKey, lang: .en), processDriven: true)
            holding.insert(Point(source: source, point: point))
        }
        if case .failed = listener { hold("PCC", "ECOUTE", .critical, "alarm.msg.pcc.listener") }
        if let snapshot {
            if snapshot.emergencyStop { hold("LIGNE", "AU", .critical, "alarm.msg.emergency") }
            for rame in snapshot.rames.sorted(by: { $0.number < $1.number }) {
                if let cab = rame.cab {
                    let source = Self.source(cab: rame.number)
                    if cab.link == .silent { hold(source, "LIAISON", .major, "alarm.msg.cab.silent") }
                    // Its own emergency brake, or the one the PCC has ordered.
                    if cab.emergencyBrake || rame.braked { hold(source, "FU", .major, "alarm.msg.fu") }
                } else if rame.braked {
                    hold(String(format: "RAME %02d", rame.number), "FU", .major, "alarm.msg.fu")
                }
            }
            // A cab that names the PCC's line in another revision cannot come
            // on it: it is another version of Cabine than the package's.
            if let line = snapshot.line?.identity {
                for session in snapshot.sessions {
                    guard let named = session.line, named.id == line.id, named.rev != line.rev else { continue }
                    hold("CABINE \(session.id)", "REVISION", .minor, "alarm.msg.cab.revision")
                }
            }
        }
        for point in standing.subtracting(holding) {
            world.clearAlarm(source: point.source, point: point.point)
        }
        standing = holding
    }

    /// What a driver says to the PCC is an event: it stands until the
    /// operator has acknowledged and cleared it.
    private func annunciate(_ entry: CabinePCC.JournalEntry) {
        let event: (rame: Int?, point: String, severity: AlarmSeverity, messageKey: String)
        switch entry.event {
        case let .cabReport(_, rame, code, _):
            let (severity, messageKey) = Self.reportAlarm(code)
            event = (rame, "RADIO", severity, messageKey)
        case let .cabCall(_, rame):
            event = (rame, "APPEL", .minor, "alarm.msg.cab.call")
        default:
            return
        }
        // A new word from the driver takes the place of the last, and is
        // put in front of the operator again.
        let source = Self.source(cab: event.rame)
        world.clearAlarm(source: source, point: event.point)
        world.raiseAlarm(source: source, point: event.point, severity: event.severity,
                         message: Strings.lookup(event.messageKey, lang: .en))
    }

    private static func reportAlarm(_ code: CabineWire.ReportCode?) -> (AlarmSeverity, String) {
        switch code {
        case .radioCheck?:      return (.advisory, "alarm.msg.cab.report.radiocheck")
        case .readyToDepart?:   return (.advisory, "alarm.msg.cab.report.readytodepart")
        case .stoppedAtSignal?: return (.minor, "alarm.msg.cab.report.stoppedatsignal")
        case .passengerIll?:    return (.major, "alarm.msg.cab.report.passengerill")
        case .technicalFault?:  return (.major, "alarm.msg.cab.report.technicalfault")
        case .incidentOver?:    return (.advisory, "alarm.msg.cab.report.incidentover")
        case .requestCall?:     return (.minor, "alarm.msg.cab.report.requestcall")
        default:                return (.minor, "alarm.msg.cab.report.other")
        }
    }

    // MARK: -- settings (SET PCC /ENABLE /DISABLE /LAN /NAME)

    /// Starts the PCC, or closes it.
    @discardableResult
    func setEnabled(_ on: Bool) -> Outcome {
        guard on != isEnabled else { return .done }
        isEnabled = on
        settings.set(on, for: PCCSettingKey.enabled)
        if on { startServer() } else { stopServer() }
        refresh()
        return .done
    }

    /// Every interface and Bonjour, or loopback only. A PCC that is running
    /// closes and starts again on the line it was on: its cabs dial it
    /// again.
    @discardableResult
    func setLAN(_ on: Bool) -> Outcome {
        guard on != isLAN else { return .done }
        isLAN = on
        settings.set(on, for: PCCSettingKey.lan)
        restartServer()
        return .done
    }

    /// Names the PCC. A PCC that is running closes and starts again.
    @discardableResult
    func setName(_ text: String) -> Outcome {
        guard let clean = Self.cleanName(text) else { return .refused(.emptyName) }
        guard clean != name else { return .done }
        name = clean
        settings.set(clean, for: PCCSettingKey.name)
        restartServer()
        return .done
    }

    /// A name as it is kept: trimmed, 64 characters at most, nil when empty.
    private static func cleanName(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(64))
    }

    // MARK: -- which line

    /// Puts the PCC on a line of its library, by its id. Refused while a
    /// cab is in service on the present line.
    @discardableResult
    func takeUp(line id: String) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        guard let held = Self.line(id, in: server.snapshot().library) else { return .refused(.noSuchLine(id)) }
        let outcome = order { try server.takeUp(held: held.identity) }
        guard outcome == .done else { return outcome }
        wantedLine = held.identity.id
        settings.set(held.identity.id, for: PCCSettingKey.line)
        return .done
    }

    /// Puts the PCC on no line. Refused while a cab is in service. The next
    /// launch takes up again the line it was last on.
    @discardableResult
    func closeLine() -> Outcome {
        guard let server else { return .refused(.notRunning) }
        let wasOn = server.snapshot().line != nil
        let outcome = order { try server.closeLine() }
        guard outcome == .done else { return outcome }
        wantedLine = nil
        if wasOn {
            note(.lineClosed)
            refresh()
        }
        return .done
    }

    // MARK: -- the operator's orders

    /// Line service on or off. With it off no train has leave to move.
    @discardableResult
    func setService(_ on: Bool) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        // The engine takes no such order on no line.
        guard server.snapshot().line != nil else { return .refused(.noLine) }
        server.setService(on)
        refresh()
        return .done
    }

    /// The general emergency stop, on or off.
    @discardableResult
    func setEmergencyStop(_ on: Bool) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        guard server.snapshot().line != nil else { return .refused(.noLine) }
        server.setEmergencyStop(on)
        refresh()
        return .done
    }

    /// Sizes the fleet for a train every `seconds` each way. It is a
    /// setting too: it is kept, and a PCC that is not running starts with
    /// it.
    @discardableResult
    func setHeadway(_ seconds: Double) -> Outcome {
        guard seconds.isFinite, CabinePCC.Settings.headwayRange.contains(seconds) else {
            return .refused(.headwayOutOfRange)
        }
        if let server {
            let outcome = order { try server.setHeadway(seconds) }
            guard outcome == .done else { return outcome }
        }
        headwayS = seconds
        settings.set(seconds, for: PCCSettingKey.headway)
        return .done
    }

    /// Fixes the number of trains on the line, cabs included; nil sizes it
    /// from the headway again.
    @discardableResult
    func setFleetSize(_ size: Int?) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        if let size, !CabinePCC.Settings.fleetRange.contains(size) { return .refused(.fleetOutOfRange) }
        return order { try server.setFleetSize(size) }
    }

    /// Keeps a rame at the platform it is at, or the next it reaches, until
    /// released.
    @discardableResult
    func hold(rame: Int, _ on: Bool) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        return order { try server.hold(rame: rame, on) }
    }

    /// Brakes one rame to a stand, and releases it.
    @discardableResult
    func emergencyBrake(rame: Int, _ on: Bool) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        return order { try server.emergencyBrake(rame: rame, on) }
    }

    /// Sends words to a cab's display.
    @discardableResult
    func message(rame: Int, _ text: String) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return .refused(.emptyMessage) }
        guard words.count <= CabineWire.maxMessageCharacters else { return .refused(.messageTooLong(words.count)) }
        return order { try server.message(rame: rame, words) }
    }

    /// Rings a cab's driver.
    @discardableResult
    func call(rame: Int) -> Outcome {
        guard let server else { return .refused(.notRunning) }
        return order { try server.call(rame: rame) }
    }

    /// Gives the engine an order, and says what became of it.
    private func order(_ body: () throws -> Void) -> Outcome {
        do {
            try body()
        } catch let error as CabinePCC.OrderError {
            switch error {
            case .noLine:                        return .refused(.noLine)
            case let .noSuchRame(number):        return .refused(.noSuchRame(number))
            case let .notACab(number):           return .refused(.notACab(number))
            case let .cabNotConnected(number):   return .refused(.cabNotConnected(number))
            case .lineInUse:                     return .refused(.lineInUse)
            case .noSuchLine:                    return .refused(.noSuchLine(""))
            case let .badValue(reason), let .badLine(reason):
                return .refused(.other(reason))
            }
        } catch {
            return .refused(.other(String(describing: error)))
        }
        refresh()
        return .done
    }
}

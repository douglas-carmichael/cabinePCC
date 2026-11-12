import Foundation
import Dispatch
import Darwin
import CabinePCCKit

/// The headless PCC: a server, the operator's commands from standard input, and what it prints.
final class Daemon {
    private let options: Options
    private let server: CabinePCC.Server
    /// What the daemon itself does (printing, signals) happens here; the server has a queue of its own.
    private let queue = DispatchQueue(label: "net.dcarmichael.cabinepcc.cabine-pccd")
    private var timers: [DispatchSourceTimer] = []
    private var signals: [DispatchSourceSignal] = []
    private var quitting = false

    init(options: Options) {
        self.options = options
        var settings = CabinePCC.Settings()
        settings.name = options.name ?? "PCC \(Host.current().localizedName ?? "cabine-pccd")"
        if let headway = options.headway { settings.headwayS = headway }
        if let rames = options.rames { settings.fleetSize = rames }
        if let turnBack = options.turnBack { settings.turnBackS = turnBack }
        var configuration = CabinePCC.Server.Configuration()
        configuration.port = options.port
        configuration.loopbackOnly = options.loopback
        configuration.bonjour = options.bonjour
        server = CabinePCC.Server(settings: settings, configuration: configuration, seed: options.seed)
    }

    func run() {
        // The library first, then the line to run out of it.
        if let directory = options.library {
            do {
                try keepLibrary(in: directory)
            } catch {
                FileHandle.standardError.write(Data("cabine-pccd: --library \(directory): \(error)\n".utf8))
                exit(2)
            }
        }
        if let wanted = options.line {
            do {
                try takeUp(wanted)
            } catch {
                FileHandle.standardError.write(Data("cabine-pccd: --line \(wanted): \(error)\n".utf8))
                exit(2)
            }
        }
        server.start()
        guard let port = server.waitUntilListening(timeout: 10) else {
            FileHandle.standardError.write(Data("cabine-pccd: could not listen: \(server.state)\n".utf8))
            exit(1)
        }
        let snapshot = server.snapshot()
        print("cabine-pccd: listening on port \(port)" + (options.loopback ? ", loopback only" : "")
              + (options.bonjour ? ", advertised as \(CabineWire.bonjourServiceType)" : ", not advertised"))
        if port != options.port && options.port != 0 { print("cabine-pccd: port \(options.port) was taken") }
        if snapshot.line == nil {
            print("cabine-pccd: on no line, with \(snapshot.library.count) in the library: `line <id>` or `line <file>` puts it on one")
        }
        printJournal()

        // What happens on the line is printed as it happens, and the table every few seconds if asked.
        every(0.25) { [weak self] in self?.printJournal() }
        if options.verbose { every(5) { [weak self] in self?.printStatus() } }

        // Ctrl-C and a plain kill close the line as `quit` does.
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in self?.quit(inS: 0) }
            source.resume()
            signals.append(source)
        }

        // The operator's commands. Standard input may end (a script's, or none at all): the PCC runs on.
        // Nor is a daemon put in the background of a terminal stopped for trying to read it: with the
        // signal ignored the read fails, and that is the end of its standard input.
        signal(SIGTTIN, SIG_IGN)
        let reader = Thread { [weak self] in
            while let line = readLine(strippingNewline: true) {
                guard let self else { return }
                self.queue.async { self.command(line) }
            }
        }
        reader.stackSize = 1 << 20
        reader.start()
    }

    private func every(_ seconds: Double, _ work: @escaping () -> Void) {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + seconds, repeating: seconds)
        source.setEventHandler(handler: work)
        source.resume()
        timers.append(source)
    }

    /// Reads a `.line.json` file: a package, or a bare description.
    private func package(file path: String) throws -> CabineWire.LinePackage {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw CabinePCC.OrderError.badValue("the file cannot be read")
        }
        do {
            return try CabineWire.LinePackage.decode(file: data)
        } catch {
            throw CabinePCC.OrderError.badLine("\(error)")
        }
    }

    /// Keeps every `*.line.json` of a directory in the library, in the order a person would list them
    /// (ligne-4 before ligne-11). A file that is not a good line is said to be so, and left out.
    private func keepLibrary(in directory: String) throws {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            throw CabinePCC.OrderError.badValue("the directory cannot be read")
        }
        var kept = 0
        for name in names.sorted(by: { $0.compare($1, options: .numeric) == .orderedAscending }) where name.hasSuffix(".line.json") {
            do {
                try server.keep(try package(file: (directory as NSString).appendingPathComponent(name)))
                kept += 1
            } catch {
                FileHandle.standardError.write(Data("cabine-pccd: \(name) is left out of the library: \(error)\n".utf8))
            }
        }
        print("cabine-pccd: \(kept) line(s) kept from \(directory)")
    }

    /// Puts the PCC on a line: `none` for no line; the id of a line of the library (the one last kept,
    /// if it holds several revisions of it); or the path of a `.line.json` file, which is kept first.
    private func takeUp(_ wanted: String) throws {
        if wanted.lowercased() == "none" {
            try server.closeLine()
        } else if let held = server.snapshot().library.last(where: { $0.identity.id == wanted }) {
            try server.takeUp(held: held.identity)
        } else if FileManager.default.fileExists(atPath: wanted) {
            try server.takeUp(try package(file: wanted))
        } else {
            throw CabinePCC.OrderError.badValue("no line \(wanted) in the library, and no file of that name")
        }
    }

    private func quit(inS seconds: Double) {
        guard !quitting else { return }
        quitting = true
        print("cabine-pccd: closing" + (seconds > 0 ? " in \(Int(seconds)) s" : ""))
        server.stop(closingInS: seconds) {
            // A moment for the last lines to leave.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
    }

    // MARK: The operator's commands

    private func command(_ line: String) {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let verb = words.first?.lowercased() else { return }

        func rame() throws -> Int {
            guard words.count >= 2, let number = Int(words[1]) else { throw CabinePCC.OrderError.badValue("\(verb) wants the number of a rame") }
            return number
        }
        do {
            switch verb {
            case "status":
                printStatus()
                return
            case "help", "?":
                print(Options.usage)
                return
            case "start": server.setService(true)
            case "stop": server.setService(false)
            case "hold": try server.hold(rame: try rame(), true)
            case "release": try server.hold(rame: try rame(), false)
            case "brake", "unbrake":
                if words.count >= 2, words[1].lowercased() == "all" {
                    server.setEmergencyStop(verb == "brake")
                } else {
                    try server.emergencyBrake(rame: try rame(), verb == "brake")
                }
            case "msg":
                let number = try rame()
                // The words as they were typed, after the rame's number.
                var text = Substring(line)
                for _ in 0..<2 {
                    text = text.drop { $0 == " " }
                    text = text.drop { $0 != " " }
                }
                try server.message(rame: number, String(text))
            case "call": try server.call(rame: try rame())
            case "headway":
                guard words.count >= 2, let seconds = Double(words[1]) else { throw CabinePCC.OrderError.badValue("headway wants seconds") }
                try server.setHeadway(seconds)
            case "rames":
                guard words.count >= 2 else { throw CabinePCC.OrderError.badValue("rames wants a number, or auto") }
                if words[1].lowercased() == "auto" {
                    try server.setFleetSize(nil)
                } else {
                    guard let size = Int(words[1]) else { throw CabinePCC.OrderError.badValue("rames wants a number, or auto") }
                    try server.setFleetSize(size)
                }
            case "lines":
                printLibrary()
                return
            case "line":
                guard words.count >= 2 else { throw CabinePCC.OrderError.badValue("line wants an id, a file, or none") }
                // What follows the verb as it was typed: a path may have spaces in it.
                try takeUp(String(line.drop { $0 == " " }.dropFirst(4).drop { $0 == " " }))
                if server.snapshot().line == nil {
                    print("ok line: the PCC is on no line")
                    return
                }
            case "quit", "exit":
                quit(inS: words.count >= 2 ? max(Double(words[1]) ?? 0, 0) : 0)
                return
            default:
                print("? \(verb): not a command (help lists them)")
                return
            }
            print("ok \(verb)")
        } catch {
            print("refused \(verb): \(error)")
        }
        printJournal()
    }

    // MARK: Printing

    /// A word in a column of the status table.
    private static func padded(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded(.down)) % 86_400
        return String(format: "%02d:%02d:%02d", whole / 3_600, whole / 60 % 60, whole % 60)
    }

    private func printJournal() {
        for entry in server.takeJournal() {
            print("\(Daemon.clock(entry.clockS))  \(entry)")
        }
    }

    private func printStatus() {
        let snapshot = server.snapshot()
        guard let line = snapshot.line else {
            print("-- on no line; \(snapshot.library.count) line(s) in the library; \(snapshot.sessions.count) connection(s)")
            printSessions(snapshot)
            return
        }
        let cabs = snapshot.cabs.count
        print("-- \(line.identity.name) (\(line.identity.id), \(line.identity.rev))  \(Daemon.clock(snapshot.clockS))  \(snapshot.mode)"
              + "  service \(snapshot.inService ? "on" : "off")\(snapshot.emergencyStop ? "  EMERGENCY STOP" : "")")
        print("   \(snapshot.rames.count) rames: \(snapshot.rames.count - cabs) automatic (\(snapshot.automaticTarget) wanted), \(cabs) cab(s);"
              + " headway \(Int(snapshot.headwayS)) s\(snapshot.fleetSize.map { ", fleet fixed at \($0)" } ?? ""); a lap takes \(Int(snapshot.lapTimeS)) s")
        print("   rame kind track       uM    m/s  phase      doors  station")
        for rame in snapshot.rames.sorted(by: { ($0.track, $0.uM) < ($1.track, $1.uM) }) {
            var row = "     " + String(format: "%02d ", rame.number) + Daemon.padded(rame.kind.rawValue, 5)
            row += String(format: "%5d %8.1f %6.2f  ", rame.track, rame.uM, rame.speedMS) + Daemon.padded(rame.phase.rawValue, 11)
            row += String(format: "%4.2f   ", rame.doors)
            row += rame.station.map { "\($0) \(rame.stationName ?? "")" } ?? "-"
            if rame.held { row += "  HELD" }
            if rame.braked { row += "  BRAKED" }
            if let cab = rame.cab {
                row += "  | \(cab.name): \(cab.link.rawValue), heard \(String(format: "%.1f", cab.linkAgeS)) s ago"
                if let trip = cab.roundTripS { row += String(format: ", round trip %.0f ms", trip * 1_000) }
                if let mode = cab.mode { row += ", \(mode)\(cab.automatic == true ? " auto" : "")" }
                if cab.emergencyBrake { row += ", emergency brake" + (cab.emergencyCause.map { " (\($0))" } ?? "") }
                if cab.status?.paused == true { row += ", paused" }
                if let authority = cab.authority { row += String(format: ", authority to %.1f (%@)", authority.endM, authority.reason.rawValue) }
            }
            print(row)
        }
        printSessions(snapshot)
    }

    /// The library: each line's id, revision, stations, length, whether it has a source, and its name
    /// and ends; the line the PCC is on is starred.
    private func printLibrary() {
        let snapshot = server.snapshot()
        guard !snapshot.library.isEmpty else {
            print("-- the library is empty")
            return
        }
        let running = snapshot.line?.identity
        print("-- \(snapshot.library.count) line(s) in the library" + (running == nil ? "; the PCC is on none" : ""))
        print("     id       revision          stations  length    source  line")
        for held in snapshot.library {
            let on = running.map { $0.isSameLine(as: held.identity) } ?? false
            var row = (on ? "   * " : "     ") + Daemon.padded(held.identity.id, 9) + Daemon.padded(held.identity.rev, 18)
            row += String(format: "%8d  %6.1f km  ", held.stationCount, held.lengthM / 1_000) + Daemon.padded(held.hasSource ? "yes" : "no", 8)
            row += "\(held.identity.name): \(held.firstStation) to \(held.lastStation)"
            print(row)
        }
    }

    private func printSessions(_ snapshot: CabinePCC.Snapshot) {
        for session in snapshot.sessions {
            var row = "   link \(session.id) \(session.peer): "
            switch session.standing {
            case .opened: row += "connected, has not said hello"
            case .connected: row += "connected, not on the PCC's line"
            case .onLine: row += "on the line"
            case .inService: row += "in service" + (session.rame.map { String(format: " as rame %02d", $0) } ?? "")
            }
            if let name = session.name { row += ", \(name)" }
            if let app = session.app { row += " (\(app)\(session.appVersion.map { " \($0)" } ?? ""))" }
            if session.standing != .opened { row += session.line.map { ", holds line \($0.id) \($0.rev)" } ?? ", holds no line" }
            row += String(format: ", heard %.1f s ago", session.linkAgeS)
            if let trip = session.roundTripS { row += String(format: ", round trip %.0f ms", trip * 1_000) }
            print(row)
        }
    }
}

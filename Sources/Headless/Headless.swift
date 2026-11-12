import Foundation
import CabinePCCKit

/// The headless tool's two ways of running a node: serving until it is
/// told to stop, and carrying out commands for the documentation.
@MainActor
enum Headless {

    /// A folder of its own for a node that must leave nothing behind, under
    /// `parent` or the system's temporary folder.
    static func scratchStore(under parent: URL?) -> URL {
        let base = parent ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("cabinepcc-headless-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    /// The environment of a node that is on its own: its settings in
    /// memory, its files in `store`, loopback only, and ports the system
    /// chooses, so that it disturbs neither a PCC that is running nor what
    /// the app keeps.
    static func isolated(store: URL, lines: URL?, line: String? = nil, name: String? = nil) -> PCCEnvironment {
        let settings = MemorySettings()
        settings.set(false, for: PCCSettingKey.lan)
        if let line { settings.set(line, for: PCCSettingKey.line) }
        if let name { settings.set(name, for: PCCSettingKey.name) }
        var environment = PCCEnvironment(settings: settings, storeRoot: store, bundledLines: lines)
        environment.pccPort = 0
        environment.telnetPort = 0
        return environment
    }

    /// Waits until `condition` holds, for `seconds` at most. The main run
    /// loop turns meanwhile, so the node's timers fire.
    @discardableResult
    static func wait(_ seconds: Double, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// The port a link listens on, once it does.
    static func port(of link: PCCLink) -> UInt16? {
        if case let .listening(port) = link.listener { return port }
        return nil
    }

    // MARK: -- --serve

    /// The PCC and the telnet DCL with no window, until SIGINT or SIGTERM.
    static func serve(_ options: HeadlessOptions) async -> Int32 {
        // Its settings are its command line: nothing is read from the
        // app's preferences, and nothing is written to them.
        let settings = MemorySettings()
        settings.set(!options.loopback, for: PCCSettingKey.lan)
        if let line = options.line { settings.set(line, for: PCCSettingKey.line) }
        if let name = options.name { settings.set(name, for: PCCSettingKey.name) }
        var environment = PCCEnvironment(settings: settings, storeRoot: options.store ?? PCCEnvironment.userStore,
                                         bundledLines: PCCEnvironment.programLines)
        if let port = options.port { environment.pccPort = port }
        if let telnet = options.telnet { environment.telnetPort = telnet }
        environment.nodeLabel = options.node
        environment.operatorName = options.user
        let node = PCCNode(environment: environment, language: AppLanguage(initial: options.french ? .fr : .en))
        node.start()

        func say(_ text: String) { print("cabinepcc-headless: " + text) }
        say("store \(environment.storeRoot.path)")
        if environment.bundledLines == nil { say("no Lines folder beside the program: only the store's lines are kept") }
        guard await wait(8, until: { port(of: node.link) != nil || isFailed(node.link) }), let port = port(of: node.link) else {
            say("the PCC is not listening: \(PCCText.listener(node.link.listener) { node.language.t($0) })")
            node.stop()
            return 1
        }
        let snapshot = node.link.snapshot
        say("PCC \"\(node.link.name)\" listening on port \(port), "
            + (node.link.isLAN ? "every interface, advertised by Bonjour" : "loopback only"))
        say("library: \(snapshot?.library.count ?? 0) lines; on "
            + (snapshot?.line.map { "\($0.identity.name) (\($0.identity.id), rev \($0.identity.rev))" } ?? "no line"))
        for line in node.link.journal {
            if case .lineFileRefused = line.event { say(PCCText.journal(line.event) { node.language.t($0) }) }
            if case .lineNotHeld = line.event { say(PCCText.journal(line.event) { node.language.t($0) }) }
        }
        await wait(3, until: { node.telnet.port != nil })
        if let telnet = node.telnet.port {
            say("DCL on telnet: telnet localhost \(telnet)")
        } else {
            say("the telnet DCL could not listen on port \(environment.telnetPort)")
        }

        // Until it is told to stop. The cabs are told that the PCC closes.
        let stop = AsyncStream<Int32> { continuation in
            for number in [SIGINT, SIGTERM] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
                source.setEventHandler { continuation.yield(number) }
                source.resume()
                signalSources.append(source)
            }
        }
        for await _ in stop { break }
        say("closing")
        node.stop()
        return 0
    }

    private static var signalSources: [DispatchSourceSignal] = []

    private static func isFailed(_ link: PCCLink) -> Bool {
        if case .failed = link.listener { return true }
        return false
    }

    // MARK: -- --dcl

    /// Carries out commands against a fresh node, and prints what a
    /// terminal would show.
    static func dcl(_ options: HeadlessOptions) async -> Int32 {
        let store = options.store ?? scratchStore(under: nil)
        defer { if options.store == nil { try? FileManager.default.removeItem(at: store) } }
        var environment = isolated(store: store, lines: PCCEnvironment.programLines, line: options.line, name: options.name)
        environment.nodeLabel = options.node
        environment.operatorName = options.user
        let node = PCCNode(environment: environment, language: AppLanguage(initial: options.french ? .fr : .en))
        node.start()
        defer { node.stop() }
        guard await wait(8, until: { port(of: node.link) != nil }), let port = port(of: node.link) else {
            FileHandle.standardError.write(Data("cabinepcc-headless: the PCC is not listening\n".utf8))
            return 1
        }

        // Scripted cabs, for what the documentation shows of them.
        var cabs: [ScriptedCab] = []
        if options.cabs > 0, let line = node.link.snapshot?.line {
            let names = ["Alma", "Bastien", "Clarisse", "Damien", "Elise", "Fabrice", "Garance", "Hugo"]
            let stops = line.track(1).stopsM
            for index in 0..<options.cabs {
                guard let cab = ScriptedCab(port: port, name: names[index]) else { continue }
                cab.hello(line: (line.identity.id, line.identity.rev, line.identity.name))
                let stop = min(index * 2, stops.count - 2)
                cab.join(track: 1, uM: stops[stop], station: stop, atPlatform: true, rame: 21 + index)
                cab.run(to: stops[stop + 1], speed: 14, station: stop + 1)
                cabs.append(cab)
            }
            await wait(5, until: { node.link.snapshot?.cabs.count == cabs.count })
        }
        if options.settle > 0 { await sleep(options.settle) }

        let terminal = HeadlessTerminal(node: node)
        await terminal.ready()
        for (index, command) in options.commands.enumerated() {
            let prompt = terminal.engine.prompt
            let printed = await terminal.command(command)
            print(prompt + command)
            if terminal.engine.liveActive {
                // A display that has the screen: the keys asked for, one
                // frame of it, then out.
                for key in keyBytes(options.keys[index] ?? "") {
                    terminal.keys(key)
                    await sleep(0.05)
                }
                await sleep(0.3)
                terminal.refresh()
                print(terminal.frame)
                terminal.keys(HeadlessTerminal.controlZ)
                if terminal.engine.liveActive { terminal.keys(HeadlessTerminal.controlY) }
            } else {
                print(printed, terminator: printed.hasSuffix("\n") || printed.isEmpty ? "" : "\n")
            }
            // HELP and MAIL take the prompt: each is left, for the next command.
            if terminal.engine.helpActive { terminal.keys(HeadlessTerminal.controlZ) }
            if terminal.engine.mailActive { _ = await terminal.command("EXIT") }
        }
        for cab in cabs { cab.hangUp() }
        return 0
    }

    /// The keys of `--keys` as the bytes a terminal sends, a key at a time:
    /// a character is itself, and a name between angle brackets is the key
    /// of that name.
    static func keyBytes(_ text: String) -> [[UInt8]] {
        let named: [String: [UInt8]] = [
            "TAB": HeadlessTerminal.tab, "UP": HeadlessTerminal.up, "DOWN": HeadlessTerminal.down,
            "NEXT": [0x1B, 0x5B, 0x36, 0x7E], "PREV": [0x1B, 0x5B, 0x35, 0x7E],
            "RET": HeadlessTerminal.enter, "DEL": [0x7F], "CTRL/W": HeadlessTerminal.controlW,
        ]
        var keys: [[UInt8]] = []
        var rest = Substring(text)
        while let first = rest.first {
            if first == "<", let end = rest.firstIndex(of: ">"),
               let key = named[rest[rest.index(after: rest.startIndex)..<end].uppercased()] {
                keys.append(key)
                rest = rest[rest.index(after: end)...]
            } else {
                keys.append(Array(String(first).utf8))
                rest = rest.dropFirst()
            }
        }
        return keys
    }
}

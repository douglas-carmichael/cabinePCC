import Foundation

/// A DCL session of a node with no terminal emulator behind it: what the
/// shell writes goes into a `VTScreen`, and what an operator would type
/// comes from the caller, through the same line discipline the app's
/// terminal windows and the telnet server use. `--dcl` prints what it
/// shows; the self-test types at it and looks at what came back.
@MainActor
final class HeadlessTerminal {
    let engine: DCLEngine
    private(set) var screen = VTScreen()
    private var discipline: LineDiscipline?

    init(node: PCCNode) {
        engine = node.makeSession(.interactive)
        engine.outputHandler = { [weak self] text in
            // The shell ends its lines with a bare line feed; a terminal
            // wants the carriage return too.
            self?.screen.feed(Self.withCarriageReturns(text))
        }
        discipline = LineDiscipline(dcl: engine) { [weak self] text in
            self?.screen.feed(text)
        }
        node.attach(engine)
    }

    private static func withCarriageReturns(_ text: String) -> String {
        guard text.contains("\n") else { return text }
        var out = ""
        var previous: Character = "\0"
        for character in text {
            if character == "\n" && previous != "\r" { out.append("\r") }
            out.append(character)
            previous = character
        }
        return out
    }

    /// Waits for the session to have logged in: LOGIN.COM has run and the
    /// first prompt is out.
    func ready() async {
        for _ in 0..<200 where !engine.transcript.hasSuffix(engine.prompt) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Types a command line and waits for the shell to have carried it
    /// out. Returns what it printed: neither the echo of the command nor
    /// the prompt that follows.
    @discardableResult
    func command(_ line: String) async -> String {
        let before = engine.transcript.count
        await engine.submit(line)
        var printed = String(engine.transcript.dropFirst(before))
        // The echo: the prompt, the line, a line feed.
        if let feed = printed.firstIndex(of: "\n") { printed = String(printed[printed.index(after: feed)...]) }
        if printed.hasSuffix(engine.prompt) { printed.removeLast(engine.prompt.count) }
        return printed
    }

    /// Presses keys: bytes as a terminal would send them.
    func keys(_ bytes: [UInt8]) {
        discipline?.process(bytes)
    }

    /// Types text, without a carriage return.
    func type(_ text: String) {
        keys(Array(text.utf8))
    }

    /// One refresh of whatever is on the screen, now.
    func refresh() {
        if engine.liveActive { engine.refreshLiveDisplay() }
    }

    /// The frame of a full-screen display, as text.
    var frame: String { screen.text }

    static let up: [UInt8] = [0x1B, 0x5B, 0x41]
    static let down: [UInt8] = [0x1B, 0x5B, 0x42]
    static let tab: [UInt8] = [0x09]
    static let enter: [UInt8] = [0x0D]
    static let controlW: [UInt8] = [0x17]
    static let controlY: [UInt8] = [0x19]
    static let controlZ: [UInt8] = [0x1A]
}

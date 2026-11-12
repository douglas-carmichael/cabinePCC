import Foundation
import Network

/// Lightweight TCP listener on `127.0.0.1` that lets an external
/// terminal emulator (Terminal.app, iTerm, xterm, ...) connect to a
/// fresh DCL shell session. Each accepted connection gets its own
/// `DCLEngine`, attached to the node's world, link and language, so a
/// telnet client can order the PCC, run `SHOW SYSTEM`, etc. side-by-side
/// with the app's own terminal windows -- or with no window at all, under
/// the headless tool.
///
/// Connect with:    telnet localhost 2324     (or `nc localhost 2324`)
///
/// Bound to loopback only -- the listener never accepts off-host
/// connections.
@MainActor
final class DCLTelnetServer: ObservableObject {
    /// Port the listener is currently bound to, or `nil` until it has
    /// successfully entered the `.ready` state.
    @Published private(set) var port: UInt16?
    /// Number of accepted telnet sessions currently alive. Drives the
    /// "TELNET" indicator in the PCC Dispatcher's status strip.
    @Published private(set) var sessionCount: Int = 0

    private weak var node: PCCNode?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "net.dcarmichael.cabinepcc.telnet")
    private var sessions: [ObjectIdentifier: TelnetSession] = [:] {
        didSet { sessionCount = sessions.count }
    }

    init() {}

    /// The node whose sessions these are.
    func attach(node: PCCNode) {
        self.node = node
    }

    /// Opens the listener on `port`; 0 lets the system choose one.
    func start(port wanted: UInt16) {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        // Loopback only: refuse off-host connections.
        params.requiredInterfaceType = .loopback
        let listener: NWListener
        do {
            if wanted == 0 {
                listener = try NWListener(using: params)
            } else if let nwPort = NWEndpoint.Port(rawValue: wanted) {
                listener = try NWListener(using: params, on: nwPort)
            } else {
                return
            }
        } catch {
            NSLog("DCLTelnetServer: failed to bind to port \(wanted): \(error)")
            return
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            let bound = listener?.port?.rawValue ?? wanted
            Task { @MainActor in
                if case .ready = state {
                    self.port = bound
                }
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { @MainActor in self.handleNewConnection(conn) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, session) in sessions { session.cancel() }
        sessions.removeAll()
        port = nil
    }

    private func handleNewConnection(_ conn: NWConnection) {
        guard let node else {
            conn.cancel()
            return
        }
        // Attached, and joined to the node's session set so the in-universe
        // mail writer is elected across the app's windows and telnet
        // connections alike.
        let engine = node.makeSession(.network)
        node.attach(engine)
        let session = TelnetSession(connection: conn, engine: engine, queue: queue)
        session.onClose = { [weak self, weak session, engine] in
            guard let self, let session else { return }
            Task { @MainActor in
                self.node?.sessions.unregister(engine)
                self.sessions.removeValue(forKey: ObjectIdentifier(session))
            }
        }
        sessions[ObjectIdentifier(session)] = session
        session.start()
    }
}

/// One accepted TCP connection. Owns its own `DCLEngine`,
/// `LineDiscipline`, and `NWConnection`. The receive loop forwards
/// raw bytes into the line discipline; the engine's `outputHandler`
/// pushes whatever the shell emits back out to the socket (with the
/// usual LF -> CRLF normalisation so cursor placement stays correct
/// on telnet-line-mode clients).
@MainActor
final class TelnetSession {
    private let connection: NWConnection
    private let engine: DCLEngine
    private var lineDiscipline: LineDiscipline?
    private let queue: DispatchQueue
    private var closed = false

    var onClose: (() -> Void)?

    init(connection: NWConnection, engine: DCLEngine, queue: DispatchQueue) {
        self.connection = connection
        self.engine = engine
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in self.handleReady() }
            case .failed, .cancelled:
                Task { @MainActor in self.fireClose() }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    private func handleReady() {
        // Negotiate telnet character-at-a-time mode FIRST so the client's
        // tty driver releases arrow keys / Ctrl-Y / etc. as they're
        // typed instead of buffering them in cooked mode until Enter.
        // Plain `nc` won't speak telnet protocol and these bytes will
        // appear briefly in its terminal as garbage; recommend
        // `telnet localhost 2324` instead.
        sendTelnetNegotiation()
        // Engine pushes user-visible output (banner, prompt, command
        // results) here; we normalise LF -> CRLF so telnet line-mode
        // clients advance to the next line cleanly.
        engine.outputHandler = { [weak self] text in
            guard let self else { return }
            self.sendNormalised(text)
        }
        // The line discipline emits raw bytes (CR / cursor escapes /
        // line redraw) straight to the socket without touching the
        // transcript.
        lineDiscipline = LineDiscipline(dcl: engine) { [weak self] raw in
            guard let self else { return }
            self.sendRaw(raw)
        }
        receiveLoop()
    }

    /// RFC 854/857/858 negotiation: convince the telnet client to enter
    /// character-at-a-time mode so the local tty stops line-buffering
    /// (which would swallow arrow keys, Ctrl-Y, ESC ESC, etc. until the
    /// user pressed Enter).
    ///   IAC WILL ECHO              -- we'll handle echo via redraw()
    ///   IAC WILL SUPPRESS-GO-AHEAD -- full-duplex char-at-a-time
    ///   IAC DO   SUPPRESS-GO-AHEAD -- ask the client to do the same
    private func sendTelnetNegotiation() {
        let iac: [UInt8] = [
            0xFF, 0xFB, 0x01,
            0xFF, 0xFB, 0x03,
            0xFF, 0xFD, 0x03,
        ]
        connection.send(content: Data(iac), completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let filtered = Self.stripTelnetIAC(Array(data))
                if !filtered.isEmpty {
                    Task { @MainActor in
                        self.lineDiscipline?.process(filtered)
                    }
                }
            }
            if isComplete || error != nil {
                Task { @MainActor in self.fireClose() }
                return
            }
            Task { @MainActor in self.receiveLoop() }
        }
    }

    /// Consume telnet IAC sequences from the incoming byte stream so
    /// the line discipline never sees the client's WILL / DO / WONT /
    /// DONT replies or any subnegotiation payloads. Handles:
    ///   IAC <cmd> <option>          (WILL / WONT / DO / DONT)  -- 3 bytes
    ///   IAC SB <option> ... IAC SE  (subnegotiation, e.g. window size)
    ///   IAC IAC                     (escaped 0xFF in the data stream)
    nonisolated static func stripTelnetIAC(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            if bytes[i] != 0xFF {
                out.append(bytes[i])
                i += 1
                continue
            }
            // IAC byte (0xFF). Need at least one more byte to decide.
            guard i + 1 < bytes.count else { break }
            let cmd = bytes[i + 1]
            switch cmd {
            case 0xFF:                          // IAC IAC -- literal 0xFF
                out.append(0xFF)
                i += 2
            case 0xFA:                          // SB -- subnegotiation
                i += 2
                while i + 1 < bytes.count,
                      !(bytes[i] == 0xFF && bytes[i + 1] == 0xF0) {
                    i += 1
                }
                i += 2                          // skip IAC SE
            case 0xFB, 0xFC, 0xFD, 0xFE:        // WILL / WONT / DO / DONT
                i += 3                          // skip IAC <cmd> <option>
            default:                            // IAC <2-byte cmd> (NOP, GA, ...)
                i += 2
            }
        }
        return out
    }

    private func sendNormalised(_ text: String) {
        // Mirrors VTShellView.normalizeLineEndings -- engine emits bare
        // LF, telnet clients in line mode expect CRLF.
        guard text.contains("\n") else { return sendRaw(text) }
        var out = ""
        out.reserveCapacity(text.count + 8)
        var prev: Character = "\0"
        for ch in text {
            if ch == "\n" && prev != "\r" { out.append("\r") }
            out.append(ch)
            prev = ch
        }
        sendRaw(out)
    }

    private func sendRaw(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func fireClose() {
        guard !closed else { return }
        closed = true
        // Tear down monitor / test timers held by the engine before
        // dropping the reference so they don't keep firing on a session
        // nobody can see.
        if engine.liveActive {
            engine.stopMonitor(interrupt: false)
        }
        engine.outputHandler = nil
        lineDiscipline = nil
        connection.cancel()
        onClose?()
    }
}

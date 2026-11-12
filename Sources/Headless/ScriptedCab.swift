import Foundation
import Darwin

/// A plain TCP socket to 127.0.0.1 that writes lines and reads them back.
/// There is none of the engine in it, so that what it sees is what any
/// client of the wire, or of the telnet DCL, would.
final class LoopbackSocket {
    private var descriptor: Int32 = -1
    private var pending = Data()
    /// True once the other end has closed the connection.
    private(set) var closed = false

    init?(port: UInt16) {
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(descriptor, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(descriptor)
            descriptor = -1
            return nil
        }
    }

    deinit { hangUp() }

    func hangUp() {
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
    }

    /// Sends bytes as they are.
    @discardableResult
    func write(_ data: Data) -> Bool {
        guard descriptor >= 0 else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            var sent = 0
            while sent < raw.count {
                let wrote = Darwin.send(descriptor, raw.baseAddress! + sent, raw.count - sent, 0)
                if wrote < 0 && errno == EINTR { continue }
                if wrote <= 0 { return false }
                sent += wrote
            }
            return true
        }
    }

    /// Reads what comes within `seconds`: every byte of it, as it came.
    func read(for seconds: Double) -> Data {
        let deadline = Date().addingTimeInterval(seconds)
        var got = Data()
        while descriptor >= 0, !closed {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { break }
            var waiting = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&waiting, 1, Int32(max(1, (left * 1_000).rounded(.up))))
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { break }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = recv(descriptor, &buffer, buffer.count, 0)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 {
                closed = true
                break
            }
            got.append(contentsOf: buffer[0..<count])
        }
        return got
    }

    /// Reads what comes within `seconds` and returns the whole lines of it;
    /// the end of a line that has not all come waits for the next call.
    func lines(for seconds: Double) -> [Data] {
        pending.append(read(for: seconds))
        var lines: [Data] = []
        while let feed = pending.firstIndex(of: 0x0A) {
            let line = Data(pending[pending.startIndex..<feed])
            pending = Data(pending[(feed + 1)...])
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}

/// A scripted Cabine on a thread of its own, for the self-test and for the
/// samples of the documentation. It says what it is told to say, and once
/// in service reports its position five times a second and its status
/// three times, answers pings and obeys the PCC's commands, as a cab does,
/// until it falls silent or hangs up. It writes its JSON by hand and reads
/// it with JSONSerialization: it uses none of the engine's own codec.
final class ScriptedCab: @unchecked Sendable {
    let name: String
    private let socket: LoopbackSocket
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var outbox: [String] = []
    private var running = true
    private var silent = false
    private var inService = false
    private var track = 1
    private var uM = 0.0
    private var speedMS = 0.0
    private var runTo = 0.0
    private var station = 0
    private var atPlatform = true
    private var doorPhase = "closed"
    private var doorOpen = 0.0
    private var emergency: String?
    private var held = false
    private var paused = false
    private var passengers = 212
    private var deviation = -4.0
    private var mode = "PA"
    private var automatic = true
    private var seq = 0
    private var requests = 0
    private let started = Date()
    private var log: [[String: Any]] = []
    private var refused: Set<String> = []
    private var isClosed = false

    init?(port: UInt16, name: String) {
        guard let socket = LoopbackSocket(port: port) else { return nil }
        self.socket = socket
        self.name = name
        queue = DispatchQueue(label: "net.dcarmichael.cabinepcc.scriptedcab.\(name)")
        queue.async { [self] in loop() }
    }

    // MARK: What the scenario tells it

    private func send(_ json: String) {
        lock.lock()
        outbox.append(json)
        lock.unlock()
    }

    private func nextID(_ prefix: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        requests += 1
        return "\(prefix)\(requests)"
    }

    private static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    /// Says `hello`, naming the line it holds, or none.
    func hello(line: (id: String, rev: String, name: String)? = nil) {
        var message = #"{"type":"hello","protocol":1,"app":"Cabine","appVersion":"1.0","cab":{"id":"\#(name)-0001","name":\#(Self.quoted(name))}"#
        if let line {
            message += #","line":{"id":\#(Self.quoted(line.id)),"rev":\#(Self.quoted(line.rev)),"name":\#(Self.quoted(line.name))}"#
        }
        send(message + "}")
    }

    /// Asks for the line the PCC is on. The package comes as a `line`.
    func requestLine() {
        send(#"{"type":"lineRequest","id":"\#(nextID("l"))"}"#)
    }

    func join(track: Int, uM: Double, station: Int, atPlatform: Bool, rame: Int) {
        lock.lock()
        self.track = track
        self.uM = uM
        runTo = uM
        speedMS = 0
        self.station = station
        self.atPlatform = atPlatform
        inService = true
        lock.unlock()
        send(#"{"type":"join","id":"\#(nextID("j"))","track":\#(track),"uM":\#(uM),"station":\#(station),"rame":\#(rame)}"#)
    }

    func leave() {
        lock.lock()
        inService = false
        lock.unlock()
        send(#"{"type":"leave","id":"\#(nextID("v"))","reason":"ended"}"#)
    }

    /// Runs on at `speed` as far as `to`, and stands there.
    func run(to: Double, speed: Double, station: Int) {
        lock.lock()
        runTo = to
        speedMS = speed
        self.station = station
        atPlatform = false
        lock.unlock()
    }

    func set(doors phase: String, open: Double) {
        lock.lock()
        doorPhase = phase
        doorOpen = open
        lock.unlock()
    }

    func set(mode: String, automatic: Bool, paused: Bool = false) {
        lock.lock()
        self.mode = mode
        self.automatic = automatic
        self.paused = paused
        lock.unlock()
    }

    /// The driver's own emergency brake, with its cause; nil releases it.
    func emergencyBrake(_ cause: String?) {
        lock.lock()
        emergency = cause
        lock.unlock()
        if let cause {
            send(#"{"type":"event","event":"emergencyBrake","applied":true,"cause":\#(Self.quoted(cause))}"#)
        } else {
            send(#"{"type":"event","event":"emergencyBrake","applied":false}"#)
        }
    }

    /// One of the driver's coded radio reports.
    func report(code: String, text: String) {
        send(#"{"type":"event","event":"report","code":"\#(code)","text":\#(Self.quoted(text))}"#)
    }

    /// The driver calls the centre.
    func call() {
        send(#"{"type":"event","event":"call"}"#)
    }

    /// Commands it answers with a refusal from now on.
    func refuse(_ commands: Set<String>) {
        lock.lock()
        refused = commands
        lock.unlock()
    }

    /// Silent, it sends nothing and reads nothing, so that no ping is
    /// answered: a cab whose link has dropped without closing.
    func goSilent(_ on: Bool) {
        lock.lock()
        silent = on
        lock.unlock()
    }

    func hangUp() {
        lock.lock()
        running = false
        lock.unlock()
    }

    /// What it has been sent of a type, traffic, info and pings apart.
    func received(_ type: String) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return log.filter { $0["type"] as? String == type }
    }

    /// The commands it has been given of a kind, in the order they came.
    func commands(_ kind: String) -> [[String: Any]] {
        received("command").filter { $0["command"] as? String == kind }
    }

    /// True once the PCC has closed its connection.
    var closed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    /// Where it says its train is.
    var position: Double {
        lock.lock()
        defer { lock.unlock() }
        return uM
    }

    // MARK: Its own life

    private func loop() {
        var nextPosition = Date(), nextStatus = Date(), last = Date()
        while true {
            lock.lock()
            let go = running, quiet = silent, lines = outbox, serving = inService
            outbox.removeAll()
            lock.unlock()
            guard go else { break }
            let now = Date()
            if quiet {
                // What was to be said is said when it speaks again.
                lock.lock()
                outbox = lines + outbox
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.05)
                last = now
                continue
            }
            for line in lines { socket.write(Data((line + "\n").utf8)) }
            if serving {
                lock.lock()
                let dt = now.timeIntervalSince(last)
                if emergency != nil || paused { speedMS = 0 }
                if speedMS > 0 {
                    uM = min(uM + speedMS * dt, runTo)
                    if uM >= runTo {
                        speedMS = 0
                        atPlatform = true
                    }
                }
                let t = now.timeIntervalSince(started)
                let position = #"{"type":"position","seq":\#(seq),"tS":\#(String(format: "%.3f", t)),"track":\#(track),"uM":\#(String(format: "%.2f", uM)),"speedMS":\#(String(format: "%.2f", speedMS)),"accelerationMS2":0}"#
                let brake = emergency.map { #"{"applied":true,"cause":\#(Self.quoted($0))}"# } ?? #"{"applied":false}"#
                let status = #"{"type":"status","seq":\#(seq),"tS":\#(String(format: "%.3f", t)),"mode":"\#(mode)","automatic":\#(automatic),"doors":{"phase":"\#(doorPhase)","side":"right","open":\#(doorOpen)},"emergencyBrake":\#(brake),"passengers":\#(passengers),"station":{"index":\#(station),"atPlatform":\#(atPlatform && speedMS == 0)},"deviationS":\#(deviation),"held":\#(held),"paused":\#(paused),"underControl":true}"#
                seq += 1
                lock.unlock()
                if now >= nextPosition {
                    socket.write(Data((position + "\n").utf8))
                    nextPosition = now.addingTimeInterval(0.2)
                }
                if now >= nextStatus {
                    socket.write(Data((status + "\n").utf8))
                    nextStatus = now.addingTimeInterval(0.3)
                }
            }
            last = now
            for line in socket.lines(for: 0.04) {
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let type = message["type"] as? String else { continue }
                if type == "ping" { pong(message) }
                guard type != "traffic", type != "info", type != "ping" else { continue }
                lock.lock()
                log.append(message)
                lock.unlock()
                if type == "command" { obey(message) }
            }
            if socket.closed { break }
        }
        socket.hangUp()
        lock.lock()
        isClosed = true
        lock.unlock()
    }

    /// Answers a ping with its id and its tS.
    private func pong(_ ping: [String: Any]) {
        var answer: [String: Any] = ["type": "pong"]
        if let id = ping["id"] { answer["id"] = id }
        if let tS = ping["tS"] { answer["tS"] = tS }
        if let line = try? JSONSerialization.data(withJSONObject: answer) {
            socket.write(line + Data([0x0A]))
        }
    }

    private func obey(_ command: [String: Any]) {
        guard let id = command["id"] as? String, let what = command["command"] as? String else { return }
        lock.lock()
        let refuses = refused.contains(what)
        lock.unlock()
        if refuses {
            socket.write(Data((#"{"type":"result","id":"\#(id)","ok":false,"error":"badValue","message":"refused by the script"}"# + "\n").utf8))
            return
        }
        lock.lock()
        switch what {
        case "hold": held = command["value"] as? Bool ?? false
        case "emergencyBrake": emergency = (command["value"] as? Bool ?? false) ? "ARRET COMMANDE PAR LE PCC" : nil
        default: break
        }
        lock.unlock()
        socket.write(Data((#"{"type":"result","id":"\#(id)","ok":true}"# + "\n").utf8))
    }
}

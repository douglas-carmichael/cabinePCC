import Foundation
import Darwin

/// A scripted client for the self-test: a plain TCP socket to 127.0.0.1 that writes lines of JSON and
/// reads them back with JSONSerialization. There is none of the kit in it, so that what it sees is what
/// any client of the wire would.
final class TestClient {
    private var descriptor: Int32 = -1
    private var pending = Data()
    /// What has been received and not yet taken by `next`, in the order it came.
    private(set) var inbox: [[String: Any]] = []
    /// How many messages of each type have come in all.
    private(set) var counts: [String: Int] = [:]
    /// True once the other end has closed the connection.
    private(set) var closed = false
    /// Lines that were not one JSON object with a type.
    private(set) var unreadable = 0
    /// The last line of each type, as its bytes came: for what must be compared to the last digit.
    private(set) var raw: [String: Data] = [:]

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
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
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

    /// Sends one line.
    @discardableResult
    func send(_ json: String) -> Bool { write(Data((json + "\n").utf8)) }

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

    /// Reads what comes for `seconds`, answering each ping as a cab does.
    func listen(for seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        while !closed, read(until: deadline) {}
    }

    /// Takes the next message of a type that `matches`, waiting up to `seconds` for it. Others stay in
    /// the inbox.
    func next(_ type: String, within seconds: Double = 3, where matches: ([String: Any]) -> Bool = { _ in true }) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(seconds)
        var looked = 0
        while true {
            while looked < inbox.count {
                if inbox[looked]["type"] as? String == type, matches(inbox[looked]) { return inbox.remove(at: looked) }
                looked += 1
            }
            if closed || !read(until: deadline) { return nil }
        }
    }

    /// Waits for the other end to close. True if it did within `seconds`.
    func waitForClose(within seconds: Double = 3) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !closed, read(until: deadline) {}
        return closed
    }

    /// Drops what is in the inbox.
    func clear() { inbox.removeAll() }

    /// Waits until `deadline` for something to read, and reads it. False when the time ran out or the
    /// connection is closed.
    private func read(until deadline: Date) -> Bool {
        guard descriptor >= 0, !closed else { return false }
        let left = deadline.timeIntervalSinceNow
        guard left > 0 else { return false }
        var waiting = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&waiting, 1, Int32(max(1, (left * 1_000).rounded(.up))))
        if ready < 0 { return errno == EINTR }
        if ready == 0 { return false }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let got = recv(descriptor, &buffer, buffer.count, 0)
        if got < 0 && errno == EINTR { return true }
        if got <= 0 {
            closed = true
            return false
        }
        pending.append(contentsOf: buffer[0..<got])
        while let feed = pending.firstIndex(of: 0x0A) {
            let line = Data(pending[pending.startIndex..<feed])
            pending = Data(pending[(feed + 1)...])
            guard !line.isEmpty else { continue }
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = object["type"] as? String else {
                unreadable += 1
                continue
            }
            counts[type, default: 0] += 1
            raw[type] = line
            inbox.append(object)
            if type == "ping" { pong(object) }
        }
        return true
    }

    /// Answers a ping with its id and its tS.
    private func pong(_ ping: [String: Any]) {
        var answer: [String: Any] = ["type": "pong"]
        if let id = ping["id"] { answer["id"] = id }
        if let tS = ping["tS"] { answer["tS"] = tS }
        if let line = try? JSONSerialization.data(withJSONObject: answer) {
            write(line + Data([0x0A]))
        }
    }
}

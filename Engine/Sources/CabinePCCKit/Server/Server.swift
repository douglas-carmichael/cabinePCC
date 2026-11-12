import Foundation
import Network

extension CabinePCC {

    /// The engine on the network: a listener the cabs dial, one connection for each, and the timers that
    /// step the engine and send what goes out at a fixed rate.
    ///
    /// Everything it does happens on one serial queue: its own, or one its host gives it. The host reads
    /// the line and gives the operator's orders through the calls below, from any thread; each runs on
    /// that queue and waits for it, or runs at once when the caller is already on it.
    public final class Server: @unchecked Sendable {

        public struct Configuration: Sendable {
            /// The port to listen on; 0 lets the system choose one.
            public var port: UInt16 = CabineWire.preferredPort
            /// Take any free port when `port` is taken. Bonjour says which.
            public var fallsBackToAnyPort = true
            /// Listen on the loopback interface only.
            public var loopbackOnly = false
            /// Advertise the PCC by Bonjour.
            public var bonjour = true
            /// Steps of the simulation a second.
            public var stepHz = 20.0
            /// Connections served at once.
            public var maxSessions = CabineWire.maxSessions

            public init() {}
        }

        public enum State: Equatable, Sendable {
            case idle
            case starting
            case listening(port: UInt16)
            case failed(String)
            case stopped
        }

        // MARK: Parts

        /// One cab's connection.
        private final class Connection {
            let id: SessionID
            let wire: NWConnection
            let peer: String
            var framer = CabineWire.Framer()
            /// Lines handed to the connection and not yet sent.
            var inFlight = 0
            var closed = false

            init(id: SessionID, wire: NWConnection) {
                self.id = id
                self.wire = wire
                if case let .hostPort(host, port) = wire.endpoint {
                    peer = "\(host):\(port)"
                } else {
                    peer = "\(wire.endpoint)"
                }
            }
        }

        public let configuration: Configuration
        private let queue: DispatchQueue
        private let onQueue = DispatchSpecificKey<Bool>()
        private let engine: Engine
        private var listener: NWListener?
        /// The listener a stop is closing, until it has let go of its port; what waits for that; and
        /// whether a start does.
        private var closingListener: NWListener?
        private var whenClosed: [@Sendable () -> Void] = []
        private var startWhenClosed = false
        private var connections: [SessionID: Connection] = [:]
        private var nextSession = 1
        private var timer: DispatchSourceTimer?
        private var running = false
        /// When the engine was last stepped, and when each periodic message is next due, by the system's uptime.
        private var steppedAt = 0.0
        private var trafficDue = 0.0
        private var infoDue = 0.0
        private var pingDue = 0.0
        /// When the last few pings went out, by their id.
        private var pingSentAt: [Int: Double] = [:]
        /// The line id the Bonjour record carries at present.
        private var advertisedLine: String?
        private var activity: NSObjectProtocol?
        private let stateLock = NSCondition()
        private var currentState = State.idle
        private var stateHandler: (@Sendable (State) -> Void)?

        /// A reader that has fallen this many lines behind misses the periodic messages until it catches
        /// up, and one that has fallen much further behind is dropped.
        private static let behind = 32
        private static let lost = 2_048

        private static var uptime: Double { ProcessInfo.processInfo.systemUptime }

        // MARK: Life

        /// - Parameters:
        ///   - settings: the PCC's own settings.
        ///   - configuration: how it listens.
        ///   - seed: what the engine's random draws come from.
        ///   - queue: the serial queue everything is to happen on; its own when nil.
        public init(settings: Settings = Settings(), configuration: Configuration = Configuration(), seed: UInt64 = 1,
                    queue: DispatchQueue? = nil) {
            self.configuration = configuration
            self.queue = queue ?? DispatchQueue(label: "net.dcarmichael.cabinepcc.server")
            engine = Engine(settings: settings, seed: seed)
            self.queue.setSpecific(key: onQueue, value: true)
        }

        deinit {
            timer?.cancel()
            listener?.cancel()
            for connection in connections.values { connection.wire.cancel() }
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
        }

        /// Opens the listener and starts the line's clock. `state` says how it went.
        public func start() {
            queue.async { [self] in
                guard !running else { return }
                // A stop is still letting go of the port: it starts once the port is free.
                if closingListener != nil {
                    startWhenClosed = true
                    return
                }
                begin()
            }
        }

        private func begin() {
            running = true
            set(.starting)
            // A PCC in the background must keep time: App Nap would slow its timers.
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "Running a line for Cabine cabs")
            let now = Server.uptime
            steppedAt = now
            trafficDue = now
            infoDue = now
            pingDue = now
            let source = DispatchSource.makeTimerSource(queue: queue)
            let period = 1 / max(configuration.stepHz, 1)
            source.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(5))
            source.setEventHandler { [weak self] in self?.tick() }
            source.resume()
            timer = source
            listen(on: configuration.port)
        }

        /// Tells the cabs the PCC is closing, and `closingInS` seconds later closes every connection and
        /// the listener. It has stopped, and `completion` runs on the server's queue, once the listener
        /// has let go of its port: another server may then be started on that port at once.
        public func stop(closingInS: Double = 0, completion: (@Sendable () -> Void)? = nil) {
            queue.async { [self] in
                guard running else {
                    // Not running: a start that was waiting for the port is called off.
                    startWhenClosed = false
                    finish(completion)
                    return
                }
                engine.broadcastClosing(inS: closingInS)
                flush()
                queue.asyncAfter(deadline: .now() + max(closingInS, 0)) { [self] in
                    guard running else {
                        finish(completion)
                        return
                    }
                    running = false
                    timer?.cancel()
                    timer = nil
                    for connection in Array(connections.values) { close(connection, flushing: true) }
                    if let activity { ProcessInfo.processInfo.endActivity(activity) }
                    activity = nil
                    guard let closing = listener else {
                        set(.stopped)
                        completion?()
                        return
                    }
                    listener = nil
                    closingListener = closing
                    if let completion { whenClosed.append(completion) }
                    // It is stopped once the listener has let go of its port. Until then the listener
                    // holds on to the server, whoever else has let go of it.
                    closing.stateUpdateHandler = { [self] state in
                        if case .cancelled = state { listenerClosed() }
                    }
                    closing.cancel()
                }
            }
        }

        /// Runs what a stop was to run when it is done: now, or once the listener that an earlier stop is
        /// closing has let go of its port.
        private func finish(_ completion: (@Sendable () -> Void)?) {
            guard let completion else { return }
            if closingListener != nil {
                whenClosed.append(completion)
            } else {
                completion()
            }
        }

        /// The listener a stop was closing has let go of its port.
        private func listenerClosed() {
            closingListener?.stateUpdateHandler = nil
            closingListener = nil
            let waiting = whenClosed
            whenClosed.removeAll()
            if startWhenClosed {
                startWhenClosed = false
                begin()
            } else {
                set(.stopped)
            }
            for completion in waiting { completion() }
        }

        // MARK: State

        public var state: State {
            stateLock.lock()
            defer { stateLock.unlock() }
            return currentState
        }

        /// The port it listens on, once it does.
        public var port: UInt16? {
            if case let .listening(port) = state { port } else { nil }
        }

        /// Called on the server's queue whenever `state` changes.
        public func onStateChange(_ handler: (@Sendable (State) -> Void)?) {
            stateLock.lock()
            stateHandler = handler
            stateLock.unlock()
        }

        /// Waits until the server listens, and returns its port; nil if it failed, stopped or took longer
        /// than `timeout` seconds. Not to be called from the server's own queue.
        public func waitUntilListening(timeout: TimeInterval = 5) -> UInt16? {
            let deadline = Date().addingTimeInterval(timeout)
            stateLock.lock()
            defer { stateLock.unlock() }
            while true {
                switch currentState {
                case let .listening(port): return port
                case .failed, .stopped: return nil
                case .idle, .starting: break
                }
                if !stateLock.wait(until: deadline) { return nil }
            }
        }

        private func set(_ state: State) {
            stateLock.lock()
            currentState = state
            let handler = stateHandler
            stateLock.broadcast()
            stateLock.unlock()
            handler?(state)
        }

        // MARK: The host's calls

        /// Runs `body` with the engine on the server's queue, waits for it, and sends what it left to be
        /// sent. For what the calls below do not cover.
        public func withEngine<T>(_ body: (Engine) throws -> T) rethrows -> T {
            if DispatchQueue.getSpecific(key: onQueue) == true {
                defer { flush() }
                return try body(engine)
            }
            return try queue.sync {
                defer { flush() }
                return try body(engine)
            }
        }

        /// The line and everything on it at this moment.
        public func snapshot() -> Snapshot { withEngine { $0.snapshot() } }

        /// What happened since this was last called.
        public func takeJournal() -> [JournalEntry] { withEngine { $0.takeJournal() } }

        /// Keeps a line in the library, without taking it up. Its description must pass the PCC's checks
        /// (`.badLine`). A line already held under the same id and revision is replaced.
        public func keep(_ package: CabineWire.LinePackage) throws { try withEngine { try $0.keep(package) } }

        /// A line of the library, as it was kept (`Snapshot.library` lists them).
        public func heldPackage(_ identity: CabineWire.LineIdentity) -> CabineWire.LinePackage? {
            withEngine { $0.heldPackage(identity) }
        }

        /// Takes a line out of the library. Refused for the line the PCC is on, and when it holds no such
        /// line (`.noSuchLine`).
        public func forget(_ identity: CabineWire.LineIdentity) throws { try withEngine { try $0.forget(identity) } }

        /// Puts the PCC on a line of its library. Refused while a cab is in service (`.lineInUse`), and
        /// when it holds no such line (`.noSuchLine`).
        public func takeUp(held identity: CabineWire.LineIdentity) throws { try withEngine { try $0.takeUp(held: identity) } }

        /// Keeps a line, then puts the PCC on it.
        public func takeUp(_ package: CabineWire.LinePackage) throws { try withEngine { try $0.takeUp(package) } }

        /// Puts the PCC on no line. Refused while a cab is in service (`.lineInUse`).
        public func closeLine() throws { try withEngine { try $0.closeLine() } }

        /// Keeps a line of which there is only the description.
        public func keep(_ description: CabineWire.LineDescription) throws { try withEngine { try $0.keep(description) } }

        /// The description of a line of the library.
        public func heldDescription(_ identity: CabineWire.LineIdentity) -> CabineWire.LineDescription? {
            withEngine { $0.heldDescription(identity) }
        }

        /// Keeps a line of which there is only the description, then puts the PCC on it.
        public func takeUp(_ description: CabineWire.LineDescription) throws { try withEngine { try $0.takeUp(description) } }

        /// Line service on or off.
        public func setService(_ on: Bool) { withEngine { $0.setService(on) } }

        /// The general emergency stop, on or off.
        public func setEmergencyStop(_ on: Bool) { withEngine { $0.setEmergencyStop(on) } }

        /// Keeps a rame at the platform it is at, or the next it reaches, until released.
        public func hold(rame: Int, _ on: Bool) throws { try withEngine { try $0.hold(rame: rame, on) } }

        /// Brakes one rame to a stand, and releases it.
        public func emergencyBrake(rame: Int, _ on: Bool) throws { try withEngine { try $0.emergencyBrake(rame: rame, on) } }

        /// Sends words to a cab's display: 120 characters at most.
        public func message(rame: Int, _ text: String) throws { try withEngine { try $0.message(rame: rame, text) } }

        /// Rings a cab's driver.
        public func call(rame: Int) throws { try withEngine { try $0.call(rame: rame) } }

        /// Sizes the fleet for a train every `seconds` each way.
        public func setHeadway(_ seconds: Double) throws { try withEngine { try $0.setHeadway(seconds) } }

        /// Fixes the number of trains on the line, cabs included; nil sizes it from the headway.
        public func setFleetSize(_ size: Int?) throws { try withEngine { try $0.setFleetSize(size) } }

        // MARK: Listening

        private func listen(on port: UInt16) {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 10
            tcp.keepaliveInterval = 5
            tcp.keepaliveCount = 3
            let parameters = NWParameters(tls: nil, tcp: tcp)
            if configuration.loopbackOnly { parameters.requiredInterfaceType = .loopback }

            let listener: NWListener
            do {
                if port == 0 {
                    listener = try NWListener(using: parameters)
                } else {
                    listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
                }
            } catch {
                set(.failed(String(describing: error)))
                return
            }
            if configuration.bonjour {
                advertisedLine = engine.lineIdentity?.id ?? ""
                listener.service = service()
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, listener === self.listener else { return }
                self.listener(listener, became: state, askedFor: port)
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                self.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        }

        private func listener(_ listener: NWListener, became state: NWListener.State, askedFor port: UInt16) {
            switch state {
            case .ready:
                set(.listening(port: listener.port?.rawValue ?? port))
            case let .failed(error):
                listener.cancel()
                self.listener = nil
                if port != 0, configuration.fallsBackToAnyPort, case .posix(.EADDRINUSE) = error {
                    // The preferred port is taken: any free one will do. Bonjour says which, and the
                    // operator is shown it, to give to a cab.
                    listen(on: 0)
                } else {
                    set(.failed(String(describing: error)))
                }
            default:
                break
            }
        }

        /// What Bonjour says of the PCC: the protocol it speaks, its name, and the line it is running.
        private func service() -> NWListener.Service {
            var record = NWTXTRecord()
            record["proto"] = String(CabineWire.protocolVersion)
            record["name"] = engine.settings.name
            record["line"] = engine.lineIdentity?.id ?? ""
            // A Bonjour name is 63 bytes at most.
            var name = ""
            for character in engine.settings.name {
                guard name.utf8.count + String(character).utf8.count <= 63 else { break }
                name.append(character)
            }
            return NWListener.Service(name: name.isEmpty ? nil : name, type: CabineWire.bonjourServiceType,
                                      domain: CabineWire.bonjourDomain, txtRecord: record)
        }

        /// Keeps the Bonjour record's line in step with the line the PCC is on.
        private func advertise() {
            guard configuration.bonjour, let listener else { return }
            let line = engine.lineIdentity?.id ?? ""
            guard line != advertisedLine else { return }
            advertisedLine = line
            listener.service = service()
        }

        // MARK: Connections

        private func accept(_ wire: NWConnection) {
            guard connections.count < configuration.maxSessions else {
                refuse(wire)
                return
            }
            let connection = Connection(id: SessionID(nextSession), wire: wire)
            nextSession += 1
            connections[connection.id] = connection
            engine.open(connection.id, peer: connection.peer)
            wire.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection else { return }
                switch state {
                case .ready:
                    self.receive(on: connection)
                case .failed, .cancelled, .waiting:
                    self.close(connection)
                default:
                    break
                }
            }
            wire.start(queue: queue)
        }

        /// Turns away a connection beyond the limit, saying why.
        private func refuse(_ wire: NWConnection) {
            let line = CabineWire.Codec.framed(.error(.init(error: .tooManySessions,
                                                             message: "this PCC already serves \(configuration.maxSessions) connections")))
            wire.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    wire.send(content: line, contentContext: .finalMessage, isComplete: true,
                              completion: .contentProcessed { _ in wire.cancel() })
                case .failed, .cancelled:
                    wire.stateUpdateHandler = nil
                default:
                    break
                }
            }
            wire.start(queue: queue)
        }

        private func receive(on connection: Connection) {
            connection.wire.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self, weak connection] data, _, isComplete, error in
                guard let self, let connection, !connection.closed else { return }
                if let data, !data.isEmpty { self.consume(data, from: connection) }
                guard !connection.closed else { return }
                if error != nil {
                    self.close(connection)
                } else if isComplete {
                    // The cab has finished sending: it is answered, then let go.
                    self.close(connection, flushing: true)
                } else {
                    self.receive(on: connection)
                }
            }
        }

        private func consume(_ data: Data, from connection: Connection) {
            for line in connection.framer.append(data) {
                let message = engine.receive(line: line, from: connection.id)
                // The round trip of a ping is told by the system's clock, which the engine does not have.
                if case let .pong(pong)? = message, case let .integer(id)? = pong.id, let sent = pingSentAt[id] {
                    engine.noteRoundTrip(Server.uptime - sent, for: connection.id)
                }
            }
            flush()
            if connection.framer.lineTooLong, !connection.closed {
                write(.error(.init(error: .lineTooLong, message: "a line may be 1 MiB at most")), to: connection)
                close(connection, flushing: true)
            }
        }

        /// Sends what the engine has to send.
        private func flush() {
            for outbound in engine.takeOutbox() {
                guard let connection = connections[outbound.session], !connection.closed else { continue }
                // A reader that has fallen behind misses a picture; it is not sent them all in a heap later.
                if outbound.message.isPeriodic, connection.inFlight >= Server.behind { continue }
                write(outbound.message, to: connection)
                if outbound.thenClose { close(connection, flushing: true) }
            }
        }

        private func write(_ message: CabineWire.PCCMessage, to connection: Connection) {
            guard connection.inFlight < Server.lost else {
                close(connection)
                return
            }
            connection.inFlight += 1
            connection.wire.send(content: CabineWire.Codec.framed(message), completion: .contentProcessed { [weak self, weak connection] error in
                guard let connection else { return }
                connection.inFlight -= 1
                if error != nil { self?.close(connection) }
            })
        }

        /// Drops a connection. `cancel()` throws away what is still queued, so one that is owed an answer
        /// is closed `flushing`: the end of the stream goes out behind the queued lines, and the
        /// connection is torn down once it has been sent, or after a few seconds if the cab has stopped
        /// reading.
        private func close(_ connection: Connection, flushing: Bool = false) {
            guard !connection.closed else { return }
            connection.closed = true
            let wire = connection.wire
            wire.stateUpdateHandler = nil
            if flushing {
                wire.send(content: nil, contentContext: .finalMessage, isComplete: true,
                          completion: .contentProcessed { _ in wire.cancel() })
                queue.asyncAfter(deadline: .now() + 5) { wire.cancel() }
            } else {
                wire.cancel()
            }
            connections[connection.id] = nil
            engine.close(connection.id)
            // The other cabs may have something to hear of it.
            flush()
        }

        // MARK: Time

        /// One beat of the timer: the engine is stepped by the time that has really passed, and the
        /// messages that are due go out.
        private func tick() {
            guard running else { return }
            let now = Server.uptime
            // After a stall the line does not race to catch up: it loses the time.
            engine.step(min(max(now - steppedAt, 0), 1))
            steppedAt = now

            let link = engine.settings.link
            if due(&trafficDue, every: link.trafficPeriodS, now) { engine.broadcastTraffic() }
            if due(&infoDue, every: link.infoPeriodS, now) { engine.broadcastInfo() }
            if due(&pingDue, every: link.pingPeriodS, now) {
                let id = engine.broadcastPing()
                pingSentAt[id] = now
                pingSentAt = pingSentAt.filter { now - $0.value < 10 }
            }
            flush()
            advertise()
        }

        /// True when something sent every `period` seconds is due, moving its next time on. It stays on
        /// its grid, and starts a new one after a long stall instead of bursting to catch up.
        private func due(_ next: inout Double, every period: Double, _ now: Double) -> Bool {
            // The timer beats a little early as often as late: half a beat's grace keeps the rate.
            let grace = 0.5 / max(configuration.stepHz, 1)
            guard now + grace >= next else { return false }
            next = now - next > period ? now + period : next + period
            return true
        }
    }
}

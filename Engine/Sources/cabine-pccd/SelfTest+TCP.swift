import Foundation
import CabinePCCKit

// 5. Over real TCP on 127.0.0.1, with a port the system chooses: scripted clients against the server,
// and the operator's orders given through the server's own calls.

extension SelfTest {

    func tcp(_ lines: [Subject]) {
        var settings = CabinePCC.Settings()
        settings.name = "PCC ESSAI"
        settings.pccID = "selftest"
        var configuration = CabinePCC.Server.Configuration()
        configuration.port = 0
        configuration.loopbackOnly = true
        configuration.bonjour = false
        configuration.maxSessions = 4
        let server = CabinePCC.Server(settings: settings, configuration: configuration, seed: 5)
        server.start()
        guard let port = server.waitUntilListening(timeout: 5) else {
            check("the server listens on 127.0.0.1", false, "\(server.state)")
            return
        }
        check("the server listens on 127.0.0.1, on a port the system chose", port != 0 && server.port == port, "port \(port)")
        defer { server.stop() }

        func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        func flag(_ value: Any?) -> Bool? { value as? Bool }
        func whole(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
        func named(_ message: [String: Any]?) -> [String: Any]? { message?["line"] as? [String: Any] }
        func isLine(_ message: [String: Any]) -> Bool { message["event"] as? String == "line" }

        // The library the operator will give the PCC: the built-in line with the sample source, and
        // another line with none.
        let line = CabinePCC.testLine
        let identity = #"{"id":"\#(line.id)","rev":"\#(line.rev)","name":"\#(line.name)"}"#
        let packageText = SelfTest.packageText(line, source: SelfTest.sampleSource)
        var other = line
        other.id = "bis"
        other.name = "Ligne bis"
        other.rev = "0000000000000002"
        other.stations[0].name = "Porte Bis"
        let otherIdentity = #"{"id":"bis","rev":"0000000000000002","name":"Ligne bis"}"#
        guard let package = try? CabineWire.LinePackage.decode(file: Data(packageText.utf8)) else {
            check("the test's own package is read", false)
            return
        }
        let firstStop = line.tracks[0].stopsM[0]

        // The first cab holds no line, and the PCC is on none.
        guard let a = TestClient(port: port) else {
            check("a client connects", false)
            return
        }
        a.send(#"{"type":"hello","protocol":1,"app":"Cabine","appVersion":"selftest","cab":{"id":"5F0C4F0E-2B1A-4E57-9C55-0D6A3E1B7C21","name":"Mac mini"}}"#)
        let hello = a.next("hello")
        let link = hello?["link"] as? [String: Any]
        check("hello is answered with hello: the PCC is on no line and names none",
              flag(hello?["onLine"]) == false && hello?["line"] == nil && hello?["needLine"] == nil && whole(hello?["protocol"]) == 1
                && hello?["app"] as? String == "CabinePCC" && hello?["name"] as? String == "PCC ESSAI"
                && (hello?["pcc"] as? [String: Any])?["id"] as? String == "selftest"
                && number(link?["positionPeriodS"]) == 0.2 && number(link?["statusPeriodS"]) == 0.3 && number(link?["trafficPeriodS"]) == 0.2
                && number(link?["authorityPeriodS"]) == 0.6 && number(link?["infoPeriodS"]) == 0.4 && number(link?["pingPeriodS"]) == 0.5
                && number(link?["timeoutS"]) == 3 && number(link?["staleHoldS"]) == 30)
        a.listen(for: 0.9)
        let idle = a.inbox.filter { $0["type"] as? String == "info" }
        check("a cab of a PCC on no line gets info and nothing else: 08:42:00, stopped, no rames",
              !idle.isEmpty && a.counts.keys.sorted() == ["hello", "info"] && idle.allSatisfy { info in
                  number(info["clockS"]) == 31_320 && info["mode"] as? String == "stopped" && whole(info["rames"]) == 0
                      && whole(info["cabs"]) == 0 && (info["numbers"] as? [Any])?.isEmpty == true
              }, a.counts.keys.sorted().joined(separator: " "))
        a.send(#"{"type":"lineRequest","id":"l0"}"#)
        let none = a.next("result")
        check("a lineRequest that names no line, of a PCC on none, is refused with noLine",
              flag(none?["ok"]) == false && none?["error"] as? String == "noLine" && none?["id"] as? String == "l0")

        // The operator fills the library and puts the PCC on a line: the cab is told, asks for the line,
        // is sent it, and says hello again once it holds it.
        a.clear()
        let filled = refusal(of: {
            try server.keep(package)
            try server.keep(CabineWire.LinePackage(description: other))
            try server.takeUp(held: line.identity)
        })
        let told = a.next("event", where: isLine)
        check("the operator puts the PCC on a line of its library, and the cab is told with event line",
              filled == nil && named(told)?["id"] as? String == line.id && named(told)?["rev"] as? String == line.rev
                && named(told)?["name"] as? String == line.name && server.snapshot().library.map(\.identity) == [line.identity, other.identity],
              filled.map { "\($0)" } ?? "")
        a.send(#"{"type":"lineRequest","id":"l1"}"#)
        let sent = a.next("line")
        var faithful = false
        if let raw = a.raw["line"], let document = Parsed(raw), let got = document["package"], let wanted = Parsed(packageText) {
            faithful = got.same(as: wanted) && document["id"]?.same(as: Parsed.string("l1")) == true
        }
        check("it asks for the line and is sent the package: the description, and the source to the last digit of every number",
              sent != nil && faithful, "a line of \(a.raw["line"]?.count ?? 0) bytes")
        a.send(#"{"type":"hello","protocol":1,"app":"Cabine","appVersion":"selftest","cab":{"id":"5F0C4F0E-2B1A-4E57-9C55-0D6A3E1B7C21","name":"Mac mini"},"line":\#(identity)}"#)
        let again = a.next("hello")
        check("it says hello again, naming the line, and is on the line",
              flag(again?["onLine"]) == true && named(again)?["id"] as? String == line.id && named(again)?["rev"] as? String == line.rev)

        // From here on: traffic, info and ping.
        a.clear()
        let traffic = a.next("traffic", within: 2)
        let info = a.next("info", within: 2)
        let ping = a.next("ping", within: 2)
        let trains = traffic?["trains"] as? [[String: Any]] ?? []
        let wellFormed = !trains.isEmpty && trains.allSatisfy { train in
            train["kind"] as? String == "auto" && whole(train["rame"]) != nil && [1, 2].contains(whole(train["track"]) ?? 0)
                && number(train["uM"]) != nil && number(train["speedMS"]) != nil && number(train["doors"]) != nil
                && train["phase"] as? String != nil && number(train["lengthM"]) == 75 && train["name"] == nil
        }
        check("traffic comes: every rame of the line, each with its number, kind, track, uM, speed, doors, phase and length",
              wellFormed && number(traffic?["tS"]) != nil, "\(trains.count) trains")
        check("info comes: the clock from 08:42:00, the mode, the numbers in use",
              (31_320...31_335).contains(number(info?["clockS"]) ?? 0) && info?["mode"] as? String == "normal" && whole(info?["rames"]) == trains.count
                && whole(info?["cabs"]) == 0 && (info?["numbers"] as? [Any])?.count == trains.count && number(info?["tS"]) != nil)
        check("ping comes, with an id and a tS", ping?["id"] != nil && number(ping?["tS"]) != nil)

        // It joins where an automatic rame stands, reports, and is sent its authority.
        a.send(#"{"type":"join","id":"j1","track":1,"uM":\#(firstStop),"station":0,"rame":21}"#)
        let joined = a.next("result")
        check("join is answered with the number asked for", flag(joined?["ok"]) == true && whole(joined?["rame"]) == 21 && joined?["id"] as? String == "j1")
        var authorities: [[String: Any]] = []
        if let first = a.next("authority", within: 1) { authorities.append(first) }
        check("the first authority comes with the answer", authorities.count == 1)
        for report in 1...8 {
            a.send(#"{"type":"position","seq":\#(report),"tS":\#(Double(report) * 0.2),"track":1,"uM":\#(firstStop),"speedMS":0,"accelerationMS2":0}"#)
            if report % 2 == 1 {
                a.send(#"{"type":"status","seq":\#(report),"tS":\#(Double(report) * 0.2),"mode":"CM","automatic":false,"doors":{"phase":"open","side":"right","open":1},"emergencyBrake":{"applied":false},"passengers":40,"station":{"index":0,"atPlatform":true},"deviationS":0,"held":false,"paused":false,"underControl":true}"#)
            }
            a.listen(for: 0.2)
        }
        while let more = a.next("authority", within: 0.01) { authorities.append(more) }
        // Three by now on a machine with time to spare; one that is busy is given a little longer.
        while authorities.count < 3, let more = a.next("authority", within: 1.5) { authorities.append(more) }
        let sequence = authorities.compactMap { whole($0["seq"]) }
        let reaches = authorities.allSatisfy { authority in
            whole(authority["track"]) == 1 && (number(authority["endM"]) ?? 0) > firstStop && number(authority["validS"]) == 3
                && ["train", "horizon", "end"].contains(authority["reason"] as? String ?? "")
        }
        check("it reports, and its authority is renewed: ahead of its nose, numbered in order",
              authorities.count >= 3 && sequence == Array(1...max(sequence.count, 1)) && reaches,
              "\(authorities.count) of them, the last to \(number(authorities.last?["endM"]) ?? 0) m (\(authorities.last?["reason"] as? String ?? "-"))")
        check("nothing the server sent was unreadable, and its own train is never in its picture", a.unreadable == 0 && !a.inbox.contains { message in
            message["type"] as? String == "traffic" && (message["trains"] as? [[String: Any]] ?? []).contains { whole($0["rame"]) == 21 }
        })

        // The host sees the cab, and how long a ping takes to come back.
        let snapshot = server.snapshot()
        let cab = snapshot.cabs.first
        check("the host's snapshot shows the cab in service, with its name, its mode and the round trip of a ping",
              snapshot.cabs.count == 1 && cab?.number == 21 && cab?.cab?.name == "Mac mini" && cab?.cab?.link == .live
                && cab?.cab?.mode == .manual && cab?.cab?.automatic == false && cab?.doors == 1 && cab?.cab?.roundTripS != nil
                && snapshot.sessions.count == 1 && snapshot.sessions.first?.standing == .inService && snapshot.sessions.first?.rame == 21
                && snapshot.sessions.first?.app == "Cabine" && snapshot.sessions.first?.line == line.identity,
              String(format: "round trip %.1f ms", (cab?.cab?.roundTripS ?? -1) * 1_000))
        let journal = server.takeJournal().map(\.event)
        check("the journal has the cab connecting with no line, the line taken up, the cab on the line and joining",
              journal.contains(.cabConnected(name: "Mac mini", cabID: "5F0C4F0E-2B1A-4E57-9C55-0D6A3E1B7C21", line: nil))
                && journal.contains { if case .lineTakenUp(line: line.identity, rames: _) = $0 { true } else { false } }
                && journal.contains(.cabOnLine(name: "Mac mini"))
                && journal.contains { if case .cabJoined(name: "Mac mini", rame: 21, track: 1, uM: _, withdrawn: _) = $0 { true } else { false } })

        // A second cab, which holds a line the PCC has not.
        guard let b = TestClient(port: port) else {
            check("a second client connects", false)
            return
        }
        b.send(#"{"type":"hello","protocol":1,"app":"Cabine","cab":{"id":"B","name":"Autre"},"line":{"id":"autre","rev":"1","name":"Autre ligne"}}"#)
        let apart = b.next("hello")
        check("a cab that holds another line is told onLine false, and which line the PCC is on",
              flag(apart?["onLine"]) == false && apart?["needLine"] == nil && named(apart)?["id"] as? String == line.id
                && named(apart)?["rev"] as? String == line.rev)
        b.send(#"{"type":"lineRequest","id":"l2","line":{"id":"autre","rev":"1"}}"#)
        let unknown = b.next("result")
        b.send(#"{"type":"join","id":"j2","track":1,"uM":\#(firstStop)}"#)
        let notOn = b.next("result")
        b.listen(for: 0.5)
        check("the line it names is not in the library: noSuchLine; its join is refused with notOnLine, and it is sent no traffic",
              flag(unknown?["ok"]) == false && unknown?["error"] as? String == "noSuchLine" && unknown?["id"] as? String == "l2"
                && unknown?["message"] as? String == "no line autre in the library"
                && flag(notOn?["ok"]) == false && notOn?["error"] as? String == "notOnLine" && b.counts["traffic"] == nil
                && b.counts["ping"] == nil && (b.counts["info"] ?? 0) >= 1)
        b.send(#"{"type":"lineRequest","id":"l3","line":{"id":"bis","rev":"0000000000000002"}}"#)
        let spare = b.next("line")
        let spared = spare?["package"] as? [String: Any]
        check("a cab may ask for any line of the library by its id and its rev: one kept without a source is sent without one",
              spare?["id"] as? String == "l3" && whole(spared?["format"]) == 1 && spared?["source"] == nil
                && (spared?["description"] as? [String: Any])?["id"] as? String == "bis"
                && ((spared?["description"] as? [String: Any])?["stations"] as? [[String: Any]])?.first?["name"] as? String == "Porte Bis")

        // While the first cab is in service the line is the operator's to change no more.
        let busy = refusal(of: { try server.takeUp(held: other.identity) })
        let shut = refusal(of: { try server.closeLine() })
        let nowhere = refusal(of: { try server.takeUp(held: .init(id: "nulle", rev: "0", name: "")) })
        check("while a cab is in service the operator can neither change line nor close it; a line the library has not is noSuchLine",
              busy == .lineInUse && shut == .lineInUse && nowhere == .noSuchLine && server.snapshot().line?.identity == line.identity
                && server.snapshot().cabs.count == 1)

        // A third cab on the same line: on the line at once, and the first cab is in its picture.
        guard let c = TestClient(port: port) else {
            check("a third client connects", false)
            return
        }
        c.send(#"{"type":"hello","protocol":1,"app":"Cabine","cab":{"id":"C","name":"Troisième"},"line":\#(identity)}"#)
        let welcome = c.next("hello")
        let picture = c.next("traffic", within: 2)
        let seen = (picture?["trains"] as? [[String: Any]] ?? []).first { whole($0["rame"]) == 21 }
        check("a cab that holds the PCC's line is on the line at once, and its traffic shows the first cab with kind cab",
              flag(welcome?["onLine"]) == true && seen?["kind"] as? String == "cab"
                && seen?["name"] as? String == "Mac mini" && whole(seen?["track"]) == 1 && number(seen?["uM"]) == firstStop
                && number(seen?["doors"]) == 1 && seen?["phase"] as? String == "dwelling" && whole(seen?["station"]) == 0
                && (picture?["trains"] as? [Any])?.count == trains.count)

        // A real line's source, kept and asked for: what crosses TCP is what Cabine wrote.
        let real = lines.filter { subject in
            subject.file != nil && subject.package.source != nil && (try? CabinePCC.Line(subject.package.description)) != nil
                && !subject.package.identity.isSameLine(as: line.identity) && !subject.package.identity.isSameLine(as: other.identity)
        }.max { ($0.file?.count ?? 0) < ($1.file?.count ?? 0) }
        if let real, let file = real.file, let original = Parsed(file).flatMap(SelfTest.asPackage), let source = original["source"] {
            let kept = refusal(of: { try server.keep(real.package) })
            let wanted = real.package.identity
            c.send(#"{"type":"lineRequest","id":"l9","line":{"id":"\#(wanted.id)","rev":"\#(wanted.rev)"}}"#)
            let came = c.next("line", within: 5)
            var same = false
            if let raw = c.raw["line"], let got = Parsed(raw)?["package"], let crossed = got["source"], let described = got["description"],
               let given = original["description"] {
                same = crossed.same(as: source) && described.isWithin(given)
            }
            check("the source of the \(real.name) crosses TCP as Cabine wrote it: every number to its last digit",
                  kept == nil && came?["id"] as? String == "l9" && same && server.heldPackage(wanted) == real.package,
                  "\(source.numberCount) numbers in a line of \(c.raw["line"]?.count ?? 0) bytes")
        } else {
            print("      (no fixture with a source: the sample source alone has crossed TCP)")
        }

        // The operator's order through the server's calls reaches the cab.
        var ordered = false
        do {
            try server.message(rame: 21, "ESSAI DE LIAISON")
            let command = a.next("command")
            ordered = command?["command"] as? String == "message" && command?["value"] as? String == "ESSAI DE LIAISON" && command?["id"] != nil
            if let id = command?["id"] as? String { a.send(#"{"type":"result","id":"\#(id)","ok":true}"#) }
        } catch {
            ordered = false
        }
        check("an order given through the server reaches the cab as a command", ordered)

        // What closes a connection: another protocol version, a session too many, a line too long.
        if let d = TestClient(port: port) {
            d.send(#"{"type":"hello","protocol":2,"cab":{"id":"D"},"line":\#(identity)}"#)
            let error = d.next("error")
            check("a hello of another version is answered with error unsupportedProtocol, and the connection is closed",
                  error?["error"] as? String == "unsupportedProtocol" && d.waitForClose())
        } else {
            check("a fourth client connects", false)
        }
        if let e = TestClient(port: port), let f = TestClient(port: port) {
            let error = f.next("error")
            check("a connection beyond the limit is answered with error tooManySessions, and closed",
                  error?["error"] as? String == "tooManySessions" && f.waitForClose() && server.snapshot().sessions.count == 4)
            // Exactly as much as makes a line too long, so that the server has read all of it when it closes.
            e.write(Data(repeating: UInt8(ascii: "a"), count: CabineWire.maxLineBytes + 2))
            let long = e.next("error", within: 5)
            check("a line over 1 MiB is answered with error lineTooLong, and the connection is closed",
                  long?["error"] as? String == "lineTooLong" && e.waitForClose())
        } else {
            check("two more clients connect", false)
        }

        // leave: the train goes back to automation.
        a.send(#"{"type":"leave","id":"v1","reason":"ended"}"#)
        let left = a.next("result") { $0["id"] as? String == "v1" }
        let gone = c.next("event") { $0["event"] as? String == "peer" && $0["state"] as? String == "left" }
        let after = server.snapshot()
        check("leave is answered, the train goes back to automation, and the other cab is told",
              flag(left?["ok"]) == true && after.cabs.isEmpty && after.rame(numbered: 21)?.kind == .auto && whole(gone?["rame"]) == 21
                && gone?["name"] as? String == "Mac mini")

        // No cab is in service now: the operator changes line, and every cab is told. The cabs that hold
        // the line it has left are on the line no more.
        a.clear()
        b.clear()
        c.clear()
        let changed = refusal(of: { try server.takeUp(held: other.identity) })
        let toA = a.next("event", where: isLine), toB = b.next("event", where: isLine), toC = c.next("event", where: isLine)
        check("with no cab in service the operator changes line, and every cab is told with event line",
              changed == nil && [toA, toB, toC].allSatisfy { named($0)?["id"] as? String == "bis" && named($0)?["rev"] as? String == "0000000000000002" }
                && server.snapshot().line?.identity == other.identity,
              changed.map { "\($0)" } ?? "")
        c.clear()
        c.listen(for: 0.9)
        let kinds = Set(c.inbox.compactMap { $0["type"] as? String })
        let restarted = c.inbox.first { $0["type"] as? String == "info" }
        check("a cab that holds the line the PCC has left is on the line no more: info still comes, traffic and ping do not",
              kinds == ["info"] && (31_320...31_325).contains(number(restarted?["clockS"]) ?? 0) && restarted?["mode"] as? String == "normal",
              kinds.sorted().joined(separator: " "))
        c.send(#"{"type":"lineRequest","id":"l4"}"#)
        let followed = c.next("line")
        c.send(#"{"type":"hello","protocol":1,"app":"Cabine","cab":{"id":"C","name":"Troisième"},"line":\#(otherIdentity)}"#)
        let onNew = c.next("hello")
        let newPicture = c.next("traffic", within: 2)
        check("it follows the PCC: it asks for the line, is sent it, says hello naming it, and is on the line again",
              followed?["id"] as? String == "l4" && ((followed?["package"] as? [String: Any])?["description"] as? [String: Any])?["id"] as? String == "bis"
                && flag(onNew?["onLine"]) == true && named(onNew)?["id"] as? String == "bis" && newPicture != nil
                && server.snapshot().sessions.filter { $0.standing == .onLine }.count == 1)

        // The operator closes the line: every cab is told, with an event that names no line.
        a.clear()
        b.clear()
        c.clear()
        let closed = refusal(of: { try server.closeLine() })
        let shutA = a.next("event", where: isLine), shutB = b.next("event", where: isLine), shutC = c.next("event", where: isLine)
        let off = server.snapshot()
        check("the operator closes the line: every cab is told with an event line that names none",
              closed == nil && [shutA, shutB, shutC].allSatisfy { $0 != nil && $0?["line"] == nil } && off.line == nil && off.rames.isEmpty
                && off.mode == .stopped && off.sessions.allSatisfy { $0.standing == .connected })
        c.clear()
        let quiet = c.next("info", within: 2)
        let forgotten = refusal(of: { try server.forget(other.identity) })
        check("and info says so: stopped, no rames, 08:42:00; a line the PCC is not on can then be taken out of the library",
              quiet?["mode"] as? String == "stopped" && whole(quiet?["rames"]) == 0 && number(quiet?["clockS"]) == 31_320
                && forgotten == nil && server.heldPackage(other.identity) == nil && server.heldPackage(line.identity) == package)

        // The PCC closes.
        server.stop()
        let closing = a.next("event") { $0["event"] as? String == "closing" }
        check("when the server stops the cabs are told it is closing, and the connections are closed",
              closing != nil && a.waitForClose() && c.waitForClose() && b.waitForClose())
        let stopped = Date().addingTimeInterval(2)
        while server.state != .stopped, Date() < stopped { usleep(20_000) }
        // Stopped is said once the listener has let go of its port: nothing answers there any more.
        let answers = TestClient(port: port) != nil
        check("the server has stopped, and its port is free", server.state == .stopped && !answers,
              "\(server.state)" + (answers ? ", and the port still answers" : ""))
        // A host that starts its PCC again finds the port where it left it. This one is let go of as
        // soon as it is told to stop: it still says when it has, and has let go of the port by then.
        var same = configuration
        same.port = port
        same.fallsBackToAnyPort = false
        var successor: CabinePCC.Server? = CabinePCC.Server(settings: settings, configuration: same, seed: 7)
        successor?.start()
        let taken = successor?.waitUntilListening(timeout: 3)
        check("another server started as soon as the first has stopped is given the same port", taken == port,
              successor.map { "\($0.state)" } ?? "")
        let done = DispatchSemaphore(value: 0)
        successor?.stop { done.signal() }
        successor = nil
        let finished = done.wait(timeout: .now() + 3) == .success
        check("a server its host lets go of as it stops still says when it has stopped, and its port is free by then",
              finished && TestClient(port: port) == nil)

        hostedOnMain(settings, configuration, identity)
    }

    /// A host may give the server a queue of its own choosing: here the main one, as a main-actor app
    /// would. The server then works from the main run loop, and what the main thread asks of it is
    /// answered at once, without waiting for itself.
    private func hostedOnMain(_ settings: CabinePCC.Settings, _ configuration: CabinePCC.Server.Configuration, _ identity: String) {
        /// What the client's thread found, handed over once it has finished.
        final class Found: @unchecked Sendable {
            var hello: [String: Any]?
            var info: [String: Any]?
        }
        func turnMain(until done: () -> Bool, for seconds: Double) {
            let deadline = Date().addingTimeInterval(seconds)
            while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }

        let server = CabinePCC.Server(settings: settings, configuration: configuration, seed: 6, queue: .main)
        // Asked from the main thread, which is the server's own queue, before it has even started.
        let taken = refusal(of: { try server.takeUp(CabineWire.LinePackage(description: CabinePCC.testLine)) })
        server.start()
        turnMain(until: { server.port != nil }, for: 5)
        guard let port = server.port else {
            check("a server given the main queue listens from it", false, "\(server.state)")
            return
        }
        let found = Found()
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            if let client = TestClient(port: port) {
                client.send(#"{"type":"hello","protocol":1,"cab":{"id":"M","name":"Principal"},"line":\#(identity)}"#)
                found.hello = client.next("hello")
                found.info = client.next("info")
                client.hangUp()
            }
            finished.signal()
        }
        var over = false
        turnMain(until: {
            if !over { over = finished.wait(timeout: .now()) == .success }
            return over
        }, for: 8)
        let snapshot = server.snapshot()
        let journal = server.takeJournal()
        check("a server given the main queue serves from it, on the line its host put it on, and answers the main thread at once",
              taken == nil && over && found.hello?["onLine"] as? Bool == true && found.info?["mode"] as? String == "normal"
                && snapshot.line?.identity == CabinePCC.testLine.identity && snapshot.library.count == 1
                && journal.contains { if case .cabConnected(name: "Principal", cabID: "M", line: _) = $0.event { true } else { false } })
        server.stop()
        turnMain(until: { server.state == .stopped }, for: 3)
    }
}

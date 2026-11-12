import Foundation
import CabinePCCKit

// 1. Every message of the specification encodes and decodes, and a message with unknown fields or an
// unknown type does no harm. The samples are the specification's own examples, as it prints them; where
// it prints only the beginning of a line's package, the sample is a whole one of the same shape.

extension SelfTest {

    /// The description the specification prints: Ligne 21, cut down to its first two stations.
    static let specificationLine = #"""
    {"id":"21","name":"Ligne 21","rev":"9f3c2a7d5e1b0c44","lengthM":7617.5,
     "colour":"E4572E","textColour":"FFFFFF","lineSpeedMS":19.444,
     "train":{"lengthM":75,"maxSpeedMS":19.444,"accelerationMS2":1.25,"serviceBrakeMS2":1.25,
              "emergencyBrakeMS2":1.78,"approachDecelMS2":0.6,"marginMS":1.3,"capacity":560},
     "cbtc":{"safetyMarginM":25,"stoppingShortM":6,"horizonM":1500,"departureRoomM":40,
             "uncertaintyBaseM":1.5,"uncertaintyPerM":0.02,"uncertaintyMaxM":8},
     "dwell":{"minS":17,"maxS":27,"terminusS":30,"doorsOpenS":2.2,"doorsCloseS":2.4,"departS":4.2},
     "endBufferM":28,
     "stations":[{"name":"Porte du Levant"},{"name":"Rue des Tanneurs"}],
     "tracks":[
       {"track":1,"stopsM":[279.5,877.9],
        "zones":[{"fromM":355.0,"toM":521.0,"limitMS":15.28}],
        "beaconsM":[186.0,326.0,471.0]},
       {"track":2,"stopsM":[6816.6,7415.0],
        "zones":[{"fromM":7096.5,"toM":7262.5,"limitMS":15.28}],
        "beaconsM":[6648.0,6865.0]}]}
    """#

    /// A source in the shape of the specification's, which prints only the beginning of one.
    static let specificationSource = #"""
    {"format":1,"id":"21","name":"Ligne 21","length":13224.5,
     "stations":[{"name":"Porte du Levant","at":150.89},{"name":"Rue des Tanneurs","at":749.3}],
     "headingStep":10,"heading":[41.87,41.9,42.25]}
    """#

    /// The specification's examples of what a cab sends.
    private static let fromCab: [(name: String, json: String)] = [
        ("hello from a cab", #"""
        {"type":"hello","protocol":1,"app":"Cabine","appVersion":"1.0",
         "cab":{"id":"5F0C4F0E-2B1A-4E57-9C55-0D6A3E1B7C21","name":"Mac mini"},
         "line":{"id":"21","rev":"9f3c2a7d5e1b0c44","name":"Ligne 21"}}
        """#),
        ("lineRequest", #"{"type":"lineRequest","id":"l1"}"#),
        ("join", #"{"type":"join","id":"j1","track":1,"uM":279.5,"station":0,"rame":21}"#),
        ("position", #"{"type":"position","seq":812,"tS":162.417,"track":1,"uM":1834.52,"speedMS":13.61,"accelerationMS2":-0.42}"#),
        ("status", #"""
        {"type":"status","seq":271,"tS":162.4,"mode":"PA","automatic":true,
         "doors":{"phase":"closed","side":"right","open":0},
         "emergencyBrake":{"applied":false},
         "passengers":212,"station":{"index":4,"atPlatform":false},
         "deviationS":-4,"held":false,"paused":false,"underControl":true}
        """#),
        ("event report", #"{"type":"event","event":"report","code":"passengerIll","text":"MALAISE VOYAGEUR"}"#),
        ("event call", #"{"type":"event","event":"call"}"#),
        ("event acknowledge", #"{"type":"event","event":"acknowledge"}"#),
        ("event emergencyBrake", #"{"type":"event","event":"emergencyBrake","applied":true,"cause":"FREINAGE D'URGENCE CONDUCTEUR"}"#),
        ("leave", #"{"type":"leave","id":"v1","reason":"finished"}"#),
        ("pong", #"{"type":"pong","id":41,"tS":8123.5}"#),
        ("a cab's result to a command", #"{"type":"result","id":"c7","ok":true}"#)
    ]

    /// The specification's examples of what the PCC sends.
    private static let fromPCC: [(name: String, json: String)] = [
        ("hello from the PCC", #"""
        {"type":"hello","protocol":1,"app":"CabinePCC","name":"PCC LIGNE 21","pcc":{"id":"…"},
         "line":{"id":"21","rev":"9f3c2a7d5e1b0c44","name":"Ligne 21"},"onLine":true,
         "link":{"positionPeriodS":0.2,"statusPeriodS":0.3,"trafficPeriodS":0.2,"authorityPeriodS":0.6,
                 "infoPeriodS":0.4,"pingPeriodS":0.5,"timeoutS":3,"staleHoldS":30}}
        """#),
        ("result of a join", #"{"type":"result","id":"j1","ok":true,"rame":21}"#),
        ("result refusing a line", #"{"type":"result","id":"l1","ok":false,"error":"noSuchLine","message":"no line 9 in the library"}"#),
        ("line, with a whole package", #"{"type":"line","id":"l1","package":{"format":1,"description":"# + specificationLine
            + #","source":"# + specificationSource + "}}"),
        ("traffic", #"""
        {"type":"traffic","tS":8123.4,"trains":[
          {"rame":12,"kind":"auto","track":1,"uM":2390.4,"speedMS":0,"accelerationMS2":0,"doors":1,
           "phase":"dwelling","station":4,"lengthM":75},
          {"rame":31,"kind":"cab","name":"Mac mini","track":2,"uM":5120.0,"speedMS":14.2,"accelerationMS2":0.3,
           "doors":0,"phase":"running","station":7,"lengthM":75},
          {"rame":8,"kind":"auto","track":2,"uM":7589.5,"speedMS":0,"doors":0,"phase":"tail","lengthM":75}]}
        """#),
        ("authority", #"{"type":"authority","seq":93,"tS":8123.6,"track":1,"endM":2284.0,"reason":"train","rame":12,"gapM":31.4,"validS":3}"#),
        ("info", #"{"type":"info","tS":8123.6,"clockS":31337.2,"mode":"normal","rames":17,"cabs":2,"numbers":[3,8,12,31]}"#),
        ("ping", #"{"type":"ping","id":41,"tS":8123.5}"#),
        ("command", #"{"type":"command","id":"c7","command":"message","value":"REPRENEZ LA MARCHE NORMALE"}"#),
        ("event line", #"{"type":"event","event":"line","line":{"id":"21","rev":"9f3c2a7d5e1b0c44","name":"Ligne 21"}}"#),
        ("event peer", #"{"type":"event","event":"peer","rame":31,"name":"Mac mini","state":"joined"}"#),
        ("event closing", #"{"type":"event","event":"closing","inS":5}"#),
        ("error", #"{"type":"error","error":"lineTooLong","message":"a line may be 1 MiB at most"}"#)
    ]

    private static func oneLine(_ json: String) -> Data {
        Data(json.replacingOccurrences(of: "\n", with: " ").utf8)
    }

    /// Reads one of the specification's examples, writes it again, and checks that it comes back the same
    /// object: nothing lost, nothing added, nothing null, the type first, all on one line.
    private func roundTrip(_ name: String, _ json: String, fromCab: Bool) {
        let line = SelfTest.oneLine(json)
        do {
            let written: Data
            let type: String
            if fromCab {
                let message = try CabineWire.Codec.decodeCabMessage(line)
                if case .unknown = message {
                    check("\(name) decodes and encodes", false, "its type is not known")
                    return
                }
                written = CabineWire.Codec.encode(message)
                type = message.type
            } else {
                let message = try CabineWire.Codec.decodePCCMessage(line)
                if case .unknown = message {
                    check("\(name) decodes and encodes", false, "its type is not known")
                    return
                }
                written = CabineWire.Codec.encode(message)
                type = message.type
            }
            let text = String(decoding: written, as: UTF8.self)
            guard let before = SelfTest.object(line), let after = SelfTest.object(written) else {
                check("\(name) decodes and encodes", false, "wrote \(text)")
                return
            }
            let same = SelfTest.canonical(before) == SelfTest.canonical(after)
            let tidy = text.hasPrefix("{\"type\":\"\(type)\"") && !text.contains("null") && !text.contains("\n")
            check("\(name) decodes and encodes", same && tidy, same && tidy ? "" : "wrote \(text)")
        } catch {
            check("\(name) decodes and encodes", false, "\(error)")
        }
    }

    /// Why a line a cab might send cannot be read; nil if it can.
    private func failure(_ text: String) -> CabineWire.DecodeFailure? {
        do {
            _ = try CabineWire.Codec.decodeCabMessage(Data(text.utf8))
            return nil
        } catch {
            return error as? CabineWire.DecodeFailure
        }
    }

    func wire() {
        for sample in SelfTest.fromCab { roundTrip(sample.name, sample.json, fromCab: true) }
        for sample in SelfTest.fromPCC { roundTrip(sample.name, sample.json, fromCab: false) }

        // What was read is what was written: a field or two of each kind, by name.
        func cab(_ name: String) -> CabineWire.CabMessage? {
            SelfTest.fromCab.first { $0.name == name }.flatMap { try? CabineWire.Codec.decodeCabMessage(SelfTest.oneLine($0.json)) }
        }
        func pcc(_ name: String) -> CabineWire.PCCMessage? {
            SelfTest.fromPCC.first { $0.name == name }.flatMap { try? CabineWire.Codec.decodePCCMessage(SelfTest.oneLine($0.json)) }
        }
        var read = false
        if case let .hello(hello)? = cab("hello from a cab"), case let .lineRequest(request)? = cab("lineRequest"), case let .join(join)? = cab("join"),
           case let .position(position)? = cab("position"), case let .status(status)? = cab("status"), case let .event(report)? = cab("event report"),
           case let .event(brake)? = cab("event emergencyBrake"), case let .leave(leave)? = cab("leave"), case let .pong(pong)? = cab("pong") {
            read = hello.protocol == 1 && hello.cab?.id == "5F0C4F0E-2B1A-4E57-9C55-0D6A3E1B7C21" && hello.cab?.name == "Mac mini"
                && hello.line == CabineWire.LineIdentity(id: "21", rev: "9f3c2a7d5e1b0c44", name: "Ligne 21")
                && request.id == "l1" && request.line == nil
                && join.id == "j1" && join.track == 1 && join.uM == 279.5 && join.station == 0 && join.rame == 21
                && position.seq == 812 && position.uM == 1834.52 && position.speedMS == 13.61 && position.accelerationMS2 == -0.42
                && status.mode == .pa && status.automatic == true && status.doors?.phase == .closed && status.doors?.side == "right"
                && status.emergencyBrake?.applied == false && status.passengers == 212 && status.station?.index == 4
                && status.station?.atPlatform == false && status.deviationS == -4 && status.underControl == true
                && report.event == .report && report.code == .passengerIll && report.text == "MALAISE VOYAGEUR"
                && brake.event == .emergencyBrake && brake.applied == true && brake.cause == "FREINAGE D'URGENCE CONDUCTEUR"
                && leave.id == "v1" && leave.reason == .finished && pong.id == 41 && pong.tS == 8123.5
        }
        check("the fields of what a cab sends are read as they were written", read)
        read = false
        if case let .hello(hello)? = pcc("hello from the PCC"), case let .result(joined)? = pcc("result of a join"),
           case let .result(refused)? = pcc("result refusing a line"), case let .traffic(traffic)? = pcc("traffic"),
           case let .authority(authority)? = pcc("authority"), case let .info(info)? = pcc("info"), case let .command(command)? = pcc("command"),
           case let .event(now)? = pcc("event line"), case let .event(peer)? = pcc("event peer"), case let .event(closing)? = pcc("event closing"),
           case let .error(error)? = pcc("error") {
            read = hello.app == "CabinePCC" && hello.name == "PCC LIGNE 21" && hello.onLine
                && hello.line?.rev == "9f3c2a7d5e1b0c44" && hello.link == CabineWire.LinkTimings()
                && joined.ok && joined.rame == 21 && !refused.ok && refused.error == .noSuchLine && refused.message == "no line 9 in the library"
                && traffic.tS == 8123.4 && traffic.trains.count == 3 && traffic.trains[0].phase == .dwelling
                && traffic.trains[0].station == 4 && traffic.trains[1].kind == .cab && traffic.trains[1].name == "Mac mini"
                && traffic.trains[1].uM == 5120 && traffic.trains[2].phase == .tail && traffic.trains[2].station == nil
                && traffic.trains[2].uM == 7589.5 && traffic.trains[2].speedMS == 0
                && traffic.trains[2].accelerationMS2 == nil && traffic.trains[2].lengthM == 75
                && authority.seq == 93 && authority.endM == 2284 && authority.reason == .train && authority.rame == 12
                && authority.gapM == 31.4 && authority.validS == 3
                && info.clockS == 31337.2 && info.mode == .normal && info.rames == 17 && info.cabs == 2 && info.numbers == [3, 8, 12, 31]
                && command.id == "c7" && command.command == .message && command.value == .string("REPRENEZ LA MARCHE NORMALE")
                && now.event == .line && now.line == CabineWire.LineIdentity(id: "21", rev: "9f3c2a7d5e1b0c44", name: "Ligne 21")
                && peer.event == .peer && peer.rame == 31 && peer.state == .joined && closing.inS == 5
                && error.error == .lineTooLong
        }
        check("the fields of what the PCC sends are read as they were written", read)
        read = false
        if case let .line(sent)? = pcc("line, with a whole package") {
            let line = sent.package.description
            let source = sent.package.source
            read = sent.id == "l1" && sent.package.format == 1 && sent.package.identity == line.identity
                && line.lengthM == 7617.5 && line.rev == "9f3c2a7d5e1b0c44" && line.lineSpeedMS == 19.444
                && line.train?.approachDecelMS2 == 0.6 && line.train?.capacity == 560 && line.cbtc?.horizonM == 1500
                && line.cbtc?.uncertaintyPerM == 0.02 && line.dwell?.departS == 4.2 && line.endBufferM == 28
                && line.stations.map(\.name) == ["Porte du Levant", "Rue des Tanneurs"] && line.tracks.count == 2
                && line.tracks[0].track == 1 && line.tracks[0].stopsM == [279.5, 877.9]
                && line.tracks[0].zones == [.init(fromM: 355, toM: 521, limitMS: 15.28)] && line.tracks[0].beaconsM == [186, 326, 471]
                && line.tracks[1].track == 2 && line.tracks[1].stopsM == [6816.6, 7415]
                && source?["length"]?.number == 13224.5 && source?["stations"]?[0]?["at"]?.number == 150.89
                && source?["heading"]?[0]?.number == 41.87 && source?["name"]?.string == "Ligne 21"
        }
        check("a line message is read with its package: the description field by field, and the source as it came", read)

        // Optional fields are left out, never null.
        let tail = CabineWire.TrafficTrain(rame: 8, kind: .auto, track: 2, uM: 7589.5, speedMS: 0, doors: 0, phase: .tail, lengthM: 75)
        let sparse = String(decoding: CabineWire.Codec.encode(.traffic(.init(tS: 1, trains: [tail]))), as: UTF8.self)
        check("an optional field that is absent is left out, not written as null",
              !sparse.contains("null") && !sparse.contains("station") && !sparse.contains("name") && !sparse.contains("accelerationMS2"), sparse)

        let nowhere = String(decoding: CabineWire.Codec.encode(CabineWire.PCCMessage.event(.init(event: .line))), as: UTF8.self)
        var closed = false
        if case let .event(event)? = try? CabineWire.Codec.decodePCCMessage(Data(nowhere.utf8)) { closed = event.event == .line && event.line == nil }
        check("the event of a PCC that has closed its line names none", nowhere == #"{"type":"event","event":"line"}"# && closed, nowhere)
        let holdsNone = try? CabineWire.Codec.decodeCabMessage(Data(#"{"type":"hello","protocol":1,"app":"Cabine","cab":{"id":"A"}}"#.utf8))
        var lineless = false
        if case let .hello(hello)? = holdsNone {
            lineless = hello.line == nil && !String(decoding: CabineWire.Codec.encode(CabineWire.CabMessage.hello(hello)), as: UTF8.self).contains("line")
        }
        check("a hello that names no line is read, and written, with none", lineless)
        let byRev = try? CabineWire.Codec.decodeCabMessage(Data(#"{"type":"lineRequest","id":"l2","line":{"id":"4","rev":"c4f41e9d8fbc77b4"}}"#.utf8))
        check("a lineRequest that names a line by its id and its rev is read, the line going by its id for a name",
              byRev == .lineRequest(.init(id: "l2", line: .init(id: "4", rev: "c4f41e9d8fbc77b4", name: "4"))))

        // What a newer end might send.
        let extra = try? CabineWire.Codec.decodeCabMessage(Data(#"{"type":"join","id":"j9","track":2,"uM":300,"future":{"a":[1,2]},"station":0,"rame":null}"#.utf8))
        check("unknown fields, and null for an optional one, do not stop a message being read",
              extra == .join(.init(id: "j9", track: 2, uM: 300, station: 0)))
        let stranger = try? CabineWire.Codec.decodeCabMessage(Data(#"{"type":"teleport","id":"t1","to":"elsewhere"}"#.utf8))
        check("an unknown type is read as unknown, with its id", stranger == .unknown(type: "teleport", id: "t1"))
        let words = try? CabineWire.Codec.decodeCabMessage(Data(#"{"type":"status","mode":"XX","doors":{"phase":"ajar","open":0.5}}"#.utf8))
        var kept = false
        if case let .status(status)? = words { kept = status.mode?.rawValue == "XX" && status.doors?.phase?.rawValue == "ajar" }
        check("a word this version does not know is kept as it came", kept)
        let odd = try? CabineWire.Codec.decodePCCMessage(Data(#"{"type":"event","event":"confetti","amount":3}"#.utf8))
        var named = false
        if case let .event(event)? = odd { named = event.event.rawValue == "confetti" }
        check("an unknown event name is read", named)

        // The id comes back as it went: a string, a whole number, or a number with a fraction.
        let ids = [#""a-7""#, "41", "2.5"].map { id -> Bool in
            guard case let .ping(ping)? = try? CabineWire.Codec.decodeCabMessage(Data("{\"type\":\"ping\",\"id\":\(id)}".utf8)) else { return false }
            return String(decoding: CabineWire.Codec.encode(CabineWire.PCCMessage.pong(ping)), as: UTF8.self) == "{\"type\":\"pong\",\"id\":\(id)}"
        }
        check("an id is echoed as it came, string or number", ids == [true, true, true])

        // What cannot be read says why.
        check("what is not JSON, not an object or has no type is malformed",
              failure("ceci n'est pas du JSON")?.kind == .malformed && failure("[1,2,3]")?.kind == .malformed
                && failure(#"{"track":1}"#)?.kind == .malformed && failure(#"{"type":7}"#)?.kind == .malformed)
        let wrong = failure(#"{"type":"join","id":"j2","track":"one","uM":12}"#)
        let missing = failure(#"{"type":"join","id":3,"track":1}"#)
        check("a field of the wrong kind, or a missing one, is named with the message's id",
              wrong?.kind == .fields && wrong?.type == "join" && wrong?.id == "j2" && wrong?.reason == "track should be a whole number"
                && missing?.id == 3 && missing?.reason == "uM is missing",
              "\(wrong?.reason ?? "-"); \(missing?.reason ?? "-")")

        // Framing: a line feed ends a line, a carriage return before it and blank lines are dropped, a
        // line may come in pieces, and one over the limit is an error.
        var framer = CabineWire.Framer()
        var lines = framer.append(Data("{\"a\":1}\r\n\n\r\n{\"b\"".utf8))
        lines += framer.append(Data(":2}\n{\"c\":3}".utf8))
        lines += framer.append(Data("\n".utf8))
        check("lines are split at line feeds, without carriage returns or blank lines, across pieces",
              lines.map { String(decoding: $0, as: UTF8.self) } == ["{\"a\":1}", "{\"b\":2}", "{\"c\":3}"] && !framer.lineTooLong)
        var small = CabineWire.Framer(maxLineBytes: 16)
        let fits = small.append(Data("0123456789abcdef\r\n".utf8))
        let before = small.append(Data("ok\n0123456789abcdefg\nlost\n".utf8))
        check("a line at the limit passes, one over it is an error and nothing is read after it",
              fits.count == 1 && before.map { String(decoding: $0, as: UTF8.self) } == ["ok"] && small.lineTooLong
                && small.append(Data("more\n".utf8)).isEmpty && CabineWire.maxLineBytes == 1_048_576)

        // The same through the engine: nothing a connection sends stops it serving that connection.
        let engine = CabinePCC.Engine(seed: 3)
        let session = CabinePCC.SessionID(1)
        engine.open(session, peer: "selftest")
        func said(_ text: String) -> [CabinePCC.Outbound] {
            engine.receive(line: Data(text.utf8), from: session)
            return engine.takeOutbox()
        }
        func refusal(_ sent: [CabinePCC.Outbound]) -> CabineWire.ResultMessage? {
            if sent.count == 1, case let .result(result) = sent[0].message, !result.ok, !sent[0].thenClose { return result }
            return nil
        }
        var answers = said("ceci n'est pas du JSON") + said("[1,2,3]") + said(#"{"track":1}"#)
        check("a line that cannot be read is answered with error badMessage, and the connection is kept",
              answers.count == 3 && answers.allSatisfy { if case let .error(error) = $0.message { error.error == .badMessage && !$0.thenClose } else { false } })
        let unknown = refusal(said(#"{"type":"teleport","id":"t1","to":"elsewhere"}"#))
        check("an unknown type is answered with result unknownType and its id", unknown?.error == .unknownType && unknown?.id == "t1")
        let early = refusal(said(#"{"type":"join","id":"j0","track":1,"uM":300}"#))
        let tooSoon = refusal(said(#"{"type":"lineRequest","id":"l0"}"#))
        check("a request before hello is turned away with badMessage",
              early?.error == .badMessage && early?.id == "j0" && tooSoon?.error == .badMessage && tooSoon?.id == "l0")
        answers = said(#"{"type":"ping","id":"p1","tS":4.5}"#)
        check("a ping from a cab is answered with pong", answers.map(\.message) == [.pong(.init(id: "p1", tS: 4.5))])
        answers = said(#"{"type":"hello","protocol":1,"app":"Cabine","shiny":true,"cab":{"id":"A","name":"Essai","colour":"vert"},"line":{"id":"essai","rev":"r1","name":"Essai","gauge":1435}}"#)
        var answered = false
        if answers.count == 1, case let .hello(hello) = answers[0].message {
            answered = !hello.onLine && hello.line == nil && hello.protocol == 1 && hello.app == "CabinePCC"
        }
        check("a hello with unknown fields is answered: the PCC is on no line, and names none", answered)
        let offered = refusal(said(#"{"type":"line","id":"l5","line":{"id":"essai","rev":"r1","name":"Essai","lengthM":5000}}"#))
        check("a line that a cab offers is no message of the wire: the PCC takes no line from a cab",
              offered?.error == .unknownType && offered?.id == "l5" && engine.snapshot().line == nil && engine.snapshot().library.isEmpty)
        let noRev = refusal(said(#"{"type":"hello","protocol":1,"cab":{"id":"A"},"line":{"id":"essai"}}"#))
        let emptyRev = refusal(said(#"{"type":"hello","protocol":1,"cab":{"id":"A"},"line":{"id":"essai","rev":""}}"#))
        check("a hello whose line has no rev is answered with result badMessage",
              noRev?.error == .badMessage && noRev?.message?.contains("rev") == true && emptyRev?.error == .badMessage,
              "\(noRev?.message ?? "-"); \(emptyRev?.message ?? "-")")
        check("an unknown event from a cab is ignored", said(#"{"type":"event","event":"confetti","amount":3}"#).isEmpty)
        let field = refusal(said(#"{"type":"join","id":"j7","track":"one","uM":10}"#))
        check("a message with a field of the wrong kind is answered with result badMessage and its id",
              field?.error == .badMessage && field?.id == "j7" && field?.message?.contains("track") == true)
        try? engine.takeUp(CabineWire.LinePackage(description: CabinePCC.testLine))
        let told = engine.takeOutbox()
        answers = said(#"{"type":"lineRequest","id":"l9"}"#)
        var served = false
        if told.count == 1, case let .event(event) = told[0].message, answers.count == 1, case let .line(sent) = answers[0].message {
            served = event.event == .line && event.line == CabinePCC.testLine.identity && sent.id == "l9"
                && sent.package == CabineWire.LinePackage(description: CabinePCC.testLine)
        }
        check("after all that the connection still works: told of the PCC's line, it asks for it and is sent it", served)

        let other = CabinePCC.SessionID(2)
        engine.open(other, peer: "selftest")
        engine.receive(line: Data(#"{"type":"hello","protocol":2,"cab":{"id":"B"},"line":{"id":"essai","rev":"r1"}}"#.utf8), from: other)
        let version = engine.takeOutbox()
        var turnedAway = false
        if version.count == 1, case let .error(error) = version[0].message { turnedAway = error.error == .unsupportedProtocol && version[0].thenClose }
        check("a hello of another protocol version is answered with error unsupportedProtocol, and closed", turnedAway)
    }
}

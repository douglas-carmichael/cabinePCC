import Foundation
import CabinePCCKit

// 2, continued. A line of the library is a package: the description the PCC runs it on, and the source
// it keeps for the cabs without reading it. A package is read from a file and written back the same,
// and its source leaves the PCC as it came, to the last digit of every number.

extension SelfTest {

    /// A source of the test's own, for a line that comes without one: the kinds of thing a Cabine line
    /// file holds, and numbers that are awkward to write back.
    static let sampleSource = #"""
    {"format":1,"id":"essai","name":"Ligne d'essai","colour":"0A7D5A","textColour":"FFFFFF","service":"Amont – Aval",
     "source":{"track":"© les contributeurs d'OpenStreetMap, ODbL","stations":"Île-de-France Mobilités, Licence Ouverte",
               "ground":"IGN, \"RGE ALTI\"","date":"2026-11-10"},
     "length":13224.5,"stations":[{"name":"Amont","at":150.89},{"name":"Château d'Eau – Aval","at":4913.07}],
     "headingStep":10.0,
     "heading":[41.87,41.9,-0.0,1e-7,359.99999999999994,0.1,0.30000000000000004,123456789.12345679,5e-324,1.7976931348623157e308],
     "levelStep":25,"ground":[33.4,33.25,null],"rail":[-12.5,-12.75,2.5e1],"openAir":[[1200,1850.5],[]],
     "speedLimits":[{"from":0,"to":420.5,"kmh":40},{"from":420.5,"to":13224.5,"kmh":70}],
     "flags":{"closed":false,"loop":true},"note":"a/b \\ é€ 𠀀 \t fin"}
    """#

    /// The text of a package made of a description and, if there is one, a source.
    static func packageText(_ description: CabineWire.LineDescription, source: String?) -> String {
        let line = String(decoding: (try? JSONEncoder().encode(description)) ?? Data(), as: UTF8.self)
        return #"{"format":1,"description":\#(line)"# + (source.map { #","source":\#($0)"# } ?? "") + "}"
    }

    /// A file's document in the shape of a package, whichever of the three shapes the file has: a
    /// package, a whole `line` message, or a bare description.
    static func asPackage(_ file: Parsed) -> Parsed? {
        if let inner = file["package"] { return asPackage(inner) }
        guard case var .object(fields) = file else { return nil }
        guard fields["description"] != nil else { return .object(["format": .number(1), "description": file]) }
        if fields["format"] == nil { fields["format"] = .number(1) }
        if case .null? = fields["source"] { fields["source"] = nil }
        return .object(fields)
    }

    /// Why the bytes of a file cannot be read as a line package; nil if they can.
    private func packageFailure(_ text: String) -> CabineWire.DecodeFailure? {
        do {
            _ = try CabineWire.LinePackage.decode(file: Data(text.utf8))
            return nil
        } catch {
            return error as? CabineWire.DecodeFailure
        }
    }

    /// True when the package of a document is the package of another as far as the PCC answers for it:
    /// the source the same to the last bit, and nothing in the description that the other has not.
    private static func carries(_ copy: Parsed, _ original: Parsed) -> Bool {
        switch (original["source"], copy["source"]) {
        case (nil, nil): break
        case let (before?, after?): guard before.same(as: after) else { return false }
        default: return false
        }
        guard let described = copy["description"], let given = original["description"] else { return false }
        return described.isWithin(given)
    }

    func packages(_ lines: [Subject]) {
        typealias Package = CabineWire.LinePackage
        let line = CabinePCC.testLine
        let description = String(decoding: (try? JSONEncoder().encode(line)) ?? Data(), as: UTF8.self)
        let whole = SelfTest.packageText(line, source: SelfTest.sampleSource)
        func read(_ text: String) -> Package? { try? Package.decode(file: Data(text.utf8)) }

        // The three shapes of a file.
        let asPackage = read(whole)
        let asMessage = read(#"{"type":"line","id":"l1","package":\#(whole)}"#)
        let asBare = read(description)
        let unversioned = read(#"{"description":\#(description)}"#)
        check("a .line.json file is read whether it is a package, a whole line message or a bare description",
              asPackage != nil && asPackage?.description == line && asPackage?.format == 1 && asPackage?.identity == line.identity
                && asMessage == asPackage && asBare == Package(description: line) && asBare?.source == nil && unversioned == asBare)
        let expected = Parsed(SelfTest.sampleSource)
        var faithful = false
        if let expected, let source = asPackage?.source { faithful = expected.matches(source) }
        check("its source is read as it is written: every key, and every number to its last digit", faithful,
              "\(expected?.numberCount ?? 0) numbers, among them -0.0, 1e-7, 0.30000000000000004, the least and the greatest")
        let source = asPackage?.source
        let credits = source?["source"]
        check("a host reads what it wants of a source by key and by place",
              credits?["date"]?.string == "2026-11-10" && credits?["ground"]?.string == #"IGN, "RGE ALTI""#
                && source?["stations"]?[1]?["at"]?.number == 4913.07 && source?["flags"]?["loop"]?.bool == true
                && source?["ground"]?[2] == CabineWire.JSONValue.null && source?["openAir"]?[1]?.array?.isEmpty == true
                && source?["nothing"] == nil && source?["stations"]?[9] == nil && source?.object?.count == 18)

        // What cannot be read says why.
        let noTracks = #"{"id":"x","name":"X","rev":"1","lengthM":3000,"stations":[{"name":"A"},{"name":"B"}]}"#
        let bare = packageFailure(noTracks)
        let inside = packageFailure(#"{"format":1,"description":\#(noTracks)}"#)
        let wrongKind = packageFailure(#"{"format":"one","description":\#(description)}"#)
        let empty = packageFailure(#"{"format":1}"#)
        check("a file with a part missing or of the wrong kind is not read, and the failure names the part",
              bare?.kind == .fields && bare?.reason == "tracks is missing" && inside?.reason == "description.tracks is missing"
                && inside?.path == ["description", "tracks"] && wrongKind?.reason == "format should be a whole number"
                && empty?.reason == "id is missing",
              "\(bare?.reason ?? "-"); \(inside?.reason ?? "-"); \(wrongKind?.reason ?? "-"); \(empty?.reason ?? "-")")
        check("what is not JSON, or not an object, is not a line package",
              packageFailure("ceci n'est pas du JSON")?.kind == .malformed && packageFailure("[1,2,3]")?.kind == .malformed
                && packageFailure("")?.kind == .malformed)

        // Written to a file.
        let written = asPackage.flatMap { try? $0.encodedForFile() } ?? Data()
        let text = String(decoding: written, as: UTF8.self)
        let reread = try? Package.decode(file: written)
        let again = reread.flatMap { try? $0.encodedForFile() }
        var sameDocument = false
        if let one = Parsed(written), let other = Parsed(whole) { sameDocument = one.same(as: other) }
        check("a package is written to a file on one line ended by a line feed, its keys in order, and reads back the same",
              asPackage != nil && reread == asPackage && sameDocument && again == written && text.hasPrefix(#"{"description":{"#)
                && text.contains(#"},"format":1,"source":{"#) && text.hasSuffix("}\n") && !text.dropLast().contains("\n"),
              "\(written.count) bytes")
        let plain = String(decoding: (try? Package(description: line).encodedForFile()) ?? Data(), as: UTF8.self)
        check("a package with no source is written without one, and not as null",
              plain.contains(#""format":1"#) && !plain.contains("source") && !plain.contains("null"))

        // The lines that came from files.
        for subject in lines {
            if let file = subject.file { writtenBack(subject, file) }
        }

        // Kept in a library, each is listed; and a cab that asks for one is sent it as it was kept.
        // The built-in line goes in with the sample source, so that there is always a source to send.
        var subjects = lines.filter { (try? CabinePCC.Line($0.package.description)) != nil }
        for index in subjects.indices where subjects[index].file == nil {
            subjects[index].package.source = asPackage?.source
            subjects[index].file = Data(whole.utf8)
        }
        let engine = CabinePCC.Engine(seed: 8)
        var held: [Subject] = []
        var keptAll = true
        for subject in subjects {
            if refusal(of: { try engine.keep(subject.package) }) != nil { keptAll = false }
            // A line kept again under the same id and revision takes the place of the first.
            if let place = held.firstIndex(where: { $0.package.identity.isSameLine(as: subject.package.identity) }) {
                held[place] = subject
            } else {
                held.append(subject)
            }
        }
        let listed = engine.snapshot().library
        let wanted = held.map { subject -> CabinePCC.HeldLine in
            let described = subject.package.description
            return CabinePCC.HeldLine(identity: subject.package.identity, stationCount: described.stations.count, lengthM: described.lengthM,
                                      hasSource: subject.package.source != nil, firstStation: described.stations.first?.name ?? "",
                                      lastStation: described.stations.last?.name ?? "")
        }
        check("every line is kept in the library, and listed in the order kept with its stations, its length and whether it has a source",
              keptAll && listed == wanted && engine.snapshot().line == nil && held.allSatisfy { engine.heldPackage($0.package.identity) == $0.package },
              "\(listed.count) lines, \(listed.filter(\.hasSource).count) with a source")

        let session = CabinePCC.SessionID(1)
        engine.open(session, peer: "selftest")
        engine.receive(.hello(.init(app: "Cabine", cab: .init(id: "A", name: "Essai"))), from: session)
        _ = engine.takeOutbox()
        for (number, subject) in held.enumerated() {
            let identity = subject.package.identity
            engine.receive(line: CabineWire.Codec.encode(CabineWire.CabMessage.lineRequest(.init(id: .integer(number), line: identity))), from: session)
            let answers = engine.takeOutbox()
            var sent = false
            var size = 0
            if answers.count == 1, case let .line(body) = answers[0].message, !answers[0].thenClose {
                // As the kit holds it, and as it goes on the wire, read here without the kit.
                let onTheWire = CabineWire.Codec.encode(answers[0].message)
                size = onTheWire.count
                if let document = Parsed(onTheWire), let package = document["package"], let file = subject.file,
                   let original = Parsed(file).flatMap(SelfTest.asPackage) {
                    sent = body.id == .integer(number) && body.package == subject.package && SelfTest.carries(package, original)
                        && document["type"]?.same(as: Parsed.string("line")) == true
                        && document["id"]?.same(as: Parsed.number(Double(number))) == true
                        && !onTheWire.contains(0x0A)
                }
            }
            let what = subject.package.source == nil ? "its description, and no source" : "its description, and its source to the last digit"
            check("asked for by a cab, the \(subject.name) is sent as it is kept: \(what)", sent, "a line of \(size) bytes")
        }

        // A package that could not go down the wire as one line is not kept.
        let heavy = Package(description: line, source: .object(["padding": .string(String(repeating: "x", count: CabineWire.maxLineBytes))]))
        var tooLong = false
        if case let .badLine(reason)? = refusal(of: { try CabinePCC.Engine().keep(heavy) }) { tooLong = reason.contains("1 MiB") }
        check("a package too long to be sent as one line of the wire is not kept", tooLong)
    }

    /// A fixture's file, read and written back: the same package, the same source to the last bit, and
    /// nothing in the description that the file has not.
    private func writtenBack(_ subject: Subject, _ file: Data) {
        let package = subject.package
        guard let original = Parsed(file).flatMap(SelfTest.asPackage), let written = try? package.encodedForFile(),
              let copy = Parsed(written) else {
            check("the \(subject.name) is read from its file and written back the same", false, "it could not be read here, or written")
            return
        }
        let reread = try? CabineWire.LinePackage.decode(file: written)
        let again = reread.flatMap { try? $0.encodedForFile() }
        var how = "\(written.count) bytes for \(file.count), \(copy.numberCount) numbers"
        if written == file {
            how += ", byte for byte"
        } else if !copy.same(as: original) {
            how += ", the file has fields the PCC does not read"
        }
        check("the \(subject.name) is read from its file and written back the same",
              reread == package && again == written && SelfTest.carries(copy, original), how)
        if let source = original["source"] {
            check("the source of the \(subject.name) is read to the last digit of every number",
                  package.source.map { source.matches($0) } ?? false, "\(source.numberCount) numbers")
        }
    }
}

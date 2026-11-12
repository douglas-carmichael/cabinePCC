import Foundation
import CabinePCCKit

/// `--selftest`: the DCL's own SELFTEST, then a scenario that runs a PCC
/// for scripted cabs over loopback and checks, verb by verb, that the DCL
/// really reads and orders the engine, that the alarms are raised and
/// return to normal, and that every monitor and form draws.
///
/// It touches nothing of the user's: its settings are in memory, its files
/// in a scratch folder that it removes, and its ports are the system's
/// choice on loopback.
@MainActor
final class SelfTest {
    let options: HeadlessOptions
    private var passed = 0
    private var failures: [String] = []
    private var sectionName = ""

    /// The scratch folder of the run, and the node's store inside it.
    let scratch: URL
    var store: URL { scratch.appendingPathComponent("store", isDirectory: true) }

    /// The node under test, its terminal, and the cab it serves.
    var node: PCCNode!
    var terminal: HeadlessTerminal!
    var cab: ScriptedCab?
    /// The number of the cab's train, once it is in service.
    var cabRame = 0

    var link: PCCLink { node.link }
    var world: PCCWorld { node.world }
    var snapshot: CabinePCC.Snapshot? { link.snapshot }

    init(_ options: HeadlessOptions) {
        self.options = options
        scratch = Headless.scratchStore(under: options.store)
    }

    // MARK: -- the harness

    func section(_ title: String) {
        sectionName = title
        print("\n== " + title)
    }

    /// One check: its name, whether it holds, and what was seen when it
    /// does not.
    func check(_ what: String, _ holds: Bool, _ seen: @autoclosure () -> String = "") {
        if holds {
            passed += 1
            print("  ok    " + what)
        } else {
            let detail = seen()
            failures.append("[\(sectionName)] \(what)" + (detail.isEmpty ? "" : " -- " + detail))
            print("  FAIL  " + what + (detail.isEmpty ? "" : "\n          " + detail.replacingOccurrences(of: "\n", with: "\n          ")))
        }
    }

    /// Types a command at the terminal, and returns what it printed.
    func dcl(_ line: String) async -> String {
        let printed = await terminal.command(line)
        if options.verbose {
            print("        $ " + line)
            for row in printed.split(separator: "\n", omittingEmptySubsequences: false) { print("        " + row) }
        }
        return printed
    }

    /// A command and a check that what it printed has every one of `words`.
    @discardableResult
    func expect(_ line: String, has words: [String], lacks: [String] = [], _ what: String? = nil) async -> String {
        let printed = await dcl(line)
        let missing = words.filter { !printed.contains($0) }
        let unwanted = lacks.filter { printed.contains($0) }
        check(what ?? line, missing.isEmpty && unwanted.isEmpty,
              (missing.isEmpty ? "" : "missing \(missing) ") + (unwanted.isEmpty ? "" : "unwanted \(unwanted) ") + "in:\n" + printed)
        return printed
    }

    func wait(_ seconds: Double = 5, until condition: () -> Bool) async -> Bool {
        await Headless.wait(seconds, until: condition)
    }

    /// The standing alarm of a source and point, if there is one.
    func alarm(_ source: String, _ point: String) -> SCADAAlarm? {
        world.alarmLog.first { $0.isActive && $0.source == source && $0.point == point }
    }

    /// Whether the log holds an alarm of that source and point that has
    /// returned to normal or been cleared.
    func returned(_ source: String, _ point: String) -> Bool {
        alarm(source, point) == nil && world.alarmLog.contains { $0.source == source && $0.point == point && !$0.isActive }
    }

    /// The last status a command left: a warning or not.
    var refused: Bool { terminal.engine.lastStatusLabel == "PCC-W-REFUSED" }

    func setLanguage(_ language: Lang) async {
        node.language.current = language
        // The terminal logs in again in the new language.
        await Headless.sleep(0.05)
        await terminal.ready()
    }

    // MARK: -- the run

    func run() async -> Int32 {
        let userStore = PCCEnvironment.userStore
        let userStoreWas = FileManager.default.fileExists(atPath: userStore.path)
        print("cabinepcc-headless --selftest")
        print("scratch \(scratch.path)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        guard prepareStore() else { return 1 }
        let environment = Headless.isolated(store: store, lines: PCCEnvironment.programLines)
        node = PCCNode(environment: environment, language: AppLanguage(initial: .en))
        node.start()
        guard await wait(8, until: { Headless.port(of: self.link) != nil }) else {
            print("the PCC is not listening: \(link.listener)")
            return 1
        }
        terminal = HeadlessTerminal(node: node)
        await terminal.ready()

        await testShell()
        await testLaunch()
        await testOtherNodes()
        await testLineVerbs()
        await testTrainVerbs()
        await testCab()
        await testCabAlarms()
        await testScripts()
        await testFrench()
        await testMonitors()
        await testForms()
        await testLineChange()
        await testTelnet()

        section("Nothing of the user's is touched")
        check("the settings are in memory", environment.settings is MemorySettings)
        check("the store is the scratch folder", terminal.engine.scriptStore.rootPath.hasPrefix(scratch.path))
        check("the user's store was neither made nor removed",
              FileManager.default.fileExists(atPath: userStore.path) == userStoreWas)

        cab?.hangUp()
        node.stop()

        print("\n\(passed) checks passed, \(failures.count) failed")
        for failure in failures { print("  FAILED " + failure) }
        print(failures.isEmpty ? "SELFTEST PASSED" : "SELFTEST FAILED")
        return failures.isEmpty ? 0 : 1
    }

    /// The test line as a package with a source that names where its data
    /// came from, as a real line's does.
    static var testPackage: CabineWire.LinePackage {
        let credits: [String: CabineWire.JSONValue] = [
            "track": .string("Tracé d'essai, données inventées (aucune licence)"),
            "stations": .string("Stations d'essai, données inventées"),
            "ground": .string("Niveau d'essai"),
            "date": .string("2026-11-11"),
        ]
        let source: [String: CabineWire.JSONValue] = [
            "format": .number(1), "id": .string("essai"), "name": .string("Ligne d'essai"),
            "length": .number(4_600), "heading": .array([.number(0), .number(0.5), .number(1.25)]),
            "source": .object(credits),
        ]
        return CabineWire.LinePackage(description: CabinePCC.testLine, source: .object(source))
    }

    /// The operator's own lines of the run: a good package, and three
    /// files that are not.
    private func prepareStore() -> Bool {
        let lines = store.appendingPathComponent("Lines", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: lines, withIntermediateDirectories: true)
            try Self.testPackage.encodedForFile().write(to: lines.appendingPathComponent("essai.line.json"))
            try Data("ceci n'est pas du JSON".utf8).write(to: lines.appendingPathComponent("pas-du-json.line.json"))
            try Data(#"{"format":1,"description":{"id":"x","name":"X"}}"#.utf8)
                .write(to: lines.appendingPathComponent("champ-manquant.line.json"))
            var short = CabinePCC.testLine
            short.id = "courte"
            short.stations = [short.stations[0]]
            try CabineWire.LinePackage(description: short).encodedForFile()
                .write(to: lines.appendingPathComponent("une-station.line.json"))
            return true
        } catch {
            print("the scratch store could not be written: \(error)")
            return false
        }
    }

    // MARK: -- the shell

    /// The DCL's own SELFTEST, in both languages, and the rule that every
    /// verb it drives has its HELP topic.
    private func testShell() async {
        section("DCL SELFTEST")
        for language in [Lang.en, Lang.fr] {
            await setLanguage(language)
            let report = await dcl("SELFTEST")
            let figure = report.split(separator: "\n").last { $0.contains("verbs returned cleanly") }.map(String.init) ?? ""
            let numbers = figure.split { !$0.isNumber }.compactMap { Int($0) }
            let bad = report.split(separator: "\n").filter { $0.contains("UNKNOWN") || $0.contains("BAD-FMT") }
            check("SELFTEST in \(language.displayName): \(figure.trimmingCharacters(in: .whitespaces))",
                  numbers.count == 2 && numbers[0] == numbers[1] && numbers[1] > 150 && bad.isEmpty,
                  bad.joined(separator: "\n"))
            check("SELFTEST leaves the session as it found it", terminal.engine.prompt == "$ " && !terminal.engine.dryRun)
        }
        await setLanguage(.en)

        // Every verb SELFTEST drives is in the HELP library. The short
        // forms are documented together, under HELP PCC Vocabulary.
        let shortForms: Set<String> = ["TRAIN", "FLEET", "LINE", "STATIONS", "CABS"]
        var topics: Set<String> = []
        for line in terminal.engine.selfTestLines {
            let words = line.split(separator: " ").map(String.init)
            guard let first = words.first else { continue }
            let verb = String(first.split(separator: "/")[0])
            if verb.hasPrefix("@") || verb == "HELP" || shortForms.contains(verb) { continue }
            topics.insert(verb)
            // The subjects of SHOW, SET, MONITOR and RUN have topics of their own.
            if ["SHOW", "SET", "MONITOR", "RUN"].contains(verb), words.count > 1, !words[1].hasPrefix("/") {
                var subject = String(words[1].split(separator: "/")[0].split(separator: "=")[0])
                if verb == "RUN", subject.contains(".") { continue }
                // SET NOON is under SET ON, as HELP has it.
                if verb == "SET", subject == "NOON" { subject = "ON" }
                topics.insert(verb + " " + subject)
            }
        }
        terminal.engine.dryRun = true
        var undocumented: [String] = []
        for topic in topics.sorted() {
            let text = await terminal.engine.execute("HELP " + topic)
            if text.contains("Sorry, no documentation") { undocumented.append(topic) }
        }
        terminal.engine.dryRun = false
        check("every verb and subject SELFTEST drives has its HELP topic (\(topics.count))", undocumented.isEmpty,
              "no topic for: " + undocumented.joined(separator: ", "))
    }

    // MARK: -- launch

    /// What the node did when it started: the library, the files it
    /// refused, the line it took up.
    private func testLaunch() async {
        section("Launch: the library, and the line last run")
        check("the Lines folder is beside the tool", PCCEnvironment.programLines != nil)
        let library = snapshot?.library ?? []
        let ids = library.map(\.identity.id)
        check("the six lines the program was built with are kept",
              ["1", "4", "6", "11", "14", "21"].allSatisfy(ids.contains), "library: \(ids)")
        check("the operator's own line is kept after them", ids.last == "essai", "library: \(ids)")
        check("a real line's package has its source, Ligne 21's has none",
              library.first { $0.identity.id == "4" }?.hasSource == true
                  && library.first { $0.identity.id == "21" }?.hasSource == false)
        let refusals = link.journal.compactMap { line -> String? in
            if case let .lineFileRefused(file, _) = line.event { return file }
            return nil
        }
        check("the three bad files are in the journal, and skipped",
              Set(refusals) == ["pas-du-json.line.json", "champ-manquant.line.json", "une-station.line.json"],
              "refused: \(refusals)")
        check("a refused line file raises PCC FICHIER", alarm("PCC", "FICHIER") != nil)
        check("the first launch takes up Ligne 21", snapshot?.line?.identity.id == "21")
        check("the line runs: automatic trains are on it, service is on",
              (snapshot?.rames.count ?? 0) >= 2 && snapshot?.inService == true && snapshot?.mode == .normal)
        check("the PCC listens on loopback, on a port of its own",
              Headless.port(of: link) != nil && Headless.port(of: link) != 5289 && !link.isLAN)

        let port = Headless.port(of: link) ?? 0
        await expect("SHOW PCC", has: ["LISTENING ON PORT \(port)", "THIS MAC ONLY", "localhost port \(port)", "Ligne 21",
                                       "7 lines"])
        await expect("SHOW JOURNAL", has: ["une-station.line.json", "pas-du-json.line.json", "Line taken up: Ligne 21"])
        await expect("SHOW JOURNAL /LAST=1", has: ["lines shown: 1 of"])
        await expect("SHOW ALARMS", has: ["PCC", "FICHIER", "A line file was refused"])

        // An event stands until it is acknowledged and cleared.
        let sequence = alarm("PCC", "FICHIER")?.sequence ?? 0
        await expect("ACKNOWLEDGE ALARM \(sequence) /CLEAR", has: ["acknowledged", "cleared"])
        check("PCC FICHIER is cleared by the operator", returned("PCC", "FICHIER"))
    }

    /// Two more nodes, for the alarms a healthy one never raises: a
    /// listener that fails, and a line last run that the library has lost.
    private func testOtherNodes() async {
        section("Alarms of a PCC that cannot start as it was left")
        // A second PCC on the first one's port, told not to take another.
        var taken = Headless.isolated(store: scratch.appendingPathComponent("second", isDirectory: true), lines: nil)
        taken.pccPort = Headless.port(of: link) ?? 0
        taken.pccFallsBackToAnyPort = false
        let second = PCCNode(environment: taken, language: AppLanguage(initial: .en))
        second.start()
        let failed = await wait(6) {
            if case .failed = second.link.listener { return true }
            return false
        }
        check("a PCC whose port is taken fails to listen", failed, "listener: \(second.link.listener)")
        check("a failed listener raises PCC ECOUTE", second.world.alarmLog.contains { $0.isActive && $0.point == "ECOUTE" })
        let shell = HeadlessTerminal(node: second)
        await shell.ready()
        let shown = await shell.command("SHOW PCC")
        check("SHOW PCC says the listener failed", shown.contains("FAILED"), shown)
        _ = await shell.command("SET PCC /DISABLE")
        check("PCC ECOUTE returns to normal when the PCC is closed",
              !second.world.alarmLog.contains { $0.isActive && $0.point == "ECOUTE" }
                  && second.world.alarmLog.contains { $0.point == "ECOUTE" })
        second.stop()

        // A third whose settings name a line the library does not hold.
        let third = PCCNode(environment: Headless.isolated(store: scratch.appendingPathComponent("third", isDirectory: true),
                                                           lines: PCCEnvironment.programLines, line: "99"),
                            language: AppLanguage(initial: .en))
        third.start()
        _ = await wait(6) { Headless.port(of: third.link) != nil }
        check("a line last run that is not held leaves the PCC on no line", third.link.snapshot?.line == nil)
        check("and raises PCC LIGNE", third.world.alarmLog.contains { $0.isActive && $0.source == "PCC" && $0.point == "LIGNE" })
        check("and is in the journal", third.link.journal.contains { $0.event == .lineNotHeld(id: "99") })
        let other = HeadlessTerminal(node: third)
        await other.ready()
        let loaded = await other.command("SET LINE /LOAD=4")
        check("SET LINE /LOAD puts that PCC on a real line", third.link.snapshot?.line?.identity.id == "4", loaded)
        _ = await other.command("ACKNOWLEDGE ALARM ALL /CLEAR")
        check("PCC LIGNE is cleared by the operator", !third.world.alarmLog.contains { $0.isActive })
        third.stop()
    }

    // MARK: -- the line

    /// SHOW LINES, SHOW LINE and SET LINE, with no cab in service.
    private func testLineVerbs() async {
        section("The line: SHOW LINES, SHOW LINE, SET LINE, START, STOP, EMERGENCY, RESUME")
        let lines = await expect("SHOW LINES", has: ["7 held", "Ligne 21", "Ligne d'essai", "Aéroport d'Orly"])
        check("SHOW LINES marks the line the PCC is on",
              lines.split(separator: "\n").contains { $0.contains(" * 21 ") }, lines)

        await expect("SET LINE /LOAD=essai", has: ["%PCC-S-LOAD", "Ligne d'essai"])
        check("SET LINE /LOAD puts the PCC on the line", snapshot?.line?.identity.id == "essai")
        await expect("SHOW LINE", has: ["Ligne d'essai (essai, rev \(CabinePCC.testLine.rev))", "5000.0 m", "6 stations",
                                      "Porte des Essais -- Porte du Banc", "NORMAL", "08:42:"])
        await expect("SHOW LINE /STATIONS", has: ["Porte des Essais", "Cours du Repère", "279.5 m", "4797.5 m"])
        await expect("SHOW LINE /SOURCE", has: ["Tracé d'essai, données inventées", "Stations d'essai", "2026-11-11",
                                              "carries the line's source"])
        await expect("SET LINE /LOAD=4", has: ["%PCC-S-LOAD", "Ligne 4"])
        await expect("SHOW LINE /SOURCE", has: ["Île-de-France Mobilités", "© OpenStreetMap contributors (ODbL)",
                                              "IGN RGE ALTI (Licence Ouverte 2.0)"], "SHOW LINE /SOURCE gives a real line's credits")
        await expect("SET LINE /LOAD=21", has: ["%PCC-S-LOAD"])
        await expect("SHOW LINE /SOURCE", has: ["built into every Cabine"], "SHOW LINE /SOURCE says Ligne 21 is invented")

        await expect("SET LINE /LOAD=99", has: ["%PCC-W-REFUSED", "99"], "SET LINE /LOAD refuses a line it does not hold")
        check("and leaves a warning in $STATUS", refused && snapshot?.line?.identity.id == "21")

        await expect("SET LINE /CLOSE", has: ["%PCC-S-CLOSE"])
        check("SET LINE /CLOSE puts the PCC on no line", snapshot?.line == nil && snapshot?.rames.isEmpty == true)
        await expect("SHOW LINE", has: ["no line"], "SHOW LINE says the PCC is on no line")
        await expect("SET LINE /SERVICE=ON", has: ["%PCC-W-REFUSED"], "an order for the line is refused on no line")
        await expect("SHOW JOURNAL /LAST=3", has: ["on no line"])
        // A line the operator adds while the PCC runs is kept by /REREAD.
        var added = CabinePCC.testLine
        added.id = "bis"
        added.name = "Ligne bis"
        try? CabineWire.LinePackage(description: added).encodedForFile()
            .write(to: store.appendingPathComponent("Lines/bis.line.json"))
        await expect("SET LINE /REREAD", has: ["%PCC-S-REREAD", "8"])
        check("SET LINE /REREAD keeps a line added to the Lines folder", snapshot?.library.contains { $0.identity.id == "bis" } == true)
        await expect("SET LINE /LOAD=essai", has: ["%PCC-S-LOAD"])
        check("the PCC is on the test line again, in service", snapshot?.line?.identity.id == "essai" && snapshot?.inService == true)

        await expect("SET LINE /HEADWAY=90", has: ["%PCC-S-HEADWAY", "90"])
        check("SET LINE /HEADWAY reaches the engine", snapshot?.headwayS == 90 && link.headwayS == 90)
        await expect("SET LINE /HEADWAY=5", has: ["%PCC-W-REFUSED", "30", "3600"], "a headway out of range is refused")
        await expect("SET LINE /RAMES=6", has: ["%PCC-S-FLEET", "6"])
        check("SET LINE /RAMES fixes the fleet", snapshot?.fleetSize == 6)
        await expect("SET LINE /RAMES=AUTO", has: ["%PCC-S-FLEET"])
        check("SET LINE /RAMES=AUTO sizes it from the headway again", snapshot?.fleetSize == nil)
        await expect("SET LINE /RAMES=99", has: ["%PCC-W-REFUSED"], "a fleet out of range is refused")
        await expect("SET LINE /SERVICE=PEUT-ETRE", has: ["ON", "OFF"], "a value that is neither ON nor OFF is refused")
        await expect("SET LINE", has: ["%PCC-W-MISSQUAL"])

        await expect("STOP LINE", has: ["%PCC-S-SERVICE"])
        check("STOP LINE stops line service", snapshot?.inService == false && snapshot?.mode == .stopped)
        await expect("SHOW LINE", has: ["SERVICE STOPPED"])
        await expect("START LINE", has: ["%PCC-S-SERVICE"])
        check("START LINE starts it", snapshot?.inService == true && snapshot?.mode == .normal)
        await expect("SET LINE /SERVICE=OFF", has: ["%PCC-S-SERVICE"])
        check("SET LINE /SERVICE=OFF stops it", snapshot?.inService == false)
        await expect("SET LINE /SERVICE=ON", has: ["%PCC-S-SERVICE"])

        await expect("EMERGENCY", has: ["%PCC-S-EMERGENCY"])
        check("EMERGENCY orders the general emergency stop", snapshot?.emergencyStop == true && snapshot?.mode == .emergency)
        check("and raises LIGNE AU, critical", alarm("LIGNE", "AU")?.severity == .critical)
        await expect("SHOW STATUS", has: ["EMERGENCY STOP"])
        await expect("RESUME", has: ["%PCC-S-EMERGENCY"])
        check("RESUME releases it", snapshot?.emergencyStop == false && snapshot?.mode == .normal)
        check("and LIGNE AU returns to normal", returned("LIGNE", "AU"))
        await expect("SET LINE /EMERGENCY=ON", has: ["%PCC-S-EMERGENCY"])
        check("SET LINE /EMERGENCY=ON does the same", snapshot?.emergencyStop == true)
        await expect("SET LINE /EMERGENCY=OFF", has: ["%PCC-S-EMERGENCY"])
        check("and /EMERGENCY=OFF releases it", snapshot?.emergencyStop == false)
        let mailed = terminal.engine.mailbox.contains { $0.subject.contains("GENERAL EMERGENCY STOP") }
        check("OPCOM mailed the general emergency stop", mailed, terminal.engine.mailbox.map(\.subject).joined(separator: " | "))
    }

    // MARK: -- the trains

    /// SHOW RAMES, SHOW RAME and SET RAME, on automatic trains.
    private func testTrainVerbs() async {
        section("The trains: SHOW RAMES, SHOW RAME, SET RAME, START RAME, STOP RAME")
        _ = await wait(3) { (self.snapshot?.rames.count ?? 0) >= 2 }
        guard let rame = snapshot?.rames.sorted(by: { $0.number < $1.number }).first(where: { $0.phase != .tail }) else {
            check("the line has a train to give orders to", false)
            return
        }
        let n = rame.number, label = PCCText.number(n)
        let fleet = await expect("SHOW RAMES", has: ["Trains of Ligne d'essai", "AUTO"])
        check("SHOW RAMES lists every train", (snapshot?.rames ?? []).allSatisfy { fleet.contains("    " + PCCText.number($0.number) + "  ") }, fleet)
        await expect("SHOW RAME \(n)", has: ["Train \(label) of Ligne d'essai", "AUTO", "m/s"])
        await expect("SHOW RAME 98", has: ["%PCC-W-NOSUCHRAME"], "SHOW RAME refuses a number that is not on the line")
        await expect("TRAIN \(n)", has: ["Train \(label)"], "the short form TRAIN")
        await expect("FLEET", has: ["Trains of"], "the short form FLEET")
        await expect("LINE", has: ["Ligne d'essai"], "the short form LINE")
        await expect("STATIONS", has: ["Place des Jalons"], "the short form STATIONS")
        await expect("RAME \(n)", has: ["%DCL-W-IVVERB"], "the French short form is refused in English mode")

        await expect("SET RAME \(n) /HOLD", has: ["%PCC-S-HOLD", label])
        check("SET RAME /HOLD holds the train", snapshot?.rame(numbered: n)?.held == true)
        await expect("SHOW RAME \(n)", has: ["HELD BY THE PCC"])
        await expect("SET RAME \(n) /RELEASE", has: ["%PCC-S-RELEASE"])
        check("SET RAME /RELEASE releases it", snapshot?.rame(numbered: n)?.held == false)

        await expect("SET RAME \(n) /BRAKE", has: ["%PCC-S-BRAKE"])
        check("SET RAME /BRAKE brakes the train", snapshot?.rame(numbered: n)?.braked == true)
        check("and raises RAME \(label) FU", alarm("RAME \(label)", "FU") != nil)
        await expect("SET RAME \(n) /UNBRAKE", has: ["%PCC-S-UNBRAKE"])
        check("SET RAME /UNBRAKE releases it", snapshot?.rame(numbered: n)?.braked == false)
        check("and RAME \(label) FU returns to normal", returned("RAME \(label)", "FU"))
        await expect("STOP RAME \(n)", has: ["%PCC-S-BRAKE"])
        check("STOP RAME brakes the train", snapshot?.rame(numbered: n)?.braked == true)
        await expect("START RAME \(n)", has: ["%PCC-S-UNBRAKE"])
        check("START RAME releases it", snapshot?.rame(numbered: n)?.braked == false)

        await expect("SET RAME \(n) /MESSAGE=\"BONJOUR\"", has: ["%PCC-W-REFUSED", "not a cab"], "a message to an automatic train is refused")
        await expect("SET RAME \(n) /CALL", has: ["%PCC-W-REFUSED"], "a call to an automatic train is refused")
        await expect("SET RAME 98 /HOLD", has: ["%PCC-W-REFUSED", "98"], "an order for a train that is not on the line is refused")
        await expect("SET RAME /HOLD", has: ["%PCC-W-NORAME"])
        await expect("SET RAME \(n)", has: ["%PCC-W-MISSQUAL"])
        await expect("SET RAME \(n) /RETENIR", has: ["%PCC-W-MISSQUAL"], "the French qualifier is refused in English mode")
    }
}

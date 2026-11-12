import Foundation
import CabinePCCKit

// The self-test's scenario with a scripted cab: the line handed to a cab
// that asks for it, the orders that reach it, the alarms it raises, the
// command procedures that read the engine, the French vocabulary, and a
// change of line.
extension SelfTest {

    // MARK: -- a cab

    /// A cab that holds no line asks for the PCC's, is sent the package,
    /// comes on the line and enters service; then the verbs that show it
    /// and the orders that reach it.
    func testCab() async {
        section("A cab: the line handed to it, SHOW CABS, SHOW CONNECTIONS, the orders")
        guard let port = Headless.port(of: link), let line = snapshot?.line, let cab = ScriptedCab(port: port, name: "Alma") else {
            check("a cab can dial the PCC", false)
            return
        }
        self.cab = cab
        cab.hello()
        let connected = await wait { self.snapshot?.sessions.contains { $0.name == "Alma" && $0.standing == .connected } == true }
        check("a cab that holds no line is connected, and not on the line", connected,
              "sessions: \(snapshot?.sessions.map { "\($0.name ?? "?") \($0.standing)" } ?? [])")
        _ = await wait { !cab.received("hello").isEmpty }
        let greeted = cab.received("hello").last
        check("the PCC's hello names its line, and says the cab is not on it",
              (greeted?["line"] as? [String: Any])?["id"] as? String == "essai" && greeted?["onLine"] as? Bool == false
                  && greeted?["app"] as? String == "CabinePCC", "\(greeted ?? [:])")

        cab.requestLine()
        _ = await wait { !cab.received("line").isEmpty }
        let package = cab.received("line").last?["package"] as? [String: Any]
        let description = package?["description"] as? [String: Any]
        let source = package?["source"] as? [String: Any]
        check("the cab that asks for the line is sent its package",
              description?["id"] as? String == "essai" && description?["rev"] as? String == CabinePCC.testLine.rev,
              "\(cab.received("line").count) line message(s), \(cab.received("result"))")
        await expect("SHOW JOURNAL /LAST=4", has: ["Ligne d'essai (essai, rev \(CabinePCC.testLine.rev)) handed to cab Alma"],
                     "the journal says the line was handed to the cab")
        check("the package's source comes as it was kept",
              (source?["source"] as? [String: Any])?["track"] as? String == "Tracé d'essai, données inventées (aucune licence)"
                  && (source?["heading"] as? [Double]) == [0, 0.5, 1.25] && source?["length"] as? Double == 4_600,
              "\(source ?? [:])")

        cab.hello(line: (line.identity.id, line.identity.rev, line.identity.name))
        let onLine = await wait { self.snapshot?.sessions.contains { $0.name == "Alma" && $0.standing == .onLine } == true }
        check("the cab that names the PCC's line is on the line", onLine)

        let stops = line.track(1).stopsM
        cab.join(track: 1, uM: stops[2], station: 2, atPlatform: true, rame: 21)
        let joined = await wait { self.snapshot?.cabs.count == 1 }
        cabRame = snapshot?.cabs.first?.number ?? 0
        check("the cab enters service as train 21", joined && cabRame == 21,
              "cabs: \(snapshot?.cabs.map(\.number) ?? []), results: \(cab.received("result"))")
        let label = PCCText.number(cabRame)
        _ = await wait { self.snapshot?.cabs.first?.cab?.status != nil && self.snapshot?.cabs.first?.cab?.authority != nil }

        await expect("SHOW CABS", has: ["Cabs in service on Ligne d'essai: 1", "Alma", "LIVE", "PA", "ENGAGED", "ends"])
        await expect("CABS", has: ["Alma"], "the short form CABS")
        await expect("SHOW CONNECTIONS", has: ["IN SERVICE", "Alma", "Cabine 1.0", "127.0.0.1", "Ligne d'essai"])
        await expect("SHOW RAME \(cabRame)", has: ["Train \(label)", "CAB", "Alma", "LIVE", "PA", "ENGAGED", "212/560",
                                                 "4 s EARLY", "RELEASED", "ends"])
        await expect("SHOW RAMES", has: ["CAB"])
        await expect("SHOW JOURNAL /LAST=6", has: ["Cab Alma connected, holding no line", "Cab Alma is on the line",
                                                  "Cab Alma in service as train \(label)"])
        await expect("SHOW PCC", has: ["1 --", "in service: 1"])
        await expect("SHOW SYSTEM", has: ["PCC_ENGINE", "PCC_LISTENER", "CAB_\(label)_LINK"], "SHOW SYSTEM has the PCC's processes")

        // The line cannot change under a cab.
        await expect("SET LINE /LOAD=21", has: ["%PCC-W-REFUSED", "cab is in service"], "a change of line is refused while a cab is in service")
        await expect("SET LINE /CLOSE", has: ["%PCC-W-REFUSED", "cab is in service"], "and so is closing the line")
        check("the PCC stays on its line", snapshot?.line?.identity.id == "essai" && snapshot?.cabs.count == 1)

        // The orders reach the cab.
        await expect("SET RAME \(cabRame) /HOLD /MESSAGE=\"ATTENDEZ LE SIGNAL\"", has: ["%PCC-S-HOLD", "%PCC-S-MESSAGE"])
        let held = await wait { cab.commands("hold").last?["value"] as? Bool == true && !cab.commands("message").isEmpty }
        check("the cab is ordered to hold, and has the message",
              held && cab.commands("message").last?["value"] as? String == "ATTENDEZ LE SIGNAL", "\(cab.received("command"))")
        check("the engine has the train held", snapshot?.rame(numbered: cabRame)?.held == true)
        await expect("SET RAME \(cabRame) /RELEASE", has: ["%PCC-S-RELEASE"])
        let released = await wait { cab.commands("hold").last?["value"] as? Bool == false }
        check("the cab is released", released && snapshot?.rame(numbered: cabRame)?.held == false)

        await expect("SET RAME \(cabRame) /CALL", has: ["%PCC-S-CALL"])
        check("the cab's driver is rung", await wait { !cab.commands("call").isEmpty })

        await expect("SET RAME \(cabRame) /BRAKE", has: ["%PCC-S-BRAKE"])
        let braked = await wait { cab.commands("emergencyBrake").last?["value"] as? Bool == true
            && self.snapshot?.rame(numbered: self.cabRame)?.cab?.emergencyBrake == true }
        check("the cab is ordered to brake, and reports its brake applied", braked)
        check("which raises CABINE \(label) FU", await wait { self.alarm("CABINE \(label)", "FU") != nil })
        await expect("SHOW RAME \(cabRame)", has: ["APPLIED", "ARRET COMMANDE PAR LE PCC", "EB ORDERED BY THE PCC"])
        await expect("SET RAME \(cabRame) /UNBRAKE", has: ["%PCC-S-UNBRAKE"])
        let unbraked = await wait { self.snapshot?.rame(numbered: self.cabRame)?.cab?.emergencyBrake == false }
        check("the brake is released", unbraked)
        check("and CABINE \(label) FU returns to normal", await wait { self.returned("CABINE \(label)", "FU") })

        await expect("SET RAME \(cabRame) /MESSAGE=\"\(String(repeating: "X", count: 121))\"", has: ["%PCC-W-REFUSED", "120", "121"],
                     "a message longer than the wire allows is refused, not cut")
        await expect("SET RAME \(cabRame) /MESSAGE=\"\"", has: ["%PCC-W-REFUSED"], "a message with no words is refused")

        // A cab that refuses an order is in the journal.
        cab.refuse(["hold"])
        _ = await dcl("SET RAME \(cabRame) /HOLD")
        _ = await wait { self.link.journal.contains { PCCText.journal($0.event) { self.node.language.t($0) }.contains("refused the order") } }
        await expect("SHOW JOURNAL /LAST=4", has: ["Cab Alma (train \(label)) refused the order HOLD"])
        cab.refuse([])
        _ = await dcl("SET RAME \(cabRame) /RELEASE")
    }

    // MARK: -- the cab's alarms

    /// What a cab raises: its driver's reports and calls, its own
    /// emergency brake, its silence, and another revision of the line.
    func testCabAlarms() async {
        section("The cab's alarms, raised and returned to normal")
        guard let cab, cabRame > 0 else {
            check("a cab is in service", false)
            return
        }
        let label = PCCText.number(cabRame), source = "CABINE \(label)"

        cab.report(code: "passengerIll", text: "MALAISE VOYAGEUR VOITURE 3")
        check("a driver's report raises \(source) RADIO, major", await wait { self.alarm(source, "RADIO")?.severity == .major })
        await expect("SHOW ALARMS", has: [source, "RADIO", "Driver report: passenger taken ill"])
        await expect("SHOW RAME \(cabRame)", has: ["PASSENGER ILL", "MALAISE VOYAGEUR VOITURE 3"])
        await expect("ACKNOWLEDGE ALARM \(alarm(source, "RADIO")?.sequence ?? 0)", has: ["acknowledged"])
        check("ACKNOWLEDGE leaves the event standing, acknowledged", alarm(source, "RADIO")?.isAcknowledged == true)
        await expect("ACKNOWLEDGE ALARM \(alarm(source, "RADIO")?.sequence ?? 0) /CLEAR", has: ["cleared"])
        check("/CLEAR clears it", returned(source, "RADIO"))

        cab.call()
        check("a driver's call raises \(source) APPEL", await wait { self.alarm(source, "APPEL") != nil })
        let call = alarm(source, "APPEL")?.sequence ?? 0
        await expect("SHELVE ALARM \(call)", has: ["shelved"])
        check("SHELVE takes it off the annunciator", world.activeAlarms.contains { $0.sequence == call } == false
            && world.shelvedAlarms.contains { $0.sequence == call })
        await expect("UNSHELVE ALARM \(call)", has: ["restored"])
        check("UNSHELVE puts it back", world.activeAlarms.contains { $0.sequence == call })
        await expect("ACKNOWLEDGE ALARM ALL /CLEAR", has: ["acknowledged", "cleared"])
        check("ACKNOWLEDGE ALARM ALL /CLEAR clears the events", returned(source, "APPEL"))

        cab.emergencyBrake("FREINAGE D'URGENCE CONDUCTEUR")
        check("the driver's own emergency brake raises \(source) FU", await wait { self.alarm(source, "FU") != nil })
        let brake = alarm(source, "FU")?.sequence ?? 0
        await expect("ACKNOWLEDGE ALARM \(brake) /CLEAR", has: ["acknowledged", "held by its condition"],
                     "a process-driven alarm is not the operator's to clear")
        check("it still stands", alarm(source, "FU") != nil)
        await expect("SHOW CABS", has: ["FREINAGE D'URGENCE CONDUCTEUR"])
        cab.emergencyBrake(nil)
        check("and returns to normal when the brake is released", await wait { self.returned(source, "FU") })

        // Silence: nothing sent, and no ping answered, for longer than the
        // link's timeout.
        cab.goSilent(true)
        check("a cab that falls silent raises \(source) LIAISON", await wait(8) { self.alarm(source, "LIAISON") != nil })
        await expect("SHOW RAME \(cabRame)", has: ["SILENT"])
        await expect("SHOW JOURNAL /LAST=2", has: ["is silent"])
        cab.goSilent(false)
        check("and LIAISON returns to normal when it is heard again", await wait(8) { self.returned(source, "LIAISON") })

        // A cab of another version of Cabine: the same line, another revision.
        if let port = Headless.port(of: link), let other = ScriptedCab(port: port, name: "Basile") {
            other.hello(line: ("essai", "0000000000000000", "Ligne d'essai"))
            let raised = await wait { self.world.alarmLog.contains { $0.isActive && $0.point == "REVISION" } }
            check("a cab that holds another revision of the line raises CABINE #n REVISION", raised)
            await expect("SHOW CONNECTIONS", has: ["Basile", "NOT ON THE PCC'S LINE", "0000000000000000"])
            other.hangUp()
            let cleared = await wait { !self.world.alarmLog.contains { $0.isActive && $0.point == "REVISION" } }
            check("and REVISION returns to normal when it has gone", cleared)
        } else {
            check("a second cab can dial the PCC", false)
        }
        await expect("SHOW ALARMS/ALL", has: ["RTN", "CLEARED", "LIAISON", "REVISION"], "SHOW ALARMS/ALL has the history")
        check("no alarm is left standing", world.activeAlarms.isEmpty,
              world.activeAlarms.map { "\($0.source) \($0.point)" }.joined(separator: ", "))
    }

    // MARK: -- command procedures

    /// The lexical functions and built-in symbols that read the engine,
    /// and the seeded procedure that waits for a cab and holds it.
    func testScripts() async {
        section("Command procedures: F$PCC, F$RAME, the built-in symbols, @WAITCAB")
        guard let cab, cabRame > 0 else {
            check("a cab is in service", false)
            return
        }
        await expect("WRITE SYS$OUTPUT F$PCC(\"LINE\")", has: ["essai"])
        await expect("WRITE SYS$OUTPUT F$PCC(\"MODE\")", has: ["NORMAL"])
        await expect("WRITE SYS$OUTPUT F$PCC(\"CABS\")", has: ["1"])
        await expect("WRITE SYS$OUTPUT F$PCC(\"FIRST_CAB\")", has: ["\(cabRame)"])
        await expect("WRITE SYS$OUTPUT F$PCC(\"LISTENING\")", has: ["TRUE"])
        await expect("WRITE SYS$OUTPUT F$RAME(\(cabRame),\"IS_CAB\")", has: ["TRUE"])
        await expect("WRITE SYS$OUTPUT F$RAME(\(cabRame),\"CAB\")", has: ["Alma"])
        await expect("WRITE SYS$OUTPUT F$RAME(\(cabRame),\"MODE\")", has: ["PA"])
        await expect("WRITE SYS$OUTPUT F$RAME(98,\"EXISTS\")", has: ["FALSE"])
        await expect("SHOW SYMBOL PCC$LINE", has: ["PCC$LINE = \"essai\""])
        await expect("SHOW SYMBOL PCC$CABS", has: ["PCC$CABS = \"1\""])
        await expect("SHOW SYMBOL PCC$MODE", has: ["NORMAL"])

        // The seeded procedure: a cab is in service, so it is held at once
        // and its driver told why.
        let before = cab.commands("message").count
        let ran = await dcl("@WAITCAB 5")
        let held = await wait { self.snapshot?.rame(numbered: self.cabRame)?.held == true && cab.commands("message").count > before }
        check("@WAITCAB holds the cab and tells its driver", held && ran.contains("%PCC-S-HOLD")
            && cab.commands("message").last?["value"] as? String == "Hold at the next platform: the PCC will release you", ran)
        _ = await dcl("SET RAME \(cabRame) /RELEASE")

        // A procedure of the operator's own, with a loop that reads the
        // engine: the example of HELP TUTORIAL, on the trains there are.
        let numbers = (snapshot?.rames.map(\.number) ?? []).sorted()
        let first = numbers.first ?? 1, last = numbers.last ?? 1
        terminal.engine.scriptStore.write(name: "SWEEP.COM", body: """
        $ ! SWEEP.COM -- hold every train, then release them
        $ N = \(first)
        $LOOP:
        $   IF N .GT. \(last) THEN GOTO HELD
        $   IF F$RAME('N',"EXISTS") .EQS. "TRUE" THEN SET RAME 'N' /HOLD
        $   N = N + 1
        $   GOTO LOOP
        $HELD:
        $ COUNT = F$PCC("RAMES")
        $ WRITE SYS$OUTPUT "HELD ''COUNT' TRAINS"
        $ EXIT
        """)
        let swept = await dcl("@SWEEP")
        check("a procedure that loops on F$RAME holds every train",
              (snapshot?.rames ?? []).allSatisfy(\.held) && swept.contains("HELD \(numbers.count) TRAINS"), swept)
        for number in numbers { _ = link.hold(rame: number, false) }
        check("and they are released", (snapshot?.rames ?? []).allSatisfy { !$0.held })
        let noFile = await dcl("@NOSUCHPROCEDURE")
        check("a procedure that does not exist is reported", noFile.contains("RMS-E-FNF"), noFile)

        // What became of an order is in $STATUS, at the prompt and in a
        // procedure, and a truth value tests as DCL has it.
        _ = await dcl("SET RAME 98 /HOLD")
        await expect("SHOW SYMBOL $STATUS", has: ["%X000080D0"], "$STATUS has the warning of an order that was refused")
        _ = await dcl("SET RAME 98 /HOLD")
        await expect("WRITE SYS$OUTPUT $STATUS", has: ["%X000080D0"], "WRITE SYS$OUTPUT $STATUS prints it")
        _ = await dcl("SHOW PCC")
        await expect("SHOW SYMBOL $STATUS", has: ["%X00000001"], "and a success after a command that succeeded")
        terminal.engine.scriptStore.write(name: "ORDERS.COM", body: """
        $ ! ORDERS.COM -- what a procedure sees of its orders
        $ SET RAME 98 /HOLD
        $ IF .NOT. $STATUS THEN WRITE SYS$OUTPUT "REFUSED 98"
        $ SET RAME 98 /HOLD
        $ S = $STATUS
        $ WRITE SYS$OUTPUT "STATUS ''S' SEVERITY ''$SEVERITY'"
        $ SET RAME \(cabRame) /HOLD
        $ IF $STATUS THEN WRITE SYS$OUTPUT "HELD \(cabRame)"
        $ IF F$RAME(\(cabRame),"IS_CAB") THEN WRITE SYS$OUTPUT "A CAB"
        $ IF F$RAME(\(first),"IS_CAB") THEN WRITE SYS$OUTPUT "NOT SAID"
        $ IF .NOT. F$RAME(98,"EXISTS") THEN WRITE SYS$OUTPUT "NO 98"
        $ IF F$RAME(\(cabRame),"HELD") .AND. F$PCC("SERVICE") THEN SET RAME \(cabRame) /RELEASE
        $ N = \(cabRame)
        $ WRITE SYS$OUTPUT "CAB OF ''N': ''F$RAME('N',"CAB")', ON ''F$PCC("LINE")'"
        $ EXIT
        """)
        let orders = await dcl("@ORDERS")
        check("in a procedure IF .NOT. $STATUS catches a refusal, and IF $STATUS a success",
              orders.contains("REFUSED 98") && orders.contains("HELD \(cabRame)"), orders)
        check("a symbol takes $STATUS, and $SEVERITY goes with it",
              orders.contains("STATUS %X000080D0 SEVERITY 0"), orders)
        check("IF takes TRUE and FALSE as DCL does", orders.contains("A CAB") && orders.contains("NO 98")
            && !orders.contains("NOT SAID") && orders.contains("%PCC-S-RELEASE"), orders)
        check("and the cab is released", snapshot?.rame(numbered: cabRame)?.held == false)
        check("a lexical function goes into a string with apostrophes",
              orders.contains("CAB OF \(cabRame): Alma, ON essai"), orders)
        let hello = await dcl("@HELLO")
        check("the seeded HELLO.COM ends with the time", hello.contains("Iteration 3") && hello.contains("Done at ")
            && !hello.contains("''"), hello)
    }

    // MARK: -- French

    /// The same desk in French: the gated words resolve only in their own
    /// language, and what is printed is French.
    func testFrench() async {
        section("En français : le vocabulaire et les messages")
        guard let cab, cabRame > 0 else {
            check("a cab is in service", false)
            return
        }
        let label = PCCText.number(cabRame)
        await setLanguage(.fr)
        check("PCC$LANGUAGE follows the language", await dcl("SHOW SYMBOL PCC$LANGUAGE").contains("FR"))

        await expect("SHOW PCC", has: ["À L'ÉCOUTE SUR LE PORT", "CE MAC SEULEMENT", "Connexions"], lacks: ["LISTENING", "Network"])
        await expect("SHOW LIGNES", has: ["Bibliothèque de lignes : 8.", "Ligne d'essai"], lacks: ["held", "Length"])
        await expect("SHOW LIGNE", has: ["Intervalle", "Parc", "par voie"], lacks: ["Headway", "Fleet", "a track"])
        await expect("SHOW LIGNE /STATIONS", has: ["Voie 1", "Porte des Essais"], lacks: ["Track 1"])
        await expect("SHOW LIGNE /SOURCE", has: ["Tracé d'essai"], lacks: ["Where the data"])
        await expect("SHOW RAMES", has: ["Rames de", "CABINE"], lacks: ["Trains of"])
        await expect("SHOW RAME \(cabRame)", has: ["Rame \(label)", "ACTIVE", "ENGAGÉ", "4 s D'AVANCE"], lacks: ["LIVE", "ENGAGED", "EARLY"])
        await expect("SHOW CABINES", has: ["Alma", "ACTIVE"], lacks: ["LIVE"])
        await expect("SHOW CONNECTIONS", has: ["EN SERVICE", "sa ligne"], lacks: ["IN SERVICE"])
        await expect("SHOW JOURNAL /LAST=30", has: ["Cabine Alma en service, rame \(label)"], lacks: ["Cab Alma in service"])
        await expect("SHOW LINE", has: ["%DCL-W-IVKEYW"], "the English object is refused in French mode")
        await expect("SHOW CABS", has: ["%DCL-W-IVKEYW"], "and so is CABS")
        await expect("LIGNE", has: ["Ligne d'essai"], "the short form LIGNE")
        await expect("FLOTTE", has: ["Rames de"], "the short form FLOTTE")
        await expect("GARES", has: ["Pont de la Mesure"], "the short form GARES")
        await expect("CABINES", has: ["Alma"], "the short form CABINES")
        await expect("RAME \(cabRame)", has: ["Rame \(label)"], "the short form RAME")
        await expect("TRAIN \(cabRame)", has: ["%DCL-W-IVVERB"], "the English short form is refused in French mode")

        await expect("SET RAME \(cabRame) /RETENIR /MESSAGE=\"ATTENDEZ\"", has: ["%PCC-S-HOLD", "retenue"], lacks: ["held"])
        check("/RETENIR holds the train", snapshot?.rame(numbered: cabRame)?.held == true)
        await expect("SET RAME \(cabRame) /HOLD", has: ["%PCC-W-MISSQUAL"], "the English qualifier is refused in French mode")
        await expect("SET RAME \(cabRame) /LIBERER", has: ["%PCC-S-RELEASE", "libérée"])
        check("/LIBERER releases it", snapshot?.rame(numbered: cabRame)?.held == false)
        await expect("SET RAME \(cabRame) /FREINER", has: ["%PCC-S-BRAKE", "FU"])
        check("/FREINER brakes it", snapshot?.rame(numbered: cabRame)?.braked == true)
        await expect("SET RAME \(cabRame) /DEFREINER", has: ["%PCC-S-UNBRAKE"])
        check("/DEFREINER releases it", snapshot?.rame(numbered: cabRame)?.braked == false)
        let calls = cab.commands("call").count
        await expect("SET RAME \(cabRame) /APPELER", has: ["%PCC-S-CALL", "appel du conducteur"])
        check("/APPELER rings the driver", await wait { cab.commands("call").count > calls })
        await expect("SET RAME 98 /RETENIR", has: ["%PCC-W-REFUSED", "Aucune rame 98"], lacks: ["No train"], "a refusal is in French")

        await expect("SET LIGNE /INTERVALLE=120", has: ["%PCC-S-HEADWAY", "intervalle réglé"])
        check("/INTERVALLE reaches the engine", snapshot?.headwayS == 120)
        await expect("SET LIGNE /HEADWAY=150", has: ["%PCC-W-MISSQUAL"], "the English qualifier is refused in French mode")
        await expect("URGENCE", has: ["%PCC-S-EMERGENCY", "arrêt d'urgence général"])
        check("URGENCE orders the general emergency stop", snapshot?.emergencyStop == true)
        await expect("SHOW ALARMS", has: ["LIGNE", "AU", "CRITIQUE", "Arrêt d'urgence général"], lacks: ["CRITICAL"])
        await expect("REPRISE", has: ["%PCC-S-EMERGENCY"])
        check("REPRISE releases it", snapshot?.emergencyStop == false)
        _ = await wait { self.snapshot?.rame(numbered: self.cabRame)?.cab?.emergencyBrake == false }
        await expect("STOP LIGNE", has: ["%PCC-S-SERVICE", "arrêté"])
        check("STOP LIGNE stops line service", snapshot?.inService == false)
        await expect("START LIGNE", has: ["%PCC-S-SERVICE", "démarré"])
        check("START LIGNE starts it", snapshot?.inService == true)
        await expect("SET LIGNE /CHARGER=21", has: ["%PCC-W-REFUSED", "Une cabine est en service"], "the refusal of a change of line is in French")
        await expect("SET LIGNE /FERMER", has: ["%PCC-W-REFUSED"])
        await expect("SET LIGNE /RELIRE", has: ["%PCC-S-REREAD"])
        await expect("SET PCC /LAN=OFF", has: ["%PCC-S-LAN", "boucle locale"])

        // The seeded procedure branches on the language.
        let before = cab.commands("message").count
        _ = await dcl("@WAITCAB 5")
        let held = await wait { cab.commands("message").count > before }
        check("@WAITCAB gives its order in French", held
            && cab.commands("message").last?["value"] as? String == "Retenue au prochain quai : le PCC vous liberera")
        _ = await dcl("SET RAME \(cabRame) /LIBERER")
        await expect("ACKNOWLEDGE ALARM ALL /CLEAR", has: ["acquitt"])
        await setLanguage(.en)
    }

    // MARK: -- a change of line

    /// The cab leaves; the PCC's name and its listener; the line changes.
    func testLineChange() async {
        section("The cab leaves; SET PCC; the line changes")
        if let cab, cabRame > 0 {
            let label = PCCText.number(cabRame)
            cab.leave()
            check("the cab leaves service", await wait { self.snapshot?.cabs.isEmpty == true })
            await expect("SHOW JOURNAL /LAST=3", has: ["Cab Alma left service, train \(label)"])
            await expect("SHOW CABS", has: ["no cab in service"])
            check("its train runs on as an automatic one", (snapshot?.rames.count ?? 0) >= 2 && snapshot?.cabs.isEmpty == true)
        }
        await formChangesLine(to: "21", named: "Ligne 21")
        await expect("SET LINE /LOAD=14", has: ["%PCC-S-LOAD", "Ligne 14"])
        check("with no cab in service the line changes", snapshot?.line?.identity.id == "14")
        if let cab {
            let told = await wait { cab.received("event").contains { ($0["line"] as? [String: Any])?["id"] as? String == "14" } }
            check("the cab is told of the new line", told, "\(cab.received("event"))")
        }
        check("the choice is kept as a setting", node.environment.settings.string(PCCSettingKey.line) == "14")

        // The name: the PCC closes and starts again, on the line it was on.
        await expect("SET PCC /NAME=\"PCC ESSAI\"", has: ["%PCC-S-NAME", "PCC ESSAI"])
        check("SET PCC /NAME names it, and keeps the name", link.name == "PCC ESSAI"
            && node.environment.settings.string(PCCSettingKey.name) == "PCC ESSAI")
        let again = await wait(8) { Headless.port(of: self.link) != nil && self.snapshot?.line?.identity.id == "14" }
        check("it listens again, on the line it was on", again, "listener: \(link.listener), line: \(snapshot?.line?.identity.id ?? "none")")
        check("the cab was told the PCC was closing", await wait { self.cab?.closed != false })
        await expect("SET PCC /NAME=\"\"", has: ["%PCC-W-REFUSED"], "a PCC with no name is refused")
        await expect("SET PCC", has: ["%PCC-W-MISSQUAL"])

        await expect("SET PCC /DISABLE", has: ["%PCC-S-DISABLED"])
        check("SET PCC /DISABLE closes the PCC", link.listener == .disabled && snapshot == nil && !link.isEnabled)
        await expect("SHOW PCC", has: ["DISABLED", "SET PCC /ENABLE"])
        await expect("SHOW LINE", has: ["not running"])
        await expect("SET LINE /SERVICE=ON", has: ["%PCC-W-REFUSED", "not running"], "an order is refused while the PCC is closed")
        await expect("SET RAME 1 /HOLD", has: ["%PCC-W-REFUSED"])
        await expect("SET PCC /ENABLE", has: ["%PCC-S-ENABLED"])
        let listening = await wait(8) { Headless.port(of: self.link) != nil && self.snapshot?.line?.identity.id == "14" }
        check("SET PCC /ENABLE starts it again, on the line it was on", listening)
        await expect("SET PCC /LAN=OFF", has: ["%PCC-S-LAN"])
        check("the PCC stayed on loopback throughout", !link.isLAN)
    }

    // MARK: -- telnet

    /// The DCL over telnet, as a terminal emulator would reach it.
    func testTelnet() async {
        section("The DCL over telnet")
        _ = await wait(4) { self.node.telnet.port != nil }
        guard let port = node.telnet.port else {
            check("the telnet DCL listens on loopback", false)
            return
        }
        check("the telnet DCL listens on loopback, on a port of its own", port != 2324 && port != 0)
        // The socket is read on a thread of its own: the session it talks
        // to runs here, on the main actor.
        let transcript = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            DispatchQueue.global().async {
                guard let socket = LoopbackSocket(port: port) else {
                    continuation.resume(returning: "")
                    return
                }
                var text = String(decoding: socket.read(for: 1.5), as: UTF8.self)
                socket.write(Data("SHOW PCC\r".utf8))
                text += String(decoding: socket.read(for: 1.0), as: UTF8.self)
                socket.write(Data("LOGOUT\r".utf8))
                text += String(decoding: socket.read(for: 0.6), as: UTF8.self)
                socket.hangUp()
                continuation.resume(returning: text)
            }
        }
        check("a telnet session logs in to the node", transcript.contains("Welcome to") && transcript.contains(world.nodeName),
              String(transcript.prefix(400)))
        check("and SHOW PCC answers over it", transcript.contains("LISTENING ON PORT") && transcript.contains("PCC ESSAI"),
              String(transcript.suffix(600)))
        check("and LOGOUT ends it", transcript.contains("logged out"))
    }
}

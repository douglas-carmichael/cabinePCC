import Foundation
import CabinePCCKit

// The self-test's look at the full-screen displays: a frame of each
// monitor, read back from the screen it was painted on, and the two forms
// driven by their keys, with the engine checked for what the keys ordered.
extension SelfTest {

    /// The rows of the frame that are rails of the mimic board.
    private func rails(_ frame: String) -> [String] {
        frame.split(separator: "\n").map(String.init).filter { $0.contains(" 1→╭") || $0.contains(" 2←╰") }
    }

    /// Starts a display and waits for it to have painted, and for its own
    /// timer to have refreshed it once.
    private func show(_ command: String) async -> String {
        _ = await dcl(command)
        await Headless.sleep(0.7)
        return terminal.frame
    }

    /// Leaves a display with CTRL/Z, and says whether the terminal is the
    /// shell's again.
    private func leave() -> Bool {
        terminal.keys(HeadlessTerminal.controlZ)
        return !terminal.engine.liveActive && !terminal.screen.onAlternate && !terminal.screen.cursorHidden
            && terminal.engine.transcript.hasSuffix(terminal.engine.prompt)
    }

    // MARK: -- monitors

    func testMonitors() async {
        section("The monitors: a frame of each")
        guard cabRame > 0, let before = snapshot else {
            check("a cab is in service", false)
            return
        }
        let label = PCCText.number(cabRame)
        // One train held and one braked, on track 2 where the cab is not,
        // so that their marks show.
        let automatic = before.rames.filter { $0.cab == nil && $0.phase != .tail }.sorted { ($0.track == 2 ? 0 : 1, $0.number) < ($1.track == 2 ? 0 : 1, $1.number) }
        guard automatic.count >= 2 else {
            check("the line has two automatic trains to mark", false, "\(before.rames.map { "\($0.number) \($0.phase)" })")
            return
        }
        let held = automatic[0].number, braked = automatic[1].number
        _ = link.hold(rame: held, true)
        _ = link.emergencyBrake(rame: braked, true)
        _ = await wait { self.alarm("RAME \(PCCText.number(braked))", "FU") != nil }

        var frame = await show("MONITOR LINE")
        check("MONITOR LINE takes the screen, and hides the cursor",
              terminal.engine.liveActive && terminal.screen.onAlternate && terminal.screen.cursorHidden)
        check("its banner names the product, the display and the node",
              frame.contains("LPD PCC-CABINE V1.0") && frame.contains("LINE MONITOR") && frame.contains(world.nodeName), frame)
        check("its status row has the line, its mode and its clock",
              frame.contains("Ligne d'essai") && frame.contains("NORMAL") && frame.contains("08:"), frame)
        check("the mimic board has both tracks, joined at the ends", rails(frame).count == 2 && frame.contains("╮") && frame.contains("╯"), frame)
        check("the two ends of the line are named", frame.contains("▼Porte des Essais") && frame.contains("Porte du Banc"), frame)
        // The board with no train on it: a tick for every station on both rails.
        if var empty = snapshot, let line = empty.line {
            empty.rames = []
            let board = terminal.engine.lineMimicRows(empty, line)
            let named = line.stationNames.filter { (board[0] + board[3]).contains($0) }
            check("every station is ticked on both rails, and named where there is room",
                  board[1].filter { $0 == "╤" }.count == 6 && board[2].filter { $0 == "╧" }.count == 6
                      && named.count >= 4 && named.contains("Porte des Essais") && named.contains("Porte du Banc"),
                  board.joined(separator: "\n"))
        }
        check("the tails are drawn", rails(frame).allSatisfy { $0.contains("╌") }, frame)
        check("the cab is on track 1, told apart from the automatic trains",
              rails(frame).first?.contains(label + "»") == true && terminal.screen.isReversed(label + "»"), frame)
        check("an automatic train is its number and an arrow",
              rails(frame).contains { $0.contains(">") || $0.contains("<") }, frame)
        check("a held train is marked H", rails(frame).contains { $0.contains("H" + PCCText.number(held)) || $0.contains(PCCText.number(held) + "H") }, frame)
        check("a braked train is marked !", rails(frame).contains { $0.contains("!" + PCCText.number(braked)) || $0.contains(PCCText.number(braked) + "!") }, frame)
        check("the alarms display has the most severe standing alarm",
              frame.contains("%PCC-E-FU") && frame.contains("RAME \(PCCText.number(braked))") && frame.contains("1 active"), frame)
        check("the cabs' summary has the cab: link, mode, state, authority",
              frame.contains("Alma") && frame.contains("LIVE") && frame.contains(" PA ") && frame.contains(" m: "), frame)
        check("the frame fits the pasteboard: 24 rows of 79 columns",
              terminal.screen.lines.allSatisfy { $0.count <= 79 } && !terminal.screen.lines[23].isEmpty
                  && frame.contains("Ctrl/Z Exit"), frame)
        // The pasteboard is updated row by row: a refresh that changes
        // nothing writes nothing, and CTRL/W paints it all again.
        terminal.keys(HeadlessTerminal.controlW)
        check("CTRL/W repaints it", terminal.frame.contains("LINE MONITOR") && rails(terminal.frame).count == 2)
        check("CTRL/Z leaves it, and the shell has the terminal again", leave())
        check("and it says so", terminal.engine.transcript.contains("%PCC-I-MONEXIT"))
        _ = link.hold(rame: held, false)
        _ = link.emergencyBrake(rame: braked, false)

        frame = await show("MONITOR CABS")
        check("MONITOR CABS has the cab: link, driving mode, automatic driver",
              frame.contains("CAB MONITOR") && frame.contains("Alma") && frame.contains("LIVE") && frame.contains("PA")
                  && frame.contains("autopilot ENGAGED"), frame)
        check("where it is, its doors and its brake",
              frame.contains("track 1") && frame.contains("AT Place des Jalons") && frame.contains("doors CLOSED")
                  && frame.contains("EB RELEASED"), frame)
        check("and its authority and what ends it", frame.contains("authority ends") && frame.contains("m ahead"), frame)
        check("CTRL/Z leaves it", leave())

        frame = await show("MONITOR RAMES")
        let numbers = (snapshot?.rames ?? []).map { PCCText.number($0.number) }
        check("MONITOR RAMES has every train", frame.contains("TRAIN MONITOR") && numbers.allSatisfy { frame.contains(" " + $0 + " ") }, frame)
        check("with its kind, state and station", frame.contains("CAB") && frame.contains("AUTO") && frame.contains("km/h")
            && frame.contains("Place des Jalons"), frame)
        check("CTRL/Z leaves it", leave())

        frame = await show("MONITOR CONNECTIONS")
        check("MONITOR CONNECTIONS has the listener", frame.contains("CONNECTION MONITOR") && frame.contains("LISTENING ON PORT"), frame)
        check("and the connection: standing, train, cab, line, age",
              frame.contains("IN SERVICE") && frame.contains(label) && frame.contains("Alma") && frame.contains("essai")
                  && frame.contains("127.0.0.1"), frame)
        check("CTRL/Y interrupts it", {
            terminal.keys(HeadlessTerminal.controlY)
            return !terminal.engine.liveActive && terminal.engine.transcript.contains("%PCC-W-INTERRUPT")
        }())

        // The system's own classes.
        frame = await show("MONITOR SYSTEM")
        check("MONITOR SYSTEM draws the system class", frame.contains("SYSTEM STATISTICS") && frame.contains("Interrupt State")
            && frame.contains("Ctrl/Y"), frame)
        check("its frame fits the 24 rows of the screen, banner first",
              terminal.screen.lines[0].contains("Monitor Utility") && terminal.screen.lines[23].contains("Elapsed"), frame)
        terminal.keys(HeadlessTerminal.controlY)
        check("CTRL/Y interrupts it", !terminal.engine.liveActive && terminal.engine.transcript.contains("%MONITOR-I-INTERRUPT"))
        frame = await show("MONITOR PROCESSES")
        check("MONITOR PROCESSES has the PCC's processes",
              frame.contains("PCC_ENGINE") && frame.contains("PCC_LISTENER") && frame.contains("CAB_\(label)_LINK"), frame)
        terminal.keys(HeadlessTerminal.controlY)
        for other in ["MODES", "IO", "PAGE", "STATES", "DISK", "LOCK", "FCP", "ALL_CLASSES"] {
            frame = await show("MONITOR \(other)")
            check("MONITOR \(other) draws, and fits the screen",
                  terminal.engine.liveActive && terminal.screen.lines[0].contains("Monitor Utility") && frame.contains("Elapsed"), frame)
            terminal.keys(HeadlessTerminal.controlY)
        }

        await expect("MONITOR CLUSTER", has: ["%CLI-W-IVKEYW"], "a class this node does not have is refused")
        await expect("MONITOR LINE /INTERVAL=0.1", has: ["%PCC-W-IVINTERVAL"], "an interval under a quarter of a second is refused")
        check("and takes no screen", !terminal.engine.liveActive)

        // In French.
        await setLanguage(.fr)
        frame = await show("MONITOR LIGNE")
        check("MONITOR LIGNE is in French", frame.contains("MONITEUR DE LIGNE") && frame.contains("Ctrl/Z Quitter")
            && !frame.contains("LINE MONITOR") && !frame.contains("Elapsed"), frame)
        check("CTRL/Z leaves it", leave())
        frame = await show("MONITOR CABINES")
        check("MONITOR CABINES is in French", frame.contains("pilote auto ENGAGÉ") && frame.contains("portes FERMÉES")
            && !frame.contains("autopilot"), frame)
        check("CTRL/Z leaves it", leave())
        await expect("MONITOR LINE", has: ["%CLI-W-IVKEYW"], "the English class is refused in French mode")
        await setLanguage(.en)
    }

    // MARK: -- forms

    func testForms() async {
        section("The forms: RUN RAME_DIR and RUN LIGNE_DIR")
        guard let cab, cabRame > 0 else {
            check("a cab is in service", false)
            return
        }
        let label = PCCText.number(cabRame)
        func press(_ text: String) async -> String {
            terminal.type(text)
            await Headless.sleep(0.15)
            return terminal.frame
        }
        func rame() -> CabinePCC.Rame? { snapshot?.rame(numbered: cabRame) }

        var frame = await show("RUN RAME_DIR")
        check("RUN RAME_DIR takes the screen", terminal.engine.liveActive && terminal.screen.onAlternate)
        check("its title bar and its status", frame.contains("TRAINS AND CABS") && frame.contains("Ligne d'essai") && frame.contains("NORMAL"), frame)
        check("its list has every train", (snapshot?.rames ?? []).allSatisfy { frame.contains(PCCText.number($0.number) + " ") }, frame)
        check("its foot names the keys", frame.contains("H Hold") && frame.contains("Ctrl/Z"), frame)

        frame = await press(label)
        check("digits find a train by its number", frame.contains("▶" + label) && frame.contains("Find: \(label)____")
            && frame.contains("1 train"), frame)
        check("the record is the train's", frame.contains("Train:") && frame.contains("CAB") && frame.contains("Station:"), frame)
        terminal.keys(HeadlessTerminal.tab)
        await Headless.sleep(0.15)
        frame = terminal.frame
        check("Tab turns to the cab's page", frame.contains("Cab:") && frame.contains("Alma") && frame.contains("LIVE")
            && frame.contains("Authority:") && frame.contains("2/2"), frame)

        frame = await press("h")
        check("H asks before it acts", frame.contains("Hold train \(label)") && frame.contains("(Y/N)") && rame()?.held == false, frame)
        frame = await press("n")
        check("any key but Y takes the question back", frame.contains("Nothing done") && rame()?.held == false, frame)
        _ = await press("h")
        frame = await press("y")
        check("Y carries it out: the train is held", rame()?.held == true && frame.contains("%PCC-S-HOLD"), frame)
        check("and the cab has the order", await wait { cab.commands("hold").last?["value"] as? Bool == true })
        _ = await press("r")
        frame = await press("y")
        check("R, Y releases it", rame()?.held == false && frame.contains("%PCC-S-RELEASE"), frame)

        let messages = cab.commands("message").count
        frame = await press("m")
        check("M opens the message field", frame.contains("Message for train \(label)"), frame)
        frame = await press("DEPART IMMINENT, é")
        check("the words go in the field as they are typed", frame.contains("DEPART IMMINENT, é_"), frame)
        terminal.keys([0x7F, 0x7F, 0x7F])
        terminal.keys(HeadlessTerminal.enter)
        await Headless.sleep(0.15)
        frame = terminal.frame
        check("RETURN asks before the message goes", frame.contains("Send") && frame.contains("(Y/N)")
            && cab.commands("message").count == messages, frame)
        frame = await press("y")
        let sent = await wait { cab.commands("message").count > messages }
        check("Y sends it", sent && cab.commands("message").last?["value"] as? String == "DEPART IMMINENT" && frame.contains("%PCC-S-MESSAGE"),
              "\(cab.commands("message").last ?? [:])\n" + frame)

        let calls = cab.commands("call").count
        _ = await press("c")
        frame = await press("y")
        check("C, Y rings the driver", await wait { cab.commands("call").count > calls } && frame.contains("%PCC-S-CALL"), frame)
        _ = await press("b")
        frame = await press("y")
        check("B, Y orders the emergency brake", rame()?.braked == true && frame.contains("%PCC-S-BRAKE"), frame)
        _ = await press("u")
        frame = await press("y")
        check("U, Y releases it", rame()?.braked == false && frame.contains("%PCC-S-UNBRAKE"), frame)
        _ = await wait { rame()?.cab?.emergencyBrake == false }

        // The whole list again, and an automatic train.
        terminal.keys([0x15])
        await Headless.sleep(0.15)
        let first = (snapshot?.rames ?? []).map(\.number).min() ?? 0
        check("CTRL/U clears the find field", terminal.frame.contains("Find: ______"), terminal.frame)
        terminal.keys(HeadlessTerminal.down)
        terminal.keys(HeadlessTerminal.up)
        await Headless.sleep(0.15)
        check("the arrows move the cursor bar", terminal.frame.contains("▶" + PCCText.number(first))
            && terminal.screen.isReversed("▶" + PCCText.number(first)), terminal.frame)
        frame = await press("m")
        check("a message to an automatic train is refused on the form", frame.contains("%PCC-W-REFUSED") && frame.contains("not a cab"), frame)
        terminal.keys(HeadlessTerminal.controlW)
        check("CTRL/W repaints the form", terminal.frame.contains("TRAINS AND CABS"))
        check("CTRL/Z leaves the form", leave())

        // The same form in French: its keys are the French orders'.
        await setLanguage(.fr)
        frame = await show("RUN RAME_DIR")
        check("RUN RAME_DIR is in French", frame.contains("RAMES ET CABINES") && frame.contains("R Retenir")
            && !frame.contains("TRAINS AND CABS"), frame)
        _ = await press(label)
        frame = await press("r")
        check("R asks, in French", frame.contains("Retenir la rame \(label)") && frame.contains("(O/N)"), frame)
        frame = await press("o")
        check("O carries it out, and what it says is whole, on two rows",
              rame()?.held == true && frame.contains("%PCC-S-HOLD") && frame.contains("au prochain quai") && frame.contains("atteint"), frame)
        _ = await press("l")
        frame = await press("o")
        check("L, O releases it", rame()?.held == false, frame)
        frame = await press("h")
        check("the English key is not an order in French mode", !frame.contains("(O/N)") && rame()?.held == false, frame)
        check("CTRL/Z leaves the form", leave())
        await setLanguage(.en)

        // The line library.
        frame = await show("RUN LIGNE_DIR")
        check("RUN LIGNE_DIR has the library, the PCC's line marked",
              frame.contains("LINE LIBRARY") && frame.contains("8 lines") && frame.contains("● essai") && frame.contains("Ligne 14"), frame)
        frame = await press("4")
        check("digits find a line by its id", frame.contains("▶  4") && frame.contains("2 lines"), frame)
        check("the record is the line's", frame.contains("Ligne 4") && frame.contains("Porte de Clignancourt")
            && frame.contains("13.71 km") && frame.contains("29"), frame)
        terminal.keys(HeadlessTerminal.tab)
        await Headless.sleep(0.15)
        frame = terminal.frame
        check("Tab turns to where the line's data came from",
              frame.contains("OpenStreetMap") && frame.contains("Île-de-France") && frame.contains("IGN RGE ALTI") && frame.contains("2026-11-10"), frame)
        terminal.keys(HeadlessTerminal.tab)
        await Headless.sleep(0.15)
        frame = terminal.frame
        check("and Tab again to its stations, with the stop on each track",
              frame.contains("Porte de Clignancourt") && frame.contains("Château Rouge") && frame.contains("3/"), frame)
        frame = await press("l")
        check("L asks before the PCC changes line", frame.contains("Put the PCC on Ligne 4") && frame.contains("(Y/N)"), frame)
        frame = await press("y")
        check("and it is refused while a cab is in service, with the whole of the reason",
              frame.contains("%PCC-W-REFUSED") && frame.contains("cab is in service") && frame.contains("only when none is.")
              && snapshot?.line?.identity.id == "essai", frame)
        terminal.keys(HeadlessTerminal.tab)
        await Headless.sleep(0.15)
        frame = terminal.frame
        check("the next key clears it, and the find field is back", frame.contains("Find: 4") && !frame.contains("%PCC-W-REFUSED"), frame)
        _ = await press("c")
        frame = await press("y")
        check("C, Y: closing the line is refused too", frame.contains("%PCC-W-REFUSED") && snapshot?.line != nil, frame)
        _ = await press("r")
        frame = await press("y")
        check("R, Y reads the library again", frame.contains("%PCC-S-REREAD"), frame)
        check("CTRL/Z leaves the form", leave())
    }

    /// With no cab in service, the library form puts the PCC on a line.
    func formChangesLine(to id: String, named name: String) async {
        var frame = await show("RUN LIGNE_DIR")
        terminal.type(id)
        await Headless.sleep(0.15)
        terminal.type("l")
        await Headless.sleep(0.15)
        frame = terminal.frame
        check("on the form, L asks for \(name)", frame.contains("Put the PCC on \(name)"), frame)
        terminal.type("y")
        await Headless.sleep(0.3)
        frame = terminal.frame
        check("and Y puts the PCC on it", snapshot?.line?.identity.id == id && frame.contains("%PCC-S-LOAD") && frame.contains("● \(id)"), frame)
        check("CTRL/Z leaves the form", leave())
    }
}

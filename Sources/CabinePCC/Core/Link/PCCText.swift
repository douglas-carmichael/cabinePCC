import Foundation
import CabinePCCKit

/// The line in the operator's language: the words of the wire, the journal
/// and the refusals, for the PCC Dispatcher and for the DCL verbs, monitors
/// and forms alike. `t` is the caller's lookup: AppLanguage.t in a view,
/// DCLEngine.tr in a verb.
@MainActor
enum PCCText {
    typealias Lookup = (String) -> String

    /// A rame's number as the line writes it.
    static func number(_ rame: Int) -> String { String(format: "%02d", rame) }

    /// A time of day from seconds since midnight.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(max(seconds, 0).rounded(.down)) % 86_400
        return String(format: "%02d:%02d:%02d", whole / 3_600, whole / 60 % 60, whole % 60)
    }

    /// A word of the wire in the operator's language; the word itself when
    /// this version has none for it.
    private static func word(_ family: String, _ raw: String, _ t: Lookup) -> String {
        let key = "pcc.\(family).\(raw.lowercased())"
        let text = t(key)
        return text == key ? raw : text
    }

    static func mode(_ mode: CabineWire.LineMode, _ t: Lookup) -> String { word("mode", mode.rawValue, t) }
    static func kind(_ kind: CabineWire.TrainKind, _ t: Lookup) -> String { word("kind", kind.rawValue, t) }
    static func phase(_ phase: CabineWire.TrainPhase, _ t: Lookup) -> String { word("phase", phase.rawValue, t) }
    static func doors(_ phase: CabineWire.DoorPhase, _ t: Lookup) -> String { word("doorphase", phase.rawValue, t) }
    static func command(_ command: CabineWire.CommandName, _ t: Lookup) -> String { word("command", command.rawValue, t) }
    static func link(_ state: CabinePCC.LinkState, _ t: Lookup) -> String { word("link", state.rawValue, t) }
    static func standing(_ standing: CabinePCC.Standing, _ t: Lookup) -> String { word("standing", standing.rawValue, t) }

    /// A driver's coded report; a code this version does not know as it
    /// came.
    static func report(_ code: CabineWire.ReportCode?, _ t: Lookup) -> String {
        code.map { word("report", $0.rawValue, t) } ?? t("pcc.report.none")
    }

    /// A cab's last report: what it was, when by the line's clock, and what
    /// the driver added in their own words.
    static func report(_ report: CabinePCC.Report, _ t: Lookup) -> String {
        var text = String(format: t("pcc.report.at"), self.report(report.code, t), clock(report.clockS))
        if let words = report.text, !words.isEmpty { text += String(format: t("pcc.journal.saying"), words) }
        return text
    }

    /// How the listener stands.
    static func listener(_ listener: PCCLink.Listener, _ t: Lookup) -> String {
        switch listener {
        case .disabled:            return t("pcc.listener.disabled")
        case .starting:            return t("pcc.listener.starting")
        case let .listening(port): return String(format: t("pcc.listener.listening"), Int(port))
        case let .failed(reason):  return String(format: t("pcc.listener.failed"), reason)
        }
    }

    /// A length of time, in minutes and seconds.
    static func duration(_ seconds: Double) -> String {
        let whole = Int(max(seconds, 0).rounded())
        return whole < 60 ? "\(whole) s" : String(format: "%d min %02d s", whole / 60, whole % 60)
    }

    /// A length of track, in kilometres.
    static func kilometres(_ metres: Double) -> String { String(format: "%.2f km", metres / 1_000) }

    /// How the fleet is sized: from the headway, or fixed by the operator.
    static func fleet(_ size: Int?, _ t: Lookup) -> String {
        size.map { String(format: t("pcc.fleet.fixed"), $0) } ?? t("pcc.fleet.auto")
    }

    /// A line as its roundel and its ends: "Ligne 4 (4): Porte de
    /// Clignancourt -- Bagneux".
    static func line(_ held: CabinePCC.HeldLine) -> String {
        "\(held.identity.name) (\(held.identity.id)): \(held.firstStation) -- \(held.lastStation)"
    }

    /// Where the data of a line came from, one line for each kind of data
    /// its package names; one line saying so for a package that names none.
    static func credits(_ credits: LineCredits?, _ t: Lookup) -> [String] {
        guard let credits else { return [t("pcc.credits.none")] }
        var lines: [String] = []
        if let track = credits.track { lines.append(String(format: t("pcc.credits.track"), track)) }
        if let stations = credits.stations { lines.append(String(format: t("pcc.credits.stations"), stations)) }
        if let ground = credits.ground { lines.append(String(format: t("pcc.credits.ground"), ground)) }
        if let date = credits.date { lines.append(String(format: t("pcc.credits.date"), date)) }
        return lines
    }

    /// When something was last heard from, and the round trip of its last
    /// ping.
    private static func heard(_ age: Double, _ roundTrip: Double?, _ t: Lookup) -> String {
        var text = String(format: t("pcc.heard"), max(age, 0))
        if let roundTrip { text += ", " + String(format: t("pcc.roundtrip"), roundTrip * 1_000) }
        return text
    }

    /// One connection, in two parts: how it stands to the PCC and who it
    /// is; then where it comes from, the line it holds and when it was last
    /// heard.
    static func connection(_ session: CabinePCC.Session, _ t: Lookup) -> (who: String, detail: String) {
        var who = "\(session.id)  " + standing(session.standing, t)
        if let rame = session.rame { who += "  " + t("pcc.rame") + " " + number(rame) }
        if let name = session.name { who += "  \(name)" }
        if let app = session.app { who += " (\(app)\(session.appVersion.map { " \($0)" } ?? ""))" }
        var detail = session.peer
        if let line = session.line {
            detail += "  " + String(format: t("pcc.connection.line"), line.name, line.id, line.rev)
        } else if session.standing != .opened {
            detail += "  " + t("pcc.connection.noline")
        }
        return (who, detail + "  " + heard(session.linkAgeS, session.roundTripS, t))
    }

    /// A cab's link: live, with the round trip of its last ping, or silent,
    /// with how long it has been.
    static func link(_ cab: CabinePCC.Cab, _ t: Lookup) -> String {
        switch cab.link {
        case .live:
            let live = link(CabinePCC.LinkState.live, t)
            return cab.roundTripS.map { live + " (" + String(format: t("pcc.roundtrip"), $0 * 1_000) + ")" } ?? live
        case .silent:
            return link(CabinePCC.LinkState.silent, t) + " (" + heard(cab.linkAgeS, nil, t) + ")"
        }
    }

    /// Whether the automatic driver has a cab's train.
    static func autopilot(_ cab: CabinePCC.Cab, _ t: Lookup) -> String {
        cab.automatic.map { t($0 ? "pcc.autopilot.on" : "pcc.autopilot.off") } ?? "--"
    }

    /// A cab's emergency brake, and its cause in the cab's own words: the
    /// first of them, should the cab have a great deal to say.
    static func emergencyBrake(_ cab: CabinePCC.Cab, _ t: Lookup) -> String {
        guard cab.emergencyBrake else { return t("pcc.fu.released") }
        guard let cause = cab.emergencyCause, !cause.isEmpty else { return t("pcc.fu.applied") }
        return t("pcc.fu.applied") + " (" + (cause.count > 48 ? String(cause.prefix(47)) + "…" : cause) + ")"
    }

    /// The passengers aboard a cab's train, of the places the stock has.
    static func passengers(_ cab: CabinePCC.Cab, capacity: Int?) -> String {
        guard let aboard = cab.status?.passengers else { return "--" }
        return capacity.map { "\(aboard)/\($0)" } ?? "\(aboard)"
    }

    /// How late or early a cab runs on its timetable.
    static func deviation(_ cab: CabinePCC.Cab, _ t: Lookup) -> String {
        guard let deviation = cab.status?.deviationS, deviation.isFinite else { return "--" }
        let seconds = Int(deviation.rounded())
        if seconds == 0 { return t("pcc.deviation.ontime") }
        return String(format: t(seconds > 0 ? "pcc.deviation.late" : "pcc.deviation.early"), abs(seconds))
    }

    /// The station a train stands at, or runs to.
    static func station(of rame: CabinePCC.Rame, _ t: Lookup) -> String {
        guard let name = rame.stationName else { return "--" }
        let standing = rame.cab?.status?.station?.atPlatform
            ?? (rame.phase == .dwelling || rame.phase == .departing || rame.phase == .held)
        return String(format: t(standing ? "pcc.station.at" : "pcc.station.to"), name)
    }

    /// A train's doors: what its cab says of them, or how far open they
    /// are.
    static func doors(of rame: CabinePCC.Rame, _ t: Lookup) -> String {
        guard let doors = rame.cab?.status?.doors, let phase = doors.phase else {
            return self.doors(open: rame.doors, t)
        }
        var text = self.doors(phase, t)
        if phase != .closed, let side = doors.side { text += " " + word("side", side, t) }
        return text
    }

    /// A train's doors, from how far open they are.
    static func doors(open fraction: Double, _ t: Lookup) -> String {
        if fraction <= 0.01 { return t("pcc.doorphase.closed") }
        if fraction >= 0.99 { return t("pcc.doorphase.open") }
        return String(format: "%.0f %%", fraction * 100)
    }

    /// What marks a train out: the operator's hold on it and brake, and a
    /// cab whose player has paused the game.
    static func flags(of rame: CabinePCC.Rame, _ t: Lookup) -> [String] {
        var flags: [String] = []
        if rame.held { flags.append(t("pcc.flag.held")) }
        if rame.braked { flags.append(t("pcc.flag.braked")) }
        if rame.cab?.status?.paused == true { flags.append(t("pcc.flag.paused")) }
        return flags
    }

    /// What ends a cab's authority.
    static func reason(_ authority: CabineWire.Authority, _ t: Lookup) -> String {
        if authority.reason == .train {
            if let rame = authority.rame, let gap = authority.gapM {
                return String(format: t("pcc.reason.train.gap"), number(rame), gap)
            }
            return t("pcc.reason.train")
        }
        return word("reason", authority.reason.rawValue, t)
    }

    /// Where a cab's authority ends, in metres ahead of its nose, and what
    /// ends it.
    static func authority(_ authority: CabineWire.Authority, nose: Double, _ t: Lookup) -> String {
        String(format: t("pcc.authority.fmt"), max(authority.endM - nose, 0), reason(authority, t))
    }

    /// A message of the DCL shell as a sentence for a window: without its
    /// `%PCC-S-IDENT, ` and with a capital and a full stop.
    static func sentence(_ message: String) -> String {
        var text = message
        if text.hasPrefix("%"), let comma = text.range(of: ", ") { text = String(text[comma.upperBound...]) }
        guard let first = text.first else { return text }
        text = first.uppercased() + text.dropFirst()
        return text.hasSuffix(".") ? text : text + "."
    }

    /// Why an order was not carried out.
    static func refusal(_ refusal: PCCLink.Refusal, _ t: Lookup) -> String {
        switch refusal {
        case .notRunning:
            return t("pcc.refusal.notrunning")
        case .noLine:
            return t("pcc.refusal.noline")
        case let .noSuchRame(rame):
            return String(format: t("pcc.refusal.nosuchrame"), number(rame))
        case let .notACab(rame):
            return String(format: t("pcc.refusal.notacab"), number(rame))
        case let .cabNotConnected(rame):
            return String(format: t("pcc.refusal.notconnected"), number(rame))
        case .headwayOutOfRange:
            let range = CabinePCC.Settings.headwayRange
            return String(format: t("pcc.refusal.headway"), Int(range.lowerBound), Int(range.upperBound))
        case .fleetOutOfRange:
            let range = CabinePCC.Settings.fleetRange
            return String(format: t("pcc.refusal.fleet"), range.lowerBound, range.upperBound)
        case .emptyMessage:
            return t("pcc.refusal.emptymessage")
        case let .messageTooLong(count):
            return String(format: t("pcc.refusal.longmessage"), CabineWire.maxMessageCharacters, count)
        case .emptyName:
            return t("pcc.refusal.emptyname")
        case .lineInUse:
            return t("pcc.refusal.lineinuse")
        case let .noSuchLine(id):
            return id.isEmpty ? t("pcc.refusal.nosuchline") : String(format: t("pcc.refusal.nosuchline.id"), id)
        case let .other(reason):
            return String(format: t("pcc.refusal.other"), reason)
        }
    }

    /// Why a line file was not kept.
    static func fault(_ fault: LineFileFault, _ t: Lookup) -> String {
        switch fault {
        case .unreadable:               return t("pcc.fault.unreadable")
        case .notAPackage:              return t("pcc.fault.notapackage")
        // The engine's reason names the field more often than not.
        case let .field(path, reason):  return reason.contains(path) ? reason : String(format: t("pcc.fault.field"), path, reason)
        case let .refused(reason):      return String(format: t("pcc.fault.refused"), reason)
        }
    }

    /// One line of the journal: the line's time of day, and what happened.
    static func journal(_ line: PCCLink.JournalLine, _ t: Lookup) -> String {
        (line.clockS.map(clock) ?? "--:--:--") + "  " + journal(line.event, t)
    }

    /// One thing that happened, as the journal tells it.
    static func journal(_ event: PCCLink.JournalLine.Event, _ t: Lookup) -> String {
        switch event {
        case let .engine(event):
            return journal(event, t)
        case let .libraryRead(held):
            return held == 1 ? t("pcc.journal.library.one") : String(format: t("pcc.journal.library"), held)
        case let .lineFileRefused(file, fault):
            return String(format: t("pcc.journal.linefile"), file, self.fault(fault, t))
        case let .lineNotHeld(id):
            return String(format: t("pcc.journal.linenotheld"), id)
        case .lineClosed:
            return t("pcc.journal.lineclosed")
        }
    }

    /// One thing the engine noted.
    private static func journal(_ event: CabinePCC.JournalEntry.Event, _ t: Lookup) -> String {
        /// " (train 21)", for an event of a cab that is in service.
        func of(_ rame: Int?) -> String {
            rame.map { String(format: t("pcc.journal.oframe"), number($0)) } ?? ""
        }
        /// " -- words", for what a cab adds in its own words.
        func saying(_ words: String?) -> String {
            guard let words, !words.isEmpty else { return "" }
            return String(format: t("pcc.journal.saying"), words)
        }
        switch event {
        case let .lineTakenUp(line, rames):
            return String(format: t("pcc.journal.linetakenup"), line.name, line.id, line.rev, rames)
        case let .cabConnected(name, _, line):
            guard let line else { return String(format: t("pcc.journal.connected.noline"), name) }
            return String(format: t("pcc.journal.connected"), name, line.name, line.id, line.rev)
        case let .cabOnLine(name):
            return String(format: t("pcc.journal.online"), name)
        case let .lineRefused(name, error, reason):
            // The engine gives its reason in English. The one an operator
            // meets has words of its own.
            let why = error == .noSuchLine ? t("pcc.journal.refused.nosuchline") : reason
            return String(format: t("pcc.journal.linerefused"), name, error.rawValue, why)
        case let .lineHandedOver(name, line):
            return String(format: t("pcc.journal.linehanded"), line.name, line.id, line.rev, name)
        case let .cabJoined(name, rame, track, uM, withdrawn):
            var text = String(format: t("pcc.journal.joined"), name, number(rame), track, uM)
            if !withdrawn.isEmpty {
                text += String(format: t("pcc.journal.joined.inplace"),
                               withdrawn.map(number).joined(separator: ", "))
            }
            return text
        case let .cabLeft(name, rame, reason):
            let key = "pcc.leave.\(reason.lowercased())"
            let why = t(key) == key ? reason : t(key)
            return String(format: t("pcc.journal.left"), name, number(rame), why)
        case let .cabSilent(name, rame):
            return String(format: t("pcc.journal.silent"), name, number(rame))
        case let .cabHeardAgain(name, rame):
            return String(format: t("pcc.journal.heardagain"), name, number(rame))
        case let .cabHandedBack(name, rame, automatic):
            return String(format: t("pcc.journal.handedback"), number(rame), name, number(automatic))
        case let .cabDisconnected(name):
            return String(format: t("pcc.journal.disconnected"), name)
        case let .cabEmergencyBrake(name, rame, applied, cause):
            return String(format: t(applied ? "pcc.journal.fu.applied" : "pcc.journal.fu.released"),
                          name, of(rame)) + saying(cause)
        case let .cabReport(name, rame, code, text):
            return String(format: t("pcc.journal.report"), name, of(rame), report(code, t)) + saying(text)
        case let .cabCall(name, rame):
            return String(format: t("pcc.journal.call"), name, of(rame))
        case let .cabAcknowledge(name, rame):
            return String(format: t("pcc.journal.acknowledge"), name, of(rame))
        case let .commandRefused(name, rame, command, error):
            return String(format: t("pcc.journal.commandrefused"), name, of(rame), self.command(command, t))
                + saying(error)
        }
    }
}

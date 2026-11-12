import Foundation
import CabinePCCKit

// The verbs that read and order the PCC (Link/PCCLink.swift), which is the
// host of the engine that runs the line for the Cabine cabs:
//
//      $ SHOW PCC                      the listener, the network, the name
//      $ SET PCC /ENABLE /DISABLE /LAN=ON|OFF /NAME="name"
//      $ SHOW LINES                    the library
//      $ SHOW LINE [/STATIONS] [/SOURCE]
//      $ SET LINE /LOAD=id | /CLOSE | /REREAD
//      $ SET LINE /SERVICE=ON|OFF /EMERGENCY=ON|OFF /HEADWAY=s /RAMES=n|AUTO
//      $ START LINE, STOP LINE         line service on and off
//      $ SHOW RAMES, SHOW RAME n
//      $ SET RAME n /HOLD /RELEASE /BRAKE /UNBRAKE /MESSAGE="text" /CALL
//      $ START RAME n, STOP RAME n     the emergency brake of one train
//      $ SHOW CABS, SHOW CONNECTIONS, SHOW JOURNAL [/LAST=n]
//
// The vocabulary is language-gated as the rest of the shell's: PCC, RAME,
// RAMES, CONNECTIONS, JOURNAL and the qualifiers that read the same in both
// languages are fixed; LINE / LIGNE, LINES / LIGNES, CABS / CABINES and the
// qualifiers that do not (/EMERGENCY and /URGENCE, /HOLD and /RETENIR ...)
// resolve only in their own language. What is printed is layered-product
// content, and localized; the `%PCC-x-IDENT` codes are identifiers.
//
// Every order goes to the engine through the link, and what the link says
// became of it is what is printed: a refusal sets a warning in $STATUS.
// Under SELFTEST (dryRun) an order is named and not carried out.
extension DCLEngine {

    // MARK: -- shared pieces

    /// What became of an order, as the message a verb or a form prints.
    func pccMessage(_ outcome: PCCLink.Outcome, _ done: @autoclosure () -> String) -> String {
        switch outcome {
        case .done:
            return done()
        case let .refused(refusal):
            fail("PCC-W-REFUSED", "%X000080D0")
            return "%PCC-W-REFUSED, " + PCCText.refusal(refusal, tr)
        }
    }

    /// A command as it was typed, near enough, for a dry run to name.
    private func typed(_ cmd: Parsed) -> String {
        var text = ([cmd.verb] + cmd.positional).joined(separator: " ")
        for qualifier in cmd.qualifiers {
            text += " /" + qualifier.name + (qualifier.value.map { "=" + $0 } ?? "")
        }
        return text
    }

    /// What a library read again has to say: how many lines it holds now.
    func rereadMessage() -> String {
        let held = link?.snapshot?.library.count ?? 0
        return held == 1 ? tr("pcc.set.reread.one") : String(format: tr("pcc.set.reread"), held)
    }

    /// Under SELFTEST an order is named, not carried out.
    private func dryRunLine(_ cmd: Parsed) -> String {
        String(format: tr("pcc.dryrun"), typed(cmd)) + "\n"
    }

    /// A field of a report: its label, a colon as the language writes one,
    /// and its value.
    private func field(_ labelKey: String, _ value: String, width: Int = 22) -> String {
        let label = labelled(labelKey)
        return "  " + label.padding(toLength: max(width, label.count), withPad: " ", startingAt: 0) + value + "\n"
    }

    private func left(_ text: String, _ width: Int) -> String {
        text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0)
    }

    private func right(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }

    /// The ON or OFF a qualifier was given; nil with `lines` told why when
    /// it was given neither.
    private func onOff(_ cmd: Parsed, _ name: String, min: Int = 3, _ lines: inout [String]) -> Bool? {
        switch cmd.qualifierValue(name, min: min)?.uppercased() {
        case "ON"?:  return true
        case "OFF"?: return false
        default:
            fail("PCC-W-IVVALUE", "%X000080D8")
            lines.append(String(format: tr("pcc.set.onoff"), name, name))
            return nil
        }
    }

    /// The PCC is not attached, or it is not running, or it is on no line:
    /// what a SHOW verb that needs the line says instead.
    private func noLineText(_ link: PCCLink) -> String {
        "  " + tr(link.snapshot == nil ? "pcc.refusal.notrunning" : "pcc.noline") + "\n"
    }

    // MARK: -- SHOW PCC / SET PCC

    /// SHOW PCC -- the listener, the port, the network, the name, the
    /// address to give a Cabine, how long it has listened, the line and the
    /// connections.
    func showPCC() -> String {
        guard let link else { return tr("pcc.err.nolink") }
        // The picture as it stands, not as the last scan left it.
        link.refresh()
        var s = "\n  " + String(format: tr("pcc.dcl.title"), Self.productName, nodeName) + "\n\n"
        s += field("pcc.label.listener", PCCText.listener(link.listener, tr))
        s += field("pcc.label.network", tr(link.isLAN ? "pcc.lan.on" : "pcc.lan.off"))
        s += field("pcc.label.name", link.name)
        if let address = link.address {
            s += field("pcc.label.address", String(format: tr("pcc.address.fmt"), address.host, Int(address.port)))
        }
        if let since = link.listeningSince {
            s += field("pcc.label.uptime", uptimeString(from: since, to: Date()))
        }
        guard let snapshot = link.snapshot else {
            // Not running: what it is set to do when it is.
            s += field("pcc.label.headway", "\(Int(link.headwayS)) s")
            if link.listener == .disabled { s += "\n  " + tr("pcc.hint.disabled") + "\n" }
            return s
        }
        if let line = snapshot.line {
            s += field("pcc.label.line", String(format: tr("pcc.dcl.line.id"), line.identity.name, line.identity.id,
                                                line.identity.rev))
        } else {
            s += field("pcc.label.line", tr("pcc.line.none"))
        }
        let inService = snapshot.sessions.filter { $0.standing == .inService }.count
        let onLine = snapshot.sessions.filter { $0.standing == .onLine }.count
        s += field("pcc.label.connections", String(format: tr("pcc.dcl.connections"), snapshot.sessions.count, inService,
                                                   onLine, snapshot.sessions.count - inService - onLine))
        s += field("pcc.label.library", snapshot.library.count == 1 ? tr("pcc.dcl.library.one")
                   : String(format: tr("pcc.dcl.library"), snapshot.library.count))
        if link.isSlowToStart {
            s += "\n  " + tr(link.isLAN ? "pcc.hint.slow.lan" : "pcc.hint.slow") + "\n"
        }
        if case .failed = link.listener { s += "\n  " + tr("pcc.hint.failed") + "\n" }
        return s
    }

    /// SET PCC /ENABLE | /DISABLE   /LAN=ON|OFF   /NAME="name"
    ///
    /// Qualifiers compose, and are carried out in that order whatever the
    /// order they were typed in, /DISABLE last.
    func setPCC(_ cmd: Parsed) -> String {
        guard let link else { return tr("pcc.err.nolink") }
        let enable = cmd.hasQualifier("ENABLE", min: 3), disable = cmd.hasQualifier("DISABLE", min: 3)
        let lan = cmd.hasQualifier("LAN", min: 3), name = cmd.hasQualifier("NAME", min: 3)
        guard enable || disable || lan || name else {
            fail("PCC-W-MISSQUAL", "%X000080E0")
            return tr("pcc.set.pcc.missqual") + "\n"
        }
        if dryRun { return dryRunLine(cmd) }
        var lines: [String] = []
        if enable {
            lines.append(pccMessage(link.setEnabled(true), tr("pcc.set.enabled")))
        }
        if lan, let on = onOff(cmd, "LAN", &lines) {
            lines.append(pccMessage(link.setLAN(on), tr(on ? "pcc.set.lan.on" : "pcc.set.lan.off")))
        }
        if name {
            let outcome = link.setName(cmd.qualifierValue("NAME", min: 3) ?? "")
            lines.append(pccMessage(outcome, String(format: tr("pcc.set.name"), link.name)))
        }
        if disable {
            lines.append(pccMessage(link.setEnabled(false), tr("pcc.set.disabled")))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: -- SHOW LINES / SHOW LINE / SET LINE

    /// SHOW LINES -- the library: every line the PCC holds, and which one
    /// it is on.
    func showLines() -> String {
        guard let link else { return tr("pcc.err.nolink") }
        link.refresh()
        guard let snapshot = link.snapshot else { return "\n" + noLineText(link) }
        let on = snapshot.line?.identity
        var s = "\n  " + String(format: tr("pcc.dcl.lines.title"), snapshot.library.count) + "  "
            + (on.map { String(format: tr("pcc.dcl.lines.on"), $0.name) } ?? tr("pcc.dcl.lines.onnone")) + "\n"
        s += "     " + left(tr("pcc.col.id"), 6) + " " + left(tr("pcc.col.name"), 16) + " " + left(tr("pcc.col.rev"), 16)
            + " " + right(tr("pcc.col.stations"), 8) + " " + right(tr("pcc.col.length"), 10)
            + "  " + left(tr("pcc.col.source"), 7) + " " + tr("pcc.col.ends") + "\n"
        s += "     ------ ---------------- ---------------- -------- ----------  ------- "
            + String(repeating: "-", count: 40) + "\n"
        for held in snapshot.library {
            let mark = on.map { $0.isSameLine(as: held.identity) } == true ? "*" : " "
            s += "   \(mark) " + left(held.identity.id, 6) + " " + left(held.identity.name, 16) + " "
                + left(held.identity.rev, 16) + " " + right("\(held.stationCount)", 8) + " "
                + right(PCCText.kilometres(held.lengthM), 10) + "  "
                + left(tr(held.hasSource ? "pcc.word.yes" : "pcc.word.no"), 7) + " "
                + held.firstStation + " -- " + held.lastStation + "\n"
        }
        if snapshot.library.isEmpty { s += "     " + tr("pcc.dcl.lines.none") + "\n" }
        s += "\n  " + tr("pcc.dcl.lines.hint") + "\n"
        return s
    }

    /// SHOW LINE -- the line the PCC is on. /STATIONS lists every station
    /// with its stop on each track, /SOURCE says where the line's data came
    /// from, with the credits its licences ask for.
    func showLine(_ cmd: Parsed) -> String {
        guard let link else { return tr("pcc.err.nolink") }
        link.refresh()
        guard let snapshot = link.snapshot, let line = snapshot.line else { return "\n" + noLineText(link) }
        let identity = line.identity
        var s = "\n  " + String(format: tr("pcc.dcl.line.id"), identity.name, identity.id, identity.rev) + "\n"
        let stations = cmd.hasQualifier("STATIONS", min: 3), source = cmd.hasQualifier("SOURCE", min: 3)

        if stations {
            s += "  " + tr("pcc.dcl.stations.title") + "\n"
            s += "    " + right(tr("pcc.col.no"), 3) + "  " + left(tr("pcc.col.station"), 32) + right(tr("pcc.col.stop1"), 12)
                + right(tr("pcc.col.stop2"), 12) + "\n"
            s += "    ---  " + String(repeating: "-", count: 30) + "  " + "  ----------  ----------\n"
            let stops1 = line.track(1).stopsM, stops2 = line.track(2).stopsM
            for (index, name) in line.stationNames.enumerated() {
                // A stop of track 2 is the station counted from the other end.
                let mirrored = line.stationCount - 1 - index
                s += "    " + right("\(index + 1)", 3) + "  " + left(name, 32)
                    + right(String(format: "%.1f m", stops1[index]), 12)
                    + right(String(format: "%.1f m", stops2[mirrored]), 12) + "\n"
            }
        }
        if source {
            s += "  " + tr("pcc.credits.title") + "\n"
            for credit in PCCText.credits(link.credits[identity], tr) { s += "    " + credit + "\n" }
            let held = snapshot.library.first { $0.identity.isSameLine(as: identity) }
            s += "  " + tr(held?.hasSource == true ? "pcc.dcl.source.yes" : "pcc.dcl.source.no") + "\n"
        }
        if stations || source { return s }

        s += field("pcc.label.track", String(format: tr("pcc.dcl.track"), line.lengthM, line.stationCount))
        s += field("pcc.label.ends", (line.stationNames.first ?? "") + " -- " + (line.stationNames.last ?? ""))
        s += field("pcc.label.service", tr(snapshot.inService ? "pcc.word.on" : "pcc.word.off")
                   + "   " + labelled("pcc.label.mode") + PCCText.mode(snapshot.mode, tr)
                   + "   " + labelled("pcc.label.clock") + PCCText.clock(snapshot.clockS))
        s += field("pcc.label.headway", "\(Int(snapshot.headwayS)) s   " + labelled("pcc.label.fleet")
                   + PCCText.fleet(snapshot.fleetSize, tr) + "   " + labelled("pcc.label.lap")
                   + PCCText.duration(snapshot.lapTimeS))
        let cabs = snapshot.cabs.count
        s += field("pcc.label.trains", String(format: tr("pcc.dcl.trains"), snapshot.rames.count,
                                              snapshot.rames.count - cabs, snapshot.automaticTarget, cabs))
        s += field("pcc.label.stock", String(format: tr("pcc.dcl.stock"), line.train.lengthM, line.train.maxSpeedMS * 3.6,
                                             line.train.capacity))
        s += "\n  " + tr("pcc.dcl.line.hint") + "\n"
        return s
    }

    /// SET LINE /LOAD=id | /CLOSE | /REREAD
    ///          /SERVICE=ON|OFF   /EMERGENCY=ON|OFF   /HEADWAY=seconds
    ///          /RAMES=n|AUTO
    ///
    /// Which line first, then its orders, in that order whatever the order
    /// they were typed in. FR: /CHARGER, /FERMER, /RELIRE, /URGENCE,
    /// /INTERVALLE.
    func setLine(_ cmd: Parsed) -> String {
        guard let link else { return tr("pcc.err.nolink") }
        let loadName = locQual(en: "LOAD", fr: "CHARGER"), closeName = locQual(en: "CLOSE", fr: "FERMER")
        let rereadName = locQual(en: "REREAD", fr: "RELIRE")
        let emergencyName = locQual(en: "EMERGENCY", fr: "URGENCE")
        let headwayName = locQual(en: "HEADWAY", fr: "INTERVALLE")
        let load = cmd.hasQualifier(loadName, min: 3), close = cmd.hasQualifier(closeName, min: 3)
        let reread = cmd.hasQualifier(rereadName, min: 3)
        let service = cmd.hasQualifier("SERVICE", min: 4), emergency = cmd.hasQualifier(emergencyName, min: 4)
        let headway = cmd.hasQualifier(headwayName, min: 3), rames = cmd.hasQualifier("RAMES", min: 3)
        guard load || close || reread || service || emergency || headway || rames else {
            fail("PCC-W-MISSQUAL", "%X000080E0")
            return tr("pcc.set.line.missqual") + "\n"
        }
        if dryRun { return dryRunLine(cmd) }
        var lines: [String] = []

        if reread {
            lines.append(pccMessage(link.rereadLibrary(), rereadMessage()))
        }
        if close {
            lines.append(pccMessage(link.closeLine(), tr("pcc.set.close")))
        }
        if load {
            let id = cmd.qualifierValue(loadName, min: 3) ?? ""
            let outcome = link.takeUp(line: id)
            lines.append(pccMessage(outcome, String(format: tr("pcc.set.load"), link.snapshot?.line?.identity.name ?? id)))
        }
        if service, let on = onOff(cmd, "SERVICE", min: 4, &lines) {
            lines.append(pccMessage(link.setService(on), tr(on ? "pcc.set.service.on" : "pcc.set.service.off")))
        }
        if emergency, let on = onOff(cmd, emergencyName, min: 4, &lines) {
            lines.append(pccMessage(link.setEmergencyStop(on), tr(on ? "pcc.set.emergency.on" : "pcc.set.emergency.off")))
        }
        if headway {
            if let seconds = cmd.qualifierValue(headwayName, min: 3).flatMap({ Double($0) }) {
                lines.append(pccMessage(link.setHeadway(seconds), String(format: tr("pcc.set.headway"), Int(seconds))))
            } else {
                lines.append(pccMessage(.refused(.headwayOutOfRange), ""))
            }
        }
        if rames {
            let value = cmd.qualifierValue("RAMES", min: 3)?.uppercased() ?? ""
            if value == "AUTO" {
                lines.append(pccMessage(link.setFleetSize(nil), tr("pcc.set.fleet.auto")))
            } else if let size = Int(value) {
                lines.append(pccMessage(link.setFleetSize(size), String(format: tr("pcc.set.fleet"), size)))
            } else {
                lines.append(pccMessage(.refused(.fleetOutOfRange), ""))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: -- SHOW RAMES / SHOW RAME / SET RAME

    /// SHOW RAMES -- every train of the line, cabs and automatic rames
    /// alike, by number.
    func showRames() -> String {
        guard let link else { return tr("pcc.err.nolink") }
        link.refresh()
        guard let snapshot = link.snapshot, let line = snapshot.line else { return "\n" + noLineText(link) }
        var s = "\n  " + String(format: tr("pcc.dcl.rames.title"), line.identity.name, PCCText.clock(snapshot.clockS)) + "\n"
        s += "    " + left(tr("pcc.col.no"), 2) + "  " + left(tr("pcc.col.kind"), 6)
            + "  " + right(tr("pcc.col.track"), 4) + "  " + right(tr("pcc.col.position"), 10)
            + "  " + right(tr("pcc.col.speed"), 9) + "  " + left(tr("pcc.col.state"), 12)
            + "  " + left(tr("pcc.col.doors"), 9) + "  " + tr("pcc.col.station") + "\n"
        s += "    --  ------  ----  ----------  ---------  ------------  ---------  ----------------------\n"
        for rame in snapshot.rames.sorted(by: { $0.number < $1.number }) {
            s += "    " + PCCText.number(rame.number) + "  " + left(PCCText.kind(rame.kind, tr), 6)
                + "  " + right("\(rame.track)", 4) + "  " + right(String(format: "%.1f m", rame.uM), 10)
                + "  " + right(String(format: "%.1f m/s", rame.speedMS), 9)
                + "  " + left(PCCText.phase(rame.phase, tr), 12)
                + "  " + left(PCCText.doors(open: rame.doors, tr), 9)
                + "  " + (rame.stationName ?? "--")
            for flag in PCCText.flags(of: rame, tr) { s += "   [\(flag)]" }
            s += "\n"
        }
        if snapshot.rames.isEmpty { s += "    " + tr("pcc.rames.none") + "\n" }
        return s
    }

    /// SHOW RAME n -- one train in full, with all that is known of its cab
    /// if it has one. With no number it lists them all.
    func showRame(_ cmd: Parsed) -> String {
        guard let word = cmd.positional.dropFirst().first else { return showRames() }
        guard let link else { return tr("pcc.err.nolink") }
        link.refresh()
        guard let snapshot = link.snapshot, let line = snapshot.line else { return "\n" + noLineText(link) }
        guard let number = Int(word), let rame = snapshot.rame(numbered: number) else {
            fail("PCC-W-NOSUCHRAME", "%X000080A4")
            return String(format: tr("pcc.err.nosuchrame"), word) + "\n"
        }
        var s = "\n  " + String(format: tr("pcc.dcl.rame.title"), PCCText.number(rame.number), line.identity.name,
                                PCCText.clock(snapshot.clockS)) + "\n"
        s += field("pcc.label.kind", PCCText.kind(rame.kind, tr))
        s += field("pcc.label.track", "\(rame.track)   " + labelled("pcc.label.position")
                   + String(format: "%.1f m", rame.uM))
        s += field("pcc.label.speed", String(format: "%.1f m/s  (%.1f km/h)   ", rame.speedMS, rame.speedMS * 3.6)
                   + labelled("pcc.label.acceleration") + String(format: "%+.2f m/s²", rame.accelerationMS2))
        s += field("pcc.label.state", PCCText.phase(rame.phase, tr) + "   " + labelled("pcc.label.doors")
                   + PCCText.doors(of: rame, tr))
        s += field("pcc.label.station", PCCText.station(of: rame, tr))
        let flags = PCCText.flags(of: rame, tr)
        s += field("pcc.label.orders", flags.isEmpty ? tr("pcc.form.none") : flags.joined(separator: ", "))
        guard let cab = rame.cab else { return s }

        s += "\n"
        s += field("pcc.label.cab", cab.name + "  (\(cab.cabID))")
        if let session = cab.session, let connection = snapshot.sessions.first(where: { $0.id == session }) {
            var from = "\(connection.id)  \(connection.peer)"
            if let app = connection.app { from += "  \(app)" + (connection.appVersion.map { " \($0)" } ?? "") }
            s += field("pcc.label.connection", from)
        } else {
            s += field("pcc.label.connection", tr("pcc.connection.gone"))
        }
        s += field("pcc.label.link", PCCText.link(cab, tr))
        s += field("pcc.label.driving", (cab.mode?.rawValue ?? "--") + "   " + labelled("pcc.label.autopilot")
                   + PCCText.autopilot(cab, tr))
        s += field("pcc.label.pax", PCCText.passengers(cab, capacity: line.train.capacity) + "   "
                   + labelled("pcc.label.timetable") + PCCText.deviation(cab, tr))
        s += field("pcc.label.eb", PCCText.emergencyBrake(cab, tr))
        s += field("pcc.label.authority", cab.authority.map { PCCText.authority($0, nose: rame.uM, tr) }
                   ?? tr("pcc.authority.none"))
        s += field("pcc.label.report", cab.lastReport.map { PCCText.report($0, tr) } ?? tr("pcc.report.never"))
        return s
    }

    /// SET RAME number /HOLD | /RELEASE   /BRAKE | /UNBRAKE
    ///                 /MESSAGE="text"   /CALL
    ///
    /// Qualifiers compose, and are carried out in that order: one line can
    /// hold a rame and tell its driver why. FR: /RETENIR, /LIBERER,
    /// /FREINER, /DEFREINER, /APPELER.
    func setRame(_ cmd: Parsed) -> String {
        guard let link else { return tr("pcc.err.nolink") }
        let hold = cmd.hasQualifier(locQual(en: "HOLD", fr: "RETENIR"), min: 3)
        let release = cmd.hasQualifier(locQual(en: "RELEASE", fr: "LIBERER"), min: 3)
        let brake = cmd.hasQualifier(locQual(en: "BRAKE", fr: "FREINER"), min: 3)
        let unbrake = cmd.hasQualifier(locQual(en: "UNBRAKE", fr: "DEFREINER"), min: 3)
        let message = cmd.hasQualifier("MESSAGE", min: 3)
        let call = cmd.hasQualifier(locQual(en: "CALL", fr: "APPELER"), min: 3)
        guard let word = cmd.positional.dropFirst().first, let rame = Int(word) else {
            fail("PCC-W-NORAME", "%X000080E8")
            return tr("pcc.set.rame.needrame") + "\n"
        }
        guard hold || release || brake || unbrake || message || call else {
            fail("PCC-W-MISSQUAL", "%X000080E0")
            return tr("pcc.set.rame.missqual") + "\n"
        }
        if dryRun { return dryRunLine(cmd) }
        let number = PCCText.number(rame)
        var lines: [String] = []
        if hold {
            lines.append(pccMessage(link.hold(rame: rame, true), String(format: tr("pcc.set.hold"), number)))
        }
        if release {
            lines.append(pccMessage(link.hold(rame: rame, false), String(format: tr("pcc.set.release"), number)))
        }
        if brake {
            lines.append(pccMessage(link.emergencyBrake(rame: rame, true), String(format: tr("pcc.set.brake"), number)))
        }
        if unbrake {
            lines.append(pccMessage(link.emergencyBrake(rame: rame, false), String(format: tr("pcc.set.unbrake"), number)))
        }
        if message {
            lines.append(pccMessage(link.message(rame: rame, cmd.qualifierValue("MESSAGE", min: 3) ?? ""),
                                    String(format: tr("pcc.set.message"), number)))
        }
        if call {
            lines.append(pccMessage(link.call(rame: rame), String(format: tr("pcc.set.call"), number)))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: -- START / STOP

    /// START LINE            line service on
    /// START RAME number     releases the emergency brake of one train
    func startCmd(_ cmd: Parsed) -> String {
        startOrStop(cmd, start: true)
    }

    /// STOP LINE             line service off
    /// STOP RAME number      brakes one train to a stand
    func stopCmd(_ cmd: Parsed) -> String {
        startOrStop(cmd, start: false)
    }

    private func startOrStop(_ cmd: Parsed, start: Bool) -> String {
        guard let link else { return tr("pcc.err.nolink") }
        guard let first = cmd.positional.first else {
            fail("PCC-W-MISSPARM", "%X000080F0")
            return tr(start ? "pcc.start.usage" : "pcc.stop.usage") + "\n"
        }
        if matchesLoc(first, en: "LINE", fr: "LIGNE", min: 3) {
            if dryRun { return dryRunLine(cmd) }
            return pccMessage(link.setService(start), tr(start ? "pcc.set.service.on" : "pcc.set.service.off")) + "\n"
        }
        guard matches(first, "RAME", min: 4), let word = cmd.positional.dropFirst().first, let rame = Int(word) else {
            fail("PCC-W-MISSPARM", "%X000080F0")
            return tr(start ? "pcc.start.usage" : "pcc.stop.usage") + "\n"
        }
        if dryRun { return dryRunLine(cmd) }
        return pccMessage(link.emergencyBrake(rame: rame, !start),
                          String(format: tr(start ? "pcc.set.unbrake" : "pcc.set.brake"), PCCText.number(rame))) + "\n"
    }

    // MARK: -- SHOW CABS / SHOW CONNECTIONS / SHOW JOURNAL

    /// SHOW CABS -- the cabs in service, with link, driving mode and
    /// authority.
    func showCabs() -> String {
        guard let link else { return tr("pcc.err.nolink") }
        link.refresh()
        guard let snapshot = link.snapshot, let line = snapshot.line else { return "\n" + noLineText(link) }
        let cabs = snapshot.cabs.sorted { $0.number < $1.number }
        var s = "\n  " + String(format: tr("pcc.dcl.cabs.title"), line.identity.name, cabs.count) + "\n"
        guard !cabs.isEmpty else { return s + "    " + tr("pcc.cabs.none") + "\n" }
        s += "    " + left(tr("pcc.col.no"), 2) + "  " + left(tr("pcc.col.cab"), 18) + "  " + left(tr("pcc.col.link"), 8)
            + "  " + right(tr("pcc.col.roundtrip"), 7) + "  " + left(tr("pcc.col.mode"), 4)
            + "  " + left(tr("pcc.col.autopilot"), 9) + "  " + right(tr("pcc.col.track"), 4)
            + "  " + right(tr("pcc.col.position"), 10) + "  " + right(tr("pcc.col.speed"), 9)
            + "  " + tr("pcc.col.authority") + "\n"
        s += "    --  ------------------  --------  -------  ----  ---------  ----  ----------  ---------  "
            + String(repeating: "-", count: 34) + "\n"
        for rame in cabs {
            guard let cab = rame.cab else { continue }
            s += "    " + PCCText.number(rame.number) + "  " + left(shortened(cab.name, to: 18), 18)
                + "  " + left(PCCText.link(cab.link, tr), 8)
                + "  " + right(cab.roundTripS.map { String(format: "%.0f ms", $0 * 1_000) } ?? "--", 7)
                + "  " + left(cab.mode?.rawValue ?? "--", 4)
                + "  " + left(PCCText.autopilot(cab, tr), 9)
                + "  " + right("\(rame.track)", 4)
                + "  " + right(String(format: "%.1f m", rame.uM), 10)
                + "  " + right(String(format: "%.1f m/s", rame.speedMS), 9)
                + "  " + (cab.authority.map { PCCText.authority($0, nose: rame.uM, tr) } ?? tr("pcc.authority.none"))
            for flag in PCCText.flags(of: rame, tr) { s += "   [\(flag)]" }
            if cab.emergencyBrake { s += "   [" + tr("pcc.label.eb") + " " + PCCText.emergencyBrake(cab, tr) + "]" }
            s += "\n"
        }
        s += "\n  " + tr("pcc.dcl.cabs.hint") + "\n"
        return s
    }

    /// SHOW CONNECTIONS -- every connection, whatever its standing.
    func showPCCConnections() -> String {
        guard let link else { return tr("pcc.err.nolink") }
        link.refresh()
        guard let snapshot = link.snapshot else { return "\n" + noLineText(link) }
        var s = "\n  " + String(format: tr("pcc.dcl.connections.title"), snapshot.sessions.count,
                                PCCText.listener(link.listener, tr)) + "\n"
        if snapshot.sessions.isEmpty { s += "    " + tr("pcc.connections.none") + "\n" }
        for session in snapshot.sessions {
            let connection = PCCText.connection(session, tr)
            s += "    \(connection.who)\n        \(connection.detail)\n"
        }
        return s
    }

    /// SHOW JOURNAL [/LAST=n] -- the last things that happened, in the
    /// order they happened, by the line's clock.
    func showJournal(_ cmd: Parsed) -> String {
        guard let link else { return tr("pcc.err.nolink") }
        link.refresh()
        var last = 20
        if cmd.hasQualifier("LAST", min: 3) {
            guard let n = cmd.qualifierValue("LAST", min: 3).flatMap({ Int($0) }), n >= 1 else {
                fail("PCC-W-IVVALUE", "%X000080D8")
                return tr("pcc.dcl.journal.last") + "\n"
            }
            last = n
        }
        let shown = link.journal.suffix(last)
        var s = "\n  " + String(format: tr("pcc.dcl.journal.title"), shown.count, link.journal.count) + "\n"
        if shown.isEmpty { s += "    " + tr("pcc.journal.none") + "\n" }
        for line in shown { s += "    " + PCCText.journal(line, tr) + "\n" }
        return s
    }

    // MARK: -- what a command procedure reads of the PCC

    /// F$PCC(item): the PCC and its line, for a command procedure. The
    /// values are identifiers, the same in both languages: TRUE and FALSE,
    /// numbers, a line's id, the words of the wire in capitals.
    ///
    ///     LISTENING  PORT  NAME  LAN  LINE  LINE_NAME  LINES  MODE
    ///     SERVICE  EMERGENCY  CLOCK  HEADWAY  RAMES  FIRST_RAME  CABS
    ///     FIRST_CAB  CONNECTIONS  ALARMS  UNACKED
    func pccLexical(_ item: String) -> String {
        guard let link else { return "" }
        link.refresh()
        let snapshot = link.snapshot
        func flag(_ value: Bool) -> String { value ? "TRUE" : "FALSE" }
        switch item.uppercased() {
        case "LISTENING":
            if case .listening = link.listener { return "TRUE" }
            return "FALSE"
        case "PORT":        return link.address.map { "\($0.port)" } ?? "0"
        case "NAME":        return link.name
        case "LAN":         return flag(link.isLAN)
        case "LINE":        return snapshot?.line?.identity.id ?? ""
        case "LINE_NAME":   return snapshot?.line?.identity.name ?? ""
        case "LINES":       return "\(snapshot?.library.count ?? 0)"
        case "MODE":        return snapshot?.line == nil ? "" : (snapshot?.mode.rawValue.uppercased() ?? "")
        case "SERVICE":     return flag(snapshot?.line != nil && snapshot?.inService == true)
        case "EMERGENCY":   return flag(snapshot?.emergencyStop == true)
        case "CLOCK":       return snapshot?.line == nil ? "" : PCCText.clock(snapshot?.clockS ?? 0)
        case "HEADWAY":     return "\(Int(snapshot?.headwayS ?? link.headwayS))"
        case "RAMES":       return "\(snapshot?.rames.count ?? 0)"
        case "FIRST_RAME":  return "\(snapshot?.rames.map(\.number).min() ?? 0)"
        case "CABS":        return "\(snapshot?.cabs.count ?? 0)"
        case "FIRST_CAB":   return "\(snapshot?.cabs.map(\.number).min() ?? 0)"
        case "CONNECTIONS": return "\(snapshot?.sessions.count ?? 0)"
        case "ALARMS":      return "\(world?.activeAlarms.count ?? 0)"
        case "UNACKED":     return "\(world?.unacknowledgedAlarmCount ?? 0)"
        default:            return ""
        }
    }

    /// F$RAME(number, item): one train of the line, for a command
    /// procedure; empty when there is no such train, but for EXISTS.
    ///
    ///     EXISTS  KIND  IS_CAB  TRACK  POSITION  SPEED  PHASE  STATION
    ///     HELD  BRAKED  CAB  LINK  MODE  AUTOMATIC  EB
    func rameLexical(_ number: String, _ item: String) -> String {
        guard let link else { return "" }
        link.refresh()
        func flag(_ value: Bool) -> String { value ? "TRUE" : "FALSE" }
        let rame = Int(number).flatMap { link.snapshot?.rame(numbered: $0) }
        let what = item.uppercased()
        if what == "EXISTS" { return flag(rame != nil) }
        guard let rame else { return "" }
        switch what {
        case "KIND":      return rame.kind.rawValue.uppercased()
        case "IS_CAB":    return flag(rame.cab != nil)
        case "TRACK":     return "\(rame.track)"
        case "POSITION":  return "\(Int(rame.uM.rounded()))"
        case "SPEED":     return "\(Int((rame.speedMS * 3.6).rounded()))"
        case "PHASE":     return rame.phase.rawValue.uppercased()
        case "STATION":   return rame.stationName ?? ""
        case "HELD":      return flag(rame.held)
        case "BRAKED":    return flag(rame.braked)
        case "CAB":       return rame.cab?.name ?? ""
        case "LINK":      return rame.cab.map { $0.link.rawValue.uppercased() } ?? ""
        case "MODE":      return rame.cab?.mode?.rawValue ?? ""
        case "AUTOMATIC": return rame.cab.map { flag($0.automatic == true) } ?? ""
        case "EB":        return rame.cab.map { flag($0.emergencyBrake) } ?? flag(rame.braked)
        default:          return ""
        }
    }

    // MARK: -- the PCC as OpenVMS processes

    /// One of the PCC's processes, as SHOW SYSTEM and MONITOR show it.
    struct PCCProcess {
        let pid: String
        let name: String
        /// LEF, HIB or COM, from what the PCC is doing.
        let state: String
        /// Its share of the processor that is busy.
        let share: Double
    }

    /// The PCC as the processes an OpenVMS node would run it in: the
    /// engine, the listener, the alarm server, and the link of each cab in
    /// service. Their states are the PCC's: the engine computes while a
    /// line runs, the listener waits for a cab, a cab's link computes while
    /// its cab is heard.
    func pccProcesses() -> [PCCProcess] {
        let snapshot = link?.snapshot
        var listening = false
        if case .listening? = link?.listener { listening = true }
        var processes = [
            PCCProcess(pid: "00000403", name: "PCC_ENGINE", state: snapshot?.line == nil ? "HIB" : "COM", share: 0.42),
            PCCProcess(pid: "00000404", name: "PCC_LISTENER", state: listening ? "LEF" : "HIB", share: 0.04),
            PCCProcess(pid: "00000405", name: "PCC_SCADA", state: (world?.activeAlarms.isEmpty ?? true) ? "HIB" : "LEF",
                       share: 0.03),
        ]
        for (index, rame) in (snapshot?.cabs ?? []).sorted(by: { $0.number < $1.number }).prefix(8).enumerated() {
            processes.append(PCCProcess(pid: String(format: "%08X", 0x040A + index),
                                        name: "CAB_\(PCCText.number(rame.number))_LINK",
                                        state: rame.cab?.link == .live ? "COM" : "LEF", share: 0.06))
        }
        return processes
    }
}

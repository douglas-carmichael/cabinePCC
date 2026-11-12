import Foundation
import CabinePCCKit

// MONITOR LINE | CABS | RAMES | CONNECTIONS -- the PCC's live displays.
//
// Each is a frame of 24 pasteboard rows (DCLPasteboard.swift): the product
// banner and the line's status row, one or more bordered virtual displays,
// a message row and the key-legend status bar. They read the picture the
// link publishes (PCCLink.snapshot) and nothing else, so what they show is
// what the engine is doing.
//
//   LINE          the line as a mimic board: track 1 above running left to
//                 right, track 2 below running right to left, the stations
//                 ticked and named, every train where it is, with the
//                 alarms and a summary of the cabs.
//   CABS          every cab in service, four rows each.
//   RAMES         every train of the line.
//   CONNECTIONS   every connection, whatever its standing.
extension DCLEngine {

    /// The name of a PCC monitor, for its banner and its messages.
    func monitorTitle(_ cls: String) -> String {
        switch cls {
        case Self.pccLineClass:  return tr("pcc.mon.title.line")
        case Self.pccCabsClass:  return tr("pcc.mon.title.cabs")
        case Self.pccRamesClass: return tr("pcc.mon.title.rames")
        default:                 return tr("pcc.mon.title.connections")
        }
    }

    /// One frame of a PCC monitor: 24 pasteboard rows.
    func pccMonitorRows(_ cls: String, elapsed: String) -> [String] {
        var rows = pccHeaderRows(title: monitorTitle(cls))
        // Rows left for the displays, between the header and the footer.
        let room = Self.screenRows - rows.count - 2
        switch cls {
        case Self.pccLineClass:  rows += lineMonitorDisplays()
        case Self.pccCabsClass:  rows += cabsMonitorDisplay(rows: room)
        case Self.pccRamesClass: rows += ramesMonitorDisplay(rows: room)
        default:                 rows += connectionsMonitorDisplay(rows: room)
        }
        // A fixed height, so that the pasteboard never shifts.
        while rows.count < Self.screenRows - 2 { rows.append("") }
        return Array(rows.prefix(Self.screenRows - 2)) + pccFooterRows(elapsed: elapsed)
    }

    /// The page of a table that is on show: a table longer than its display
    /// turns its pages by itself, one every five seconds.
    private func page<Item>(of items: [Item], size: Int) -> (items: ArraySlice<Item>, number: Int, count: Int) {
        let count = max(1, (items.count + size - 1) / size)
        let number = Int(Date().timeIntervalSince(monitorStartedAt) / 5) % count
        let start = number * size
        return (items[min(start, items.count)..<min(start + size, items.count)], number + 1, count)
    }

    /// The label of a table: how many there are, and which are on show when
    /// they do not all fit.
    private func tableLabel(_ key: String, total: Int, shown: ArraySlice<some Any>, page: Int, pages: Int) -> String {
        guard pages > 1 else { return String(format: tr(key), total) }
        return String(format: tr(key + ".part"), shown.startIndex + 1, shown.endIndex, total, page, pages)
    }

    // MARK: -- MONITOR LINE

    /// Columns of the mimic board's tracks.
    private static let mimicCols = 72

    private func lineMonitorDisplays() -> [String] {
        guard let snapshot = link?.snapshot, let line = snapshot.line else {
            return smgDisplay(label: tr("pcc.mon.lbl.line.none"), rows: ["", " " + tr("pcc.noline"), ""])
                + pccAlarmDisplay()
        }
        let label = String(format: tr("pcc.line.fmt"), line.identity.name, line.lengthM / 1_000, line.stationCount)
        var rows = smgDisplay(label: label, rows: lineMimicRows(snapshot, line))
        rows += pccAlarmDisplay()

        // The cabs, in a few words each.
        let cabs = snapshot.cabs.sorted { $0.number < $1.number }
        let widths = [4, 14, 8, 5, 7, 13]
        let heads = ["pcc.col.no", "pcc.col.cab", "pcc.col.link", "pcc.col.mode", "pcc.col.kmh", "pcc.col.state"]
        var header = " "
        for (key, width) in zip(heads, widths) { header += smgCol(tr(key), width) }
        header += tr("pcc.col.authority")
        var table = [reversed(fit(header, Self.screenWidth - 2))]
        let size = 7
        let shown = page(of: cabs, size: size)
        if cabs.isEmpty { table.append(" " + tr("pcc.cabs.none")) }
        for rame in shown.items {
            guard let cab = rame.cab else { continue }
            var row = " " + smgCol(PCCText.number(rame.number), widths[0])
            row += smgCol(cab.name, widths[1])
            row += smgCol(PCCText.link(cab.link, tr), widths[2])
            row += smgCol(cab.mode?.rawValue ?? "--", widths[3])
            row += smgColRight(String(format: "%.1f", rame.speedMS * 3.6), widths[4])
            let state = smgCol(PCCText.phase(rame.phase, tr), widths[5])
            row += rame.phase == .emergency && blinkOn ? reversed(state) : state
            row += cab.authority.map { String(format: tr("pcc.mon.sum.authority"), max($0.endM - rame.uM, 0), shortReason($0)) }
                ?? tr("pcc.authority.none")
            table.append(row)
        }
        while table.count < size + 1 { table.append("") }
        rows += smgDisplay(label: tableLabel("pcc.mon.lbl.cabs", total: cabs.count, shown: shown.items,
                                             page: shown.number, pages: shown.count), rows: table)
        return rows
    }

    /// What ends a cab's authority, in a word or two.
    private func shortReason(_ authority: CabineWire.Authority) -> String {
        if authority.reason == .train, let rame = authority.rame {
            return String(format: tr("pcc.reason.short.train"), PCCText.number(rame))
        }
        let key = "pcc.reason.short.\(authority.reason.rawValue.lowercased())"
        let text = tr(key)
        return text == key ? authority.reason.rawValue : text
    }

    /// The mimic board: five rows. Track 1 runs left to right on the upper
    /// rail and track 2 right to left on the lower, so that a station is at
    /// one place on both and the two ends are the turn-backs. A train is its
    /// number and a mark at its nose: `>` an automatic rame, `»` a cab (in
    /// reverse video), `H` a train that is held, `!` one that is braked
    /// (flashing), `·` one that is turning back in a tail; where trains
    /// stand too close for their numbers, the mark alone.
    func lineMimicRows(_ snapshot: CabinePCC.Snapshot, _ line: CabinePCC.Line) -> [String] {
        let cols = Self.mimicCols
        let length = max(line.lengthM, 1)
        func column(_ x: Double) -> Int {
            min(cols - 1, max(0, Int((x / length * Double(cols - 1)).rounded())))
        }

        // Where each station is drawn: the middle of its two platforms.
        let count = line.stationCount
        let stops1 = line.track(1).stopsM, stops2 = line.track(2).stopsM
        let half = line.train.lengthM / 2
        var places: [Int] = []
        for index in 0..<count {
            let one = stops1[index] - half
            let two = length - stops2[count - 1 - index] + half
            places.append(column((one + two) / 2))
        }

        // The rails: double between the two terminus stations, broken in
        // the tails, with a tick at every station.
        let first = places.first ?? 0, last = places.last ?? cols - 1
        var upper = [String](repeating: "═", count: cols)
        var lower = upper
        for c in 0..<cols where c < first || c > last {
            upper[c] = "╌"
            lower[c] = "╌"
        }
        for c in places {
            upper[c] = "╤"
            lower[c] = "╧"
        }

        // The trains. A train is its number and its mark where the board
        // has room for both, and its mark alone where another train
        // stands too close for that: on a long line with a full fleet a
        // column is some hundreds of metres. The trains that are held or
        // braked are placed first, then the cabs, so that those keep their
        // numbers.
        func rank(_ rame: CabinePCC.Rame) -> Int {
            if rame.braked || rame.held || rame.phase == .emergency || rame.phase == .held { return 0 }
            return rame.cab != nil ? 1 : 2
        }
        var taken1 = [Bool](repeating: false, count: cols), taken2 = taken1
        for rame in snapshot.rames.sorted(by: { (rank($0), $0.number) < (rank($1), $1.number) }) {
            let onTrack2 = rame.track == 2
            let nose = column(onTrack2 ? length - rame.uM : rame.uM)
            let mark: String
            if rame.braked || rame.phase == .emergency {
                mark = "!"
            } else if rame.held || rame.phase == .held {
                mark = "H"
            } else if rame.phase == .tail {
                mark = "·"
            } else if rame.cab != nil {
                mark = onTrack2 ? "«" : "»"
            } else {
                mark = onTrack2 ? "<" : ">"
            }
            let number = PCCText.number(rame.number)
            let whole = Array(onTrack2 ? mark + number : number + mark)
            let start = onTrack2 ? nose : nose - (whole.count - 1)
            let taken = onTrack2 ? taken2 : taken1
            let fits = (start..<(start + whole.count)).allSatisfy { (0..<cols).contains($0) && !taken[$0] }
            // Its number and its mark, or its mark alone at its nose.
            let glyph = fits ? whole : Array(mark)
            let from = fits ? start : nose
            var lit = rame.cab != nil
            if mark == "!" && blinkOn { lit.toggle() }
            for (offset, character) in glyph.enumerated() {
                let c = from + offset
                guard (0..<cols).contains(c) else { continue }
                // A mark alone gives way to a number that is already there.
                if !fits && taken[c] { continue }
                let cell = lit ? reversed(String(character)) : String(character)
                if onTrack2 {
                    lower[c] = cell
                    taken2[c] = true
                } else {
                    upper[c] = cell
                    taken1[c] = true
                }
            }
        }

        // The station names: above and below by turns, each at its tick,
        // left out where there is no room for it. The two ends first: they
        // are the names an operator steers by.
        var above = [Character](repeating: " ", count: cols)
        var below = above
        var taken: [(row: Int, range: ClosedRange<Int>)] = []
        let ends = count > 1 ? [0, count - 1] : [0]
        for index in ends + (0..<count).filter({ !ends.contains($0) }) {
            let name = line.stationNames[index]
            let short = name.count > 14 ? String(name.prefix(13)) + "." : name
            // The whole name where there is room for it, above or below;
            // failing that, the name cut short.
            var placed = false
            for label in name == short ? [name] : [name, short] where !placed {
                for row in [index % 2, 1 - index % 2] where !placed {
                    let pointer = row == 0 ? "▼" : "▲"
                    // The pointer stands at the tick, and the name runs on
                    // from it: back from it, at the right-hand edge.
                    var text = Array(pointer + label)
                    var from = places[index]
                    if from + text.count > cols {
                        text = Array(label + pointer)
                        from = places[index] - label.count
                    }
                    guard from >= 0 else { continue }
                    let range = from...(from + text.count)
                    if taken.contains(where: { $0.row == row && $0.range.overlaps(range) }) { continue }
                    taken.append((row, range))
                    for (offset, character) in text.enumerated() where from + offset < cols {
                        if row == 0 { above[from + offset] = character } else { below[from + offset] = character }
                    }
                    placed = true
                }
            }
        }

        let indent = "    "
        return [
            indent + String(above),
            " 1→╭" + upper.joined() + "╮",
            " 2←╰" + lower.joined() + "╯",
            indent + String(below),
            " " + tr("pcc.mon.legend"),
        ]
    }

    // MARK: -- MONITOR CABS

    private func cabsMonitorDisplay(rows room: Int) -> [String] {
        guard let snapshot = link?.snapshot, snapshot.line != nil else {
            return smgDisplay(label: String(format: tr("pcc.mon.lbl.cabs"), 0), rows: ["", " " + tr("pcc.noline"), ""])
        }
        let cabs = snapshot.cabs.sorted { $0.number < $1.number }
        // Four rows a cab, inside the border.
        let size = max(1, (room - 2) / 4)
        let shown = page(of: cabs, size: size)
        var table: [String] = []
        if cabs.isEmpty { table.append(" " + tr("pcc.cabs.none")) }
        let capacity = snapshot.line?.train.capacity
        for rame in shown.items {
            guard let cab = rame.cab else { continue }
            let who = " " + PCCText.number(rame.number) + "  " + smgCol(cab.name, 18)
            let linked: String
            switch cab.link {
            case .live:
                linked = PCCText.link(cab.link, tr) + (cab.roundTripS.map { String(format: " %.0f ms", $0 * 1_000) } ?? "")
            case .silent:
                let silent = PCCText.link(cab.link, tr) + String(format: " %.0f s", cab.linkAgeS)
                linked = blinkOn ? reversed(silent) : silent
            }
            table.append(reversed(who) + " " + String(format: tr("pcc.mon.cab.r1"), linked, cab.mode?.rawValue ?? "--",
                                                      PCCText.autopilot(cab, tr)))
            table.append("     " + String(format: tr("pcc.mon.cab.r2"), rame.track, rame.uM, rame.speedMS * 3.6,
                                          PCCText.phase(rame.phase, tr), PCCText.station(of: rame, tr)))
            // An emergency brake that is applied first, then what the PCC
            // has ordered, then the rest by what matters most to a PCC. A
            // row too long for the screen loses its last items whole.
            let brake = String(format: tr("pcc.mon.cab.eb"), PCCText.emergencyBrake(cab, tr))
            let doors = String(format: tr("pcc.mon.cab.r3"), PCCText.doors(of: rame, tr))
            let flags = PCCText.flags(of: rame, tr).map { "[\($0)]" }
            var items = cab.emergencyBrake ? [blinkOn ? reversed(brake) : brake] + flags + [doors] : flags + [doors, brake]
            items += [PCCText.deviation(cab, tr),
                      String(format: tr("pcc.mon.cab.pax"), PCCText.passengers(cab, capacity: capacity))]
            var third = "     " + (items.first ?? "")
            for item in items.dropFirst() {
                guard visibleWidth(third) + 3 + visibleWidth(item) <= Self.screenWidth - 2 else { break }
                third += "   " + item
            }
            table.append(third)
            table.append("     " + String(format: tr("pcc.mon.cab.r4"),
                                          cab.authority.map { PCCText.authority($0, nose: rame.uM, tr) }
                                              ?? tr("pcc.authority.none")))
        }
        while table.count < room - 2 { table.append("") }
        return smgDisplay(label: tableLabel("pcc.mon.lbl.cabs", total: cabs.count, shown: shown.items,
                                            page: shown.number, pages: shown.count), rows: table)
    }

    // MARK: -- MONITOR RAMES

    private func ramesMonitorDisplay(rows room: Int) -> [String] {
        guard let snapshot = link?.snapshot, snapshot.line != nil else {
            return smgDisplay(label: String(format: tr("pcc.mon.lbl.rames"), 0), rows: ["", " " + tr("pcc.noline"), ""])
        }
        let rames = snapshot.rames.sorted { $0.number < $1.number }
        // Positions to the metre, which is as much as a live table can
        // be read to, so that the station has the room of most names.
        let widths = [3, 7, 5, 9, 6, 13, 9, 4]
        let heads = ["pcc.col.no", "pcc.col.kind", "pcc.col.track", "pcc.col.position", "pcc.col.kmh",
                     "pcc.col.state", "pcc.col.doors", "pcc.col.orders"]
        var header = " "
        for (index, (key, width)) in zip(heads, widths).enumerated() {
            header += index == 3 || index == 4 ? smgColRight(tr(key), width) : smgCol(tr(key), width)
        }
        header += tr("pcc.col.station")
        let stationRoom = Self.screenWidth - 2 - 1 - widths.reduce(0, +)
        var table = [reversed(fit(header, Self.screenWidth - 2))]
        let size = max(1, room - 3)
        let shown = page(of: rames, size: size)
        if rames.isEmpty { table.append(" " + tr("pcc.rames.none")) }
        for rame in shown.items {
            var row = " " + smgCol(PCCText.number(rame.number), widths[0])
            let kind = smgCol(PCCText.kind(rame.kind, tr), widths[1])
            row += rame.cab != nil ? reversed(kind) : kind
            row += smgCol("\(rame.track)", widths[2])
            row += smgColRight(String(format: "%.0f m", rame.uM), widths[3])
            row += smgColRight(String(format: "%.1f", rame.speedMS * 3.6), widths[4])
            let state = smgCol(PCCText.phase(rame.phase, tr), widths[5])
            row += rame.phase == .emergency && blinkOn ? reversed(state) : state
            row += smgCol(PCCText.doors(open: rame.doors, tr), widths[6])
            row += smgCol((rame.held ? "H" : "") + (rame.braked ? "!" : ""), widths[7])
            row += shortened(rame.stationName ?? "--", to: stationRoom)
            table.append(row)
        }
        while table.count < room - 2 { table.append("") }
        return smgDisplay(label: tableLabel("pcc.mon.lbl.rames", total: rames.count, shown: shown.items,
                                            page: shown.number, pages: shown.count), rows: table)
    }

    // MARK: -- MONITOR CONNECTIONS

    private func connectionsMonitorDisplay(rows room: Int) -> [String] {
        guard let link else { return [] }
        // The listener, in a display of its own: how it stands, and the
        // address to give a Cabine.
        let listener = " " + PCCText.listener(link.listener, tr) + " -- " + tr(link.isLAN ? "pcc.lan.on" : "pcc.lan.off")
        let address = link.address.map {
            " " + labelled("pcc.label.address") + String(format: tr("pcc.address.fmt"), $0.host, Int($0.port))
        }
        var rows = smgDisplay(label: link.name, rows: [listener, address ?? ""])

        let sessions = link.snapshot?.sessions ?? []
        let widths = [4, 11, 6, 12, 12, 9, 7]
        let heads = ["pcc.col.session", "pcc.col.standing", "pcc.col.rame", "pcc.col.cab", "pcc.col.line",
                     "pcc.col.heard", "pcc.col.roundtrip"]
        var header = " "
        for (index, (key, width)) in zip(heads, widths).enumerated() {
            header += index >= 5 ? smgColRight(tr(key), width) : smgCol(tr(key), width)
        }
        header += tr("pcc.col.from")
        var table = [reversed(fit(header, Self.screenWidth - 2))]
        let size = max(1, room - rows.count - 3)
        let shown = page(of: sessions, size: size)
        if sessions.isEmpty { table.append(" " + tr("pcc.connections.none")) }
        for session in shown.items {
            var row = " " + smgCol("\(session.id)", widths[0])
            let standingKey = "pcc.standing.short.\(session.standing.rawValue.lowercased())"
            row += smgCol(tr(standingKey), widths[1])
            row += smgCol(session.rame.map(PCCText.number) ?? "--", widths[2])
            row += smgCol(session.name ?? "--", widths[3])
            row += smgCol(session.line.map { "\($0.id) \($0.rev.prefix(8))" } ?? "--", widths[4])
            row += smgColRight(String(format: "%.1f s", max(session.linkAgeS, 0)), widths[5])
            row += smgColRight(session.roundTripS.map { String(format: "%.0f ms", $0 * 1_000) } ?? "--", widths[6])
            // The host, without its port: SHOW CONNECTIONS has the whole.
            let host = session.peer.lastIndex(of: ":").map { String(session.peer[..<$0]) } ?? session.peer
            row += shortened(host, to: Self.screenWidth - 2 - 1 - widths.reduce(0, +))
            table.append(row)
        }
        while table.count < room - rows.count - 2 { table.append("") }
        rows += smgDisplay(label: tableLabel("pcc.mon.lbl.connections", total: sessions.count, shown: shown.items,
                                             page: shown.number, pages: shown.count), rows: table)
        return rows
    }
}

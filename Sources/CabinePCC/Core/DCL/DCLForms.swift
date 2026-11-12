import Foundation
import CabinePCCKit

// RUN RAME_DIR and RUN LIGNE_DIR -- the PCC's two forms, presented as
// simulated DECforms applications (the way a real VMS shop would ship an
// operator's form on top of FMS/DECforms): a scrolling list on the left
// with a cursor bar, the selected record on the right, a field at the
// bottom, and the keys along the foot.
//
//   RAME_DIR    the trains and the cabs. The arrows choose one, digits
//               find one by its number, Tab turns the pages of its record,
//               and a key gives it an order: hold, release, emergency
//               brake and its release, a message, a call. Every order asks
//               before it acts.
//   LIGNE_DIR   the library of lines. A line's record, where its data came
//               from, and its stations with their stops; a key puts the PCC
//               on the line, another on none, another reads the library
//               again. Each asks before it acts, and a change of line is
//               refused while a cab is in service.
//
// Both are live: they are painted on the PCC's SMG pasteboard twice a
// second (DCLPasteboard.swift), and only the rows that changed are
// rewritten. The order keys follow the session language, like the
// qualifiers of SET RAME and SET LINE; the foot of the form names them.

/// A form on the screen.
struct FormState {
    enum Kind {
        case rames
        case lines
    }

    /// What the field at the bottom is doing.
    enum Prompt: Equatable {
        /// The find field.
        case none
        /// Asking before an order is carried out.
        case confirm(FormOrder)
        /// Taking the words of a message for a cab, as UTF-8.
        case message(rame: Int, bytes: [UInt8])
    }

    let kind: Kind
    /// What the cursor bar is on: a rame's number, or a line's id and
    /// revision. It follows its item when the list changes under it.
    var selected: String?
    /// Where the cursor bar stood, for when its item has gone.
    var cursor = 0
    /// The digits typed into the find field.
    var find = ""
    /// The page of the record on show.
    var page = 0
    var prompt = Prompt.none
    /// What became of the last order.
    var result = ""
}

/// An order a form gives, once its operator has said yes.
enum FormOrder: Equatable {
    case hold(rame: Int, on: Bool)
    case brake(rame: Int, on: Bool)
    case message(rame: Int, text: String)
    case call(rame: Int)
    case load(id: String, name: String)
    case closeLine
    case reread
}

extension DCLEngine {
    /// Interior width of a form, of its list pane and of its record pane.
    private static let formWidth = 76
    private static let formListWidth = 24
    private static var formDetailWidth: Int { formWidth - formListWidth - 1 }
    /// Rows of the list that are on show; the record has one more.
    private static let formListRows = 13

    /// The name of a form, for its title bar and its messages.
    func formTitle(_ kind: FormState.Kind) -> String {
        tr(kind == .rames ? "pcc.form.rames.title" : "pcc.form.lines.title")
    }

    /// RUN RAME_DIR / RUN LIGNE_DIR entry point.
    func startForm(_ kind: FormState.Kind) {
        liveTimer?.invalidate()
        var state = FormState(kind: kind)
        // The library opens on the line the PCC is on.
        if kind == .lines, let on = link?.snapshot?.line?.identity {
            state.selected = on.id + "\u{1F}" + on.rev
        }
        form = state
        liveMode = .form
        monitorIntervalSec = 0.5
        monitorStartedAt = Date()
        pasteboardRows = []
        enterLiveScreen()
        outRaw("\u{1B}[?25l")
        refreshLiveDisplay()
        liveTimer = Timer.scheduledTimer(withTimeInterval: monitorIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLiveDisplay() }
        }
    }

    // MARK: -- what the forms list

    /// The trains the rame form lists: every one, or those whose number
    /// has the digits of the find field.
    private func formRames(_ state: FormState) -> [CabinePCC.Rame] {
        let all = (link?.snapshot?.rames ?? []).sorted { $0.number < $1.number }
        guard !state.find.isEmpty else { return all }
        return all.filter { PCCText.number($0.number).contains(state.find) }
    }

    /// The lines the library form lists: every one, or those whose id has
    /// the digits of the find field.
    private func formLines(_ state: FormState) -> [CabinePCC.HeldLine] {
        let all = link?.snapshot?.library ?? []
        guard !state.find.isEmpty else { return all }
        return all.filter { $0.identity.id.contains(state.find) }
    }

    private func key(_ rame: CabinePCC.Rame) -> String { "\(rame.number)" }
    private func key(_ line: CabinePCC.HeldLine) -> String { line.identity.id + "\u{1F}" + line.identity.rev }

    /// Where the cursor bar is in a list of `keys`: on its item if that is
    /// still listed, or where it stood.
    private func cursor(_ state: FormState, in keys: [String]) -> Int? {
        guard !keys.isEmpty else { return nil }
        if let selected = state.selected, let index = keys.firstIndex(of: selected) { return index }
        return min(max(state.cursor, 0), keys.count - 1)
    }

    /// The keys of what a form lists, in the order it lists them.
    private func formKeys(_ state: FormState) -> [String] {
        switch state.kind {
        case .rames: return formRames(state).map(key)
        case .lines: return formLines(state).map(key)
        }
    }

    /// Puts the cursor bar on the item at `index` of the list.
    private func select(_ index: Int) {
        guard let state = form else { return }
        let keys = formKeys(state)
        guard !keys.isEmpty else { return }
        let clamped = min(max(index, 0), keys.count - 1)
        form?.cursor = clamped
        form?.selected = keys[clamped]
        form?.page = 0
    }

    // MARK: -- painting

    /// One frame of the form on the screen: 24 pasteboard rows.
    func formRows() -> [String] {
        guard let state = form else { return [] }
        let width = Self.formWidth, listWidth = Self.formListWidth, detailWidth = Self.formDetailWidth
        let listRows = Self.formListRows

        func sep(_ l: String, _ m: String, _ r: String) -> String {
            l + String(repeating: "─", count: listWidth) + m + String(repeating: "─", count: detailWidth) + r
        }
        func full(_ l: String, _ r: String) -> String { l + String(repeating: "─", count: width) + r }
        func boxLine(_ inner: String, reverse: Bool = false) -> String {
            let body = fit(inner, width)
            return "│" + (reverse ? reversed(body) : body) + "│"
        }
        func centered(_ s: String) -> String {
            String(repeating: " ", count: max(0, (width - visibleWidth(s)) / 2)) + s
        }
        /// One split row: list cell + record cell; the selected list row
        /// paints its interior in reverse video (the DECforms cursor bar).
        func splitLine(_ list: String, _ detail: String, selected: Bool = false) -> String {
            let cell = fit(list, listWidth)
            return "│" + (selected ? reversed(cell) : cell) + "│" + fit(detail, detailWidth) + "│"
        }

        // What is listed, and the record of what the cursor bar is on.
        let list: [String]
        let record: [[String]]
        let header: String
        let counted: String
        let keys = formKeys(state)
        let at = cursor(state, in: keys)
        switch state.kind {
        case .rames:
            let rames = formRames(state)
            header = tr("pcc.col.no") + " " + smgCol(tr("pcc.col.kind"), 7) + tr("pcc.form.rames.who")
            list = rames.map { rame in
                PCCText.number(rame.number) + " " + smgCol(PCCText.kind(rame.kind, tr), 7)
                    + (rame.cab?.name ?? PCCText.phase(rame.phase, tr))
            }
            record = at.map { rameRecord(rames[$0]) } ?? [[ "", "  " + tr(link?.snapshot?.line == nil ? "pcc.noline" : "pcc.form.nomatch")]]
            counted = rames.count == 1 ? tr("pcc.form.rames.count.one") : String(format: tr("pcc.form.rames.count"), rames.count)
        case .lines:
            let lines = formLines(state)
            let on = link?.snapshot?.line?.identity
            header = "  " + smgCol(tr("pcc.col.id"), 7) + tr("pcc.col.line")
            list = lines.map { line in
                (on.map { $0.isSameLine(as: line.identity) } == true ? "●" : " ") + " " + smgCol(line.identity.id, 7)
                    + line.identity.name
            }
            record = at.map { lineRecord(lines[$0]) } ?? [["", "  " + tr("pcc.form.nomatch")]]
            counted = lines.count == 1 ? tr("pcc.form.lines.count.one") : String(format: tr("pcc.form.lines.count"), lines.count)
        }
        let pages = max(record.count, 1)
        let shownPage = min(state.page, pages - 1)
        var detail = record.isEmpty ? [] : record[shownPage]
        if pages > 1 {
            // The last row of the pane says which page this is.
            detail = Array(detail.prefix(listRows))
            while detail.count < listRows { detail.append("") }
            detail.append("  " + String(format: tr("pcc.form.page"), shownPage + 1, pages))
        }

        // The list window, centred on the cursor bar.
        var top = 0
        if list.count > listRows, let at {
            top = min(max(0, at - listRows / 2), list.count - listRows)
        }

        var rows: [String] = []
        rows.append(full("┌", "┐"))
        rows.append(boxLine(centered(Self.productName + "  --  " + formTitle(state.kind)), reverse: true))
        rows.append(boxLine(centered(formStatus())))
        rows.append(sep("├", "┬", "┤"))
        rows.append(splitLine(" " + header, detail.first ?? ""))
        for i in 0..<listRows {
            let index = top + i
            let cell = index < list.count ? (index == at ? "▶" : " ") + list[index] : ""
            rows.append(splitLine(cell, i + 1 < detail.count ? detail[i + 1] : "", selected: index == at && index < list.count))
        }
        rows.append(sep("├", "┴", "┤"))

        // The field: the find field with what it has found, or what the
        // form is asking. What the last order came to is on the row under
        // it; an answer too long for one row takes both, until the next key.
        let said = wrappedResult(state.result)
        switch state.prompt {
        case .none where said.count > 1:
            rows.append(boxLine("  " + said[0]))
        case .none:
            // DECforms text field: typed characters fill the underscores.
            let fieldLength = 6
            let filled = String(state.find.prefix(fieldLength))
            let field = "  " + tr("pcc.form.find") + " " + filled + String(repeating: "_", count: fieldLength - filled.count)
            rows.append(boxLine(field + String(repeating: " ", count: max(1, width - field.count - counted.count - 2)) + counted))
        case let .confirm(order):
            let asked = "  " + question(order) + " " + tr("pcc.form.yesno")
            rows.append(boxLine(blinkOn ? reversed(asked) : asked))
        case let .message(rame, bytes):
            let typed = String(decoding: bytes, as: UTF8.self)
            let lead = "  " + String(format: tr("pcc.form.message"), PCCText.number(rame)) + " "
            // The end of a long message stays in sight.
            let room = max(8, width - lead.count - 2)
            rows.append(boxLine(lead + String(typed.suffix(room - 1)) + "_"))
        }
        rows.append(boxLine("  " + (said.last ?? "")))
        let legend = tr(state.kind == .rames ? "pcc.form.rames.keys" : "pcc.form.lines.keys")
        rows.append(boxLine("  " + legend))
        rows.append(boxLine("  " + tr("pcc.form.keys")))
        rows.append(full("└", "┘"))
        return rows
    }

    /// The line and its state, under the title bar.
    private func formStatus() -> String {
        guard let link else { return "" }
        guard let snapshot = link.snapshot else { return PCCText.listener(link.listener, tr) }
        guard let line = snapshot.line else { return tr("pcc.mon.noline") }
        return String(format: tr("pcc.form.status"), line.identity.name, PCCText.mode(snapshot.mode, tr),
                      PCCText.clock(snapshot.clockS), snapshot.rames.count, snapshot.cabs.count)
    }

    /// A field of a record: its label, which comes pre-padded from the
    /// string table so that the values align in a column, the way DECforms
    /// lays out a record, and its value.
    private func field(_ labelKey: String, _ value: String) -> [String] {
        wrapped("  " + tr(labelKey) + " ", value)
    }

    /// What the last order came to, on one row of the form when it fits and
    /// on two when it does not.
    private func wrappedResult(_ text: String) -> [String] {
        let room = Self.formWidth - 4
        guard text.count > room else { return [text] }
        var first = ""
        var words = text.split(separator: " ")[...]
        while let word = words.first, first.count + (first.isEmpty ? 0 : 1) + word.count <= room {
            first += (first.isEmpty ? "" : " ") + word
            words = words.dropFirst()
        }
        return [first, words.joined(separator: " ")]
    }

    /// Wraps a value onto lines of the record pane after `label`, with a
    /// hanging indent under the value's first column.
    private func wrapped(_ label: String, _ value: String) -> [String] {
        let hang = String(repeating: " ", count: label.count)
        let room = Self.formDetailWidth - 1
        var lines: [String] = []
        var current = label
        for word in value.split(separator: " ") {
            let candidate = current == label || current == hang ? current + word : current + " " + word
            if candidate.count > room && current != label && current != hang {
                lines.append(current)
                current = hang + word
            } else {
                current = candidate
            }
        }
        lines.append(current)
        return lines
    }

    /// The record of a train: its own page, and its cab's if it has one.
    private func rameRecord(_ rame: CabinePCC.Rame) -> [[String]] {
        var train = [""]
        train += field("pcc.form.f.train", PCCText.number(rame.number) + "   " + PCCText.kind(rame.kind, tr))
        train += field("pcc.form.f.track", "\(rame.track)")
        train += field("pcc.form.f.position", String(format: "%.1f m", rame.uM))
        train += field("pcc.form.f.speed", String(format: "%.1f km/h  (%.1f m/s)", rame.speedMS * 3.6, rame.speedMS))
        train += field("pcc.form.f.state", PCCText.phase(rame.phase, tr))
        train += field("pcc.form.f.doors", PCCText.doors(of: rame, tr))
        train += field("pcc.form.f.station", PCCText.station(of: rame, tr))
        let flags = PCCText.flags(of: rame, tr)
        train += field("pcc.form.f.orders", flags.isEmpty ? tr("pcc.form.none") : flags.joined(separator: ", "))
        guard let cab = rame.cab else { return [train] }

        var driver = [""]
        driver += field("pcc.form.f.cab", cab.name)
        driver += field("pcc.form.f.link", PCCText.link(cab, tr))
        driver += field("pcc.form.f.driving", (cab.mode?.rawValue ?? "--") + "   " + labelled("pcc.label.autopilot")
                        + PCCText.autopilot(cab, tr))
        driver += field("pcc.form.f.pax", PCCText.passengers(cab, capacity: link?.snapshot?.line?.train.capacity))
        driver += field("pcc.form.f.timetable", PCCText.deviation(cab, tr))
        driver += field("pcc.form.f.eb", PCCText.emergencyBrake(cab, tr))
        driver += field("pcc.form.f.authority",
                        cab.authority.map { PCCText.authority($0, nose: rame.uM, tr) } ?? tr("pcc.authority.none"))
        driver += field("pcc.form.f.report", cab.lastReport.map { PCCText.report($0, tr) } ?? tr("pcc.report.never"))
        return [train, Array(driver.prefix(Self.formListRows + 1))]
    }

    /// The record of a line: the line itself, where its data came from,
    /// and its stations with the stop on each track.
    private func lineRecord(_ held: CabinePCC.HeldLine) -> [[String]] {
        let identity = held.identity
        let on = link?.snapshot?.line?.identity.isSameLine(as: identity) == true
        var record = [""]
        record += field("pcc.form.f.line", identity.name)
        record += field("pcc.form.f.id", identity.id)
        record += field("pcc.form.f.rev", identity.rev)
        record += field("pcc.form.f.length", String(format: tr("pcc.form.v.length"), held.lengthM / 1_000))
        record += field("pcc.form.f.stations", "\(held.stationCount)")
        record += field("pcc.form.f.from", held.firstStation)
        record += field("pcc.form.f.to", held.lastStation)
        record += field("pcc.form.f.source", tr(held.hasSource ? "pcc.form.v.source.yes" : "pcc.form.v.source.no"))
        record += field("pcc.form.f.running", tr(on ? "pcc.form.v.running.yes" : "pcc.form.v.running.no"))
        var pages = [Array(record.prefix(Self.formListRows + 1))]

        // Where the data came from: the licences ask that it be shown.
        var sources = ["", "  " + tr("pcc.credits.title")]
        if let credits = link?.credits[identity] {
            if let track = credits.track { sources += field("pcc.form.f.c.track", track) }
            if let stations = credits.stations { sources += field("pcc.form.f.c.stations", stations) }
            if let ground = credits.ground { sources += field("pcc.form.f.c.ground", ground) }
            if let date = credits.date { sources += field("pcc.form.f.c.date", date) }
        } else {
            sources += wrapped("  ", tr("pcc.credits.none"))
        }
        pages.append(Array(sources.prefix(Self.formListRows + 1)))

        // The stations, a dozen to a page.
        if let description = link?.package(identity)?.description, description.tracks.count == 2 {
            let names = description.stations.map(\.name)
            let stops1 = description.tracks[0].track == 1 ? description.tracks[0].stopsM : description.tracks[1].stopsM
            let stops2 = description.tracks[0].track == 1 ? description.tracks[1].stopsM : description.tracks[0].stopsM
            let size = Self.formListRows - 1
            var index = 0
            while index < names.count {
                var page = ["", "  " + smgColRight(tr("pcc.col.no"), 4) + smgCol(tr("pcc.col.station"), 27)
                                + smgColRight(tr("pcc.col.stop1"), 9) + smgColRight(tr("pcc.col.stop2"), 9)]
                for station in index..<min(index + size, names.count) {
                    let stop1 = station < stops1.count ? String(format: "%.1f", stops1[station]) : "--"
                    let mirrored = names.count - 1 - station
                    let stop2 = mirrored < stops2.count ? String(format: "%.1f", stops2[mirrored]) : "--"
                    page.append("  " + smgColRight("\(station + 1)", 4) + smgCol(names[station], 27)
                                + smgColRight(stop1, 9) + smgColRight(stop2, 9))
                }
                pages.append(page)
                index += size
            }
        }
        return pages
    }

    // MARK: -- orders

    /// What the form asks before it carries out an order.
    private func question(_ order: FormOrder) -> String {
        switch order {
        case let .hold(rame, on):
            return String(format: tr(on ? "pcc.form.ask.hold" : "pcc.form.ask.release"), PCCText.number(rame))
        case let .brake(rame, on):
            return String(format: tr(on ? "pcc.form.ask.brake" : "pcc.form.ask.unbrake"), PCCText.number(rame))
        case let .message(rame, _):
            return String(format: tr("pcc.form.ask.message"), PCCText.number(rame))
        case let .call(rame):
            return String(format: tr("pcc.form.ask.call"), PCCText.number(rame))
        case let .load(_, name):
            return String(format: tr("pcc.form.ask.load"), name)
        case .closeLine:
            return tr("pcc.form.ask.close")
        case .reread:
            return tr("pcc.form.ask.reread")
        }
    }

    /// Carries out an order the operator has said yes to, and says what
    /// became of it on the form's message row.
    private func carryOut(_ order: FormOrder) {
        guard let link else { return }
        let text: String
        switch order {
        case let .hold(rame, on):
            text = pccMessage(link.hold(rame: rame, on),
                              String(format: tr(on ? "pcc.set.hold" : "pcc.set.release"), PCCText.number(rame)))
        case let .brake(rame, on):
            text = pccMessage(link.emergencyBrake(rame: rame, on),
                              String(format: tr(on ? "pcc.set.brake" : "pcc.set.unbrake"), PCCText.number(rame)))
        case let .message(rame, words):
            text = pccMessage(link.message(rame: rame, words), String(format: tr("pcc.set.message"), PCCText.number(rame)))
        case let .call(rame):
            text = pccMessage(link.call(rame: rame), String(format: tr("pcc.set.call"), PCCText.number(rame)))
        case let .load(id, name):
            text = pccMessage(link.takeUp(line: id), String(format: tr("pcc.set.load"), name))
        case .closeLine:
            text = pccMessage(link.closeLine(), tr("pcc.set.close"))
        case .reread:
            text = pccMessage(link.rereadLibrary(), rereadMessage())
        }
        form?.result = text
    }

    /// The order a key gives, for what the cursor bar is on. The keys
    /// follow the session language, as the qualifiers of SET RAME and SET
    /// LINE do.
    private func order(for key: Character, _ state: FormState) -> FormOrder? {
        let french = uiLang == .fr
        switch state.kind {
        case .rames:
            let rames = formRames(state)
            guard let at = cursor(state, in: rames.map(self.key)) else { return nil }
            let rame = rames[at].number
            switch (key, french) {
            case ("H", false), ("R", true): return .hold(rame: rame, on: true)
            case ("R", false), ("L", true): return .hold(rame: rame, on: false)
            case ("B", false), ("F", true): return .brake(rame: rame, on: true)
            case ("U", false), ("D", true): return .brake(rame: rame, on: false)
            case ("C", false), ("A", true): return .call(rame: rame)
            default: return nil
            }
        case .lines:
            switch (key, french) {
            case ("C", false), ("F", true): return .closeLine
            case ("R", _):                  return .reread
            case ("L", false), ("C", true):
                let lines = formLines(state)
                guard let at = cursor(state, in: lines.map(self.key)) else { return nil }
                return .load(id: lines[at].identity.id, name: lines[at].identity.name)
            default: return nil
            }
        }
    }

    // MARK: -- keys

    /// Keystroke handling: the arrows move the cursor bar, digits feed the
    /// find field, Tab and Next/Prev Screen turn the record's pages, the
    /// order keys ask and then act, CTRL/W repaints, and CTRL/Z (or the
    /// usual interrupt gestures) leaves the form -- or, while the form is
    /// asking something, takes the question back. What an order came to
    /// stays on the message row until the next key.
    func handleFormKey(_ bytes: [UInt8]) {
        guard case .form = liveMode, var state = form else { return }
        var i = 0
        var dirty = false
        /// Leaves the form, or takes back what it is asking.
        func leave(interrupt: Bool) -> Bool {
            if state.prompt != .none {
                state.prompt = .none
                state.result = tr("pcc.form.cancelled")
                dirty = true
                return false
            }
            form = state
            stopMonitor(interrupt: interrupt, exitKey: !interrupt)
            return true
        }
        while i < bytes.count {
            let b = bytes[i]
            // ESC ESC -- exit fallback for ttys that eat control bytes.
            if b == 0x1B, i + 1 < bytes.count, bytes[i + 1] == 0x1B {
                if leave(interrupt: false) { return }
                i += 2
                continue
            }
            // CSI sequence (arrow keys, Next Screen, Prev Screen).
            if b == 0x1B, i + 1 < bytes.count, bytes[i + 1] == 0x5B {
                var j = i + 2
                while j < bytes.count, !((0x40...0x7E).contains(bytes[j])) { j += 1 }
                guard j < bytes.count else { break }                 // incomplete escape
                if state.prompt == .none {
                    state.result = ""
                    form = state
                    let keys = formKeys(state)
                    let at = cursor(state, in: keys) ?? 0
                    switch bytes[j] {
                    case 0x41: select(at - 1)                        // Up
                    case 0x42: select(at + 1)                        // Down
                    case 0x7E:
                        let parameter = String(decoding: bytes[(i + 2)..<j], as: UTF8.self)
                        let page = state.page
                        if parameter == "6" { form?.page = page + 1 }           // Next Screen
                        if parameter == "5" { form?.page = max(0, page - 1) }   // Prev Screen
                    default: break
                    }
                    if let moved = form { state = moved }
                    dirty = true
                }
                i = j + 1
                continue
            }
            switch state.prompt {
            case let .confirm(order):
                // Anything but a yes takes the question back.
                state.prompt = .none
                let yes: UInt8 = uiLang == .fr ? 0x4F : 0x59           // O / Y
                if b == yes || b == yes + 0x20 {
                    form = state
                    carryOut(order)
                    if let acted = form { state = acted }
                } else {
                    state.result = tr("pcc.form.cancelled")
                }
                dirty = true
            case .message(let rame, var typed):
                switch b {
                case 0x03, 0x19, 0x1A:
                    _ = leave(interrupt: false)
                case 0x0D, 0x0A:
                    let words = String(decoding: typed, as: UTF8.self).trimmingCharacters(in: .whitespaces)
                    if words.isEmpty {
                        state.prompt = .none
                        state.result = tr("pcc.form.cancelled")
                    } else {
                        state.prompt = .confirm(.message(rame: rame, text: words))
                    }
                    dirty = true
                case 0x7F, 0x08:
                    // A whole character, however many bytes it is.
                    while let last = typed.popLast(), last & 0xC0 == 0x80 {}
                    state.prompt = .message(rame: rame, bytes: typed)
                    dirty = true
                case 0x15:
                    state.prompt = .message(rame: rame, bytes: [])
                    dirty = true
                default:
                    if b >= 0x20, String(decoding: typed, as: UTF8.self).count < CabineWire.maxMessageCharacters {
                        typed.append(b)
                        state.prompt = .message(rame: rame, bytes: typed)
                        dirty = true
                    }
                }
            case .none:
                // What the last order came to stands until the next key.
                if !state.result.isEmpty, b != 0x17 {
                    state.result = ""
                    dirty = true
                }
                switch b {
                case 0x03, 0x19:
                    if leave(interrupt: true) { return }
                case 0x1A:
                    if leave(interrupt: false) { return }
                case 0x17:                                           // Ctrl/W: repaint
                    form = state
                    repaintPasteboard()
                case 0x09:                                           // Tab: the record's next page
                    state.page += 1
                    dirty = true
                case 0x7F, 0x08:
                    if !state.find.isEmpty {
                        state.find.removeLast()
                        state.selected = nil
                        state.cursor = 0
                        dirty = true
                    }
                case 0x15:
                    if !state.find.isEmpty {
                        state.find = ""
                        state.selected = nil
                        state.cursor = 0
                        dirty = true
                    }
                case 0x30...0x39:                                    // a digit: the find field
                    if state.find.count < 6 {
                        state.find.append(Character(UnicodeScalar(b)))
                        state.selected = nil
                        state.cursor = 0
                        state.page = 0
                        dirty = true
                    }
                case 0x41...0x5A, 0x61...0x7A:                       // a letter: an order
                    let letter = Character(UnicodeScalar(b & 0xDF))
                    form = state
                    if state.kind == .rames, letter == "M" {
                        // A message is for a cab: its words first, then the question.
                        let rames = formRames(state)
                        if let at = cursor(state, in: rames.map(self.key)) {
                            if rames[at].cab == nil {
                                state.result = pccMessage(.refused(.notACab(rames[at].number)), "")
                            } else {
                                state.prompt = .message(rame: rames[at].number, bytes: [])
                                state.result = ""
                            }
                            dirty = true
                        }
                    } else if let order = order(for: letter, state) {
                        state.prompt = .confirm(order)
                        state.result = ""
                        dirty = true
                    }
                default:
                    break
                }
            }
            i += 1
        }
        // The pages of a record turn round: past the last is the first.
        form = state
        if dirty {
            let pages = formPageCount()
            if let page = form?.page, page >= pages { form?.page = 0 }
            refreshLiveDisplay()
        }
    }

    /// How many pages the record on show has.
    private func formPageCount() -> Int {
        guard let state = form else { return 1 }
        switch state.kind {
        case .rames:
            let rames = formRames(state)
            return cursor(state, in: rames.map(key)).map { rameRecord(rames[$0]).count } ?? 1
        case .lines:
            let lines = formLines(state)
            return cursor(state, in: lines.map(key)).map { lineRecord(lines[$0]).count } ?? 1
        }
    }
}

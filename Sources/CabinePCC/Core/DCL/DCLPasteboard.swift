import Foundation

// The SMG$ pasteboard the PCC's live displays are painted on.
//
// A layered product's screens are its own: like LATCP's or NCP's displays,
// the PCC's monitors (DCLMonitorPCC.swift) and its forms (DCLForms.swift)
// paint a product-owned pasteboard, 24 rows by 80 columns: a reverse-video
// product banner, bordered and labelled virtual displays, a message row and
// a key-legend status bar. Like SMG$ the screen is drawn once and then
// updated by rewriting only the rows that changed, each addressed with CUP:
// no full-screen clear, no flicker. CTRL/W repaints it all (SMG$REPAINT_
// SCREEN); CTRL/Z leaves.
//
// What is painted is localised; the `%PCC-x-IDENT` facility codes and the
// SCADA identifiers stay as they are. The emulator honours only reverse
// video, so "blink" is done by toggling reverse video on alternate frames.
extension DCLEngine {
    /// The product's name on every banner.
    static let productName = "LPD PCC-CABINE V1.0"

    /// Columns of the pasteboard that are written: the 80th is left alone,
    /// so that no terminal wraps a full row onto the next.
    nonisolated static let screenWidth = 79
    /// Rows of the pasteboard.
    nonisolated static let screenRows = 24

    /// True on alternate half seconds: what blinks is in reverse video then.
    var blinkOn: Bool {
        Int(Date().timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
    }

    /// Reverse video round a text.
    func reversed(_ text: String) -> String { "\u{1B}[7m" + text + "\u{1B}[27m" }

    /// A label with its colon as the session's language writes one, and
    /// the space before the value: "Mode: " and "Mode : ".
    func labelled(_ key: String) -> String {
        tr(key) + (uiLang == .fr ? " : " : ": ")
    }

    /// "0.5" / "0,5": the interval with the language's decimal separator.
    func localizedInterval(_ t: TimeInterval) -> String {
        let s = formatInterval(t)
        return uiLang == .fr ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// VMS absolute time with the month abbreviation in the session
    /// language -- what LIB$FORMAT_DATE_TIME yields under SYS$LANGUAGE
    /// FRENCH. The rest of the format is identical in both. Truncated to
    /// whole seconds, as on an operator display: the hundredths are a VMS
    /// system-time artefact, and at a 0.5 s refresh they would rewrite
    /// the status row on every frame.
    func lpdStamp(_ date: Date) -> String {
        var s = stamp(date)
        if let dot = s.lastIndex(of: ".") { s = String(s[..<dot]) }
        guard uiLang == .fr else { return s }
        let fr = ["JAN": "JAN", "FEB": "FÉV", "MAR": "MAR", "APR": "AVR",
                  "MAY": "MAI", "JUN": "JUN", "JUL": "JUL", "AUG": "AOÛ",
                  "SEP": "SEP", "OCT": "OCT", "NOV": "NOV", "DEC": "DÉC"]
        var parts = s.components(separatedBy: "-")
        if parts.count >= 3, let m = fr[parts[1]] { parts[1] = m }
        return parts.joined(separator: "-")
    }

    /// A full-width reverse-video bar with left / centre / right fields.
    func smgBar(_ left: String, _ mid: String, _ right: String) -> String {
        let w = Self.screenWidth
        var row = [Character](repeating: " ", count: w)
        func put(_ text: String, at col: Int) {
            for (i, ch) in text.enumerated() where col + i >= 0 && col + i < w { row[col + i] = ch }
        }
        // Centre field slides right of a long left field rather than
        // overprinting it (the FR key legend is wider than the EN one).
        put(left, at: 1)
        put(right, at: w - 1 - right.count)
        put(mid, at: max((w - mid.count) / 2, left.count + 4))
        return reversed(String(row))
    }

    // MARK: -- SMG pasteboard

    /// Printable width of a row, ignoring SGR escape sequences.
    func visibleWidth(_ s: String) -> Int {
        var n = 0
        var inEsc = false
        for u in s.unicodeScalars {
            if inEsc {
                if (0x40...0x7E).contains(u.value) && u != "[" { inEsc = false }
            } else if u == "\u{1B}" {
                inEsc = true
            } else {
                n += 1
            }
        }
        return n
    }

    /// Truncate a row to `width` printable characters (SGR escapes pass
    /// through), so an over-long row can never auto-wrap on the 80-column
    /// screen and shift the rows below.
    func clip(_ s: String, to width: Int = DCLEngine.screenWidth) -> String {
        var out = ""
        var n = 0
        var inEsc = false
        for u in s.unicodeScalars {
            if inEsc {
                if (0x40...0x7E).contains(u.value) && u != "[" { inEsc = false }
            } else if u == "\u{1B}" {
                inEsc = true
            } else {
                if n == width { continue }
                n += 1
            }
            out.unicodeScalars.append(u)
        }
        return out
    }

    /// A row clipped to `width` printable characters and padded to it.
    func fit(_ s: String, _ width: Int) -> String {
        let clipped = clip(s, to: width)
        return clipped + String(repeating: " ", count: max(0, width - visibleWidth(clipped)))
    }

    /// One bordered SMG virtual display (SMG$CREATE_VIRTUAL_DISPLAY with
    /// SMG$M_BORDER, labelled with SMG$LABEL_BORDER): a top border carrying
    /// the label, the content rows fitted to the inner width, and the
    /// bottom border.
    func smgDisplay(label: String, rows: [String]) -> [String] {
        let inner = Self.screenWidth - 2
        let lbl = " " + String(label.prefix(inner - 4)) + " "
        let top = "┌─" + lbl + String(repeating: "─", count: max(0, inner - 1 - lbl.count)) + "┐"
        var out = [top]
        for r in rows {
            out.append("│" + fit(r, inner) + "│")
        }
        out.append("└" + String(repeating: "─", count: inner) + "┘")
        return out
    }

    /// A left-aligned table cell, always leaving one blank column after it.
    func smgCol(_ str: String, _ w: Int) -> String {
        // What does not fit is cut, and seen to be cut.
        str.count >= w ? String(str.prefix(max(w - 2, 0))) + "… " : str.padding(toLength: w, withPad: " ", startingAt: 0)
    }

    /// A name cut to the room there is for it, and seen to be cut.
    func shortened(_ name: String, to room: Int) -> String {
        name.count <= room ? name : String(name.prefix(max(room - 1, 0))) + "…"
    }

    /// A right-aligned table cell, leaving one blank column after it.
    func smgColRight(_ str: String, _ w: Int) -> String {
        let text = String(str.suffix(w - 1))
        return String(repeating: " ", count: w - 1 - text.count) + text + " "
    }

    /// CTRL/W: SMG$REPAINT_SCREEN -- forget the last frame and redraw
    /// every row (recovers from line noise or a resized window).
    func repaintPasteboard() {
        pasteboardRows = []
        refreshLiveDisplay()
    }

    /// Paste a frame onto the terminal the way SMG$ updates a pasteboard:
    /// the first frame (and a CTRL/W repaint) clears and draws every row;
    /// after that only rows that changed since the last frame are
    /// rewritten, addressed with CUP -- no full-screen clear, no flicker.
    func paint(_ rows: [String]) {
        let full = pasteboardRows.count != rows.count
        var out = full ? "\u{1B}[0m\u{1B}[2J" : ""
        for (i, row) in rows.enumerated() where full || pasteboardRows[i] != row {
            out += "\u{1B}[\(i + 1);1H" + row + "\u{1B}[0m\u{1B}[K"
        }
        pasteboardRows = rows
        if !out.isEmpty { outRaw(out) }
    }

    // MARK: -- shared pasteboard pieces

    /// The product banner (reverse-video header) and the line status row
    /// that open every PCC screen: the time, the line and its mode.
    func pccHeaderRows(title: String) -> [String] {
        var rows = [smgBar(Self.productName, title, String(format: tr("pcc.mon.node"), nodeName))]
        let snapshot = link?.snapshot
        var status = " " + lpdStamp(Date()) + "   "
        if let snapshot, let line = snapshot.line {
            var mode = PCCText.mode(snapshot.mode, tr)
            if snapshot.emergencyStop && blinkOn { mode = reversed(mode) }
            status += String(format: tr("pcc.mon.status"), line.identity.name, mode, PCCText.clock(snapshot.clockS))
        } else if let link {
            status += snapshot == nil ? PCCText.listener(link.listener, tr) : tr("pcc.mon.noline")
        }
        rows.append(clip(status))
        return rows
    }

    /// Message row (empty, as SMG leaves it until a message arrives), then
    /// the status bar: key legend, refresh interval, elapsed time.
    func pccFooterRows(elapsed: String) -> [String] {
        ["", smgBar(tr("pcc.mon.keys"),
                    String(format: tr("pcc.mon.interval"), localizedInterval(monitorIntervalSec)),
                    String(format: tr("pcc.mon.elapsed"), elapsed))]
    }

    /// The ALARMS display of a PCC screen: the most severe standing alarm,
    /// flashing while it is not acknowledged.
    func pccAlarmDisplay() -> [String] {
        let active = world?.activeAlarms ?? []
        let unacked = active.filter { !$0.isAcknowledged }.count
        var alarm = " "
        if let a = active.first {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            let sev: String
            switch a.severity {
            case .critical: sev = "F"
            case .major:    sev = "E"
            case .minor:    sev = "W"
            case .advisory: sev = "I"
            }
            // Time and ACK state lead so truncation only ever clips the
            // message tail.
            let status = a.isAcknowledged ? tr("alarm.status.ack") : tr("alarm.status.unack")
            var text = f.string(from: a.raisedAt) + "  " + status.padding(toLength: 6, withPad: " ", startingAt: 0)
            text += "%PCC-\(sev)-\(a.point), \(a.source): \(alarmMessage(a.message))"
            let room = Self.screenWidth - 4
            if text.count > room { text = String(text.prefix(room)) }
            alarm += (!a.isAcknowledged && blinkOn) ? reversed(text) : text
        } else {
            alarm += tr("pcc.mon.noalarm")
        }
        return smgDisplay(label: String(format: tr("pcc.mon.lbl.alarms"), active.count, unacked), rows: [alarm])
    }
}

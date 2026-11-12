import Foundation

/// A terminal's screen as plain text: enough of a VT220 to read back what
/// the DCL shell and its full-screen displays put on one. The headless tool
/// has no terminal emulator to look at, so it feeds what a session writes
/// into this, and reads the frame out of it: `--dcl "MONITOR LINE"` prints
/// it, and the self-test looks in it for what the display must show.
///
/// It keeps the characters and whether each is in reverse video, moves the
/// cursor (CUP, CR, LF, BS), erases (ED, EL), and has the alternate screen
/// buffer the live displays switch to. Other attributes and private modes
/// pass through without effect.
struct VTScreen {
    struct Cell {
        var character: Character = " "
        var reverse = false
    }

    let columns: Int
    let rows: Int
    private var main: [[Cell]]
    private var alternate: [[Cell]]
    private(set) var onAlternate = false
    private(set) var cursorHidden = false
    private var row = 0
    private var column = 0
    private var reverse = false
    /// An escape sequence that has begun and not yet ended.
    private var pending: String?

    init(columns: Int = 132, rows: Int = 24) {
        self.columns = columns
        self.rows = rows
        let blank = [[Cell]](repeating: [Cell](repeating: Cell(), count: columns), count: rows)
        main = blank
        alternate = blank
    }

    private var cells: [[Cell]] {
        get { onAlternate ? alternate : main }
        set { if onAlternate { alternate = newValue } else { main = newValue } }
    }

    /// What is on the screen, one line a row, without trailing blanks.
    var lines: [String] {
        cells.map { cells in
            var text = String(cells.map(\.character))
            while text.hasSuffix(" ") { text.removeLast() }
            return text
        }
    }

    /// The whole screen as text, without the blank rows at its foot.
    var text: String {
        var all = lines
        while let last = all.last, last.isEmpty { all.removeLast() }
        return all.joined(separator: "\n")
    }

    /// True when `text` is on the screen in reverse video, all of it.
    func isReversed(_ text: String) -> Bool {
        let wanted = Array(text)
        guard !wanted.isEmpty else { return false }
        for line in cells {
            guard line.count >= wanted.count else { continue }
            for start in 0...(line.count - wanted.count)
            where (0..<wanted.count).allSatisfy({ line[start + $0].character == wanted[$0] && line[start + $0].reverse }) {
                return true
            }
        }
        return false
    }

    /// Takes what a session wrote.
    mutating func feed(_ text: String) {
        for scalar in text.unicodeScalars {
            if var sequence = pending {
                sequence.unicodeScalars.append(scalar)
                // ESC [ ... final: a final byte ends a control sequence.
                if sequence.count == 1 {
                    if scalar == "[" {
                        pending = sequence
                    } else {
                        pending = nil          // a two-character escape: nothing here acts on one
                    }
                } else if (0x40...0x7E).contains(scalar.value) {
                    pending = nil
                    control(String(sequence.dropFirst()))
                } else {
                    pending = sequence
                }
                continue
            }
            switch scalar {
            case "\u{1B}":
                pending = ""
            case "\r":
                column = 0
            case "\n":
                lineFeed()
            case "\u{08}":
                column = max(0, column - 1)
            default:
                guard scalar.value >= 0x20 else { continue }
                put(Character(scalar))
            }
        }
    }

    private mutating func put(_ character: Character) {
        if column >= columns {
            column = 0
            lineFeed()
        }
        set(row, column, Cell(character: character, reverse: reverse))
        column += 1
    }

    /// Writes one cell of the buffer that is on show, in place.
    private mutating func set(_ row: Int, _ column: Int, _ cell: Cell) {
        if onAlternate { alternate[row][column] = cell } else { main[row][column] = cell }
    }

    private mutating func lineFeed() {
        if row + 1 < rows {
            row += 1
        } else {
            // The screen scrolls: the top row goes.
            var scrolled = cells
            scrolled.removeFirst()
            scrolled.append([Cell](repeating: Cell(), count: columns))
            cells = scrolled
        }
    }

    /// Carries out a control sequence: its parameters and its final byte.
    private mutating func control(_ sequence: String) {
        guard let final = sequence.last else { return }
        let body = String(sequence.dropLast())
        let isPrivate = body.hasPrefix("?")
        let parameters = body.drop { $0 == "?" }.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        func parameter(_ index: Int, _ fallback: Int) -> Int {
            index < parameters.count && parameters[index] > 0 ? parameters[index] : fallback
        }
        switch final {
        case "H", "f":
            row = min(rows, parameter(0, 1)) - 1
            column = min(columns, parameter(1, 1)) - 1
        case "A": row = max(0, row - parameter(0, 1))
        case "B": row = min(rows - 1, row + parameter(0, 1))
        case "C": column = min(columns - 1, column + parameter(0, 1))
        case "D": column = max(0, column - parameter(0, 1))
        case "J":
            let mode = parameters.first ?? 0
            if mode == 2 {
                cells = [[Cell]](repeating: [Cell](repeating: Cell(), count: columns), count: rows)
            } else if mode == 0 {
                eraseLine(from: column)
                for below in (row + 1)..<max(row + 1, rows) {
                    for index in 0..<columns { set(below, index, Cell()) }
                }
            }
        case "K":
            let mode = parameters.first ?? 0
            if mode == 2 { eraseLine(from: 0) } else if mode == 0 { eraseLine(from: column) }
        case "m":
            for code in parameters.isEmpty ? [0] : parameters {
                if code == 0 || code == 27 { reverse = false }
                if code == 7 { reverse = true }
            }
        case "h", "l":
            guard isPrivate else { return }
            let on = final == "h"
            if parameters.contains(1049) || parameters.contains(47) {
                onAlternate = on
                if on {
                    alternate = [[Cell]](repeating: [Cell](repeating: Cell(), count: columns), count: rows)
                    row = 0
                    column = 0
                }
            }
            if parameters.contains(25) { cursorHidden = !on }
        default:
            break
        }
    }

    private mutating func eraseLine(from start: Int) {
        guard row < rows else { return }
        for index in max(0, start)..<columns { set(row, index, Cell()) }
    }
}

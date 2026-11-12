import SwiftUI
import CabinePCCKit

// The panels of the PCC Dispatcher that show the line and give it its
// orders: the PCC itself, the line's controls and its library, the diagram
// of its two tracks, a card for each cab, the connections, the trains and
// the journal. Everything they show comes from the link (PCCLink), which
// publishes the engine's picture four times a second; every order goes to
// the engine through it, and what the link says became of the order is what
// the panel shows.

// MARK: - Shared pieces

/// A label and a value on one line, for a value too long to promise it room:
/// it is cut short where `StatusLine` would push its neighbours out of the
/// window.
struct LongLine: View {
    let label: String
    let value: String
    var valueColor: Color = RetroTheme.amberBright

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):")
                .foregroundColor(RetroTheme.amberDim)
                .fixedSize()
            Text(value)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(RetroTheme.mono)
    }
}

// MARK: - The PCC

/// Whether the PCC listens and where, its name, and the address to give a
/// Cabine; and, when it does not listen, why.
struct PCCHeaderPanel: View {
    @EnvironmentObject var link: PCCLink
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        BoxPanel(title: language.t("pcc.title"), accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(horizontalSpacing: 18, verticalSpacing: 4) {
                    StatusLine(label: label("pcc.label.listener"),
                               value: PCCText.listener(link.listener, words),
                               valueColor: accent)
                    StatusLine(label: label("pcc.label.network"),
                               value: language.t(link.isLAN ? "pcc.lan.on" : "pcc.lan.off"),
                               valueColor: RetroTheme.amber)
                    StatusLine(label: label("pcc.label.name"),
                               value: link.name,
                               valueColor: RetroTheme.cyan)
                    if let address = link.address {
                        StatusLine(label: label("pcc.label.address"),
                                   value: String(format: language.t("pcc.address.fmt"),
                                                 address.host, Int(address.port)),
                                   valueColor: RetroTheme.cyan)
                    }
                    if let snapshot = link.snapshot {
                        StatusLine(label: label("pcc.label.connections"),
                                   value: "\(snapshot.sessions.count)",
                                   valueColor: snapshot.sessions.isEmpty ? RetroTheme.amberDim : RetroTheme.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(sentences, id: \.self) { sentence in
                    Text(sentence)
                        .font(RetroTheme.mono)
                        .foregroundColor(RetroTheme.cyan)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var words: PCCText.Lookup { { language.t($0) } }

    private func label(_ key: String) -> String { language.t(key).uppercased() }

    /// What the operator is to know when the PCC does not listen, or
    /// listens and runs no line.
    private var sentences: [String] {
        switch link.listener {
        case .disabled:
            return [language.t("pcc.hint.disabled")]
        case .failed:
            return [language.t("pcc.hint.failed")]
        case .starting:
            return link.isSlowToStart ? [language.t(link.isLAN ? "pcc.hint.slow.lan" : "pcc.hint.slow")] : []
        case .listening:
            guard let snapshot = link.snapshot, snapshot.line == nil else { return [] }
            return [language.t("pcc.noline.window")]
        }
    }

    private var accent: Color {
        switch link.listener {
        case .listening: return RetroTheme.green
        case .starting:  return RetroTheme.amber
        case .disabled:  return RetroTheme.amberDim
        case .failed:    return RetroTheme.red
        }
    }
}

// MARK: - Line controls

/// The line the PCC is on, the orders for it as a whole (service, the
/// general emergency stop, the headway), and the library: a button for each
/// line the PCC holds, which puts the PCC on it. A change of line is
/// refused while a cab is in service, and the panel says so.
struct LineControlPanel: View {
    let snapshot: CabinePCC.Snapshot
    @EnvironmentObject var link: PCCLink
    @EnvironmentObject var language: AppLanguage
    /// Why the last order was refused, if it was.
    @State private var refusal: String?

    private static let headways: [Double] = [90, 120, 150, 180, 240, 300]

    var body: some View {
        let hasLine = snapshot.line != nil
        BoxPanel(title: language.t("pcc.controls.title"), accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(horizontalSpacing: 18, verticalSpacing: 4) {
                    StatusLine(label: label("pcc.label.line"),
                               value: lineValue,
                               valueColor: hasLine ? RetroTheme.amberBright : RetroTheme.amberDim)
                    if hasLine {
                        StatusLine(label: label("pcc.label.clock"),
                                   value: PCCText.clock(snapshot.clockS),
                                   valueColor: RetroTheme.green)
                        StatusLine(label: label("pcc.label.mode"),
                                   value: PCCText.mode(snapshot.mode, words),
                                   valueColor: modeColor)
                        StatusLine(label: label("pcc.label.trains"),
                                   value: String(format: language.t("pcc.trains.fmt"),
                                                 snapshot.rames.count, snapshot.cabs.count))
                        StatusLine(label: label("pcc.label.fleet"),
                                   value: PCCText.fleet(snapshot.fleetSize, words),
                                   valueColor: RetroTheme.amber)
                        StatusLine(label: label("pcc.label.lap"),
                                   value: PCCText.duration(snapshot.lapTimeS),
                                   valueColor: RetroTheme.amber)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // A button that shows a state is lit while the state holds,
                // and stays enabled: lit and disabled, its label is hard
                // to read.
                HStack(spacing: 10) {
                    RetroButton(language.t("pcc.btn.service.start"),
                                enabled: hasLine,
                                highlighted: hasLine && snapshot.inService && !snapshot.emergencyStop) {
                        give(link.setService(true))
                    }
                    RetroButton(language.t("pcc.btn.service.stop"),
                                enabled: hasLine && snapshot.inService) {
                        give(link.setService(false))
                    }
                    RetroButton(language.t("pcc.btn.emergency"),
                                enabled: hasLine,
                                highlighted: snapshot.emergencyStop) {
                        give(link.setEmergencyStop(!snapshot.emergencyStop))
                    }
                    Text("\(language.t("pcc.label.headway").uppercased()):")
                        .font(RetroTheme.monoSm)
                        .foregroundColor(RetroTheme.amberDim)
                        .fixedSize()
                        .padding(.leading, 10)
                    ForEach(Self.headways, id: \.self) { value in
                        RetroButton("\(Int(value)) s", highlighted: abs(snapshot.headwayS - value) < 0.5) {
                            give(link.setHeadway(value))
                        }
                    }
                    Spacer()
                }
                // The library: the line the PCC is on is lit.
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                    Text("\(language.t("pcc.label.library").uppercased()):")
                        .font(RetroTheme.monoSm)
                        .foregroundColor(RetroTheme.amberDim)
                        .fixedSize()
                        .padding(.vertical, 5)
                    ForEach(snapshot.library) { held in
                        RetroButton(held.identity.name, highlighted: isOn(held)) {
                            give(link.takeUp(line: held.identity.id))
                        }
                    }
                    RetroButton(language.t("pcc.btn.closeline"), enabled: hasLine) {
                        give(link.closeLine())
                    }
                    RetroButton(language.t("pcc.btn.reread")) {
                        give(link.rereadLibrary())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let refusal {
                    Text(refusal)
                        .font(RetroTheme.monoSm)
                        .foregroundColor(RetroTheme.red)
                }
            }
        }
    }

    private var words: PCCText.Lookup { { language.t($0) } }

    private func label(_ key: String) -> String { language.t(key).uppercased() }

    private func isOn(_ held: CabinePCC.HeldLine) -> Bool {
        snapshot.line?.identity.isSameLine(as: held.identity) == true
    }

    /// The line's name, its length and its stations; a dash while the PCC
    /// is on none.
    private var lineValue: String {
        guard let line = snapshot.line else { return "—" }
        return String(format: language.t("pcc.line.fmt"), line.identity.name,
                      line.lengthM / 1_000, line.stationCount)
    }

    private func give(_ outcome: PCCLink.Outcome) {
        switch outcome {
        case .done:
            refusal = nil
        case let .refused(why):
            refusal = PCCText.refusal(why) { language.t($0) }
        }
    }

    private var accent: Color {
        guard snapshot.line != nil else { return RetroTheme.amberDim }
        if snapshot.emergencyStop { return RetroTheme.red }
        return snapshot.inService ? RetroTheme.green : RetroTheme.amberDim
    }

    private var modeColor: Color {
        switch snapshot.mode {
        case .normal:    return RetroTheme.green
        case .emergency: return RetroTheme.red
        default:         return RetroTheme.amberDim
        }
    }
}

// MARK: - Diagram

/// The line as two horizontal tracks. Track 1 is above and runs left to
/// right; track 2 is below and runs right to left, so that each station is
/// at one place across the diagram on both. The stretches beyond the
/// termini are the tails, where a rame turns back out of sight.
struct LineDiagramPanel: View {
    let snapshot: CabinePCC.Snapshot
    let line: CabinePCC.Line
    @EnvironmentObject var language: AppLanguage

    private static let height: CGFloat = 204
    private static let leftInset: CGFloat = 34
    /// Room for the name of the last station, which leans to the right.
    private static let rightInset: CGFloat = 104
    private static let track1Y: CGFloat = 122
    private static let track2Y: CGFloat = 162
    /// The least distance between two station names, and the most
    /// characters of one that are drawn.
    private static let labelGap: CGFloat = 24
    private static let labelLength = 22
    /// The shortest a train is drawn, however long the line.
    private static let shortestTrain: CGFloat = 7

    var body: some View {
        let tail = language.t("pcc.diagram.tail")
        BoxPanel(title: language.t("pcc.diagram.title"), accent: RetroTheme.amber) {
            VStack(alignment: .leading, spacing: 6) {
                Canvas { context, size in
                    draw(context: context, size: size, tailLabel: tail)
                }
                .frame(height: Self.height)
                .frame(maxWidth: .infinity)
                legend
            }
        }
    }

    private var legend: some View {
        let words: PCCText.Lookup = { language.t($0) }
        return FlowLayout(horizontalSpacing: 16, verticalSpacing: 2) {
            swatch(RetroTheme.green, PCCText.kind(.auto, words))
            swatch(RetroTheme.cyan, PCCText.kind(.cab, words))
            swatch(RetroTheme.amberBright, PCCText.phase(.held, words), outlined: true)
            swatch(RetroTheme.red, language.t("pcc.btn.eb"), outlined: true)
            swatch(RetroTheme.green.opacity(0.35), PCCText.phase(.tail, words))
            swatch(RetroTheme.cyan, language.t("pcc.label.authority").uppercased(), thin: true)
            Text(language.t("pcc.diagram.tracks"))
                .font(RetroTheme.monoSm)
                .foregroundColor(RetroTheme.amberDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func swatch(_ color: Color, _ text: String, outlined: Bool = false, thin: Bool = false) -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(outlined ? Color.clear : color)
                .frame(width: 14, height: thin ? 2 : 8)
                .overlay(Rectangle().stroke(color, lineWidth: outlined ? 1.5 : 0))
            Text(text)
                .font(RetroTheme.monoSm)
                .foregroundColor(RetroTheme.amberDim)
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, tailLabel: String) {
        let length = line.lengthM
        let width = size.width - Self.leftInset - Self.rightInset
        guard length > 0, width > 80 else { return }
        let trainLength = line.train.lengthM
        let top = Self.track1Y, bottom = Self.track2Y
        let left = Self.leftInset, right = Self.leftInset + width

        /// Where a position on a track is drawn. A position `uM` on track 2
        /// is drawn at `lengthM − uM`.
        func x(_ track: Int, _ uM: Double) -> CGFloat {
            let along = track == 2 ? length - uM : uM
            return left + CGFloat(min(max(along / length, 0), 1)) * width
        }
        func y(_ track: Int) -> CGFloat { track == 2 ? bottom : top }
        func stroke(_ from: CGPoint, _ to: CGPoint, _ color: Color, width: CGFloat = 1, dash: [CGFloat] = []) {
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
        }

        // The two tracks: the running line between the termini, and dashed
        // beyond them the tails.
        for track in [1, 2] {
            let stops = line.track(track).stopsM
            guard let first = stops.first, let last = stops.last else { continue }
            let level = y(track)
            let platform = max(first - trainLength, 0)
            stroke(CGPoint(x: x(track, platform), y: level), CGPoint(x: x(track, last), y: level),
                   RetroTheme.amber, width: 2)
            stroke(CGPoint(x: x(track, 0), y: level), CGPoint(x: x(track, platform), y: level),
                   RetroTheme.amberDim, width: 2, dash: [3, 3])
            stroke(CGPoint(x: x(track, last), y: level), CGPoint(x: x(track, length), y: level),
                   RetroTheme.amberDim, width: 2, dash: [3, 3])
        }
        // The loop: the end of each track turns back into the start of the
        // other.
        for (edge, bulge) in [(left, CGFloat(-18)), (right, CGFloat(18))] {
            var turn = Path()
            turn.move(to: CGPoint(x: edge, y: top))
            turn.addCurve(to: CGPoint(x: edge, y: bottom),
                          control1: CGPoint(x: edge + bulge, y: top),
                          control2: CGPoint(x: edge + bulge, y: bottom))
            context.stroke(turn, with: .color(RetroTheme.amberDim), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        let tail = Text(tailLabel).font(RetroTheme.monoSm).foregroundColor(RetroTheme.amberDim)
        context.draw(tail, at: CGPoint(x: left - 18, y: bottom + 30), anchor: .leading)
        context.draw(tail, at: CGPoint(x: right + 18, y: bottom + 30), anchor: .trailing)

        // The direction of travel, marked along each track.
        var chevrons = Path()
        var mark = left + 70
        while mark < right - 30 {
            chevrons.move(to: CGPoint(x: mark - 4, y: top - 4))
            chevrons.addLine(to: CGPoint(x: mark, y: top))
            chevrons.addLine(to: CGPoint(x: mark - 4, y: top + 4))
            chevrons.move(to: CGPoint(x: mark + 4, y: bottom - 4))
            chevrons.addLine(to: CGPoint(x: mark, y: bottom))
            chevrons.addLine(to: CGPoint(x: mark + 4, y: bottom + 4))
            mark += 140
        }
        context.stroke(chevrons, with: .color(RetroTheme.amberDim), lineWidth: 1)

        // The stations. On track 2 the stop of `stations[i]` is
        // `stopsM[n − 1 − i]`; a station is drawn where the middles of its
        // two platforms meet.
        let names = line.stationNames
        let stops1 = line.track(1).stopsM, stops2 = line.track(2).stopsM
        let count = min(names.count, stops1.count, stops2.count)
        var places: [CGFloat] = []
        for index in 0..<count {
            let stop1 = stops1[index], stop2 = stops2[count - 1 - index]
            let place = (x(1, stop1 - trainLength / 2) + x(2, stop2 - trainLength / 2)) / 2
            places.append(place)
            stroke(CGPoint(x: place, y: top - 9), CGPoint(x: place, y: bottom + 9), RetroTheme.amberDim)
            // The platforms, a train long.
            stroke(CGPoint(x: x(1, stop1 - trainLength), y: top), CGPoint(x: x(1, stop1), y: top),
                   RetroTheme.amberBright, width: 4)
            stroke(CGPoint(x: x(2, stop2 - trainLength), y: bottom), CGPoint(x: x(2, stop2), y: bottom),
                   RetroTheme.amberBright, width: 4)
        }
        // Their names lean, so that many fit; where stations crowd, some go
        // unnamed. The termini are always named.
        var named: [Int] = []
        for index in 0..<count {
            if let last = named.last, places[index] - places[last] < Self.labelGap { continue }
            named.append(index)
        }
        if count > 0, named.last != count - 1 {
            while named.count > 1, let last = named.last, places[count - 1] - places[last] < Self.labelGap {
                named.removeLast()
            }
            named.append(count - 1)
        }
        for index in named {
            var name = names[index]
            if name.count > Self.labelLength { name = String(name.prefix(Self.labelLength - 1)) + "…" }
            let terminus = index == 0 || index == count - 1
            var leaning = context
            leaning.translateBy(x: places[index] + 2, y: top - 24)
            leaning.rotate(by: .degrees(-38))
            leaning.draw(Text(name).font(RetroTheme.monoSm)
                            .foregroundColor(terminus ? RetroTheme.amberBright : RetroTheme.amber),
                         at: .zero, anchor: .leading)
        }

        // Each cab's movement authority: a line from its nose to where its
        // leave to run ends, between the two tracks.
        for rame in snapshot.rames {
            guard let cab = rame.cab, cab.link == .live, let authority = cab.authority,
                  authority.track == rame.track else { continue }
            let level = rame.track == 2 ? bottom - 9 : top + 9
            let from = x(rame.track, rame.uM), to = x(rame.track, max(authority.endM, rame.uM))
            let color: Color
            switch authority.reason {
            case .emergency:      color = RetroTheme.red
            case .hold, .service: color = RetroTheme.amberBright
            default:              color = RetroTheme.cyan
            }
            stroke(CGPoint(x: from, y: level), CGPoint(x: to, y: level), color, width: 1.5)
            stroke(CGPoint(x: to, y: level - 4), CGPoint(x: to, y: level + 4), color, width: 1.5)
        }

        // The trains: a bar of the train's own length, pointed at its nose,
        // with its number. The cabs are drawn last, over the others.
        let order = snapshot.rames.sorted { ($0.cab == nil ? 0 : 1, $0.number) < ($1.cab == nil ? 0 : 1, $1.number) }
        for rame in order {
            let towards: CGFloat = rame.track == 2 ? -1 : 1
            let level = y(rame.track)
            let nose = x(rame.track, rame.uM)
            let rear = nose - towards * max(CGFloat(rame.lengthM / length) * width, Self.shortestTrain)
            var shape = Path()
            shape.move(to: CGPoint(x: rear, y: level - 4))
            shape.addLine(to: CGPoint(x: nose - towards * 3, y: level - 4))
            shape.addLine(to: CGPoint(x: nose, y: level))
            shape.addLine(to: CGPoint(x: nose - towards * 3, y: level + 4))
            shape.addLine(to: CGPoint(x: rear, y: level + 4))
            shape.closeSubpath()

            let own = rame.cab == nil ? RetroTheme.green : RetroTheme.cyan
            // A rame in the tail is out of sight: it is shown dimmed.
            let strength = rame.phase == .tail ? 0.35 : 1.0
            let braked = rame.braked || rame.phase == .emergency
            let held = rame.held || rame.phase == .held
            let mark = braked ? RetroTheme.red : (held ? RetroTheme.amberBright : own)
            context.fill(shape, with: .color(own.opacity(strength)))
            if braked || held {
                context.stroke(shape, with: .color(mark), lineWidth: 1.5)
            }
            context.draw(Text(PCCText.number(rame.number)).font(RetroTheme.monoSm)
                            .foregroundColor(mark.opacity(strength)),
                         at: CGPoint(x: (nose + rear) / 2, y: level + (rame.track == 2 ? 13 : -13)),
                         anchor: .center)
        }
    }
}

// MARK: - Cabs

/// A card for each cab in service, or a line saying that there is none.
struct CabsSection: View {
    let snapshot: CabinePCC.Snapshot
    let line: CabinePCC.Line
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        let cabs = snapshot.cabs.sorted { $0.number < $1.number }
        if cabs.isEmpty {
            BoxPanel(title: language.t("pcc.cabs.title"), accent: RetroTheme.amberDim) {
                Text(language.t("pcc.cabs.none"))
                    .font(RetroTheme.mono)
                    .foregroundColor(RetroTheme.greenDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(cabs) { rame in
                if let cab = rame.cab {
                    CabCard(rame: rame, cab: cab, capacity: line.train.capacity)
                }
            }
        }
    }
}

/// One cab: what it says of itself, what the PCC has given it leave to do,
/// and the orders the operator can give it.
struct CabCard: View {
    let rame: CabinePCC.Rame
    let cab: CabinePCC.Cab
    let capacity: Int
    @EnvironmentObject var link: PCCLink
    @EnvironmentObject var language: AppLanguage
    @State private var message = ""
    /// What became of the last order, in words, and whether it was refused.
    @State private var note: (text: String, refused: Bool)?

    var body: some View {
        BoxPanel(title: title, accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(horizontalSpacing: 20, verticalSpacing: 4) {
                    StatusLine(label: label("pcc.label.link"),
                               value: PCCText.link(cab, words),
                               valueColor: cab.link == .live ? RetroTheme.green : RetroTheme.red)
                    StatusLine(label: label("pcc.label.driving"),
                               value: cab.mode?.rawValue ?? "--",
                               valueColor: RetroTheme.cyan)
                    StatusLine(label: label("pcc.label.autopilot"),
                               value: PCCText.autopilot(cab, words),
                               valueColor: cab.automatic == true ? RetroTheme.green : RetroTheme.amberDim)
                    StatusLine(label: label("pcc.label.doors"),
                               value: PCCText.doors(of: rame, words),
                               valueColor: rame.doors > 0.01 ? RetroTheme.green : RetroTheme.amberDim)
                    StatusLine(label: language.t("pcc.btn.eb"),
                               value: PCCText.emergencyBrake(cab, words),
                               valueColor: cab.emergencyBrake ? RetroTheme.red : RetroTheme.amberDim)
                    StatusLine(label: label("pcc.label.pax"),
                               value: PCCText.passengers(cab, capacity: capacity))
                    StatusLine(label: label("pcc.label.speed"),
                               value: String(format: "%.1f m/s", rame.speedMS),
                               valueColor: rame.speedMS > 0.5 ? RetroTheme.green : RetroTheme.amberDim)
                    StatusLine(label: label("pcc.label.station"),
                               value: PCCText.station(of: rame, words),
                               valueColor: RetroTheme.cyan)
                    StatusLine(label: label("pcc.label.timetable"),
                               value: PCCText.deviation(cab, words),
                               valueColor: RetroTheme.amber)
                    ForEach(PCCText.flags(of: rame, words), id: \.self) { flag in
                        Text(flag)
                            .font(RetroTheme.mono)
                            .foregroundColor(RetroTheme.bg)
                            .padding(.horizontal, 5)
                            .background(RetroTheme.amberBright)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LongLine(label: label("pcc.label.authority"),
                               value: cab.authority.map { PCCText.authority($0, nose: rame.uM, words) }
                                   ?? language.t("pcc.authority.none"),
                               valueColor: authorityColor)
                LongLine(label: label("pcc.label.report"),
                               value: cab.lastReport.map { PCCText.report($0, words) }
                                   ?? language.t("pcc.report.never"),
                               valueColor: cab.lastReport == nil ? RetroTheme.amberDim : RetroTheme.amberBright)
                orders
                if let note {
                    Text(note.text)
                        .font(RetroTheme.monoSm)
                        .foregroundColor(note.refused ? RetroTheme.red : RetroTheme.green)
                }
            }
        }
    }

    /// HOLD and RELEASE, the emergency brake and its release, a message for
    /// the driver's display, and a call.
    private var orders: some View {
        let number = rame.number
        let connected = cab.session != nil
        let display = PCCText.number(number)
        return HStack(spacing: 8) {
            RetroButton(language.t("pcc.btn.hold"), highlighted: rame.held) {
                give(link.hold(rame: number, true), "pcc.set.hold", display)
            }
            RetroButton(language.t("pcc.btn.release"), enabled: rame.held) {
                give(link.hold(rame: number, false), "pcc.set.release", display)
            }
            RetroButton(language.t("pcc.btn.eb"), highlighted: rame.braked) {
                give(link.emergencyBrake(rame: number, true), "pcc.set.brake", display)
            }
            RetroButton(language.t("pcc.btn.unbrake"), enabled: rame.braked) {
                give(link.emergencyBrake(rame: number, false), "pcc.set.unbrake", display)
            }
            TextField("", text: $message,
                      prompt: Text(language.t("pcc.message.prompt")).foregroundColor(RetroTheme.amberDim))
                .textFieldStyle(.plain)
                .font(RetroTheme.mono)
                .foregroundColor(RetroTheme.amberBright)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .overlay(Rectangle().stroke(connected ? RetroTheme.amber : RetroTheme.amberDim, lineWidth: 1))
                .frame(minWidth: 160, maxWidth: .infinity)
                .disabled(!connected)
                .onChange(of: message) {
                    // A message is 120 characters at most.
                    if message.count > CabineWire.maxMessageCharacters {
                        message = String(message.prefix(CabineWire.maxMessageCharacters))
                    }
                }
                .onSubmit { send() }
            Text("\(message.count)/\(CabineWire.maxMessageCharacters)")
                .font(RetroTheme.monoSm)
                .foregroundColor(RetroTheme.amberDim)
                .fixedSize()
            RetroButton(language.t("pcc.btn.message"),
                        enabled: connected && !message.trimmingCharacters(in: .whitespaces).isEmpty) {
                send()
            }
            RetroButton(language.t("pcc.btn.call"), enabled: connected) {
                give(link.call(rame: number), "pcc.set.call", display)
            }
        }
    }

    private var words: PCCText.Lookup { { language.t($0) } }

    private func label(_ key: String) -> String { language.t(key).uppercased() }

    private func send() {
        let outcome = link.message(rame: rame.number, message)
        give(outcome, "pcc.set.message", PCCText.number(rame.number))
        if outcome == .done { message = "" }
    }

    /// Notes what became of an order: what it did, or why it was refused.
    private func give(_ outcome: PCCLink.Outcome, _ doneKey: String, _ number: String) {
        switch outcome {
        case .done:
            note = (PCCText.sentence(String(format: language.t(doneKey), number)), false)
        case let .refused(why):
            note = (PCCText.refusal(why, words), true)
        }
    }

    private var title: String {
        "\(language.t("pcc.cab")) \(cab.name) — \(language.t("pcc.rame")) \(PCCText.number(rame.number))"
    }

    private var accent: Color {
        if cab.link == .silent || cab.emergencyBrake || rame.braked { return RetroTheme.red }
        return rame.held ? RetroTheme.amberBright : RetroTheme.cyan
    }

    private var authorityColor: Color {
        guard let authority = cab.authority else { return RetroTheme.amberDim }
        switch authority.reason {
        case .emergency:      return RetroTheme.red
        case .hold, .service: return RetroTheme.amberBright
        default:              return RetroTheme.cyan
        }
    }
}

// MARK: - Connections

/// The connections whose cab is not in service: a Cabine that has dialled
/// and has yet to start a service, or one that is on another line.
struct ConnectionsPanel: View {
    let snapshot: CabinePCC.Snapshot
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        let waiting = snapshot.sessions.filter { $0.standing != .inService }
        if !waiting.isEmpty {
            BoxPanel(title: language.t("pcc.connections.title").uppercased(), accent: RetroTheme.amber) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(waiting) { session in
                        let connection = PCCText.connection(session) { language.t($0) }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(connection.who)
                                .foregroundColor(session.standing == .onLine ? RetroTheme.green : RetroTheme.amber)
                                .fixedSize()
                            Text(connection.detail)
                                .foregroundColor(RetroTheme.amberDim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(RetroTheme.monoSm)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Rames

/// Every train of the line, cabs and automatic rames alike, by number: in
/// two columns, so that a full fleet stays compact.
struct RamesPanel: View {
    let snapshot: CabinePCC.Snapshot
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        let rames = snapshot.rames.sorted { $0.number < $1.number }
        let half = (rames.count + 1) / 2
        BoxPanel(title: String(format: language.t("pcc.rames.title"), rames.count),
                 accent: RetroTheme.amber) {
            if rames.isEmpty {
                Text(language.t("pcc.rames.none"))
                    .font(RetroTheme.monoSm)
                    .foregroundColor(RetroTheme.greenDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 26) {
                    column(Array(rames.prefix(half)))
                    column(Array(rames.dropFirst(half)))
                }
            }
        }
    }

    private func column(_ rames: [CabinePCC.Rame]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                cell(label("pcc.col.no"), Self.widths[0], RetroTheme.amberDim)
                cell(label("pcc.col.kind"), Self.widths[1], RetroTheme.amberDim)
                cell(label("pcc.col.track"), Self.widths[2], RetroTheme.amberDim)
                cell(label("pcc.col.position"), Self.widths[3], RetroTheme.amberDim)
                cell(label("pcc.col.speed"), Self.widths[4], RetroTheme.amberDim)
                cell(label("pcc.col.state"), Self.widths[5], RetroTheme.amberDim)
                cell(label("pcc.col.doors"), Self.widths[6], RetroTheme.amberDim)
                cell(label("pcc.col.station"), nil, RetroTheme.amberDim)
            }
            HRule(RetroTheme.amberDim)
            ForEach(rames) { rame in
                row(rame)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ rame: CabinePCC.Rame) -> some View {
        let words: PCCText.Lookup = { language.t($0) }
        let own = rame.cab == nil ? RetroTheme.green : RetroTheme.cyan
        return HStack(spacing: 0) {
            cell(PCCText.number(rame.number), Self.widths[0], own)
            cell(PCCText.kind(rame.kind, words), Self.widths[1], own)
            cell("\(rame.track)", Self.widths[2], RetroTheme.amber)
            cell(String(format: "%.0f m", rame.uM), Self.widths[3], RetroTheme.amberBright)
            cell(String(format: "%.1f m/s", rame.speedMS), Self.widths[4],
                 rame.speedMS > 0.5 ? RetroTheme.green : RetroTheme.amberDim)
            cell(PCCText.phase(rame.phase, words), Self.widths[5], stateColor(rame))
            cell(PCCText.doors(open: rame.doors, words), Self.widths[6],
                 rame.doors > 0.01 ? RetroTheme.green : RetroTheme.amberDim)
            cell(rame.stationName ?? "--", nil, RetroTheme.amber)
        }
    }

    /// The widths of the columns but the last, the station, which takes the
    /// room that is left: wide enough for the longest word of either
    /// language in either skin's type.
    private static let widths: [CGFloat] = [28, 48, 36, 62, 62, 90, 62]

    private func label(_ key: String) -> String { language.t(key).uppercased() }

    private func cell(_ text: String, _ width: CGFloat?, _ color: Color) -> some View {
        Text(text)
            .font(RetroTheme.monoSm)
            .foregroundColor(color)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private func stateColor(_ rame: CabinePCC.Rame) -> Color {
        if rame.braked || rame.phase == .emergency { return RetroTheme.red }
        if rame.held || rame.phase == .held { return RetroTheme.amberBright }
        switch rame.phase {
        case .running: return RetroTheme.green
        case .tail:    return RetroTheme.amberDim
        default:       return RetroTheme.amber
        }
    }
}

// MARK: - Journal

/// The last things that happened on the line, the newest first, by the
/// line's clock.
struct JournalPanel: View {
    let lines: [PCCLink.JournalLine]
    @EnvironmentObject var language: AppLanguage

    private static let shown = 14

    var body: some View {
        BoxPanel(title: language.t("pcc.journal.title"), accent: RetroTheme.amber) {
            VStack(alignment: .leading, spacing: 2) {
                if lines.isEmpty {
                    Text(language.t("pcc.journal.none"))
                        .font(RetroTheme.monoSm)
                        .foregroundColor(RetroTheme.greenDim)
                }
                ForEach(lines.suffix(Self.shown).reversed()) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(line.clockS.map(PCCText.clock) ?? "--:--:--")
                            .foregroundColor(RetroTheme.green)
                            .fixedSize()
                        Text(PCCText.journal(line.event) { language.t($0) })
                            .foregroundColor(RetroTheme.amber)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(RetroTheme.monoSm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

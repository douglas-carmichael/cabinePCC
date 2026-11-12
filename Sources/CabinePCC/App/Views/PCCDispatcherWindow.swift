import SwiftUI
import AppKit
import CabinePCCKit

/// The PCC Dispatcher: the operator's desk, and the app's main window.
///
/// From the top: the banner, the node's status strip, the line's controls
/// with the library, the SCADA annunciator, and beneath them what scrolls
/// -- the PCC and its listener, the diagram of the line's two tracks, a
/// card for each cab with its orders, the connections, the trains, the
/// journal and the library with where each line's data came from -- and
/// the foot, which opens the other windows and switches the language.
///
/// The window shows the node and gives it orders; it does not run it. The
/// node is started by the application delegate when the app has launched,
/// and runs whether this window is open or not.
struct PCCDispatcherWindow: View {
    @EnvironmentObject var language: AppLanguage
    @EnvironmentObject var link: PCCLink
    @Environment(\.openWindow) private var openWindow

    @State private var showHelp = false
    @State private var showCredits = false

    /// The terminal that `-openDCL` asks for is opened once, however often
    /// this view appears (a change of skin makes it afresh).
    private static var openedTerminalAtLaunch = false

    var body: some View {
        ZStack {
            RetroTheme.bg.ignoresSafeArea()
            KeyboardHost(onKey: handleKey)
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
            VStack(spacing: 14) {
                BannerHeader()
                StatusStrip()
                if let snapshot = link.snapshot {
                    LineControlPanel(snapshot: snapshot)
                }
                SCADAAlarmPanel()
                // The banner, the controls and the annunciator stay in
                // sight; what grows with the number of cabs and trains
                // scrolls beneath them.
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        PCCHeaderPanel()
                        if let snapshot = link.snapshot {
                            if let line = snapshot.line {
                                LineDiagramPanel(snapshot: snapshot, line: line)
                                CabsSection(snapshot: snapshot, line: line)
                            }
                            ConnectionsPanel(snapshot: snapshot)
                            if snapshot.line != nil {
                                RamesPanel(snapshot: snapshot)
                            }
                        }
                        JournalPanel(lines: link.journal)
                        if let snapshot = link.snapshot {
                            LibraryPanel(snapshot: snapshot)
                        }
                    }
                    .padding(.top, 8)
                }
                FooterBar(showCredits: $showCredits)
            }
            .padding(20)
            if showHelp {
                HelpOverlay(onDismiss: { showHelp = false })
                    .transition(.opacity)
            }
            if showCredits {
                CreditsOverlay(onDismiss: { showCredits = false })
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 1080, minHeight: 840)
        .id(language.themeKind)
        .environment(\.colorScheme, language.themeKind == .retro ? .dark : .light)
        .navigationTitle(language.t("window.control"))
        .onAppear {
            // `-openDCL` at launch opens a DCL Terminal beside the dispatcher,
            // as metroSystem's `-openDetail` opens a window of its own: for a
            // demonstration, or a picture of both windows. `-dcl "command"`
            // opens one too, and types that command in it.
            let command = PCCEnvironment.launchArgument("-dcl")
            guard !Self.openedTerminalAtLaunch,
                  command != nil || ProcessInfo.processInfo.arguments.contains("-openDCL") else { return }
            Self.openedTerminalAtLaunch = true
            VTShellView.typedAtLaunch = command
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                openWindow(id: "dcl", value: DCLSessionID())
            }
        }
    }

    private func handleKey(_ ev: NSEvent) -> NSEvent? {
        let mods = ev.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.intersection([.command, .option, .control]).isEmpty else { return ev }
        // A key typed into a message field is the field's.
        if ev.window?.firstResponder is NSTextView { return ev }

        if ev.keyCode == KeyCode.escape {
            if showHelp { showHelp = false; return nil }
            if showCredits { showCredits = false; return nil }
            return ev
        }
        if ev.keyCode == KeyCode.f1 {
            showHelp.toggle()
            return nil
        }
        switch (ev.charactersIgnoringModifiers ?? "").lowercased() {
        case "?":
            showHelp.toggle()
        case "l":
            language.cycle()
        case "t":
            language.toggleTheme()
        case "d":
            openWindow(id: "dcl", value: DCLSessionID())
        case "e":
            if let snapshot = link.snapshot, snapshot.line != nil {
                link.setEmergencyStop(!snapshot.emergencyStop)
            }
        case "q":
            NSApp.terminate(nil)
        default:
            return ev
        }
        return nil
    }
}

// MARK: - Banner and status

private struct BannerHeader: View {
    @EnvironmentObject var language: AppLanguage
    var body: some View {
        VStack(spacing: 2) {
            Text("*** \(language.t("banner.title")) ***")
                .font(RetroTheme.monoXl)
                .foregroundColor(RetroTheme.amber)
                .retroGlow()
            Text(language.t("banner.subtitle"))
                .font(RetroTheme.mono)
                .foregroundColor(RetroTheme.amberDim)
            Text(language.t("banner.copyright"))
                .font(RetroTheme.monoSm)
                .foregroundColor(RetroTheme.amberDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .overlay(Rectangle().stroke(RetroTheme.amber, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            RetroButton("\(language.t("theme.label")): \(language.t(language.themeKind == .retro ? "theme.retro" : "theme.iso"))",
                        highlighted: language.themeKind == .iso101) {
                language.toggleTheme()
            }
            .padding(6)
        }
    }
}

/// The node at a glance: who it is, the line and its mode, how many trains
/// and cabs, the telnet sessions and the alarms.
private struct StatusStrip: View {
    @EnvironmentObject var world: PCCWorld
    @EnvironmentObject var language: AppLanguage
    @EnvironmentObject var link: PCCLink
    @EnvironmentObject var telnet: DCLTelnetServer

    var body: some View {
        // A wrapping FlowLayout keeps the strip on one line when there's room
        // but wraps onto additional lines when the window is narrow — so every
        // field stays visible even at the minimum window size.
        FlowLayout(horizontalSpacing: 16, verticalSpacing: 4) {
            StatusLine(label: language.t("status.node"),
                       value: world.nodeName,
                       valueColor: RetroTheme.cyan)
            StatusLine(label: "PCC",
                       value: listenerValue,
                       valueColor: listenerColor)
            StatusLine(label: language.t("status.line"),
                       value: link.snapshot?.line?.identity.name ?? "—",
                       valueColor: link.snapshot?.line == nil ? RetroTheme.amberDim : RetroTheme.amberBright)
            StatusLine(label: language.t("status.rames"),
                       value: "\(link.snapshot?.rames.count ?? 0)",
                       valueColor: RetroTheme.amberBright)
            StatusLine(label: language.t("status.cabs"),
                       value: "\(link.snapshot?.cabs.count ?? 0)",
                       valueColor: (link.snapshot?.cabs.isEmpty ?? true) ? RetroTheme.amberDim : RetroTheme.cyan)
            StatusLine(label: language.t("status.telnet"),
                       value: telnetValue,
                       valueColor: telnet.sessionCount == 0 ? RetroTheme.amberDim : RetroTheme.green)
            // MODE and ALARMS change text on their own: reserve their
            // widest realistic width so the STAT item and cursor to their
            // right hold still instead of jittering with every transition.
            StatusLine(label: language.t("status.mode"),
                       value: modeValue,
                       valueColor: modeColor)
                .frame(minWidth: 200, alignment: .leading)
            StatusLine(label: language.t("status.alarms"),
                       value: alarmValue,
                       valueColor: alarmColor)
                .frame(minWidth: 190, alignment: .leading)
            // STAT and its cursor are one item: when the strip wraps, the
            // cursor does not go to the next line by itself.
            HStack(spacing: 6) {
                StatusLine(label: "STAT",
                           value: language.t("status.ready"),
                           valueColor: RetroTheme.green)
                BlinkingCursor()
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The listener in a word: the port it listens on, or why it does not.
    private var listenerValue: String {
        switch link.listener {
        case let .listening(port): return "\(port)"
        case .starting:            return language.t("pcc.listener.starting")
        case .disabled:            return language.t("pcc.listener.disabled")
        case .failed:              return language.t("status.pcc.failed")
        }
    }

    private var listenerColor: Color {
        switch link.listener {
        case .listening: return RetroTheme.green
        case .starting:  return RetroTheme.amber
        case .disabled:  return RetroTheme.amberDim
        case .failed:    return RetroTheme.red
        }
    }

    private var telnetValue: String {
        let sessions: String
        switch telnet.sessionCount {
        case 0:  sessions = language.t("status.telnet.none")
        case 1:  sessions = language.t("status.telnet.one")
        default: sessions = String(format: language.t("status.telnet.many"), telnet.sessionCount)
        }
        return telnet.port.map { "\($0) · \(sessions)" } ?? sessions
    }

    private var modeValue: String {
        guard let snapshot = link.snapshot, snapshot.line != nil else { return "—" }
        return PCCText.mode(snapshot.mode) { language.t($0) }
    }

    private var modeColor: Color {
        guard let snapshot = link.snapshot, snapshot.line != nil else { return RetroTheme.amberDim }
        switch snapshot.mode {
        case .normal:    return RetroTheme.green
        case .emergency: return RetroTheme.red
        default:         return RetroTheme.amberDim
        }
    }

    private var alarmValue: String {
        let active = world.activeAlarms.count
        return active == 0
            ? language.t("status.alarms.normal")
            : String(format: language.t("status.alarms.summary"), active, world.unacknowledgedAlarmCount)
    }

    private var alarmColor: Color {
        world.highestActiveSeverity.map(AlarmRow.color) ?? RetroTheme.green
    }
}

// MARK: - The library, and where its lines' data came from

/// Every line the PCC holds, with what its package says of where its data
/// came from. OpenStreetMap's data is under the ODbL, which asks that
/// "© OpenStreetMap contributors" be shown; Île-de-France Mobilités and the
/// IGN publish under the Licence Ouverte 2.0, which asks for the source and
/// the date. This is where an operator reads them.
struct LibraryPanel: View {
    let snapshot: CabinePCC.Snapshot
    @EnvironmentObject var link: PCCLink
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        BoxPanel(title: String(format: language.t("pcc.library.title"), snapshot.library.count), accent: RetroTheme.amber) {
            VStack(alignment: .leading, spacing: 10) {
                if snapshot.library.isEmpty {
                    Text(language.t("pcc.dcl.lines.none"))
                        .font(RetroTheme.monoSm)
                        .foregroundColor(RetroTheme.greenDim)
                }
                ForEach(snapshot.library) { held in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(held.identity.name)
                                .foregroundColor(isOn(held) ? RetroTheme.green : RetroTheme.amberBright)
                                .fixedSize()
                            Text(String(format: language.t("pcc.library.line"), held.identity.id, held.identity.rev,
                                        held.lengthM / 1_000, held.stationCount, held.firstStation, held.lastStation))
                                .foregroundColor(RetroTheme.amber)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(RetroTheme.mono)
                        ForEach(PCCText.credits(link.credits[held.identity]) { language.t($0) }, id: \.self) { credit in
                            Text(credit)
                                .font(RetroTheme.monoSm)
                                .foregroundColor(RetroTheme.amberDim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isOn(_ held: CabinePCC.HeldLine) -> Bool {
        snapshot.line?.identity.isSameLine(as: held.identity) == true
    }
}

// MARK: - Foot

private struct FooterBar: View {
    @Binding var showCredits: Bool
    @EnvironmentObject var language: AppLanguage
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Text(language.t("hint.line"))
                .font(RetroTheme.monoSm)
                .foregroundColor(RetroTheme.amberDim)
                .lineLimit(1)
            Spacer()
            RetroButton(language.t("credits.title")) {
                showCredits = true
            }
            RetroButton(language.t("window.dcl")) {
                openWindow(id: "dcl", value: DCLSessionID())
            }
            HStack(spacing: 6) {
                Text("\(language.t("hint.lang")):")
                    .font(RetroTheme.monoSm)
                    .foregroundColor(RetroTheme.amberDim)
                ForEach(Lang.allCases) { lang in
                    RetroButton(lang.code,
                                highlighted: language.current == lang) {
                        language.current = lang
                    }
                }
            }
        }
        .padding(.top, 4)
        .overlay(alignment: .top) {
            HRule(RetroTheme.amber)
        }
    }
}

// MARK: - Overlays

private struct HelpOverlay: View {
    let onDismiss: () -> Void
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        ZStack {
            RetroTheme.bg.opacity(0.85).ignoresSafeArea()
            BoxPanel(title: language.t("help.title"), accent: RetroTheme.green) {
                VStack(alignment: .leading, spacing: 8) {
                    row("F1  /  ?",  language.t("help.k.help"))
                    row("L",         language.t("help.k.lang"))
                    row("T",         language.t("help.k.theme"))
                    row("E",         language.t("help.k.emergency"))
                    row("D",         language.t("help.k.dcl"))
                    row("Q",         language.t("help.k.quit"))
                    row("ESC",       language.t("help.k.esc"))
                    Spacer().frame(height: 6)
                    Text(language.t("help.dismiss"))
                        .font(RetroTheme.monoSm)
                        .foregroundColor(RetroTheme.amberDim)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: 460)
            }
            .onTapGesture { onDismiss() }
        }
    }

    private func row(_ key: String, _ desc: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(RetroTheme.mono)
                .foregroundColor(RetroTheme.amberBright)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(RetroTheme.mono)
                .foregroundColor(RetroTheme.amber)
        }
    }
}

private struct CreditsOverlay: View {
    let onDismiss: () -> Void
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        ZStack {
            RetroTheme.bg.opacity(0.85).ignoresSafeArea()
            BoxPanel(title: language.t("credits.title"), accent: RetroTheme.cyan) {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        HRule(RetroTheme.cyan)
                        Text("Cabine PCC")
                            .font(RetroTheme.monoXl)
                            .foregroundColor(RetroTheme.amberBright)
                            .retroGlow()
                        HRule(RetroTheme.cyan)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        creditBlock(
                            role: language.t("credits.role.pcc"),
                            name: "Douglas Carmichael",
                            lines: ["dcarmich@dcarmichael.net"]
                        )
                        creditBlock(
                            role: language.t("credits.role.retro"),
                            name: "metroSystem · elevatorSystem",
                            lines: ["Amaury Crocquefer / Douglas Carmichael"]
                        )
                        // The data of the real lines: what its licences ask
                        // to be shown. Each line's own sources are in the
                        // LINE LIBRARY panel, as its package gives them.
                        creditBlock(
                            role: language.t("credits.role.data"),
                            name: "© OpenStreetMap contributors",
                            lines: [language.t("credits.data.osm"), language.t("credits.data.idfm"),
                                    language.t("credits.data.ign"), language.t("credits.data.where")]
                        )
                        creditBlock(
                            role: language.t("credits.role.font"),
                            name: "VT323",
                            lines: [language.t("credits.font.licence")]
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HRule(RetroTheme.amberDim)

                    Text(language.t("credits.dismiss"))
                        .font(RetroTheme.monoSm)
                        .foregroundColor(RetroTheme.amberDim)
                }
                .frame(width: 620)
            }
            .onTapGesture { onDismiss() }
        }
    }

    private func creditBlock(role: String, name: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(role)
                .font(RetroTheme.monoSm)
                .foregroundColor(RetroTheme.cyan)
            Text(name)
                .font(RetroTheme.monoLg)
                .foregroundColor(RetroTheme.amberBright)
                .retroGlow()
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(RetroTheme.monoSm)
                    .foregroundColor(RetroTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

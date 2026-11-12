import SwiftUI

/// The SCADA annunciator: the standing alarms of the PCC, the most severe
/// first, with the operator's acknowledgement and clearing. The alarms are
/// raised by the link (PCCLink): the general emergency stop, a cab that has
/// fallen silent, an emergency brake, a listener that failed and a cab that
/// holds another revision of the line are process-driven and return to
/// normal by themselves; a driver's report or call and a line file that was
/// refused are events, which stand until they are acknowledged and cleared.
struct SCADAAlarmPanel: View {
    @EnvironmentObject var world: PCCWorld
    @EnvironmentObject var language: AppLanguage

    var body: some View {
        BoxPanel(title: language.t("alarm.panel.title"), accent: panelAccent) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    StatusLine(label: language.t("alarm.active"),
                               value: "\(world.activeAlarms.count)",
                               valueColor: panelAccent)
                    StatusLine(label: language.t("alarm.unack"),
                               value: "\(world.unacknowledgedAlarmCount)",
                               valueColor: world.unacknowledgedAlarmCount == 0 ? RetroTheme.green : RetroTheme.amberBright)
                    Spacer()
                    RetroButton(language.t("alarm.ack.all"), enabled: world.unacknowledgedAlarmCount > 0) {
                        _ = world.acknowledgeAllAlarms()
                    }
                    RetroButton(language.t("alarm.clear.ack"), enabled: world.hasClearableAcknowledgedAlarms) {
                        _ = world.clearAcknowledgedActiveAlarms()
                    }
                    RetroButton(language.t("alarm.clear.all"), enabled: world.hasClearableAlarms) {
                        _ = world.clearAllActiveAlarms()
                    }
                }
                alarmTable
            }
        }
    }

    /// The annunciator holds a FIXED five-row page, like a real SCADA
    /// alarm summary: empty slots render as dim placeholders instead of
    /// collapsing, so the panel never changes height and the panels below
    /// don't reflow when an alarm raises or returns to normal.
    private static let annunciatorRows = 5

    private var alarmTable: some View {
        let active = Array(world.activeAlarms.prefix(Self.annunciatorRows))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                header(language.t("alarm.col.id"), width: AlarmRow.widths[0])
                header(language.t("alarm.col.sev"), width: AlarmRow.widths[1])
                header(language.t("alarm.col.state"), width: AlarmRow.widths[2])
                header(language.t("alarm.col.source"), width: AlarmRow.widths[3])
                header(language.t("alarm.col.point"), width: AlarmRow.widths[4])
                header(language.t("alarm.col.message"), width: nil)
            }
            HRule(RetroTheme.amberDim)
            ForEach(0..<Self.annunciatorRows, id: \.self) { slot in
                if slot < active.count {
                    AlarmRow(alarm: active[slot])
                } else {
                    placeholderRow(showEmptyBanner: slot == 0 && active.isEmpty)
                }
            }
        }
    }

    /// An empty annunciator slot. Carries a hidden ACK button so its
    /// intrinsic height matches a live AlarmRow exactly -- the fixed page
    /// depends on every slot measuring the same.
    private func placeholderRow(showEmptyBanner: Bool) -> some View {
        HStack(spacing: 0) {
            Text(showEmptyBanner ? language.t("alarm.none.active") : "····")
                .font(RetroTheme.monoSm)
                .foregroundColor(showEmptyBanner ? RetroTheme.green : RetroTheme.amberDim.opacity(0.4))
            Spacer(minLength: 8)
            RetroButton(language.t("alarm.ack"), enabled: false) {}
                .hidden()
        }
    }

    private func header(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .font(RetroTheme.monoSm)
            .foregroundColor(RetroTheme.amberDim)
            .frame(width: width, alignment: .leading)
    }

    private var panelAccent: Color {
        guard let severity = world.highestActiveSeverity else { return RetroTheme.green }
        return AlarmRow.color(severity)
    }
}

struct AlarmRow: View {
    let alarm: SCADAAlarm
    @EnvironmentObject var world: PCCWorld
    @EnvironmentObject var language: AppLanguage

    /// The widths of the columns but the last, the message.
    static let widths: [CGFloat] = [42, 84, 88, 100, 100]

    static func color(_ severity: AlarmSeverity) -> Color {
        switch severity {
        case .advisory: return RetroTheme.cyan
        case .minor: return RetroTheme.amber
        case .major: return RetroTheme.amberBright
        case .critical: return RetroTheme.red
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            cell(String(format: "%04d", alarm.sequence), width: Self.widths[0], color: RetroTheme.amberBright)
            cell(localizedSeverity, width: Self.widths[1], color: Self.color(alarm.severity))
            cell(localizedStatus, width: Self.widths[2], color: alarm.isAcknowledged ? RetroTheme.green : RetroTheme.amberBright)
            cell(alarm.source, width: Self.widths[3], color: RetroTheme.cyan)
            cell(alarm.point, width: Self.widths[4], color: RetroTheme.amber)
            Text(localizedMessage)
                .font(RetroTheme.monoSm)
                .foregroundColor(RetroTheme.amber)
                .lineLimit(1)
            Spacer(minLength: 8)
            RetroButton(language.t("alarm.ack"), enabled: !alarm.isAcknowledged) {
                _ = world.acknowledgeAlarm(sequence: alarm.sequence)
            }
        }
    }

    private func cell(_ text: String, width: CGFloat, color: Color) -> some View {
        Text(text)
            .font(RetroTheme.monoSm)
            .foregroundColor(color)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private var localizedSeverity: String {
        switch alarm.severity {
        case .advisory: return language.t("alarm.sev.advisory")
        case .minor: return language.t("alarm.sev.minor")
        case .major: return language.t("alarm.sev.major")
        case .critical: return language.t("alarm.sev.critical")
        }
    }

    private var localizedStatus: String {
        alarm.isAcknowledged ? language.t("alarm.status.ack") : language.t("alarm.status.unack")
    }

    private var localizedMessage: String {
        for key in Strings.alarmMessageKeys {
            if alarm.message == Strings.lookup(key, lang: .en) { return language.t(key) }
        }
        return alarm.message
    }
}

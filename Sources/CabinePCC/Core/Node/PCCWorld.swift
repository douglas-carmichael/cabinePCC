import Foundation
import Combine

// A DISPATCH DESK FOR A CAB SIMULATOR, NOT A SAFETY CONTROLLER.
//
// PCCWorld is what this node keeps of its own: who it is, and the SCADA
// alarm log that every surface renders (the annunciator of the PCC
// Dispatcher, SHOW ALARMS, MONITOR LINE) and every operator path mutates
// (ACKNOWLEDGE, SHELVE, the panel's buttons).
//
// It holds no train. The line, its rames and the cabs are the engine's
// (Engine/, CabinePCCKit) and are read from the snapshot that PCCLink
// publishes; PCCLink is also what raises the alarms of the line into this
// log, and returns them to normal.

enum AlarmSeverity: Int, Codable, CaseIterable, Comparable {
    case advisory = 0
    case minor = 1
    case major = 2
    case critical = 3

    static func < (lhs: AlarmSeverity, rhs: AlarmSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .advisory: return "ADVISORY"
        case .minor: return "MINOR"
        case .major: return "MAJOR"
        case .critical: return "CRITICAL"
        }
    }
}

struct SCADAAlarm: Identifiable, Codable, Hashable {
    let id: UUID
    let sequence: Int
    let raisedAt: Date
    var acknowledgedAt: Date?
    var clearedAt: Date?
    let source: String
    let point: String
    let severity: AlarmSeverity
    let message: String
    /// True when the alarm is backed by a live condition that the link's
    /// scan manages (a silent cab, an emergency brake, the general stop).
    /// Such alarms return to normal on their own when the condition clears
    /// and are NOT operator-clearable -- pressing CLEAR on an in-condition
    /// alarm would be alarm suppression (ISA-18.2), so the panel skips
    /// them. Events (a driver's report or call, a line file that was
    /// refused) leave this false and are cleared by the operator.
    var processDriven: Bool = false
    /// Operator has shelved this alarm (ISA-18.2 SHLVD): removed from the
    /// primary annunciator but kept in the log so the action is auditable.
    var shelvedAt: Date? = nil

    var isActive: Bool { clearedAt == nil }
    var isAcknowledged: Bool { acknowledgedAt != nil }
    var isShelved: Bool { shelvedAt != nil && isActive }
    var isOperatorClearable: Bool { isActive && !processDriven }
    var statusLabel: String {
        if isShelved { return "SHLVD" }
        if clearedAt != nil {
            return acknowledgedAt == nil ? "RTN" : "CLEARED"
        }
        return acknowledgedAt == nil ? "UNACK" : "ACK"
    }
}

@MainActor
final class PCCWorld: ObservableObject {
    @Published private(set) var alarmLog: [SCADAAlarm] = []

    /// What tells this node from another: the `pcc.id` of its `hello`.
    let nodeId: String
    /// The Mac's own name, which the PCC goes by until its operator names it.
    let label: String
    /// The node's name as OpenVMS would have it, for every DCL session of
    /// this node and for the windows.
    let nodeName: String

    private var nextAlarmSequence: Int = 1

    init(nodeId: String = UUID().uuidString,
         label: String = Host.current().localizedName ?? "PCC") {
        self.nodeId = nodeId
        self.label = label
        self.nodeName = Self.makeNodeName(from: label)
    }

    /// Build an OpenVMS-plausible 6-character DECnet-style node name from
    /// the Mac's name. Real VMS clusters use 1-6 upper-case alphanumerics,
    /// first char must be a letter, and most shops follow a "stem +
    /// node-number" pattern (PCCVL1, PCCVL2, etc.)
    private static func makeNodeName(from raw: String) -> String {
        let alnum = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if alnum.isEmpty { return "PCCCAB" }
        var name = String(alnum.prefix(6))
        // VMS requires the first character to be a letter.
        if let first = name.first, !first.isLetter {
            name = "N" + name.dropFirst()
        }
        // Pad short names with "1" so they look like a node-numbered
        // cluster member: "IMAC" -> "IMAC11", "MBP" -> "MBP111".
        if name.count < 6 {
            name += String(repeating: "1", count: 6 - name.count)
        }
        return name
    }

    // MARK: -- alarm log API (shared by the SCADA panel and DCL verbs)

    var activeAlarms: [SCADAAlarm] {
        alarmLog
            .filter { $0.isActive && !$0.isShelved }
            .sorted {
                if $0.severity != $1.severity { return $0.severity > $1.severity }
                return $0.raisedAt > $1.raisedAt
            }
    }

    var unacknowledgedAlarmCount: Int {
        alarmLog.filter { $0.isActive && !$0.isAcknowledged && !$0.isShelved }.count
    }

    var shelvedAlarms: [SCADAAlarm] {
        alarmLog.filter(\.isShelved)
    }

    var returnedToNormalUnackedCount: Int {
        alarmLog.filter { $0.clearedAt != nil && $0.acknowledgedAt == nil }.count
    }

    var highestActiveSeverity: AlarmSeverity? {
        activeAlarms.map(\.severity).max()
    }

    @discardableResult
    func raiseAlarm(source: String, point: String, severity: AlarmSeverity, message: String, processDriven: Bool = false) -> SCADAAlarm {
        if let index = alarmLog.firstIndex(where: { $0.isActive && $0.source == source && $0.point == point }) {
            return alarmLog[index]
        }
        let alarm = SCADAAlarm(id: UUID(),
                               sequence: nextAlarmSequence,
                               raisedAt: Date(),
                               acknowledgedAt: nil,
                               clearedAt: nil,
                               source: source,
                               point: point,
                               severity: severity,
                               message: message,
                               processDriven: processDriven)
        nextAlarmSequence += 1
        alarmLog.insert(alarm, at: 0)
        if alarmLog.count > 200 {
            alarmLog.removeLast(alarmLog.count - 200)
        }
        return alarm
    }

    @discardableResult
    func acknowledgeAlarm(sequence: Int) -> Bool {
        guard let index = alarmLog.firstIndex(where: { $0.sequence == sequence && $0.isActive }) else { return false }
        guard alarmLog[index].acknowledgedAt == nil else { return true }
        alarmLog[index].acknowledgedAt = Date()
        return true
    }

    func acknowledgeAllAlarms() -> Int {
        var count = 0
        for index in alarmLog.indices where alarmLog[index].isActive && alarmLog[index].acknowledgedAt == nil {
            alarmLog[index].acknowledgedAt = Date()
            count += 1
        }
        return count
    }

    @discardableResult
    func clearAllActiveAlarms() -> Int {
        let now = Date()
        var count = 0
        for index in alarmLog.indices where alarmLog[index].isOperatorClearable {
            alarmLog[index].clearedAt = now
            count += 1
        }
        return count
    }

    @discardableResult
    func clearAcknowledgedActiveAlarms() -> Int {
        let now = Date()
        var count = 0
        for index in alarmLog.indices
        where alarmLog[index].isOperatorClearable && alarmLog[index].isAcknowledged {
            alarmLog[index].clearedAt = now
            count += 1
        }
        return count
    }

    var hasClearableAlarms: Bool {
        alarmLog.contains { $0.isOperatorClearable }
    }

    var hasClearableAcknowledgedAlarms: Bool {
        alarmLog.contains { $0.isOperatorClearable && $0.isAcknowledged }
    }

    /// The operator clears an event. A process-driven point is not his to
    /// clear: it returns to normal when its condition does.
    @discardableResult
    func clearAlarm(sequence: Int) -> Bool {
        guard let index = alarmLog.firstIndex(where: { $0.sequence == sequence && $0.isOperatorClearable }) else { return false }
        alarmLog[index].clearedAt = Date()
        return true
    }

    /// The condition behind a point has cleared, or a new word takes the
    /// place of the last: the point returns to normal.
    @discardableResult
    func clearAlarm(source: String, point: String) -> Bool {
        guard let index = alarmLog.firstIndex(where: { $0.isActive && $0.source == source && $0.point == point }) else { return false }
        alarmLog[index].clearedAt = Date()
        return true
    }

    @discardableResult
    func shelveAlarm(sequence: Int) -> Bool {
        guard let index = alarmLog.firstIndex(where: { $0.sequence == sequence && $0.isActive }) else { return false }
        if alarmLog[index].shelvedAt == nil { alarmLog[index].shelvedAt = Date() }
        return true
    }

    @discardableResult
    func unshelveAlarm(sequence: Int) -> Bool {
        guard let index = alarmLog.firstIndex(where: { $0.sequence == sequence }) else { return false }
        alarmLog[index].shelvedAt = nil
        return true
    }
}

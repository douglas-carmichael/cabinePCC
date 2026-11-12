import Foundation

// Operator-level verbs: ACKNOWLEDGE / SHELVE / UNSHELVE / ALLOCATE /
// DEALLOCATE / MOUNT / DISMOUNT / BACKUP / ANALYZE / EXAMINE / REPLY /
// REQUEST / RUN.
extension DCLEngine {
    /// ACKNOWLEDGE ALARM <id | ALL> [/CLEAR]
    ///
    /// Acknowledges a standing alarm, or all of them. With /CLEAR an event
    /// (a driver's report or call, a line file that was refused) is
    /// cleared as well, as the panel's CLEAR buttons do; a process-driven
    /// point is not the operator's to clear, and returns to normal when
    /// its condition does.
    func acknowledgeCmd(_ cmd: Parsed) -> String {
        guard let world else {
            return tr("dcl.ack.nosystem") + "\n"
        }
        guard let target = cmd.positional.first, matches(target, "ALARM", min: 3) else {
            return tr("dcl.ack.missalarm") + "\n"
        }
        guard cmd.positional.count >= 2 else {
            return tr("dcl.ack.missid") + "\n"
        }
        let clear = cmd.hasQualifier("CLEAR", min: 3)
        let id = cmd.positional[1].uppercased()
        // SELFTEST leaves the alarm log as it found it.
        if dryRun { return String(format: tr("dcl.ack.dryrun"), "ACKNOWLEDGE ALARM \(id)" + (clear ? " /CLEAR" : "")) + "\n" }
        if matches(id, "ALL", min: 1) {
            let count = world.acknowledgeAllAlarms()
            var s = count == 1 ? tr("dcl.ack.alarms.one") + "\n"
                               : String(format: tr("dcl.ack.alarms.many"), count) + "\n"
            if clear {
                s += String(format: tr("dcl.ack.cleared.many"), world.clearAcknowledgedActiveAlarms()) + "\n"
            }
            return s
        }
        guard let sequence = Int(id) else {
            return String(format: tr("dcl.ack.invalid"), cmd.positional[1]) + "\n"
        }
        let number = String(format: "%04d", sequence)
        guard world.acknowledgeAlarm(sequence: sequence) else {
            return String(format: tr("dcl.ack.notfound"), number) + "\n"
        }
        var s = String(format: tr("dcl.ack.alarm"), number) + "\n"
        if clear {
            if world.clearAlarm(sequence: sequence) {
                s += String(format: tr("dcl.ack.cleared"), number) + "\n"
            } else {
                fail("ACK-W-HELD", "%X000080F8")
                s += String(format: tr("dcl.ack.held"), number) + "\n"
            }
        }
        return s
    }

    /// SHELVE ALARM <id>  /  UNSHELVE ALARM <id> -- ISA-18.2 shelving.
    /// Shelving removes a nuisance alarm from the primary annunciator
    /// (beacon, panel, active count) while leaving it in the log; UNSHELVE
    /// restores it. Distinct from ACKNOWLEDGE (which keeps it annunciated).
    func shelveCmd(_ cmd: Parsed, unshelve: Bool) -> String {
        guard let world else {
            return tr("dcl.ack.nosystem") + "\n"
        }
        guard let target = cmd.positional.first, matches(target, "ALARM", min: 3) else {
            return tr(unshelve ? "dcl.unshelve.missalarm" : "dcl.shelve.missalarm") + "\n"
        }
        guard cmd.positional.count >= 2 else {
            return tr(unshelve ? "dcl.unshelve.missid" : "dcl.shelve.missid") + "\n"
        }
        guard let sequence = Int(cmd.positional[1]) else {
            return String(format: tr("dcl.ack.invalid"), cmd.positional[1]) + "\n"
        }
        let seqStr = String(format: "%04d", sequence)
        if dryRun {
            return String(format: tr("dcl.ack.dryrun"), (unshelve ? "UNSHELVE" : "SHELVE") + " ALARM \(seqStr)") + "\n"
        }
        let ok = unshelve ? world.unshelveAlarm(sequence: sequence)
                          : world.shelveAlarm(sequence: sequence)
        if ok {
            return String(format: tr(unshelve ? "dcl.unshelve.ok" : "dcl.shelve.ok"), seqStr) + "\n"
        }
        return String(format: tr("dcl.ack.notfound"), seqStr) + "\n"
    }

    /// ALLOCATE -- claim a device for the current process.
    func allocateCmd(_ cmd: Parsed) -> String {
        guard let raw = cmd.positional.first else {
            return "%ALLOC-F-NODEV, no device specified\n"
        }
        let dev = normalizeDevice(raw)
        if isSystemDevice(dev) {
            return noPriv("ALLOCATE \(dev)")
        }
        if allocatedDevices.contains(dev) {
            return "%ALLOC-W-ALLOCATED, _\(nodeName)$\(dev) already allocated\n"
        }
        allocatedDevices.insert(dev)
        return "%ALLOC-S-ALLOC, _\(nodeName)$\(dev) allocated\n"
    }

    func deallocateCmd(_ cmd: Parsed) -> String {
        guard let raw = cmd.positional.first else {
            if cmd.hasQualifier("ALL", min: 1) {
                let n = allocatedDevices.count
                allocatedDevices.removeAll()
                return "%DEALLOC-S-DEALLOC, \(n) device\(n == 1 ? "" : "s") deallocated\n"
            }
            return "%DEALLOC-F-NODEV, no device specified\n"
        }
        let dev = normalizeDevice(raw)
        if allocatedDevices.remove(dev) != nil {
            return "%DEALLOC-S-DEALLOC, _\(nodeName)$\(dev) deallocated\n"
        }
        return "%DEALLOC-W-NOTALLOC, _\(nodeName)$\(dev) was not allocated to this process\n"
    }

    func mountCmd(_ cmd: Parsed) -> String {
        guard let raw = cmd.positional.first else {
            return "%MOUNT-F-NODEV, no device specified\n"
        }
        let dev = normalizeDevice(raw)
        if isSystemDevice(dev) {
            return noPriv("MOUNT \(dev)")
        }
        let label = cmd.positional.count > 1 ? cmd.positional[1].uppercased()
                                              : (cmd.qualifierValue("VOLUME") ?? "SCRATCH")
        if mountedVolumes[dev] != nil {
            return "%MOUNT-W-MOUNTED, _\(nodeName)$\(dev) is already mounted\n"
        }
        mountedVolumes[dev] = label
        return "%MOUNT-I-MOUNTED, \(label) mounted on _\(nodeName)$\(dev)\n"
    }

    func dismountCmd(_ cmd: Parsed) -> String {
        guard let raw = cmd.positional.first else {
            return "%DISMNT-F-NODEV, no device specified\n"
        }
        let dev = normalizeDevice(raw)
        if mountedVolumes.removeValue(forKey: dev) != nil {
            return "%DISMNT-I-DISMOUNT, _\(nodeName)$\(dev) dismounted\n"
        }
        return "%DISMNT-W-NOTMNT, _\(nodeName)$\(dev) was not mounted\n"
    }

    func backupCmd(_ cmd: Parsed) -> String {
        guard cmd.positional.count >= 2 else {
            return "%BACKUP-F-NOSPEC, missing input or output specification\n"
        }
        let src = cmd.positional[0]
        let dst = cmd.positional[1]
        let now = Date()
        var s = "%BACKUP-I-IDENT, OpenVMS BACKUP V9.2-3 \(stamp(now))\n"
        s += "%BACKUP-I-STARTVERIFY, starting verification pass\n"
        s += "%BACKUP-S-CREATED, save set \(dst) created\n"
        s += "%BACKUP-S-COPIED, copied \(Int.random(in: 6...14)) files in \(Int.random(in: 800...2400)) blocks from \(src)\n"
        s += "%BACKUP-I-PROCDONE, operation completed\n"
        return s
    }

    func analyzeCmd(_ cmd: Parsed) -> String {
        if cmd.hasQualifier("ERROR_LOG", min: 4) || cmd.hasQualifier("ERROR", min: 4) {
            return showError()
        }
        if cmd.hasQualifier("AUDIT", min: 3) {
            return showAudit()
        }
        if cmd.hasQualifier("IMAGE", min: 3) || cmd.hasQualifier("CRASH_DUMP", min: 5) {
            return noPriv("ANALYZE\(cmd.hasQualifier("IMAGE", min: 3) ? "/IMAGE" : "/CRASH_DUMP")")
        }
        return "%ANALYZE-W-NOQUAL, ANALYZE requires /ERROR_LOG, /AUDIT, /IMAGE, or /CRASH_DUMP\n"
    }

    func runCmd(_ cmd: Parsed) -> String {
        guard let target = cmd.positional.first?.uppercased() else {
            return "%RUN-F-NOIMG, no image specified\n"
        }
        let stripped = target.hasSuffix(".EXE") ? String(target.dropLast(4)) : target
        // The PCC's two forms (DCLForms.swift) are the images an operator
        // may run.
        let kind: FormState.Kind
        switch stripped {
        case "RAME_DIR":  kind = .rames
        case "LIGNE_DIR": kind = .lines
        default:          return noPriv("RUN \(target)")
        }
        if dryRun {
            return "%RUN-S-PROC_ID, would launch \(stripped) form (dry-run)\n"
        }
        guard link != nil else { return tr("pcc.err.nolink") }
        startForm(kind)
        return ""
    }

    func examineCmd(_ cmd: Parsed) -> String {
        guard let raw = cmd.positional.first else {
            return "%EXAMINE-F-NOLOC, no address specified\n"
        }
        let addr: UInt64
        let trimmed = raw.uppercased().replacingOccurrences(of: "^X", with: "")
        if let v = UInt64(trimmed, radix: 16) {
            addr = v
        } else if let v = UInt64(trimmed) {
            addr = v
        } else {
            return "%EXAMINE-W-IVADDR, invalid address \\\(raw)\\\n"
        }
        let v = (addr &* 0x9E3779B1) ^ 0xDEADBEEF
        return String(format: "  %08llX:  %08llX\n", addr, v & 0xFFFFFFFF)
    }

    func replyCmd(_ cmd: Parsed) -> String {
        let msg = cmd.positional.joined(separator: " ").replacingOccurrences(of: "\"", with: "")
        if msg.isEmpty {
            return "%REPLY-F-NOMSG, no message text specified\n"
        }
        return "%REPLY-S-REPLIED, reply queued to OPA0:  \"\(msg)\"\n"
    }

    func requestCmd(_ cmd: Parsed) -> String {
        let msg = cmd.positional.joined(separator: " ").replacingOccurrences(of: "\"", with: "")
        if msg.isEmpty {
            return "%REQUEST-F-NOMSG, no message text specified\n"
        }
        return "%OPCOM-I-LOGGED, request from \(username) at \(stamp(Date())) -- \"\(msg)\"\n"
    }

    // MARK: -- helpers

    /// Strips a leading "_NODE$" prefix and adds a trailing colon so user
    /// input like "MUA0", "MUA0:", "_ASCEN1$MUA0:" maps to the same key.
    func normalizeDevice(_ raw: String) -> String {
        var s = raw.uppercased()
        if let dollar = s.firstIndex(of: "$") {
            s = String(s[s.index(after: dollar)...])
        }
        if !s.hasSuffix(":") { s += ":" }
        return s
    }

    /// System / production volumes the operator account cannot allocate.
    func isSystemDevice(_ dev: String) -> Bool {
        return dev.hasPrefix("DK") || dev.hasPrefix("PCC$") || dev.contains("SYS")
    }
}

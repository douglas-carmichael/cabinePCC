import Foundation

// SHOW family of commands -- one entry per `SHOW <keyword>` subcommand.
// All methods are extensions of the main DCLEngine class so they share
// state (`world`, `host`, `username` ...) directly.
extension DCLEngine {
    func showCmd(_ cmd: Parsed) -> String {
        guard let what = cmd.positional.first else {
            return missQual("SHOW")
        }
        let word = what.uppercased()
        switch true {
        case matches(what, "PROCESS",     min: 4): return showProcess(cmd)
        case matches(what, "SYSTEM",      min: 3): return showSystem()
        case matches(what, "USERS",       min: 4): return showUsers()
        case matches(what, "DEVICES",     min: 3): return showDevices()
        case matches(what, "MEMORY",      min: 3): return showMemory()
        case matches(what, "TIME"):                return showTime()
        case matches(what, "NETWORK",     min: 3): return showNetwork()
        // The PCC. The plural is the whole word: RAMES lists the trains
        // and RAME shows one, LINES the library and LINE the line.
        case matches(what, "PCC",         min: 3): return showPCC()
        case word == "RAMES":                      return showRames()
        case matches(what, "RAME",        min: 3): return showRame(cmd)
        case word == locQual(en: "LINES", fr: "LIGNES"):
            return showLines()
        case matchesLoc(what, en: "LINE", fr: "LIGNE", min: 3):
            return showLine(cmd)
        case matchesLoc(what, en: "CABS", fr: "CABINES", min: 3):
            return showCabs()
        case matches(what, "CONNECTIONS", min: 4): return showPCCConnections()
        case matches(what, "JOURNAL",     min: 3): return showJournal(cmd)
        case matches(what, "ALARMS",      min: 3): return showAlarms(cmd)
        case matches(what, "LOGICAL",     min: 3): return showLogical(cmd)
        case matches(what, "SYMBOL",      min: 3): return showSymbol(cmd)
        case matches(what, "ERROR",       min: 3): return showError()
        case matches(what, "STATUS",      min: 4): return showStatus()
        case matches(what, "LICENSE",     min: 3): return showLicense()
        case matches(what, "CPU"):                 return showCPU()
        case matches(what, "DEFAULT",     min: 3): return showDefault()
        case matches(what, "QUOTA",       min: 4): return showQuota()
        case matches(what, "PROTECTION",  min: 4): return showProtection()
        case matches(what, "TERMINAL",    min: 4): return showTerminal()
        case matches(what, "WORKING_SET", min: 4): return showWorkingSet()
        case matches(what, "VERSION",     min: 3): return showVersion()
        case matches(what, "RMS_DEFAULT", min: 3): return showRMS()
        case matches(what, "INTRUSION",   min: 3): return showIntrusion()
        case matches(what, "AUDIT",       min: 3): return showAudit()
        default:
            // DCLixKit answers only keywords this switch doesn't, and the
            // bridge reserves every name listed above so it cannot shadow
            // one of them.
            if let text = dclixShow(cmd) { return text }
            fail("DCL-W-IVKEYW", "%X00038088")
            return "%DCL-W-IVKEYW, unrecognized keyword - check validity and spelling\n   \\\(what)\\\n"
        }
    }

    func showAlarms(_ cmd: Parsed) -> String {
        // Default view mirrors the annunciator/panel: only standing
        // (uncleared, unshelved) alarms, priority-sorted. /ALL dumps the full
        // journal -- RTN / CLEARED / SHLVD history included -- for audit. This
        // is why CLEAR ALL empties the default list but the history survives.
        let showAll = cmd.hasQualifier("ALL", min: 3)
        let alarms = showAll ? (world?.alarmLog ?? []) : (world?.activeAlarms ?? [])
        var s = "\n" + String(format: tr(showAll ? "dcl.alarm.title" : "dcl.alarm.title.active"), stamp(Date())) + "\n"
        s += tr("dcl.alarm.header") + "\n"
        s += "  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------\n"
        guard !alarms.isEmpty else {
            s += tr(showAll ? "dcl.alarm.none" : "dcl.alarm.none.active") + "\n"
            return s
        }
        for alarm in alarms.prefix(40) {
            let id = String(format: "%04d", alarm.sequence)
            // stamp() returns 23 chars ("dd-MMM-yyyy HH:mm:ss.SS"); the
            // Time column dashes reserve 27. Pad so Severity lines up.
            let time = stamp(alarm.raisedAt).padding(toLength: 27, withPad: " ", startingAt: 0)
            let sev = alarmSeverityLabel(alarm.severity).padding(toLength: 9, withPad: " ", startingAt: 0)
            let state = alarmStatusLabel(alarm).padding(toLength: 7, withPad: " ", startingAt: 0)
            let source = alarm.source.padding(toLength: 10, withPad: " ", startingAt: 0)
            let point = alarm.point.padding(toLength: 13, withPad: " ", startingAt: 0)
            s += "  \(id)  \(time)  \(sev)  \(state)  \(source)  \(point)  \(alarmMessage(alarm.message))\n"
        }
        s += "\n" + tr("dcl.alarm.ackhint") + "\n"
        // In the active view, point the operator at /ALL for cleared history.
        if !showAll { s += tr("dcl.alarm.allhint") + "\n" }
        return s
    }

    private func alarmSeverityLabel(_ severity: AlarmSeverity) -> String {
        switch severity {
        case .advisory: return tr("alarm.sev.advisory")
        case .minor: return tr("alarm.sev.minor")
        case .major: return tr("alarm.sev.major")
        case .critical: return tr("alarm.sev.critical")
        }
    }

    private func alarmStatusLabel(_ alarm: SCADAAlarm) -> String {
        // Mirrors SCADAAlarm.statusLabel precedence with localized text.
        if alarm.isShelved { return tr("alarm.status.shlvd") }
        if alarm.clearedAt != nil {
            return alarm.isAcknowledged ? tr("alarm.status.cleared") : tr("alarm.status.rtn")
        }
        return alarm.isAcknowledged ? tr("alarm.status.ack") : tr("alarm.status.unack")
    }

    /// Alarm messages are stored in English (the log is in-universe VMS
    /// output); localize known messages for display.
    func alarmMessage(_ message: String) -> String {
        for key in Strings.alarmMessageKeys {
            if message == Strings.lookup(key, lang: .en) { return tr(key) }
        }
        return message
    }

    func showProcess(_ cmd: Parsed) -> String {
        let now = Date()
        let upS = Int(host.uptime())
        var s = "\n\(stamp(now))   User: \(username.padding(toLength: 12, withPad: " ", startingAt: 0))   Process ID:   \(pid)\n"
        s += "                          Node: \(nodeName.padding(toLength: 8, withPad: " ", startingAt: 0))       Process name: \"DCL_\(username)\"\n\n"
        s += "Terminal:            \(terminalName)\n"
        s += "User Identifier:     [PCC,\(username)]\n"
        s += "Base priority:       4\n"
        s += "Default file spec:   \(defaultDevice)\(defaultDirectory)\n"
        s += "Devices allocated:   none\n\n"
        s += "Process Quotas:\n"
        s += " Account name:                  PCC_ROOM\n"
        s += " CPU limit:                     Infinite       Direct I/O limit:      150\n"
        s += " Buffered I/O byte count quota: 65536          Buffered I/O limit:    150\n"
        s += " Timer queue entry quota:       20             Open file quota:       100\n"
        s += " Paging file quota:             50000          Subprocess quota:      8\n"
        s += " Default page fault cluster:    64             AST quota:             250\n"
        s += " Enqueue quota:                 200            Shared file limit:     0\n"
        s += " Max detached processes:        0              Max active jobs:       0\n\n"
        s += "Accounting information:\n"
        s += String(format: " Buffered I/O count:            %-12d  Peak working set size:    1648\n", upS / 4)
        s += String(format: " Direct I/O count:              %-12d  Peak page file size:     20384\n", upS / 8)
        s += String(format: " Page faults:                   %-12d  Mounted volumes:             0\n", upS / 2)
        s += " Images activated:              3\n"
        s += String(format: " Elapsed CPU time:              0 00:%02d:%02d.%02d\n",
                    (upS / 60) % 60, upS % 60, (upS * 7) % 100)
        s += String(format: " Connect time:                  %@\n", uptimeString(from: bootTime, to: now))
        if cmd.hasQualifier("ALL", min: 1) {
            s += "\nProcess rights:\n"
            s += "  INTERACTIVE\n"
            s += "  LOCAL\n"
            s += "  PCC_OPERATOR\n"
            s += "System rights:\n"
            s += "  SYS$NODE_\(nodeName)\n"
        }
        return s
    }

    func showSystem() -> String {
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(sessionStart))
        let uptime = uptimeString(from: bootTime, to: now)
        let loads = host.loadAverages()
        let procCount = host.processCount()
        var s = "\n\(osTitle) \(osVersion) on node \(nodeName)  \(stamp(now))  Uptime  \(uptime)\n"
        s += String(format: "  Load average: %.2f  %.2f  %.2f    Active processes: %d\n",
                    loads.one, loads.five, loads.fifteen, procCount)
        s += "  Pid    Process Name      State  Pri      I/O       CPU       Page flts Pages\n"

        // Synthetic process model: each row defines a baseline plus growth
        // rates so I/O, CPU time and page-fault counters tick upward on
        // every SHOW SYSTEM refresh, page counts oscillate around their
        // working-set baseline, and LEF processes flicker briefly to COM
        // as if they were waking to service a request -- the table looks
        // like a live VMS box instead of a frozen snapshot.
        for p in Self.systemProcs {
            s += renderSysProc(p, elapsed: elapsed)
        }

        // The PCC's processes, in the state the PCC is in: the engine
        // computes while a line runs, the listener waits for a cab, and
        // each cab in service has the process of its link.
        for (i, process) in pccProcesses().enumerated() {
            let phase = Double(i) * 1.7
            let io = 800 + i * 47 + Int(0.9 * elapsed) + Int(sin(elapsed / 5.3 + phase) * 14)
            let cpu = Double(12 + i) + Double((i * 17 + 9) % 100) / 100.0 + 0.045 * elapsed * process.share * 4
            let flts = 320 + i * 18 + Int(0.18 * elapsed)
            let pgs = 610 + i * 8 + Int(sin(elapsed / 7.1 + phase) * 22)
            s += sysLine(process.pid, process.name, process.state, i == 0 ? 8 : 6, io, formatVMSCPUTime(cpu), flts, max(0, pgs))
        }

        for p in Self.serviceProcs {
            s += renderSysProc(p, elapsed: elapsed)
        }

        // The operator's own DCL process: CUR (current) so the table
        // always ends with the row the user is typing from.
        let userName = "DCL_" + String(username.prefix(12))
        let userIO   = 21 + Int(0.3 * elapsed)
        let userCPU  = 0.18 + 0.0008 * elapsed
        let userFlts = 24 + Int(0.05 * elapsed)
        let userPgs  = 148 + Int(sin(elapsed / 4.2) * 7)
        s += sysLine(pid, userName, "CUR", 4, userIO, formatVMSCPUTime(userCPU), userFlts, max(0, userPgs))
        return s
    }

    private func sysLine(_ pid: String, _ name: String, _ state: String, _ pri: Int, _ io: Int, _ cpu: String, _ faults: Int, _ pages: Int) -> String {
        let padName = name.padding(toLength: 16, withPad: " ", startingAt: 0)
        return "\(pid) \(padName) \(state)    \(String(format: "%2d", pri))   \(String(format: "%6d", io))   \(cpu)       \(String(format: "%4d", faults))  \(String(format: "%4d", pages))\n"
    }

    /// Synthetic-process descriptor. Baseline values come from a typical
    /// snapshot of an active node; the rates produce believable per-second
    /// growth so the table looks alive on repeated SHOW SYSTEM.
    struct SysProc {
        let pid: String
        let name: String
        let baseState: String
        let pri: Int
        let ioBase: Int
        let ioRate: Double         // I/O ops per second
        let cpuBaseSec: Double     // CPU seconds at session start
        let cpuRate: Double        // CPU share (0..1) of wall time
        let faultBase: Int
        let faultRate: Double      // page faults per second
        let pagesBase: Int
        let pagesAmp: Int          // working-set oscillation amplitude
    }

    /// The system's own tasks, shown above the PCC's processes.
    static let systemProcs: [SysProc] = [
        SysProc(pid: "00000401", name: "SWAPPER",       baseState: "HIB", pri: 16,
                ioBase: 0,    ioRate: 0,    cpuBaseSec: 1.21,    cpuRate: 0.00005,
                faultBase: 0,    faultRate: 0,    pagesBase: 0,    pagesAmp: 0),
        SysProc(pid: "00000402", name: "NULL",          baseState: "COM", pri: 0,
                ioBase: 0,    ioRate: 0,    cpuBaseSec: 259_200, cpuRate: 0.55,
                faultBase: 0,    faultRate: 0,    pagesBase: 0,    pagesAmp: 0),
    ]

    /// The journal and the telnet service, shown below them.
    static let serviceProcs: [SysProc] = [
        SysProc(pid: "00000414", name: "LOGGER",        baseState: "LEF", pri: 4,
                ioBase: 208,  ioRate: 0.18, cpuBaseSec: 4.81,    cpuRate: 0.0008,
                faultBase: 72, faultRate: 0.02, pagesBase: 246, pagesAmp: 16),
        SysProc(pid: "00000415", name: "TELNET_SERVER", baseState: "LEF", pri: 6,
                ioBase: 144,  ioRate: 0.12, cpuBaseSec: 1.95,    cpuRate: 0.0003,
                faultBase: 108, faultRate: 0.04, pagesBase: 384, pagesAmp: 16),
    ]

    private func renderSysProc(_ p: SysProc, elapsed: Double) -> String {
        let io  = p.ioBase + Int(p.ioRate * elapsed)
        let cpu = p.cpuBaseSec + p.cpuRate * elapsed
        let flt = p.faultBase + Int(p.faultRate * elapsed)
        // Stable per-process phase derived from the PID so two processes
        // don't oscillate in lockstep.
        let phase = Double(abs(p.pid.hashValue) % 360) * .pi / 180.0
        let pgs  = p.pagesBase + Int(sin(elapsed / 6.0 + phase) * Double(p.pagesAmp))
        // LEF (local-event-flag wait) processes occasionally flicker to COM
        // for a 2-tick burst as if they were waking to service a request.
        let bucket = (Int(elapsed * 0.3) + abs(p.pid.hashValue)) % 20
        let state  = (p.baseState == "LEF" && bucket < 2) ? "COM" : p.baseState
        return sysLine(p.pid, p.name, state, p.pri, io, formatVMSCPUTime(cpu), flt, max(0, pgs))
    }

    /// VMS-style CPU-time string: "<days> <hh>:<mm>:<ss>.<NN>" using
    /// hundredths for the fractional part, matching real `SHOW SYSTEM`.
    func formatVMSCPUTime(_ seconds: Double) -> String {
        let clamp = max(0, seconds)
        let total = Int(clamp * 100)
        let hundredths = total % 100
        let totalSec = total / 100
        let d = totalSec / 86_400
        let h = (totalSec % 86_400) / 3600
        let m = (totalSec % 3600) / 60
        let ss = totalSec % 60
        return String(format: "%d %02d:%02d:%02d.%02d", d, h, m, ss, hundredths)
    }

    func showUsers() -> String {
        var s = "\n       OpenVMS User Processes at \(stamp(Date()))\n"
        s += "       Total number of users = 1, number of processes = \(pccProcesses().count + 5)\n\n"
        s += "  Username     Process Name         PID      Terminal\n"
        s += "  \(username.padding(toLength: 12, withPad: " ", startingAt: 0)) DCL_\(username.prefix(12).padding(toLength: 16, withPad: " ", startingAt: 0)) \(pid) \(terminalName)\n"
        return s
    }

    func showDevices() -> String {
        // Column layout (fixed widths so values can't crowd the next
        // column even when the disk is multi-terabyte and free-block
        // counts run to 11 digits). Swift's String(format:) ignores
        // width on %@, so do the padding ourselves.
        func padLeft(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        func padRight(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
        }
        func row(_ name: String, _ status: String, _ err: String,
                 _ label: String, _ free: String, _ trans: String, _ mnt: String) -> String {
            return padLeft(name,   16) + " "
                +  padLeft(status, 10) + " "
                +  padRight(err,    5) + "  "
                +  padLeft(label,  18) + " "
                +  padRight(free,  14) + " "
                +  padRight(trans,  6) + " "
                +  padRight(mnt,    4) + "\n"
        }
        var s = "\n"
        s += row("Device", "Device", "Error", "Volume", "Free",   "Trans", "Mnt")
        s += row(" Name",  "Status", "Count", " Label", "Blocks", "Count", "Cnt")

        let volumes = host.mountedVolumes()
        for (i, vol) in volumes.enumerated() {
            let dev = "DKA\(i):"
            let label = vol.vmsLabel
            let free = String(vol.freeBlocks)
            let trans = i == 0 ? 44 : max(1, 12 - (i - 1) * 3)
            s += row(dev, "Mounted", "0", label, free, String(trans), "1")
        }
        s += row("EWA0:",      "Online", "0", "(none)", "-", "-", "-")
        s += row(terminalName, "Online", "0", "(none)", "-", "-", "-")
        return s
    }

    func showMemory() -> String {
        let vm = host.vmStats()
        let procCount = host.processCount()
        let resident = max(1, procCount - 8)

        // VMS accounts for every physical page as free, on the modified list,
        // or in use -- so the three sum to Total. Derive Free that way (rather
        // than the raw Mach free_count, which excludes speculative/other
        // categories) so the row is internally consistent.
        let totalPages = vm.totalPages
        let inUse      = min(vm.inUsePages, totalPages)
        let modified   = min(vm.modifiedPages, totalPages - inUse)
        let free       = totalPages - inUse - modified

        var s = "\n                System Memory Resources on \(stamp(Date()))\n\n"
        s += "Physical Memory Usage (pages):     Total       Free      In Use     Modified\n"
        let memLabel = "  Main Memory (\(HostStats.memSize(host.usableMemoryBytes)))"
            .padding(toLength: 32, withPad: " ", startingAt: 0)
        s += memLabel + String(format: "%8llu   %8llu    %8llu     %8llu\n",
                               totalPages, free, inUse, modified)
        s += "\nSlot Usage (slots):                Total       Free   Resident      Swapped\n"
        s += String(format: "  Process Entry Slots             %4d       %4d       %4d            0\n",
                    max(procCount + 32, 160), 32, procCount)
        s += String(format: "  Balance Set Slots               %4d       %4d       %4d            0\n",
                    max(resident + 18, 140), 18, resident)
        // Dynamic-memory pools have no direct Mach analog -- oscillate
        // around realistic baselines so the figures look like a live
        // VMS kernel rather than a frozen snapshot.
        let t = Date().timeIntervalSinceReferenceDate
        let npTotal = 524288
        let npFree  = 94216 + Int(sin(t / 7.0) * 6400)
        let npUse   = npTotal - npFree
        let npLarge = 18432 + Int(sin(t / 11.0 + 1.3) * 1800)
        let pgTotal = 262144
        let pgFree  = 72488 + Int(sin(t / 6.0 + 0.7) * 3200)
        let pgUse   = pgTotal - pgFree
        let pgLarge = 12104 + Int(sin(t / 13.0 + 2.4) * 900)
        s += "\nDynamic Memory Usage (bytes):      Total       Free    In Use      Largest\n"
        s += String(format: "  Non-Paged Dynamic Memory      %8d   %8d  %8d     %8d\n",
                    npTotal, max(0, npFree), max(0, npUse), max(0, npLarge))
        s += String(format: "  Paged Dynamic Memory          %8d   %8d  %8d     %8d\n\n",
                    pgTotal, max(0, pgFree), max(0, pgUse), max(0, pgLarge))
        s += "Paging File Usage (pages):     Free  Reservable      Total\n"
        s += "  DISK$PCC_SYS:[SYS0.SYSEXE]PAGEFILE.SYS\n"
        // Back the page file with the host's real swap (sysctl vm.swapusage),
        // expressed in the same page unit as the rest of the display. Before
        // macOS activates any swap the sysctl reports zero, so fall back to a
        // RAM-derived figure to keep the section reading like a live VMS
        // backing store rather than an empty 0/0/0.
        let swap = host.swapUsage()
        let pfFree: UInt64, pfReservable: UInt64, pfTotal: UInt64
        if swap.totalBytes > 0 {
            pfTotal      = swap.totalBytes / host.pageSize
            pfFree       = swap.freeBytes  / host.pageSize
            pfReservable = pfFree
        } else {
            pfTotal      = vm.totalPages
            pfFree       = vm.freePages
            pfReservable = vm.freePages + vm.inactivePages
        }
        s += String(format: "                              %8llu    %8llu   %8llu\n",
                    pfFree, pfReservable, pfTotal)
        return s
    }

    func showTime() -> String {
        return "  \(stamp(Date()))\n"
    }

    func showNetwork() -> String {
        // Header, separator and every data row share one fixed-width builder
        // so the columns line up regardless of node-name / count widths.
        func row(_ node: String, _ state: String, _ links: String,
                 _ delay: String, _ cost: String, _ hops: String, _ name: String) -> String {
            return "  "
                + node.padding(toLength: 9, withPad: " ", startingAt: 0)
                + state.padding(toLength: 12, withPad: " ", startingAt: 0)
                + rightPad(links, width: 12) + "   "
                + rightPad(delay, width: 5) + "   "
                + rightPad(cost,  width: 4) + "   "
                + rightPad(hops,  width: 4) + "  "
                + name + "\n"
        }
        var s = "\n" + row("Node", "State", "Active Links", "Delay", "Cost", "Hops", "Name")
        s += row("----", "-----", "------------", "-----", "----", "----", "----")
        s += row("1.1", "LOCAL", "0", "0", "0", "0", nodeName)
        s += row("-", "-", "-", "-", "-", "-", "(no adjacent nodes)")
        return s
    }

    func showLogical(_ cmd: Parsed) -> String {
        let procOnly = cmd.hasQualifier("PROCESS", min: 4)
        var s = "\n"
        if !procOnly {
            s += "(LNM$SYSTEM_TABLE)\n"
            s += "  \"PCC$ROOT\"                  = \"DISK$PCC_SYS:[PCC]\"\n"
            s += "  \"PCC$LINES\"                 = \"DISK$PCC_DATA:[LINES]\"\n"
            s += "  \"PCC$JOURNAL\"               = \"DISK$PCC_DATA:[JOURNAL]\"\n"
            s += "  \"SYS$NODE\"                  = \"\(nodeName)::\"\n"
            s += "  \"SYS$LOGIN\"                 = \"PCC$ROOT:[\(username)]\"\n"
            s += "  \"SYS$SYSDEVICE\"             = \"DISK$PCC_SYS:\"\n"
            s += "  \"SYS$DISK\"                  = \"\(defaultDevice)\"\n"
        }
        s += "\n(LNM$PROCESS_TABLE)\n"
        s += "  \"SYS$COMMAND\"                = \"\(terminalName)\"\n"
        s += "  \"SYS$INPUT\"                  = \"\(terminalName)\"\n"
        s += "  \"SYS$OUTPUT\"                 = \"\(terminalName)\"\n"
        s += "  \"SYS$ERROR\"                  = \"\(terminalName)\"\n"
        for key in processLogicals.keys.sorted() {
            let padded = ("\"" + key + "\"").padding(toLength: 28, withPad: " ", startingAt: 0)
            s += "  \(padded) = \"\(processLogicals[key] ?? "")\"\n"
        }
        return s
    }

    func showSymbol(_ cmd: Parsed) -> String {
        if let name = cmd.positional.dropFirst().first {
            let key = name.uppercased()
            if let builtin = builtinSymbol(key) {
                return "  \(key) = \"\(builtin)\"\n"
            }
            if let v = symbols[key] {
                return "  \(key) = \"\(v)\"\n"
            }
            fail("DCL-W-UNDSYM", "%X00038150")
            return "%DCL-W-UNDSYM, undefined symbol - check validity and spelling\n"
        }
        if symbols.isEmpty {
            return "  (no local or global symbols defined)\n"
        }
        var s = "\n"
        for k in symbols.keys.sorted() {
            s += "  \(k) = \"\(symbols[k] ?? "")\"\n"
        }
        return s
    }

    /// DCL exposes a few read-only built-in symbols every shell sees.
    func builtinSymbol(_ name: String) -> String? {
        switch name {
        case "$STATUS":   return statusBefore ?? lastStatus
        case "$SEVERITY":
            let status = statusBefore ?? lastStatus
            let parsed = UInt32(status.replacingOccurrences(of: "%X", with: ""), radix: 16) ?? 1
            return String(parsed & 0x7)
        case "$RESTART":  return "FALSE"
        case "$PID":      return pid
        case "$PROCESS":  return "DCL_\(username)"
        // The active interface language, resolved live so a script sees
        // the language in force when it RUNS (the CLI vocabulary is
        // gated on it). Read-only: the lookup order consults builtins
        // before user symbols, so it cannot be shadowed.
        case "PCC$LANGUAGE": return uiLang == .fr ? "FR" : "EN"
        // The PCC, read live like the language: the id of the line it is
        // on (empty on none), the line's mode, and how many trains and
        // cabs. F$PCC() and F$RAME() read the rest.
        case "PCC$LINE":  return pccLexical("LINE")
        case "PCC$MODE":  return pccLexical("MODE")
        case "PCC$RAMES": return pccLexical("RAMES")
        case "PCC$CABS":  return pccLexical("CABS")
        default:          return nil
        }
    }

    func showError() -> String {
        let baseSeq = 4870 + Int.random(in: 0...12)
        var s = "\nERROR LOG SUMMARY -- last 5 entries\n"
        s += "   Sequence  Date / Time             Source           Code           Detail\n"
        s += "   ---------+------------------------+----------------+--------------+-----------------------------------\n"
        // %%X escapes %% so printf emits a literal "%X" -- without the escape
        // printf treats %X as a hex specifier and reads uninitialized memory
        // for the missing argument, printing garbage where the code should be.
        s += String(format: "    %7d  \(stamp(Date().addingTimeInterval(-2400)))  PCC_LISTENER     %%X0000002C     CONNECT TIMEOUT, retried (success)\n", baseSeq + 0)
        s += String(format: "    %7d  \(stamp(Date().addingTimeInterval(-1820)))  PCC_ENGINE       %%X00000018     STEP OVERRUN: 1 beat lost, clock kept\n", baseSeq + 11)
        s += String(format: "    %7d  \(stamp(Date().addingTimeInterval(-1100)))  PCC_SCADA        %%X00000004     INFO: alarm log rotated\n", baseSeq + 20)
        s += String(format: "    %7d  \(stamp(Date().addingTimeInterval(-220)))  TELNET_SERVER    %%X00000040     SESSION CLOSED BY PEER\n", baseSeq + 31)
        s += String(format: "    %7d  \(stamp(Date().addingTimeInterval(-12)))  LOGGER           %%X00000001     SS$_NORMAL, journal flushed\n", baseSeq + 40)
        return s
    }

    func showStatus() -> String {
        let upS = Int(host.uptime())
        var s = "\n  Status on \(stamp(Date()))\n"
        s += String(format: "  Elapsed CPU: 0 00:%02d:%02d.%02d   Buf I/O: %-6d   Dir I/O: %-6d   Page faults: %-6d\n",
                    (upS / 60) % 60, upS % 60, (upS * 7) % 100,
                    upS / 4, upS / 8, upS / 2)
        s += "  Connect time: \(uptimeString(from: bootTime, to: Date()))\n"
        // What the PCC is doing, in a line: OpenVMS's own status is
        // English, the PCC's is the layered product's and localized.
        if let link {
            link.refresh()
            if let snapshot = link.snapshot, let line = snapshot.line {
                s += "  " + String(format: tr("pcc.dcl.status"), line.identity.name, PCCText.mode(snapshot.mode, tr),
                                   snapshot.rames.count, snapshot.cabs.count) + "\n"
                for rame in snapshot.rames.sorted(by: { $0.number < $1.number }) where rame.held || rame.braked {
                    s += "    " + tr("pcc.rame") + " " + PCCText.number(rame.number) + ": "
                        + PCCText.flags(of: rame, tr).joined(separator: ", ") + "\n"
                }
            } else {
                s += "  " + tr(link.snapshot == nil ? "pcc.refusal.notrunning" : "pcc.noline") + "\n"
            }
        }
        return s
    }

    func showLicense() -> String {
        var s = "\nActive licenses on \(nodeName) (\(osTitle) \(osVersion)):\n\n"
        s += "OPENVMS-X86          Active            (loaded)\n"
        s += "DECNET-PLUS          Active            (loaded)\n"
        s += "LPD-PCC-CABINE       Active            (loaded)\n"
        return s
    }

    func showCPU() -> String {
        let now = Date()
        let usage = host.cpuUsage()
        let kernel = usage.system * 0.55
        let exec   = usage.system * 0.25
        let super_ = usage.system * 0.15
        let intr   = usage.system * 0.05

        let freqLabel: String
        if host.cpuFrequencyMHz > 0 {
            freqLabel = "\(host.cpuFrequencyMHz) MHz"
        } else {
            freqLabel = "host clock"
        }
        let cores = "\(host.activeProcessorCount) of \(host.processorCount) processors online"

        var s = "\n  CPU 0  (\(freqLabel))  -- \(stamp(now))\n"
        s += "    Model:     \(host.cpuModel)\n"
        s += "    Mode:      Multiprocessing primary\n"
        s += "    State:     Run   [\(cores)]\n"
        s += String(format: "    Idle:      %5.2f%%\n", usage.idle)
        s += String(format: "    Kernel:    %5.2f%%\n", kernel)
        s += String(format: "    Exec:      %5.2f%%\n", exec)
        s += String(format: "    Super:     %5.2f%%\n", super_)
        s += String(format: "    User:      %5.2f%%\n", usage.user + usage.nice)
        s += String(format: "    Interrupt: %5.2f%%\n", intr)
        return s
    }

    func showDefault() -> String {
        return "  \(defaultDevice)\(defaultDirectory)\n"
    }

    func showQuota() -> String {
        // Real boot-volume capacity in 512-byte VMS blocks. "Used" is total
        // minus free; "authorized" is the whole volume; overdraft mirrors
        // VMS's small soft cushion.
        let boot = host.bootVolume()
        let authorized = boot?.totalBlocks ?? 0
        let available  = boot?.freeBlocks  ?? 0
        let used = max(0, authorized - available)
        let overdraft = max(1024, authorized / 4096)
        var s = "\nUser [PCC,\(username)] has \(used) blocks used, \(available) available,\n"
        s += "   of \(authorized) authorized and permitted overdraft of \(overdraft) blocks on \(defaultDevice)\n"
        return s
    }

    func showProtection() -> String {
        return "  SYSTEM=RWED, OWNER=RWED, GROUP=RE, WORLD=NO ACCESS\n"
    }

    func showTerminal() -> String {
        var s = "\nTerminal:  \(terminalName)        Device_Type: VT100         Owner: \(username)\n\n"
        s += "Input:    9600  LFfill: 0  Width: \(terminalWidth)  Parity: None\n"
        s += "Output:   9600  CRfill: 0  Page:  \(terminalPage)\n\n"
        s += "Terminal Characteristics:\n"
        s += "  Interactive    Echo            Type_ahead     No Escape\n"
        s += "  No Hostsync    TTsync          Lowercase      Tab\n"
        s += "  Wrap           Scope           No Remote      Eightbit\n"
        s += "  Broadcast      No Readsync     No Form        Fulldup\n"
        s += "  No Modem       No Local_echo   No Autobaud    Hangup\n"
        s += "  No Brdcstmbx   No DMA          No Altypeahd   Set_speed\n"
        s += "  No Commsync    Line Editing    Overstrike editing            Smooth Scroll\n"
        s += "  No Fallback    No Dialup       No Secure server\n"
        s += "  No Disconnect  No Pasthru      No Syspassword                No SIXEL Graphics\n"
        s += "  No Soft Characters             No Printer Port               Numeric Keypad\n"
        s += "  ANSI_CRT       Edit_mode       DEC_CRT        DEC_CRT2      DEC_CRT3\n"
        s += "  Advanced_video Block_mode      No Regis       No Printer\n"
        return s
    }

    func showWorkingSet() -> String {
        // Resident size of this process from task_info; quota/extent are
        // expressed as multiples of the live working set so the VMS-style
        // /Limit, /Quota, /Extent triple is anchored to a real measurement.
        let ws = host.workingSet()
        let resident = Int(ws.residentPages)
        let limit  = max(2048, resident)
        let quota  = max(limit * 2,  8192)
        let extent = max(quota * 2, 16384)
        var s = "\nWorking Set     /Limit=\(limit)  /Quota=\(quota)  /Extent=\(extent)\n"
        s += "Adjustment enabled    Authorized Quota=\(quota)   Authorized Extent=\(extent)\n"
        s += "Current size:   \(resident) pages   (\(ws.residentBytes / 1024) KB resident)\n"
        return s
    }

    func showVersion() -> String {
        return "\n\(osTitle) \(osVersion)\n"
    }

    func showRMS() -> String {
        var s = "\nRMS_DEFAULT process values:\n"
        s += "  Multiblock count:        16        Multibuffer counts:\n"
        s += "                                       Indexed:  0    Relative:  0\n"
        s += "                                       Sequential: 0  Network:   0\n"
        s += "  Prolog level:             0        Extend quantity:        0\n"
        s += "  Block count:             32        Buffer count:           4\n"
        return s
    }

    func showIntrusion() -> String {
        var s = "\nIntrusion   Type      Count    Expiration    Source\n"
        s += "   (no intrusion records found)\n"
        return s
    }

    func showAudit() -> String {
        return "\nSystem security audit characteristics:\n  Security alarm failure mode = NONE\n  Security audit failure mode = NONE\n  (no recent audit events)\n"
    }
}

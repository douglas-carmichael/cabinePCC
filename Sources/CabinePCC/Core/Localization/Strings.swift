import Foundation

// LANGUAGE DISCIPLINE.
//
// The UI is strictly bilingual: in EN mode no French appears and in FR
// mode no English appears, with three deliberate in-universe exceptions:
//   * OpenVMS SYSTEM messages / tables in the DCL terminal stay English in
//     both modes (real VMS shipped English-only), and so does the HELP
//     library; only LPD layered-product content (the PCC's verbs, monitors
//     and forms, the alarms display) localizes.
//   * Identifiers are language-neutral and identical in both modes: DCL
//     verbs and the qualifiers that read the same in both languages, the
//     `%PCC-x-IDENT` message codes, SCADA source/point tags (CABINE 21,
//     LIAISON, FU, AU...), VMS process/facility names, the words of the
//     wire that a command procedure reads (NORMAL, TRUE...), and proper
//     nouns (station and line names, PCC, LPD, Cabine).
//   * What comes from outside is shown as it came: a cab's name, a driver's
//     own words, the credits a line's package gives for its data, and the
//     engine's reason for refusing a line file.
//
// The railway's own command words are gated by the language instead (LINE
// and LIGNE, /HOLD and /RETENIR...): see DCLEngine.matchesLoc.
//
// The table is in three files: this one, which looks a key up; the shell's
// and the windows' own strings (Strings+Shell.swift); and the PCC's
// (Strings+PCC.swift). Every key used anywhere must be in it, in both
// languages: `lookup` falls back to the raw key, which reads as a bug on
// screen.

enum Strings {
    static let table: [String: [Lang: String]] = buildTable()

    /// Every alarm-message key the link can raise. SHOW ALARMS, the
    /// monitors and the SCADA panel use this list to localize the (English)
    /// stored message back into the UI language.
    static let alarmMessageKeys: [String] = [
        "alarm.msg.emergency", "alarm.msg.fu",
        "alarm.msg.cab.silent", "alarm.msg.cab.revision", "alarm.msg.cab.call",
        "alarm.msg.cab.report.radiocheck", "alarm.msg.cab.report.readytodepart",
        "alarm.msg.cab.report.stoppedatsignal", "alarm.msg.cab.report.passengerill",
        "alarm.msg.cab.report.technicalfault", "alarm.msg.cab.report.incidentover",
        "alarm.msg.cab.report.requestcall", "alarm.msg.cab.report.other",
        "alarm.msg.pcc.listener", "alarm.msg.pcc.linefile", "alarm.msg.pcc.linenotheld",
    ]

    private static func buildTable() -> [String: [Lang: String]] {
        var table: [String: [Lang: String]] = [:]
        addShellStrings(to: &table)
        addPCCStrings(to: &table)
        return table
    }

    static func lookup(_ key: String, lang: Lang) -> String {
        if let row = table[key], let value = row[lang] { return value }
        if let row = table[key], let fallback = row[.en] { return fallback }
        return key
    }
}

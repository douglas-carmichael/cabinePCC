import Foundation

/// On-disk store for user-authored .COM files. The app's lives under
/// ~/Library/Application Support/CabinePCC/COM/ so files round-trip
/// across launches.  TYPE, DIRECTORY, CREATE, DELETE, EDIT and @file all
/// consult this store; STARTUP.COM and a small set of sample scripts are
/// seeded on first use so the operator has something to try.
final class DCLScriptStore {
    struct FileInfo {
        let name: String        // Canonical "FOO.COM"
        let version: Int        // OpenVMS ;ver -- always 1 here
        let bytes: Int
        let modified: Date
    }

    private let root: URL

    /// Absolute path of the on-disk store, surfaced through HELP STORAGE
    /// and the MAIL/.LOG output of SUBMIT so an operator can locate the
    /// real files outside the shell (Finder, shell, backups).
    var rootPath: String { root.path }

    /// - Parameter root: the folder the files are kept in: the node's
    ///   `COM` folder (PCCEnvironment.comFolder).
    init(root: URL) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        seedIfNeeded()
    }

    /// Canonical filename: uppercase, with a ".COM" suffix when none given.
    func normalize(_ raw: String) -> String {
        var s = raw.uppercased()
        // Drop any leading device/directory and trailing version ";n".
        if let bracket = s.lastIndex(of: "]") {
            s = String(s[s.index(after: bracket)...])
        }
        if let colon = s.lastIndex(of: ":") {
            s = String(s[s.index(after: colon)...])
        }
        if let semi = s.firstIndex(of: ";") {
            s = String(s[..<semi])
        }
        if !s.contains(".") { s += ".COM" }
        return s
    }

    private func url(for name: String) -> URL {
        return root.appendingPathComponent(name)
    }

    func read(name: String) -> String? {
        let u = url(for: normalize(name))
        return (try? String(contentsOf: u, encoding: .utf8))
    }

    @discardableResult
    func write(name: String, body: String) -> Bool {
        let u = url(for: normalize(name))
        do {
            try body.write(to: u, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func delete(name: String) -> Bool {
        let u = url(for: normalize(name))
        do {
            try FileManager.default.removeItem(at: u)
            return true
        } catch {
            return false
        }
    }

    func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: normalize(name)).path)
    }

    func list() -> [FileInfo] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: root,
                                                   includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        return entries.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return FileInfo(
                name: url.lastPathComponent.uppercased(),
                version: 1,
                bytes: values?.fileSize ?? 0,
                modified: values?.contentModificationDate ?? Date()
            )
        }
    }

    /// Seeds STARTUP.COM, LOGIN.COM and the sample procedures the first
    /// time the store is created.  Subsequent launches leave whatever the
    /// operator wrote alone.
    ///
    /// The procedures that give orders read the PCC$LANGUAGE builtin
    /// symbol and branch, so that each language sees only its own text and
    /// its own (language-gated) qualifier spellings. Their text has no
    /// accents: a command procedure is typed on any keyboard.
    private func seedIfNeeded() {
        seed(name: "STARTUP.COM", body: """
        $ ! PCC$ROOT:[CONTROL]STARTUP.COM
        $ ! Boot-time initialization for the PCC of the Cabine cabs
        $ SET NOON
        $ DEFINE/SYSTEM PCC$ROOT      DISK$PCC_SYS:[PCC]
        $ DEFINE/SYSTEM PCC$LINES     DISK$PCC_DATA:[LINES]
        $ DEFINE/SYSTEM PCC$JOURNAL   DISK$PCC_DATA:[JOURNAL]
        $ INSTALL ADD PCC$ROOT:[CONTROL]PCC_ENGINE.EXE   /OPEN/SHARED
        $ INSTALL ADD PCC$ROOT:[CONTROL]PCC_LISTENER.EXE /OPEN/SHARED
        $ EXIT
        """)
        seed(name: "LOGIN.COM", body: """
        $ ! SYS$LOGIN:LOGIN.COM -- per-user logon
        $ ! The LPD PCC-CABINE short-form command aliases are built into the
        $ ! shell and gated by the interface language: the English aliases
        $ ! (TRAIN FLEET LINE STATIONS CABS EMERGENCY RESUME) resolve only in
        $ ! English mode, the French ones (RAME FLOTTE LIGNE GARES CABINES
        $ ! URGENCE REPRISE AIDE) only in French mode. There is nothing to
        $ ! define here. Type HELP PCC for a worked example.
        $ SET NOON
        $ EXIT
        """)
        seed(name: "HELLO.COM", body: """
        $ ! HELLO.COM -- demonstrates symbols, IF/THEN and GOTO
        $ WRITE SYS$OUTPUT "Hello from DCL scripting!"
        $ COUNT = 1
        $LOOP:
        $   IF COUNT .GT. 3 THEN GOTO DONE
        $   WRITE SYS$OUTPUT "  Iteration ''COUNT'"
        $   COUNT = COUNT + 1
        $   GOTO LOOP
        $DONE:
        $ WRITE SYS$OUTPUT "Done at ''F$TIME()'."
        $ EXIT
        """)
        seed(name: "DEMO.COM", body: """
        $ ! DEMO.COM -- a short turn at the PCC's desk: the first train of the
        $ ! line is held at its next platform for ten seconds, then released.
        $ ! F$PCC reads the PCC; the qualifiers follow the interface language.
        $ IF F$PCC("LINE") .EQS. "" THEN GOTO NOLINE
        $ N = F$PCC("FIRST_RAME")
        $ IF PCC$LANGUAGE .EQS. "FR" THEN GOTO FR
        $ WRITE SYS$OUTPUT "Holding train ''N' at its next platform for ten seconds..."
        $ SET RAME 'N' /HOLD
        $ WAIT 00:00:10
        $ SET RAME 'N' /RELEASE
        $ SHOW RAME 'N'
        $ EXIT
        $FR:
        $ WRITE SYS$OUTPUT "Retenue de la rame ''N' a son prochain quai pendant dix secondes..."
        $ SET RAME 'N' /RETENIR
        $ WAIT 00:00:10
        $ SET RAME 'N' /LIBERER
        $ SHOW RAME 'N'
        $ EXIT
        $NOLINE:
        $ IF PCC$LANGUAGE .EQS. "FR" THEN GOTO NOLINEFR
        $ WRITE SYS$OUTPUT "The PCC is on no line: SET LINE /LOAD=21 puts it on one."
        $ EXIT
        $NOLINEFR:
        $ WRITE SYS$OUTPUT "Le PCC n'a pas de ligne : SET LIGNE /CHARGER=21 lui en donne une."
        $ EXIT
        """)
        seed(name: "WAITCAB.COM", body: """
        $ ! WAITCAB.COM -- waits for a cab to enter service, then holds it at
        $ ! its next platform and tells its driver why. P1 is how many seconds
        $ ! to wait at most (120 when left out):  @WAITCAB 300
        $ ! CTRL/Y gives up.
        $ LIMIT = 120
        $ IF P1 .NES. "" THEN LIMIT = 'P1'
        $ COUNT = 0
        $LOOP:
        $   IF F$PCC("CABS") .GT. 0 THEN GOTO FOUND
        $   IF COUNT .GE. LIMIT THEN GOTO NONE
        $   WAIT 00:00:01
        $   COUNT = COUNT + 1
        $   GOTO LOOP
        $FOUND:
        $ N = F$PCC("FIRST_CAB")
        $ IF PCC$LANGUAGE .EQS. "FR" THEN GOTO FR
        $ SET RAME 'N' /HOLD /MESSAGE="Hold at the next platform: the PCC will release you"
        $ EXIT
        $FR:
        $ SET RAME 'N' /RETENIR /MESSAGE="Retenue au prochain quai : le PCC vous liberera"
        $ EXIT
        $NONE:
        $ IF PCC$LANGUAGE .EQS. "FR" THEN GOTO NONEFR
        $ WRITE SYS$OUTPUT "No cab entered service in ''LIMIT' seconds."
        $ EXIT
        $NONEFR:
        $ WRITE SYS$OUTPUT "Aucune cabine n'est entree en service en ''LIMIT' secondes."
        $ EXIT
        """)
    }

    private func seed(name: String, body: String) {
        let u = url(for: name)
        if !FileManager.default.fileExists(atPath: u.path) {
            try? body.write(to: u, atomically: true, encoding: .utf8)
        }
    }
}

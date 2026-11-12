import Foundation
import CabinePCCKit

// Where a node keeps what it keeps, and what it listens on.
//
// The app's environment is the user's own: its preferences domain, and
// ~/Library/Application Support/CabinePCC/. The headless tool's is given on
// its command line, and its self-test's lives in memory and in a scratch
// folder, so that a test never reads or writes what the app does. Nothing
// in Core reaches for UserDefaults or for the home directory but through
// here.

/// The settings a node keeps from one run to the next.
@MainActor
protocol PCCSettingsStore: AnyObject {
    func string(_ key: String) -> String?
    func bool(_ key: String) -> Bool?
    func double(_ key: String) -> Double?
    func set(_ value: String, for key: String)
    func set(_ value: Bool, for key: String)
    func set(_ value: Double, for key: String)
}

/// The names of the settings.
enum PCCSettingKey {
    /// The PCC listens, or is closed.
    static let enabled = "pcc.enabled"
    /// Every interface and Bonjour, or loopback only.
    static let lan = "pcc.lan"
    /// Seconds between trains each way that the fleet is sized for.
    static let headway = "pcc.headway"
    /// The name the operator gave the PCC.
    static let name = "pcc.name"
    /// The id of the line the PCC was last on.
    static let line = "pcc.line"
}

/// The app's settings: its own preferences domain. A launch argument
/// (`-pcc.lan NO`) counts as well as a stored value.
@MainActor
final class DefaultsSettings: PCCSettingsStore {
    private let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    func string(_ key: String) -> String? { defaults.string(forKey: key) }
    func bool(_ key: String) -> Bool? { defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key) }
    func double(_ key: String) -> Double? { defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key) }
    func set(_ value: String, for key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Bool, for key: String) { defaults.set(value, forKey: key) }
    func set(_ value: Double, for key: String) { defaults.set(value, forKey: key) }
}

/// Settings that last as long as the process: the headless tool's.
@MainActor
final class MemorySettings: PCCSettingsStore {
    private var strings: [String: String] = [:]
    private var flags: [String: Bool] = [:]
    private var numbers: [String: Double] = [:]

    init() {}

    func string(_ key: String) -> String? { strings[key] }
    func bool(_ key: String) -> Bool? { flags[key] }
    func double(_ key: String) -> Double? { numbers[key] }
    func set(_ value: String, for key: String) { strings[key] = value }
    func set(_ value: Bool, for key: String) { flags[key] = value }
    func set(_ value: Double, for key: String) { numbers[key] = value }
}

@MainActor
struct PCCEnvironment {
    /// The settings kept from one run to the next.
    var settings: PCCSettingsStore
    /// The folder of everything the node keeps in files: `COM/` (the
    /// command procedures and the mailbox), `DCLix/` and `Lines/`.
    var storeRoot: URL
    /// The library of lines the program was built with; nil when it has none.
    var bundledLines: URL?
    /// The port the cabs dial.
    var pccPort: UInt16 = CabineWire.preferredPort
    /// Take any free port when `pccPort` is taken.
    var pccFallsBackToAnyPort = true
    /// The port of the telnet DCL, on loopback; 0 lets the system choose.
    var telnetPort: UInt16 = PCCEnvironment.telnetPort
    /// The id of the line a first run takes up: Cabine's invented Ligne 21.
    var firstLine = "21"
    /// The node's name, which the PCC and its OpenVMS node go by; the Mac's
    /// own when nil.
    var nodeLabel: String?
    /// The name the DCL sessions log in under; the user's own when nil.
    var operatorName: String?

    /// The telnet DCL's own port: beside metroSystem's 2323.
    static let telnetPort: UInt16 = 2324

    /// The operator's own lines: every `.line.json` in it is kept at launch.
    var linesFolder: URL { storeRoot.appendingPathComponent("Lines", isDirectory: true) }
    /// The command procedures and the mailbox.
    var comFolder: URL { storeRoot.appendingPathComponent("COM", isDirectory: true) }

    /// The app's own: the user's preferences and Application Support.
    ///
    /// `-node NAME` and `-user NAME` at launch name the node and its operator
    /// in place of the Mac and its user, as `--node` and `--user` do for the
    /// headless tool: for a demonstration, or a picture that shows neither.
    static func app() -> PCCEnvironment {
        var environment = PCCEnvironment(settings: DefaultsSettings(), storeRoot: userStore, bundledLines: programLines)
        environment.nodeLabel = launchArgument("-node")
        environment.operatorName = launchArgument("-user")
        return environment
    }

    /// The value that follows an argument on the command line, if it is there.
    static func launchArgument(_ name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return value.isEmpty || value.hasPrefix("-") ? nil : value
    }

    /// ~/Library/Application Support/CabinePCC
    static var userStore: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("CabinePCC", isDirectory: true)
    }

    /// The `Lines` folder that goes with the program: in the app's
    /// resources, or beside the headless tool.
    static var programLines: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Lines", isDirectory: true) else { return nil }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        return url
    }
}

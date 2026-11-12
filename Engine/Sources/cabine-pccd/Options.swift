import Foundation
import Darwin
import CabinePCCKit

/// What the command line asks for.
struct Options {
    var port = CabineWire.preferredPort
    var loopback = false
    var bonjour = true
    var headway: Double?
    var rames: Int?
    var library: String?
    var line: String?
    var name: String?
    var seed: UInt64 = 1
    var turnBack: Double?
    var verbose = false
    var selfTest = false
    var dumpLine = false
    var fixtures: String?

    static let usage = """
    cabine-pccd: a headless PCC for Cabine cabs (docs/cabine-link.md, protocol \(CabineWire.protocolVersion))

    It keeps a library of lines and runs one of them: it hands that line to the cabs that do not
    hold it, drives the automatic rames on it, keeps every train apart in moving block and
    supervises the cabs. With no --line it is on no line until it is put on one.

    USAGE:
      swift run cabine-pccd [options]

    OPTIONS:
      --port <n>            Port to listen on (default \(CabineWire.preferredPort); any free one if it is taken; 0 lets the system choose)
      --loopback            Listen on 127.0.0.1 only
      --no-bonjour          Do not advertise \(CabineWire.bonjourServiceType)
      --name <text>         The PCC's name, for the cabs and for Bonjour (default "PCC <this Mac>")
      --headway <seconds>   Seconds between trains each way that the fleet is sized for (default 150)
      --rames <n>           Fix the number of trains on the line, cabs included, instead
      --turnback <seconds>  Seconds a rame spends out of sight beyond a terminus (default 60)
      --library <dir>       Keep every *.line.json of a directory in the library at launch
      --line <id>           Take up the line of the library with that id at launch
      --line <file>         Keep the line of a .line.json file, and take it up at launch
      --seed <n>            Seed of the random draws: the same seed gives the same run (default 1)
      --verbose             Print a status table every 5 seconds
      --dump-line           Print the built-in test line as a line package, and exit
      --selftest            Run the self-test and exit: status 0 if it passed, 1 if not
      --fixtures <dir>      The lines the self-test runs, as *.line.json (default ../Lines, the repository's)
      -h, --help            Show this help and exit

    COMMANDS, one a line on standard input:
      status                      The line, every rame and every connection
      lines                       The library, and which line of it the PCC is on
      line <id>                   Take up the line of the library with that id
      line <file>                 Keep the line of a .line.json file, and take it up
      line none                   Close the line: the PCC is on none
      start | stop                Line service on, off
      hold <rame> | release <rame>      Keep a rame at its platform, let it go
      brake <rame> | unbrake <rame>     Emergency brake of one rame, on and off
      brake all | unbrake all     The general emergency stop
      msg <rame> <text>           Words for a cab's display (120 characters at most)
      call <rame>                 Ring a cab's driver
      headway <seconds>           Size the fleet for another headway
      rames <n> | rames auto      Fix the number of trains, or size it from the headway again
      help                        This list
      quit [seconds]              Tell the cabs, close the line and exit
    """

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("cabine-pccd: \(message) (try --help)\n".utf8))
        exit(2)
    }

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var rest = arguments

        func value(for flag: String) -> String {
            guard !rest.isEmpty else { fail("missing value for \(flag)") }
            return rest.removeFirst()
        }
        func whole(for flag: String) -> Int {
            let text = value(for: flag)
            guard let number = Int(text) else { fail("\(flag) wants a whole number, not \(text)") }
            return number
        }
        func real(for flag: String) -> Double {
            let text = value(for: flag)
            guard let number = Double(text), number.isFinite else { fail("\(flag) wants a number, not \(text)") }
            return number
        }

        while !rest.isEmpty {
            let flag = rest.removeFirst()
            switch flag {
            case "--port":
                let port = whole(for: flag)
                guard (0...65_535).contains(port) else { fail("--port lies between 0 and 65535") }
                options.port = UInt16(port)
            case "--loopback": options.loopback = true
            case "--no-bonjour": options.bonjour = false
            case "--name": options.name = value(for: flag)
            case "--headway":
                let headway = real(for: flag)
                guard CabinePCC.Settings.headwayRange.contains(headway) else {
                    fail("--headway lies between \(Int(CabinePCC.Settings.headwayRange.lowerBound)) and \(Int(CabinePCC.Settings.headwayRange.upperBound)) seconds")
                }
                options.headway = headway
            case "--rames":
                let rames = whole(for: flag)
                guard CabinePCC.Settings.fleetRange.contains(rames) else {
                    fail("--rames lies between \(CabinePCC.Settings.fleetRange.lowerBound) and \(CabinePCC.Settings.fleetRange.upperBound)")
                }
                options.rames = rames
            case "--turnback":
                let seconds = real(for: flag)
                guard (0...3_600).contains(seconds) else { fail("--turnback lies between 0 and 3600 seconds") }
                options.turnBack = seconds
            case "--library": options.library = value(for: flag)
            case "--line": options.line = value(for: flag)
            case "--seed":
                let text = value(for: flag)
                guard let seed = UInt64(text) else { fail("--seed wants a whole number, not \(text)") }
                options.seed = seed
            case "--verbose": options.verbose = true
            case "--selftest": options.selfTest = true
            case "--dump-line": options.dumpLine = true
            case "--fixtures": options.fixtures = value(for: flag)
            case "-h", "--help":
                print(usage)
                exit(0)
            default:
                fail("unknown option \(flag)")
            }
        }
        return options
    }
}

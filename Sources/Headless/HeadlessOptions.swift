import Foundation

/// What the command line asks for.
struct HeadlessOptions {
    enum Mode {
        case help
        case serve
        case selfTest
        case dcl
    }

    struct Problem: Error {
        let text: String
    }

    var mode = Mode.help
    /// The port the cabs dial; nil leaves the mode its own.
    var port: UInt16?
    /// The port of the telnet DCL; nil leaves the mode its own.
    var telnet: UInt16?
    /// Loopback only, and no Bonjour.
    var loopback = false
    /// The id of the line to take up.
    var line: String?
    /// The PCC's name.
    var name: String?
    /// The node's name, in place of the Mac's.
    var node: String?
    /// The name the DCL sessions log in under, in place of the user's.
    var user: String?
    /// The folder the node keeps its files in.
    var store: URL?
    /// English or French.
    var french = false
    /// The commands of `--dcl`, in the order given.
    var commands: [String] = []
    /// The keys of `--keys`, by the index of the command they follow.
    var keys: [Int: String] = [:]
    /// Scripted cabs put in service before the commands of `--dcl`.
    var cabs = 0
    /// Seconds the line runs before the commands of `--dcl`.
    var settle = 0.0
    /// The self-test prints what the commands printed as well.
    var verbose = false

    static let usage = """
    usage:
      cabinepcc-headless --serve [--port n] [--telnet n] [--loopback] [--line id] [--name "name"]
                         [--store folder] [--lang en|fr] [--node name] [--user name]
          The PCC and the telnet DCL with no window, until interrupted (CTRL/C, or SIGTERM).
          --port      the port the cabs dial (5289); another is taken if it is in use
          --telnet    the port of the telnet DCL, on loopback (2324)
          --loopback  listen on this Mac only, and do not advertise by Bonjour
          --line      the id of the line to take up (21)
          --name      the PCC's name, for the cabs' displays and for Bonjour
          --store     the folder the node keeps its files in: COM, DCLix and Lines
                      (~/Library/Application Support/CabinePCC)
          --lang      the language the DCL sessions start in (en)
          --node      the node's name, in place of this Mac's
          --user      the name the DCL sessions log in under, in place of yours

      cabinepcc-headless --selftest [--verbose] [--store folder]
          The DCL's SELFTEST, in English and in French, then a scenario with scripted cabs over
          loopback: every PCC verb, the line library, the alarms, the monitors and the forms.
          Exit status 0 when every check passes, 1 otherwise. It runs on ports of its own, with its
          settings in memory and its files in a scratch folder that it removes.

      cabinepcc-headless --dcl "command" [--keys "keys"] [--dcl "command" ...] [--lang en|fr]
                         [--line id] [--cabs n] [--settle seconds] [--store folder]
                         [--name "name"] [--node name] [--user name]
          Carries out the commands against a fresh node, on loopback, and prints what a terminal
          would show. A command that takes over the screen (MONITOR, RUN) prints one frame of it.
          --keys      keys to press in the display of the command before, ahead of the frame:
                      characters, and <TAB> <UP> <DOWN> <NEXT> <PREV> <RET> <DEL> <CTRL/W>
          --cabs      scripted cabs to put in service first
          --settle    seconds to let the line run before the first command

      cabinepcc-headless --help
    """

    init(_ arguments: [String]) throws {
        var index = 0
        func value(_ option: String) throws -> String {
            guard index + 1 < arguments.count else { throw Problem(text: "\(option) needs a value") }
            index += 1
            return arguments[index]
        }
        func portValue(_ option: String) throws -> UInt16 {
            let text = try value(option)
            guard let number = UInt16(text) else { throw Problem(text: "\(option) \(text) is not a port") }
            return number
        }
        var modes = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--serve":
                mode = .serve
                modes += 1
            case "--selftest":
                mode = .selfTest
                modes += 1
            case "--dcl":
                if mode != .dcl { modes += 1 }
                mode = .dcl
                commands.append(try value(argument))
            case "--keys":
                guard !commands.isEmpty else { throw Problem(text: "--keys follows the --dcl whose display it types at") }
                keys[commands.count - 1] = try value(argument)
            case "--help", "-h":
                mode = .help
                modes += 1
            case "--port":
                port = try portValue(argument)
            case "--telnet":
                telnet = try portValue(argument)
            case "--loopback":
                loopback = true
            case "--line":
                line = try value(argument)
            case "--name":
                name = try value(argument)
            case "--node":
                node = try value(argument)
            case "--user":
                user = try value(argument)
            case "--store":
                store = URL(fileURLWithPath: try value(argument), isDirectory: true)
            case "--lang":
                let language = try value(argument).lowercased()
                guard language == "en" || language == "fr" else { throw Problem(text: "--lang is en or fr") }
                french = language == "fr"
            case "--cabs":
                let text = try value(argument)
                guard let count = Int(text), (0...8).contains(count) else { throw Problem(text: "--cabs is 0 to 8") }
                cabs = count
            case "--settle":
                let text = try value(argument)
                guard let seconds = Double(text), (0...600).contains(seconds) else {
                    throw Problem(text: "--settle is 0 to 600 seconds")
                }
                settle = seconds
            case "--verbose":
                verbose = true
            default:
                throw Problem(text: "\(argument) is not an option")
            }
            index += 1
        }
        guard modes <= 1 else { throw Problem(text: "one of --serve, --selftest and --dcl at a time") }
    }
}

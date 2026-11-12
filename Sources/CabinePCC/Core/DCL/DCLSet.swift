import Foundation

// SET family -- per-keyword subcommands.
extension DCLEngine {
    func setCmd(_ cmd: Parsed) -> String {
        guard let first = cmd.positional.first else { return missQual("SET") }
        // SET PROMPT="string": the keyword and its value come as one word.
        let parts = first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let what = parts[0]
        switch true {
        case matches(what, "DEFAULT", min: 3):  return setDefault(cmd)
        case matches(what, "TERMINAL", min: 4): return setTerminal(cmd)
        case matches(what, "PROMPT", min: 3):   return setPrompt(cmd, value: parts.count > 1 ? parts[1] : nil)
        case matches(what, "ON"):               return ""
        case matches(what, "NOON", min: 3):     return ""
        case matches(what, "VERIFY", min: 3):   return ""
        case matches(what, "NOVERIFY", min: 3): return ""
        case matches(what, "PASSWORD", min: 4): return setPassword()
        case matches(what, "PROCESS", min: 4):  return setProcess(cmd)
        // The PCC, its line and its trains (DCLPCC.swift).
        case matches(what, "PCC", min: 3):      return setPCC(cmd)
        case matches(what, "RAME", min: 3):     return setRame(cmd)
        case matchesLoc(what, en: "LINE", fr: "LIGNE", min: 3):
            return setLine(cmd)
        default:
            if let text = dclixSet(cmd) { return text }
            return noPriv("SET \(what)")
        }
    }

    func setDefault(_ cmd: Parsed) -> String {
        guard let target = cmd.positional.dropFirst().first else { return missQual("SET DEFAULT") }
        var dev = defaultDevice
        var dir = defaultDirectory

        var spec = target
        if let colon = spec.firstIndex(of: ":") {
            dev = String(spec[...colon]).uppercased()
            spec = String(spec[spec.index(after: colon)...])
        }
        if !spec.isEmpty {
            if spec == "[-]" {
                if dir.hasPrefix("[") && dir.hasSuffix("]") {
                    var inner = String(dir.dropFirst().dropLast())
                    if let dot = inner.lastIndex(of: ".") {
                        inner = String(inner[..<dot])
                        dir = "[\(inner)]"
                    } else {
                        dir = "[000000]"
                    }
                }
            } else if spec.hasPrefix("[.") {
                let extra = String(spec.dropFirst(2).dropLast())
                let inner = dir.dropFirst().dropLast()
                dir = "[\(inner).\(extra)]"
            } else if spec.hasPrefix("[") {
                dir = spec.uppercased()
            } else {
                fail("DCL-W-IVKEYW", "%X00038088")
                return "%DCL-W-IVKEYW, unrecognized keyword - check validity and spelling\n"
            }
        }
        defaultDevice = dev
        defaultDirectory = dir
        return ""
    }

    func setTerminal(_ cmd: Parsed) -> String {
        if let w = cmd.qualifierValue("WIDTH"), let n = Int(w) { terminalWidth = n }
        if let p = cmd.qualifierValue("PAGE"),  let n = Int(p) { terminalPage = n }
        return ""
    }

    /// SET PROMPT="string"; with no string, the prompt is "$ " again.
    func setPrompt(_ cmd: Parsed, value: String? = nil) -> String {
        if let value {
            let text = value.replacingOccurrences(of: "\"", with: "")
            prompt = text.hasSuffix(" ") ? text : text + " "
            return ""
        }
        if let v = cmd.qualifiers.first(where: { $0.value != nil })?.value {
            prompt = v.replacingOccurrences(of: "\"", with: "") + " "
            return ""
        }
        if let v = cmd.positional.dropFirst().first {
            prompt = v.replacingOccurrences(of: "\"", with: "") + " "
            return ""
        }
        prompt = "$ "
        return ""
    }

    func setPassword() -> String {
        return "%SET-W-NOTSET, error modifying \(username)\n-SYSTEM-F-NOPRIV, insufficient privilege\n"
    }

    func setProcess(_ cmd: Parsed) -> String {
        if cmd.hasQualifier("PRIORITY", min: 3) || cmd.hasQualifier("NAME", min: 3) {
            return noPriv("SET PROCESS")
        }
        return ""
    }
}

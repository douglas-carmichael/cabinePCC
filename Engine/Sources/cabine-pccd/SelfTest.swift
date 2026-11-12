import Foundation
import CabinePCCKit

/// The self-test: `cabine-pccd --selftest`. It prints one line a check and ends with `SELFTEST PASSED` or
/// `SELFTEST FAILED (n)`.
///
/// It uses the kit as a host does, through what the kit makes public, and nothing else. What it checks
/// against is worked out here, from the lines' own files and the specification's own examples, not
/// asked of the kit.
final class SelfTest {
    private(set) var failures = 0

    /// A line the self-test is run on: its package, and the bytes of the file it was read from when it
    /// was read from one.
    struct Subject {
        var name: String
        var package: CabineWire.LinePackage
        var file: Data?
    }

    /// Runs every check. `fixtures` is where to look for `*.line.json`; the repository's `Lines`, beside
    /// the package, when nil.
    static func run(fixtures: String?) -> Bool {
        let test = SelfTest()
        let started = Date()

        test.section("1. The wire")
        test.wire()

        test.section("2. Line descriptions and packages")
        var lines = [Subject(name: "built-in line", package: .init(description: CabinePCC.testLine), file: nil)]
        lines += test.fixtureLines(in: fixtures)
        test.validation(lines)
        test.packages(lines)

        for line in lines {
            test.section("3. The engine alone, on the \(line.name)")
            test.engineAlone(line.name, line.package.description)
            test.section("4. A cab, without sockets, on the \(line.name)")
            test.cab(line.name, line.package.description)
        }

        test.section("5. Over TCP on 127.0.0.1")
        test.tcp(lines)

        test.section("6. The library and which line, two cabs on one track, and the fleet to order")
        test.library()
        test.twoCabs()
        test.fleetOrders()

        print(String(format: "-- %.1f s", Date().timeIntervalSince(started)))
        print(test.failures == 0 ? "SELFTEST PASSED" : "SELFTEST FAILED (\(test.failures))")
        return test.failures == 0
    }

    // MARK: Checks

    func section(_ title: String) {
        print("-- \(title)")
    }

    /// One check: one line. `detail` says what was found, and is what explains a failure.
    @discardableResult
    func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") -> Bool {
        let found = detail()
        if passed {
            print("ok    \(name)" + (found.isEmpty ? "" : "  [\(found)]"))
        } else {
            failures += 1
            print("FAIL  \(name)" + (found.isEmpty ? "" : ": \(found)"))
        }
        return passed
    }

    /// Carries out an order of the host's, and returns why it was refused; nil if it was carried out.
    func refusal(of order: () throws -> Void) -> CabinePCC.OrderError? {
        do {
            try order()
            return nil
        } catch {
            return error as? CabinePCC.OrderError ?? .badValue("\(error)")
        }
    }

    // MARK: The lines it runs on

    /// Every `*.line.json` of a directory, in name order: the one given, or the repository's `Lines`.
    /// None, and no complaint, if there is no such directory.
    private func fixtureLines(in directory: String?) -> [Subject] {
        let manager = FileManager.default
        var candidates = [directory ?? "../Lines"]
        if directory == nil {
            // `../Lines` is the repository's library as `swift run` from the package sees it; the other
            // is the same directory found from where these sources are.
            candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Lines").path)
        }
        guard let found = candidates.first(where: { manager.fileExists(atPath: $0) }),
              let names = try? manager.contentsOfDirectory(atPath: found) else {
            print("      (no directory of lines: only the built-in line is run)")
            return []
        }
        var lines: [Subject] = []
        for name in names.sorted() where name.hasSuffix(".line.json") {
            let path = (found as NSString).appendingPathComponent(name)
            guard let data = manager.contents(atPath: path) else {
                check("fixture \(name) can be read", false)
                continue
            }
            do {
                lines.append(Subject(name: "fixture \(name)", package: try CabineWire.LinePackage.decode(file: data), file: data))
            } catch {
                check("fixture \(name) is a line package", false, "\(error)")
            }
        }
        if lines.isEmpty { print("      (no *.line.json in \(found): only the built-in line is run)") }
        return lines
    }

    // MARK: JSON, read without the kit

    /// A JSON value in a form two of them can be compared in: keys in order, numbers as numbers whatever
    /// way they were written, true and false apart from 1 and 0.
    static func canonical(_ value: Any) -> String {
        switch value {
        case let dictionary as [String: Any]:
            return "{" + dictionary.keys.sorted().map { "\"\($0)\":" + canonical(dictionary[$0]!) }.joined(separator: ",") + "}"
        case let array as [Any]:
            return "[" + array.map(canonical).joined(separator: ",") + "]"
        case let text as String:
            return "\"\(text)\""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return String(format: "%.9g", number.doubleValue)
        case is NSNull:
            return "null"
        default:
            return "?"
        }
    }

    static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    static func object(_ text: String) -> [String: Any]? { object(Data(text.utf8)) }
}

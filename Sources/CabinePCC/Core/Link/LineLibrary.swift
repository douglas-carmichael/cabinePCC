import Foundation
import CabinePCCKit

// The library of lines, as files.
//
// A line is a package (docs/cabine-link.md, "Lines: the PCC's library"):
// the description the engine runs it on, and the source a Cabine builds it
// from, which the PCC keeps and hands on without reading -- but for one
// thing, `source.source`: where the data came from, which the licences ask
// to be shown.
//
// The files are `*.line.json`. Those the program was built with come from
// the repository's Lines/ folder; the operator's own are in the store's
// Lines/ folder, and are kept after them, so that an operator's revision of
// a line takes the place of the one the program came with.

enum LineLibrary {

    /// Every line file there is to keep: the program's, then the
    /// operator's, each folder in the order a person would list it.
    static func files(bundled: URL?, own: URL) -> [URL] {
        var found: [URL] = []
        for folder in [bundled, own].compactMap({ $0 }) {
            let listed = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles])) ?? []
            found += listed
                .filter { $0.lastPathComponent.lowercased().hasSuffix(".line.json") }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return found
    }

    /// Why a file was not kept.
    static func fault(_ error: Error) -> LineFileFault {
        if let failure = error as? CabineWire.DecodeFailure {
            return failure.path.isEmpty ? .notAPackage : .field(path: failure.path.joined(separator: "."), reason: failure.reason)
        }
        if let refusal = error as? CabinePCC.OrderError {
            switch refusal {
            case let .badLine(reason), let .badValue(reason): return .refused(reason)
            default: return .refused(refusal.description)
            }
        }
        return .unreadable
    }
}

/// Why a line file was not kept. What the engine says of a description it
/// refuses is in its own words, which are English.
enum LineFileFault: Equatable {
    /// The file could not be read.
    case unreadable
    /// It is not JSON, or not a line package.
    case notAPackage
    /// A field of the package is missing or of the wrong kind.
    case field(path: String, reason: String)
    /// The description fails the engine's checks.
    case refused(String)
}

/// Where the data of a line came from, as its package says in
/// `source.source`. OpenStreetMap's data is under the ODbL, which asks for
/// "© OpenStreetMap contributors"; Île-de-France Mobilités and the IGN
/// publish under the Licence Ouverte 2.0, which asks for the source and the
/// date. They are shown as the package gives them.
struct LineCredits: Equatable {
    /// Whose drawing of the track's curves.
    var track: String?
    /// Whose stations, stopping points and distances.
    var stations: String?
    /// Whose ground levels.
    var ground: String?
    /// The date of the extract.
    var date: String?

    /// The credits of a package; nil for one with no source, or whose
    /// source names none.
    init?(_ package: CabineWire.LinePackage) {
        guard let named = package.source?["source"] else { return nil }
        track = named["track"]?.string
        stations = named["stations"]?.string
        ground = named["ground"]?.string
        date = named["date"]?.string
        if track == nil, stations == nil, ground == nil, date == nil { return nil }
    }
}

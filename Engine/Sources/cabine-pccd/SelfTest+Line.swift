import Foundation
import CabinePCCKit

// 2. A good description passes the PCC's checks; one that does not is refused with a reason, and the
// library does not keep it.

extension SelfTest {

    func validation(_ lines: [Subject]) {
        typealias Description = CabineWire.LineDescription

        for line in lines {
            do {
                let taken = try CabinePCC.Line(line.package.description)
                check("the \(line.name) passes the checks", true,
                      "\(taken.identity.name), \(taken.stationCount) stations, \(Int(taken.lengthM)) m, rev \(taken.identity.rev)")
            } catch {
                check("the \(line.name) passes the checks", false, "\(error)")
            }
        }
        if let specification = try? Description.decode(file: Data(SelfTest.specificationLine.utf8)) {
            check("the specification's example line passes the checks", (try? CabinePCC.Line(specification)) != nil)
        } else {
            check("the specification's example line passes the checks", false, "it could not be read")
        }

        // Only what is required: the rest takes the values the specification shows.
        let bare = Description(id: "nu", name: "Ligne nue", rev: "1", lengthM: 2_000,
                               stations: [.init(name: "Amont"), .init(name: "Aval")],
                               tracks: [.init(track: 2, stopsM: [300, 1_700]), .init(track: 1, stopsM: [280, 1_720])])
        if let line = try? CabinePCC.Line(bare) {
            check("a description with only what is required is taken with the specification's values for the rest",
                  line.train.lengthM == 75 && line.train.maxSpeedMS == 19.444 && line.train.approachDecelMS2 == 0.6
                    && line.train.marginMS == 1.3 && line.lineSpeedMS == 19.444 && line.cbtc.safetyMarginM == 25
                    && line.cbtc.stoppingShortM == 6 && line.cbtc.horizonM == 1_500 && line.cbtc.departureRoomM == 40
                    && line.cbtc.uncertaintyBaseM == 1.5 && line.cbtc.uncertaintyPerM == 0.02 && line.cbtc.uncertaintyMaxM == 8
                    && line.dwell.minS == 17 && line.dwell.maxS == 27 && line.dwell.terminusS == 30 && line.dwell.doorsOpenS == 2.2
                    && line.dwell.doorsCloseS == 2.4 && line.dwell.departS == 4.2 && line.endBufferM == 28
                    && line.tracks[0].number == 1 && line.tracks[0].stopsM == [280, 1_720] && line.tracks[1].stopsM == [300, 1_700]
                    && line.tracks[0].zones.isEmpty && line.tracks[0].beaconsM.isEmpty)
        } else {
            check("a description with only what is required is taken with the specification's values for the rest", false)
        }

        // What is wrong with a description, and the word its refusal must have in it.
        func refused(_ what: String, saying word: String, _ change: (inout Description) -> Void) {
            var description = CabinePCC.testLine
            change(&description)
            do {
                _ = try CabinePCC.Line(description)
                check("\(what) is refused", false, "it was taken up")
            } catch let refusal as CabinePCC.LineRefusal {
                check("\(what) is refused", refusal.reason.contains(word), refusal.reason)
            } catch {
                check("\(what) is refused", false, "\(error)")
            }
        }
        refused("stops out of order", saying: "stopsM must rise") { $0.tracks[0].stopsM.swapAt(1, 2) }
        refused("two stops at one place", saying: "stopsM must rise") { $0.tracks[1].stopsM[3] = $0.tracks[1].stopsM[2] }
        refused("a missing track", saying: "exactly two") { $0.tracks.removeLast() }
        refused("track 1 given twice", saying: "exactly two") { $0.tracks[1].track = 1 }
        refused("a third track", saying: "exactly two") { $0.tracks.append(.init(track: 3, stopsM: $0.tracks[0].stopsM)) }
        refused("a stop too few for the stations", saying: "5 stops for 6 stations") { $0.tracks[0].stopsM.removeLast() }
        refused("a station too many for the stops", saying: "6 stops for 7 stations") { $0.stations.append(.init(name: "Sans quai")) }
        refused("a line of one station", saying: "2 to 128") {
            $0.stations = [.init(name: "Seule")]
            $0.tracks = [.init(track: 1, stopsM: [300]), .init(track: 2, stopsM: [300])]
        }
        refused("a line 50 m long", saying: "lengthM must lie between 100 and 100000") { $0.lengthM = 50 }
        refused("a line 2000 km long", saying: "lengthM must lie between 100 and 100000") { $0.lengthM = 2_000_000 }
        refused("a line too short to turn a train in", saying: "too short for the train") {
            $0.lengthM = 200
            $0.stations = [.init(name: "Amont"), .init(name: "Aval")]
            $0.tracks = [.init(track: 1, stopsM: [110, 160]), .init(track: 2, stopsM: [110, 160])]
        }
        refused("a train of no length", saying: "train.lengthM") { $0.train?.lengthM = 0 }
        refused("a train longer than the room before the first stop", saying: "first stop") { $0.train?.lengthM = 400 }
        refused("a stop beyond the end of the track", saying: "last stop") { $0.tracks[0].stopsM[5] = 4_990 }
        refused("an end buffer less than nothing", saying: "endBufferM") { $0.endBufferM = -1 }
        refused("a speed limit of nothing", saying: "limitMS") { $0.tracks[0].zones?[0].limitMS = 0 }
        refused("a zone that ends before it begins", saying: "fromM must be less than toM") { $0.tracks[1].zones?[0].toM = 0 }
        refused("beacons out of order", saying: "beaconsM must rise") { $0.tracks[0].beaconsM?.swapAt(0, 3) }
        refused("an approach deceleration beyond the brake", saying: "train.approachDecelMS2") { $0.train?.approachDecelMS2 = 2 }
        refused("a line with no name", saying: "name is empty") { $0.name = "  " }
        refused("a colour that is not RRGGBB", saying: "colour") { $0.colour = "rouge" }

        // The library keeps nothing that fails them, and says why; the PCC stays as it was.
        let engine = CabinePCC.Engine(seed: 2)
        var broken = CabinePCC.testLine
        broken.tracks[0].stopsM.swapAt(2, 3)
        let kept = refusal { try engine.keep(CabineWire.LinePackage(description: broken)) }
        let taken = refusal { try engine.takeUp(CabineWire.LinePackage(description: broken)) }
        let alone = refusal { try engine.takeUp(broken) }
        check("a package whose description fails the checks is not kept, nor taken up: badLine and the reason",
              kept == .badLine("track 1: stopsM must rise") && taken == kept && alone == kept
                && engine.snapshot().library.isEmpty && engine.snapshot().line == nil,
              kept.map { "\($0)" } ?? "it was kept")
        let newer = refusal { try engine.keep(CabineWire.LinePackage(format: 2, description: CabinePCC.testLine)) }
        var refusedFormat = false
        if case let .badLine(reason)? = newer { refusedFormat = reason.contains("format 2") }
        check("a package of a format this version does not know is not kept", refusedFormat && engine.snapshot().library.isEmpty,
              newer.map { "\($0)" } ?? "it was kept")
    }
}

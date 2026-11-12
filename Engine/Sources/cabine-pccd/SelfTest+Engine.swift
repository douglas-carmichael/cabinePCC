import Foundation
import CabinePCCKit

// 3. The engine alone, for an hour of simulated time on a line.

/// Watches a line through its snapshots, one a step, and notes everything the engine owes its cabs that
/// it fails in: trains too near each other, a rame over its limit, a stop missed or made badly, a
/// turn-back that is not one. What it holds the engine to is worked out here from the line's description.
final class LineWatch {
    /// What can go wrong, each counted apart, with the first few cases in words.
    enum Fault: Int, CaseIterable {
        case gap, speed, order, stop, doors, turn
    }

    private let length: Double
    private let trainLength: Double
    private let margin: Double
    private let topSpeed: Double
    private let endOfTrack: Double
    private let tailExit: Double
    private let stops: [[Double]]
    /// The zones of each track in the order a train meets them: where each begins and ends, and its limit.
    private let zoneFrom: [[Double]]
    private let zoneTo: [[Double]]
    private let zoneLimit: [[Double]]

    private(set) var steps = 0
    private(set) var faults = [Int](repeating: 0, count: Fault.allCases.count)
    private(set) var firstFaults: [String] = []
    /// The least distance seen from a nose to the rear of the train ahead of it round the loop.
    private(set) var leastGap = Double.infinity
    /// The nearest an automatic rame came to its limit: speed less limit, so less than nothing is under it.
    private(set) var nearestToLimit = -Double.infinity
    /// The furthest a rame's nose was from its stop when it began a call.
    private(set) var worstStop = 0.0
    private(set) var calls = 0
    /// Calls at each stop of each track.
    private(set) var calledAt: [[Int]]
    /// Turn-backs out of track 1 and out of track 2.
    private(set) var turns = [0, 0]
    /// The most stops any one rame has called at in a row, and the laps timed from one call at the first
    /// stop of track 1 to the same rame's next.
    private(set) var longestRun = 0
    private(set) var lapTimes: [Double] = []
    private(set) var fewestAutomatic = Int.max
    private(set) var mostAutomatic = 0
    /// True if there were ever fewer automatic rames than a step before.
    private(set) var automaticFell = false
    private var lastAutomatic = 0

    /// What is remembered of each train from one snapshot to the next.
    private struct Memory {
        var automatic: Bool
        var phase: CabineWire.TrainPhase
        var track: Int
        var uM: Double
        var lastCall: (track: Int, stop: Int)?
        var doorsSeen = 0.0
        var run = 0
        var lapBegan: Double?
        /// The first zone of its track that may still lie under it: see `limit(track:nose:cursor:)`.
        var zoneCursor = 0
    }
    /// By the train's id, which the engine counts up from 1.
    private var memory: [Memory?] = []

    init(_ line: CabinePCC.Line) {
        let description = line.description
        length = description.lengthM
        trainLength = description.train?.lengthM ?? 75
        margin = description.cbtc?.safetyMarginM ?? 25
        let trainSpeed = description.train?.maxSpeedMS ?? 19.444
        topSpeed = min(description.lineSpeedMS ?? trainSpeed, trainSpeed)
        endOfTrack = length - (description.endBufferM ?? 28)
        tailExit = trainLength + (description.endBufferM ?? 28)
        let ordered = [1, 2].map { number in description.tracks.first { $0.track == number }! }
        stops = ordered.map(\.stopsM)
        let zones = ordered.map { ($0.zones ?? []).sorted { $0.fromM < $1.fromM } }
        zoneFrom = zones.map { $0.map(\.fromM) }
        zoneTo = zones.map { $0.map(\.toM) }
        zoneLimit = zones.map { $0.map(\.limitMS) }
        calledAt = stops.map { [Int](repeating: 0, count: $0.count) }
    }

    var faultless: Bool { faults.allSatisfy { $0 == 0 } }

    func count(_ fault: Fault) -> Int { faults[fault.rawValue] }

    private func note(_ fault: Fault, _ what: @autoclosure () -> String) {
        faults[fault.rawValue] += 1
        if firstFaults.count < 6 { firstFaults.append(what()) }
    }

    /// The lowest limit anywhere under a train: the line's, and each zone's while any part of the train
    /// is inside it.
    func limit(track: Int, nose: Double) -> Double {
        var limit = topSpeed
        let tail = nose - trainLength
        // Plain loops over plain numbers, here and in `observe`: they run for every train at every step
        // of hours of simulated time, in a build that is not optimised.
        let from = zoneFrom[track - 1], to = zoneTo[track - 1], limits = zoneLimit[track - 1]
        let count = from.count
        var index = 0
        while index < count {
            // The zones are in the order they begin: none further on has begun at the nose.
            if from[index] > nose { break }
            if to[index] >= tail {
                let zone = limits[index]
                if zone < limit { limit = zone }
            }
            index += 1
        }
        return limit
    }

    /// The same, for a train that is watched step after step: `cursor` is the first zone of the track
    /// that may still lie under it, and moves on as the train does. It starts at 0 for a train new to the
    /// track, and is good for as long as the train only goes forward on it.
    private func limit(track: Int, nose: Double, cursor: inout Int) -> Double {
        var limit = topSpeed
        let tail = nose - trainLength
        let from = zoneFrom[track - 1], to = zoneTo[track - 1], limits = zoneLimit[track - 1]
        let count = from.count
        while cursor < count && to[cursor] < tail { cursor += 1 }
        var index = cursor
        while index < count {
            if from[index] > nose { break }
            if to[index] >= tail {
                let zone = limits[index]
                if zone < limit { limit = zone }
            }
            index += 1
        }
        return limit
    }

    /// Looks at the line as it is after one more step.
    func observe(_ snapshot: CabinePCC.Snapshot) {
        steps += 1
        let rames = snapshot.rames
        let count = rames.count
        let length = self.length, trainLength = self.trainLength, margin = self.margin
        let loop = 2 * length
        // Where every nose is round the loop.
        var noses = [Double]()
        noses.reserveCapacity(count)
        var index = 0
        var automatic = 0
        while index < count {
            let rame = rames[index]
            noses.append(rame.track == 2 ? length + rame.uM : rame.uM)
            index += 1
        }

        index = 0
        while index < count {
            let rame = rames[index]
            let isAutomatic = rame.cab == nil
            if isAutomatic { automatic += 1 }

            // No two trains overlap or come nearer than the safety margin: from each nose to the rear of
            // the train next ahead of it round the loop.
            var least = Double.infinity
            var nearest = -1
            var other = 0
            let nose = noses[index]
            while other < count {
                if other != index {
                    var ahead = noses[other] - nose
                    if ahead < 0 { ahead += loop }
                    if ahead < least {
                        least = ahead
                        nearest = other
                    }
                }
                other += 1
            }
            if nearest >= 0 {
                let gap = least - trainLength
                if gap < leastGap { leastGap = gap }
                if gap < margin - 1e-6 {
                    note(.gap, String(format: "at %.2f s rame %02d is %.2f m from the rear of rame %02d", snapshot.timeS, rame.number, gap, rames[nearest].number))
                }
            }

            while memory.count <= rame.id { memory.append(nil) }
            var remembered = memory[rame.id]
            // A cab's train that goes back to automation starts afresh as an automatic rame.
            if let before = remembered, before.automatic != isAutomatic { remembered = nil }
            let isNew = remembered == nil
            var m = remembered ?? Memory(automatic: isAutomatic, phase: rame.phase, track: rame.track, uM: rame.uM)

            if isAutomatic {
                // Never over a zone's limit or the line speed. A train that has changed track, or is
                // further back than it was, is looked for among the zones from the first again.
                if m.track != rame.track || rame.uM < m.uM { m.zoneCursor = 0 }
                let over = rame.speedMS - limit(track: rame.track, nose: rame.uM, cursor: &m.zoneCursor)
                if over > nearestToLimit { nearestToLimit = over }
                if over > 1e-6 {
                    note(.speed, String(format: "at %.2f s rame %02d runs at %.2f m/s on track %d at %.1f m, %.2f over its limit", snapshot.timeS, rame.number, rame.speedMS, rame.track, rame.uM, over))
                }

                let dwelling = rame.phase == .dwelling
                if dwelling && (isNew || m.phase != .dwelling) {
                    // A call begins: at the next stop in order, nose within a metre of it.
                    if let stop = rame.station, stop < stops[rame.track - 1].count {
                        let off = abs(rame.uM - stops[rame.track - 1][stop])
                        if off > worstStop { worstStop = off }
                        if off > 1 {
                            note(.stop, String(format: "at %.2f s rame %02d calls %.2f m from stop %d of track %d", snapshot.timeS, rame.number, off, stop, rame.track))
                        }
                        if let last = m.lastCall {
                            let next = last.stop + 1 < stops[last.track - 1].count ? (last.track, last.stop + 1) : (3 - last.track, 0)
                            if next != (rame.track, stop) {
                                note(.order, String(format: "at %.2f s rame %02d calls at stop %d of track %d after stop %d of track %d", snapshot.timeS, rame.number, stop, rame.track, last.stop, last.track))
                            }
                        }
                        m.lastCall = (rame.track, stop)
                        m.run += 1
                        if m.run > longestRun { longestRun = m.run }
                        calls += 1
                        calledAt[rame.track - 1][stop] += 1
                        if rame.track == 1 && stop == 0 {
                            if let began = m.lapBegan { lapTimes.append(snapshot.timeS - began) }
                            m.lapBegan = snapshot.timeS
                        }
                    } else {
                        note(.stop, String(format: "at %.2f s rame %02d dwells at no station", snapshot.timeS, rame.number))
                    }
                    m.doorsSeen = rame.doors
                } else if dwelling {
                    if rame.doors > m.doorsSeen { m.doorsSeen = rame.doors }
                } else if !isNew && m.phase == .dwelling && m.doorsSeen < 0.99 {
                    note(.doors, String(format: "at %.2f s rame %02d ends a call with its doors %.0f %% open", snapshot.timeS, rame.number, m.doorsSeen * 100))
                }

                // A turn-back: it stood in the tail at the end of one track, and comes out at the start of
                // the other with its rear a buffer clear of the buffer stops.
                if !isNew && m.track != rame.track {
                    turns[m.track - 1] += 1
                    if m.phase != .tail || abs(m.uM - endOfTrack) > 2.5 || abs(rame.uM - tailExit) > 0.5 || rame.speedMS > 0.5 {
                        note(.turn, String(format: "at %.2f s rame %02d goes from track %d at %.1f m (%@) to track %d at %.1f m", snapshot.timeS, rame.number, m.track, m.uM, m.phase.rawValue, rame.track, rame.uM))
                    }
                }
            }
            m.automatic = isAutomatic
            m.phase = rame.phase
            m.track = rame.track
            m.uM = rame.uM
            memory[rame.id] = m
            index += 1
        }
        if automatic < fewestAutomatic { fewestAutomatic = automatic }
        if automatic > mostAutomatic { mostAutomatic = automatic }
        if steps > 1 && automatic < lastAutomatic { automaticFell = true }
        lastAutomatic = automatic
    }

    /// True when every stop of both tracks has been called at.
    var everyStopCalledAt: Bool { calledAt.allSatisfy { $0.allSatisfy { $0 > 0 } } }
}

extension SelfTest {

    /// The fleet a headway asks for on a line whose lap takes `lap` seconds: a train every `headway`
    /// seconds each way, at least 2, at most the 52 of the fleet, and no more than the loop can hold
    /// with room to move (a train for every three train-and-margin lengths of it).
    static func fleet(lap: Double, headway: Double, _ line: CabinePCC.Line) -> Int {
        let room = Int(2 * line.lengthM / (3 * (line.train.lengthM + line.cbtc.safetyMarginM + line.cbtc.stoppingShortM)))
        return max(min(Int((lap / headway).rounded()), 52, max(room, 2)), 2)
    }

    func engineAlone(_ name: String, _ description: CabineWire.LineDescription) {
        let engine = CabinePCC.Engine(seed: 21)
        do {
            try engine.takeUp(description)
        } catch {
            check("the engine takes up the \(name)", false, "\(error)")
            return
        }
        let first = engine.snapshot()
        guard let line = first.line else {
            check("the engine takes up the \(name)", false, "it is on no line")
            return
        }
        let stops = [line.track(1).stopsM, line.track(2).stopsM]

        // The fleet: what the headway asks for, standing at platforms part-way through their stops.
        let wanted = SelfTest.fleet(lap: first.lapTimeS, headway: first.headwayS, line)
        let slowest = 2 * line.lengthM / 3 + Double(2 * line.stationCount) * 60 + 600
        check("a lap of the loop is measured when the line is taken up", first.lapTimeS > 2 * line.lengthM / line.lineSpeedMS && first.lapTimeS < slowest,
              "\(Int(first.lapTimeS)) s for \(Int(2 * line.lengthM)) m and \(2 * line.stationCount) stops")
        check("the fleet is what a headway of 150 s asks for", first.headwayS == 150 && first.automaticTarget == wanted,
              "\(first.automaticTarget) automatic rames wanted, \(first.rames.count) seeded")
        let seeded = first.rames.allSatisfy { rame in
            guard rame.cab == nil, rame.kind == .auto, let stop = rame.station else { return false }
            return abs(rame.uM - stops[rame.track - 1][stop]) < 0.001 && rame.phase == .dwelling && rame.doors == 1 && rame.speedMS == 0
        }
        let numbers = first.rames.map(\.number)
        check("they are seeded standing at platforms, doors open, numbered from 1, the first at the first stop of track 1",
              seeded && numbers == Array(1...max(first.rames.count, 1)) && first.rames.first?.track == 1 && first.rames.first?.station == 0
                && first.rames.count == min(wanted, 2 * line.stationCount))
        check("the line's clock starts at 08:42:00 and line service is on", first.clockS == 31_320 && first.inService && first.mode == .normal && !first.emergencyStop)

        // An hour, or a lap and a quarter if that is longer, a twentieth of a second at a time. The time
        // run is a whole number of those steps: it is what the clock is held to below.
        let steps = Int((max(3_600, min(1.25 * first.lapTimeS, 10_800)) / 0.05).rounded(.up))
        let duration = Double(steps) * 0.05
        let watch = LineWatch(line)
        watch.observe(first)
        for _ in 0..<steps {
            engine.step(0.05)
            watch.observe(engine.snapshot())
        }
        let last = engine.snapshot()
        let ran = String(format: "%.0f min", duration / 60)

        check("\(ran): no two trains ever overlap or come nearer than the safety margin", watch.count(.gap) == 0 && watch.leastGap >= line.cbtc.safetyMarginM,
              watch.count(.gap) == 0 ? String(format: "least %.2f m from a nose to the rear ahead, margin %.0f m", watch.leastGap, line.cbtc.safetyMarginM) : describe(watch))
        check("\(ran): every automatic rame calls at every stop in order", watch.count(.order) == 0 && watch.calls > 0,
              watch.count(.order) == 0 ? "\(watch.calls) calls" : describe(watch))
        check("\(ran): each call is made with the nose within 1 m of the stop", watch.count(.stop) == 0 && watch.worstStop <= 1,
              watch.count(.stop) == 0 ? String(format: "furthest %.3f m", watch.worstStop) : describe(watch))
        check("\(ran): the doors open fully at every call", watch.count(.doors) == 0, describe(watch, unless: watch.count(.doors) == 0))
        check("\(ran): no automatic rame is ever over a zone's limit or the line speed", watch.count(.speed) == 0 && watch.nearestToLimit <= 0,
              watch.count(.speed) == 0 ? String(format: "nearest %.2f m/s under", -watch.nearestToLimit) : describe(watch))
        check("\(ran): every stop of both tracks is called at", watch.everyStopCalledAt,
              watch.calledAt.map { $0.map(String.init).joined(separator: " ") }.joined(separator: " | "))
        check("\(ran): rames turn back through both tails, and come out as they should", watch.turns[0] > 0 && watch.turns[1] > 0 && watch.count(.turn) == 0,
              watch.count(.turn) == 0 ? "\(watch.turns[0]) out of track 1, \(watch.turns[1]) out of track 2" : describe(watch))
        let round = 2 * line.stationCount
        let observed = watch.lapTimes.isEmpty ? 0 : watch.lapTimes.reduce(0, +) / Double(watch.lapTimes.count)
        check("\(ran): rames get all the way round the loop", watch.longestRun > round && !watch.lapTimes.isEmpty && abs(observed - first.lapTimeS) < 0.2 * first.lapTimeS,
              String(format: "%d stops in a row by one rame; %d laps timed, %.0f s on average against %.0f s measured", watch.longestRun, watch.lapTimes.count, observed, first.lapTimeS))
        // Where there are fewer platforms than rames, the rest come out of the tails as the line runs:
        // the fleet grows to what is asked for, and never shrinks.
        check("\(ran): the fleet comes to what the headway asks for and stays there",
              watch.fewestAutomatic == first.rames.count && watch.mostAutomatic == wanted && last.rames.count == wanted && !watch.automaticFell,
              watch.fewestAutomatic == wanted ? "\(wanted) automatic rames throughout" : "from \(watch.fewestAutomatic) seeded to \(watch.mostAutomatic) automatic rames")
        let clock = (31_320 + duration).truncatingRemainder(dividingBy: 86_400)
        check("\(ran): the clock has run with the line", abs(last.clockS - clock) < 0.001 && abs(last.timeS - duration) < 0.001)

        // The same seed, the same run.
        func tenMinutes(seed: UInt64) -> [String] {
            let again = CabinePCC.Engine(seed: seed)
            try? again.takeUp(description)
            for _ in 0..<12_000 { again.step(0.05) }
            return again.snapshot().rames.map { "\($0.number) \($0.track) \($0.uM) \($0.speedMS) \($0.phase) \($0.doors)" }
        }
        let one = tenMinutes(seed: 77), two = tenMinutes(seed: 77), three = tenMinutes(seed: 78)
        check("the same seed gives the same run, and another seed another", !one.isEmpty && one == two && one != three)
    }

    /// The first few faults a watch noted, in words; nothing when `unless` holds.
    func describe(_ watch: LineWatch, unless fine: Bool = false) -> String {
        fine ? "" : watch.firstFaults.joined(separator: "; ")
    }
}

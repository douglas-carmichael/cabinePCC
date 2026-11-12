import Foundation

extension CabinePCC {

    /// A line built in code, for the self-test and as a sample of the `line` object: six invented
    /// stations over five kilometres, laid out as Cabine lays its own (tail tracks of 200 m beyond each
    /// terminus, platforms of 82 m, a beacon at each of the signals Cabine would plant), with a few speed
    /// zones, one of them through a station. It is not a mirror image of itself, so that mistaking one
    /// track for the other shows.
    public static let testLine: CabineWire.LineDescription = {
        typealias Description = CabineWire.LineDescription
        let length = 5_000.0
        let names = ["Porte des Essais", "Rue du Gabarit", "Place des Jalons", "Pont de la Mesure", "Cours du Repère", "Porte du Banc"]
        /// Middle of each station along track 1.
        let centres = [241.0, 1_100, 2_050, 3_000, 3_900, 4_759]
        /// Speed limits along track 1, which hold on both tracks: from, to, km/h.
        let limits: [(from: Double, to: Double, kmh: Double)] = [
            (520, 700, 45), (1_480, 1_640, 55), (2_380, 2_540, 40), (2_960, 3_110, 30), (3_350, 3_470, 50), (4_200, 4_390, 60)
        ]
        let platform = 82.0, setback = 2.5

        func track(_ number: Int) -> Description.Track {
            // Track 2 runs the other way: a point `s` along track 1 is at `length - s` along it.
            let middles = number == 1 ? centres : centres.reversed().map { length - $0 }
            let stops = middles.map { $0 + platform / 2 - setback }
            let zones = limits
                .map { number == 1 ? ($0.from, $0.to, $0.kmh) : (length - $0.to, length - $0.from, $0.kmh) }
                .sorted { $0.0 < $1.0 }
                .map { Description.Zone(fromM: $0.0, toM: $0.1, limitMS: CabineWire.rounded($0.2 / 3.6)) }
            // A beacon where Cabine has a signal: 14 m before each platform, 6 m beyond it, and between
            // two stations as many more as keep them 250 m apart at most.
            var beacons: [Double] = []
            for (index, middle) in middles.enumerated() {
                let entry = middle - platform / 2 - 14, exit = middle + platform / 2 + 6
                beacons += [entry, exit]
                if index + 1 < middles.count {
                    let gap = middles[index + 1] - platform / 2 - 14 - exit
                    let between = max(0, Int((gap / 250).rounded(.up)) - 1)
                    for k in 0..<between { beacons.append(CabineWire.rounded(exit + gap * Double(k + 1) / Double(between + 1))) }
                }
            }
            return Description.Track(track: number, stopsM: stops, zones: zones, beaconsM: beacons.sorted())
        }

        let tracks = [track(1), track(2)]
        // The revision is a hash of the numbers that make the geometry, as Cabine's is of its own.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ value: Double) {
            for byte in withUnsafeBytes(of: value.bitPattern.littleEndian, Array.init) {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
        }
        mix(length)
        for track in tracks {
            track.stopsM.forEach(mix)
            for zone in track.zones ?? [] { [zone.fromM, zone.toM, zone.limitMS].forEach(mix) }
            (track.beaconsM ?? []).forEach(mix)
        }

        return Description(id: "essai", name: "Ligne d'essai", rev: String(format: "%016llx", hash), lengthM: length,
                           colour: "1F6FB2", textColour: "FFFFFF", lineSpeedMS: 19.444,
                           train: Description.defaultTrain, cbtc: Description.defaultCBTC, dwell: Description.defaultDwell,
                           endBufferM: Description.defaultEndBufferM,
                           stations: names.map { Description.Station(name: $0) }, tracks: tracks)
    }()
}

import Foundation

extension CabinePCC {

    /// A small seeded generator (SplitMix64), so that a run of the engine can be had again from its seed.
    public struct SeededRandom: Sendable {
        private var state: UInt64

        public init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in [0, 1).
        public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

        public mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }

        public mutating func chance(_ probability: Double) -> Bool { unit() < probability }
    }
}

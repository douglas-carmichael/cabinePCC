import Foundation

// How an automatic rame moves: a point mass and the automatic driver that handles it. Both follow
// Cabine's own (its TrainBody and AutoDriver), so that a rame driven from here moves as one of Cabine's
// traffic trains does: it settles under a limit by the line's margin, comes down to a lower limit or to
// a stop on the line's approach deceleration, and stops within a few centimetres of where it should.
// What Cabine's model has and this one leaves out is the track's relief: gradients and the drag of
// curves.

extension CabinePCC {

    /// The stock an automatic rame is made of: the line's figures for it, and the few that the line
    /// description does not carry.
    struct Stock: Sendable {
        let lengthM: Double
        let maxSpeedMS: Double
        let accelerationMS2: Double
        let serviceBrakeMS2: Double
        let emergencyBrakeMS2: Double
        let approachDecelMS2: Double
        let marginMS: Double

        // The rest are Cabine's own estimates for its stock, as shares of the figures above where they
        // go with them.

        /// Rolling resistance as a deceleration, m/s².
        static let rollingResistance = 0.070
        /// Air resistance in a tunnel as a deceleration, m/s² for every (m/s)².
        static let airResistance = 0.000_246
        /// The speed above which the drive gives less than its starting effort, as a share of the top
        /// speed, for a train a third full; and the same for the full train the driver's handling of the
        /// controller is worked out for.
        static let powerKnee = 0.585
        static let driverKnee = 0.489

        init(_ train: Line.Train) {
            lengthM = train.lengthM
            maxSpeedMS = train.maxSpeedMS
            accelerationMS2 = train.accelerationMS2
            serviceBrakeMS2 = train.serviceBrakeMS2
            emergencyBrakeMS2 = train.emergencyBrakeMS2
            approachDecelMS2 = train.approachDecelMS2
            marginMS = train.marginMS
        }

        /// Rolling and air resistance as a deceleration, m/s².
        func resistance(at speed: Double) -> Double {
            Stock.rollingResistance + Stock.airResistance * speed * speed
        }

        /// What the drive gives with the controller full forward, m/s²: enough to start the train at its
        /// published acceleration against its rolling resistance, and above the knee what its power allows.
        func traction(at speed: Double) -> Double {
            let starting = accelerationMS2 + Stock.rollingResistance
            return min(starting, starting * Stock.powerKnee * maxSpeedMS / max(speed, 0.1))
        }
    }

    /// The motion of one rame along its track.
    struct Body: Sendable {
        /// Where its nose is: `uM` on its track.
        var position: Double
        var speed = 0.0
        var acceleration = 0.0
        /// Realised effort: +1 full power … -1 full service brake. It lags the command.
        var effort = 0.0
        /// 0 … 1 application of the emergency brake.
        var emergency = 0.0

        var isStopped: Bool { speed < 0.02 }

        /// Advances the rame by `dt`.
        /// - Parameters:
        ///   - command: demanded effort, +1 … -1.
        ///   - emergencyBrake: the emergency brake is called for (which also cuts the drive).
        mutating func step(dt: Double, command: Double, emergencyBrake: Bool, stock: Stock) {
            var target = min(max(command, -1), 1)
            if emergencyBrake && target > 0 { target = 0 }

            // Effort follows the command at a limited rate: the jerk limit and the time the brake takes.
            let rate: Double
            if target > effort {
                rate = effort < 0 ? 2.4 : 1.1          // releasing brake / building power
            } else {
                rate = effort > 0 ? 3.5 : 1.7          // cutting power / applying brake
            }
            effort += min(max(target - effort, -rate * dt), rate * dt)
            let emergencyRate = emergencyBrake ? 4.0 : 1.4
            emergency += min(max((emergencyBrake ? 1.0 : 0.0) - emergency, -emergencyRate * dt), emergencyRate * dt)

            let v = speed
            let traction = effort > 0 && v <= stock.maxSpeedMS ? effort * stock.traction(at: v) : 0
            let brake = min(max(-effort, 0) * stock.serviceBrakeMS2 + emergency * stock.emergencyBrakeMS2,
                            max(stock.emergencyBrakeMS2, stock.serviceBrakeMS2))
            let resistance = stock.resistance(at: v)

            var newSpeed: Double
            if v < 0.02 {
                // At rest the brakes hold the train unless the drive overcomes what resists it.
                let hold = brake + resistance + (effort <= 0 && target <= 0 ? stock.serviceBrakeMS2 : 0)
                newSpeed = traction > hold ? v + (traction - hold) * dt : 0
            } else {
                newSpeed = max(0, v + (traction - brake - resistance) * dt)
            }
            acceleration = (newSpeed - v) / dt
            position += (v + newSpeed) * 0.5 * dt
            speed = newSpeed
        }
    }

    /// Target-speed driver: runs up to the limit, obeys the lower limits ahead and stops accurately at a
    /// target.
    ///
    /// It works out one thing, the acceleration it wants, and asks the drive or the brake for it. That
    /// acceleration is a continuous function of where the train is and how fast it is going, so what it
    /// asks never jumps between power and brake.
    struct Driver: Sendable {
        /// Brake effort that holds the train once it has come to rest where it should.
        static let standingBrake = -0.7
        /// How hard it corrects a speed that is not the one it wants: m/s² for every m/s.
        static let gain = 0.5
        /// The speed it still has on reaching a stopping point, m/s, where the final hold takes over.
        static let arrivalSpeed = 0.3
        /// How fast the speed it aims for rises once the tail has run clear of a limit, m/s².
        static let pickUp = 1.0
        /// It gathers no speed that it would have to shed again within this many seconds.
        static let foresight = 12.0
        /// How far before a lower limit begins it is down to it, in metres.
        static let early = 6.0
        /// How far behind the tail a limit it has run clear of still shapes the speed it aims for, in metres.
        static let releaseRange = 250.0

        let stock: Stock
        /// How far ahead it looks for a lower limit, in metres: far enough to see one before it would
        /// have to hold its speed for it.
        let lookAhead: Double

        init(stock: Stock) {
            self.stock = stock
            let top = stock.maxSpeedMS
            lookAhead = max(600, top * top / (2 * stock.approachDecelMS2) + top * Driver.foresight + 50)
        }

        /// The speed it settles at under a limit: the line's margin under it, and never above it however
        /// low the limit.
        func aim(under limit: Double) -> Double {
            max(limit - stock.marginMS, min(1.5, 0.75 * limit))
        }

        /// The acceleration that keeps a train on the braking curve down to `target` m/s at `distance`
        /// metres, or brings it back to that curve. With `easing`, the brake is let go over the last
        /// second of the curve, where the curve itself ends in a corner.
        private func approach(speed v: Double, target: Double, distance: Double, easing: Bool) -> Double {
            let deceleration = stock.approachDecelMS2
            let curve = (target * target + 2 * deceleration * distance).squareRoot()
            let held = easing ? min(1, distance / max(v, 5)) : 1
            let share = min(max((v - target) / max(curve - target, 0.05), 0), 1)
            return Driver.gain * (curve - v) - deceleration * v / max(curve, 0.1) * held * share
        }

        /// What the braking curve down to `target` m/s at `distance` metres asks of a train before it
        /// reaches it: below the speed the curve will allow `foresight` seconds on it may still gather
        /// some; above it, it holds what it has.
        private func lead(speed v: Double, target: Double, distance: Double) -> Double {
            let then = (target * target + 2 * stock.approachDecelMS2 * max(distance - v * Driver.foresight, 0)).squareRoot()
            return max(Driver.gain * (then - v), 0)
        }

        /// What the driver asks of a rame, +1 full power … -1 full service brake.
        /// - Parameters:
        ///   - speed: its speed, m/s.
        ///   - nose: where its nose is on `track`.
        ///   - lineSpeed: the limit outside every zone.
        ///   - stopDistance: metres from the nose to where it must come to rest, if anywhere.
        ///   - cursor: the first zone of the track still to be minded, which this moves on as the train
        ///     does. It starts at 0 for a train new to the track, and is good for as long as the train only
        ///     goes forward on it.
        func command(speed v: Double, nose: Double, track: Line.Track, lineSpeed: Double, stopDistance: Double?,
                     cursor: inout Int) -> Double {
            let tail = nose - stock.lengthM
            var limit = lineSpeed
            // The lowest of what the limits it has run clear of still allow, and of what those ahead ask.
            var released = Double.infinity
            var ahead = Double.infinity
            // A plain loop over the zones in the order the train meets them: this runs for every rame at
            // every step.
            let zones = track.zones
            // A zone the tail has left behind by more than it still counts for is behind for good.
            while cursor < zones.count && zones[cursor].toM < tail - Driver.releaseRange { cursor += 1 }
            var index = cursor
            while index < zones.count {
                let zone = zones[index]
                index += 1
                if zone.fromM > nose {
                    // A lower limit ahead: met a little early, first by its lead, then by its curve.
                    let distance = zone.fromM - nose
                    if distance >= lookAhead { break }
                    let target = aim(under: zone.limitMS), room = distance > Driver.early ? distance - Driver.early : 0
                    let leading = lead(speed: v, target: target, distance: room)
                    let braking = approach(speed: v, target: target, distance: room, easing: true)
                    if leading < ahead { ahead = leading }
                    if braking < ahead { ahead = braking }
                } else if zone.toM >= tail {
                    // Under the train.
                    if zone.limitMS < limit { limit = zone.limitMS }
                } else if tail - zone.toM < Driver.releaseRange {
                    // The tail has lately run clear of it: the speed aimed for rises from the old one as
                    // the train runs on, and does not leap to the new.
                    let from = aim(under: zone.limitMS)
                    let rising = (from * from + 2 * Driver.pickUp * (tail - zone.toM)).squareRoot()
                    if rising < released { released = rising }
                }
            }

            var wanted = Driver.gain * (Swift.min(aim(under: limit), released) - v)
            if ahead < wanted { wanted = ahead }
            if let stop = stopDistance {
                let d = stop > 0 ? stop : 0
                // Final hold.
                if d < 0.12 && v < 0.5 { return Driver.standingBrake }
                let leading = lead(speed: v, target: Driver.arrivalSpeed, distance: d)
                let braking = approach(speed: v, target: Driver.arrivalSpeed, distance: d, easing: false)
                if leading < wanted { wanted = leading }
                if braking < wanted { wanted = braking }
            }
            // What coasting already does: the drive or the brake supplies the rest.
            let needed = wanted + stock.resistance(at: v)
            if needed >= 0 {
                // Above the knee the drive gives less: the same acceleration takes more of the controller.
                let knee = Stock.driverKnee * stock.maxSpeedMS
                return min(needed / stock.accelerationMS2 * max(v, knee) / knee, 1)
            }
            return max(needed / stock.serviceBrakeMS2, -1)
        }
    }
}

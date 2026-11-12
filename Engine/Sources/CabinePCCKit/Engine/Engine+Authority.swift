import Foundation

// A cab's movement authority: how far it has leave to run, worked out as Cabine's own zone controller
// works it out (its Session.zoneAuthority), and when it is sent.

extension CabinePCC.Engine {

    /// How far a cab has leave to run, and what ends it.
    struct Reach {
        var end: Double
        var reason: CabineWire.AuthorityReason
        /// With a train ahead: its number, and the metres from the cab's nose to its rear.
        var rame: Int?
        var gap: Double?
    }

    /// The room a train running at `speed` is left to come to a stand in when its authority is cut back
    /// under it: enough for its automatic driver to stop on the line's approach deceleration, a little
    /// short of the end as it does, with time to hear of it. Less would throw a train that is doing
    /// nothing wrong into its emergency brake.
    private func stoppingRoom(at speed: Double, _ line: CabinePCC.Line) -> Double {
        speed * speed / (2 * line.train.approachDecelMS2) + 2 * speed + line.cbtc.stoppingShortM + 5
    }

    /// True when a cab's train is at a stand at a platform: by its own word, or by where it is.
    private func standsAtPlatform(_ train: Train, _ line: CabinePCC.Line) -> Bool {
        guard train.body.speed < 0.1 else { return false }
        if train.cab?.status?.station?.atPlatform == true { return true }
        return line.stop(track: train.track, near: train.body.position, tolerance: CabinePCC.Engine.platformReach) != nil
    }

    /// The authority a cab's train has at this moment. It ends at the nearest of the train ahead on its
    /// own track (its rear, less what its position may be out by, less the margin), the end of its track,
    /// and as far as an authority reaches. While the operator holds the train at a platform, the line is
    /// out of service or a general emergency stop is on, it ends where the train stands; a train caught
    /// on the move is left the room to come to a stand.
    func reach(for index: Int, _ line: CabinePCC.Line) -> Reach {
        let train = trains[index]
        let nose = train.body.position
        var reach = Reach(end: nose + line.cbtc.horizonM, reason: .horizon)

        // The train ahead on its own track. A rame turning back at the end of that track counts: it
        // stands there until it comes out on the other.
        var ahead: Train?
        for (other, candidate) in trains.enumerated() where other != index && candidate.track == train.track {
            let there = candidate.body.position
            guard there > nose || (there == nose && candidate.id > train.id) else { continue }
            if ahead == nil || there < ahead!.body.position { ahead = candidate }
        }
        if let ahead {
            let rear = ahead.body.position - line.train.lengthM
            let end = rear - line.uncertainty(track: ahead.track, noseM: ahead.body.position) - line.cbtc.safetyMarginM
            if end < reach.end { reach = Reach(end: end, reason: .train, rame: ahead.number, gap: rear - nose) }
        }
        if line.endOfTrackM < reach.end { reach = Reach(end: line.endOfTrackM, reason: .end) }

        // What cuts it back to where the train stands.
        guard let cab = train.cab else { return reach }
        let standing = train.body.speed < 0.1
        if !train.holdOrdered {
            cab.holdLatched = false
        } else if !cab.holdLatched, standsAtPlatform(train, line) {
            // The hold takes a train at the platform it is at, or the next it reaches.
            cab.holdLatched = true
        }
        let restriction: CabineWire.AuthorityReason? = emergencyStop ? .emergency : (!inService ? .service : (cab.holdLatched ? .hold : nil))
        if let restriction {
            var limit = cab.restrictedEnd ?? (standing ? nose : nose + stoppingRoom(at: train.body.speed, line))
            // Once it has come to a stand short of that, it is held there.
            if standing && nose < limit { limit = nose }
            cab.restrictedEnd = limit
            if limit <= reach.end { reach = Reach(end: limit, reason: restriction) }
        } else {
            cab.restrictedEnd = nil
        }
        return reach
    }

    /// Sends each cab in service its authority when it is due: every `authorityPeriodS`, and at once when
    /// it has changed for the worse or ends for another reason.
    func sendAuthorities(_ h: Double, _ line: CabinePCC.Line) {
        var next = 0
        while next < trains.count {
            let index = next
            next += 1
            guard let cab = trains[index].cab, let session = cab.session, let link = linkIndex(session) else { continue }
            let reach = reach(for: index, line)
            // Rounded down to the millimetre, so that what is sent is never beyond what was worked out. (An
            // end that is a whole millimetre but for the last bit of its arithmetic, as where a train
            // stands is, stays that millimetre.)
            let end = (reach.end * 1_000 + 1e-6).rounded(.down) / 1_000
            let track = trains[index].track
            var due = time - cab.sentAt + h / 2 >= settings.link.authorityPeriodS
            if let last = cab.sent {
                if end < last.endM - 0.05 || reach.reason != last.reason || track != last.track { due = true }
            } else {
                due = true
            }
            guard due else { continue }
            links[link].authoritySeq += 1
            let authority = CabineWire.Authority(seq: links[link].authoritySeq, tS: CabineWire.rounded(time), track: track,
                                                 endM: end == 0 ? 0 : end, reason: reach.reason, rame: reach.rame,
                                                 gapM: reach.gap.map { CabineWire.rounded($0) },
                                                 validS: settings.authorityValidS)
            trains[index].cab?.sent = authority
            trains[index].cab?.sentAt = time
            send(.authority(authority), to: session)
        }
    }
}

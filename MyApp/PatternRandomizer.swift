import Foundation

/// Musical random patterns for the Randomize (dice) buttons: a melody in a scale for the
/// sequencer, a sensible beat for the drums. Pure functions; the UI applies the result.
nonisolated enum PatternRandomizer {
    /// Minor pentatonic, in semitones above the root.
    static let scale = [0, 3, 5, 7, 10]

    /// Root note: the most frequent note in the bank, or A in an octave that suits the preset.
    static func root(for steps: [Int?], category: PresetCategory) -> Int {
        let notes = steps.compactMap { $0 }
        if !notes.isEmpty {
            var counts: [Int: Int] = [:]
            for note in notes { counts[note, default: 0] += 1 }
            // Most frequent; on a tie the lowest, which is usually the tonic of a riff.
            return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }!.key
        }
        return category == .bass ? 33 : 57 // A1 for bass, A3 for everything else
    }

    /// 16 steps of minor pentatonic around `root`: step 1 is the root, 9–12 steps play,
    /// strong steps are favoured, notes repeat often and sometimes jump an octave.
    static func melody<G: RandomNumberGenerator>(root: Int, using rng: inout G) -> [Int?] {
        let count = SynthPatch.stepCount
        // Notes within an octave above the root (and the octave itself).
        let pool = (scale + [12]).map { root + $0 }.filter { (0...127).contains($0) }
        guard !pool.isEmpty else { return Array(repeating: nil, count: count) }

        // Which steps play: step 1 always, then weighted draws (downbeats > eighths > the rest).
        var active: Set<Int> = [0]
        let target = Int.random(in: 9...12, using: &rng)
        var candidates = Array(1..<count)
        while active.count < target, !candidates.isEmpty {
            let weights = candidates.map { $0 % 4 == 0 ? 4 : ($0 % 2 == 0 ? 2 : 1) }
            var pick = Int.random(in: 0..<weights.reduce(0, +), using: &rng)
            var index = 0
            while pick >= weights[index] { pick -= weights[index]; index += 1 }
            active.insert(candidates.remove(at: index))
        }

        var steps: [Int?] = Array(repeating: nil, count: count)
        var previous = root
        for step in 0..<count where active.contains(step) {
            var note: Int
            if step == 0 {
                note = root
            } else if Double.random(in: 0..<1, using: &rng) < 0.35 {
                note = previous // repeated notes are common in sequencer lines
            } else {
                note = pool.randomElement(using: &rng)!
            }
            // About 15% jump an octave (up for low roots, else either way), staying in MIDI range.
            if step != 0, Double.random(in: 0..<1, using: &rng) < 0.15 {
                let up = root < 48 || Bool.random(using: &rng)
                let jumped = note + (up ? 12 : -12)
                if (0...127).contains(jumped) { note = jumped }
            }
            steps[step] = note
            previous = note
        }
        return steps
    }

    /// A beat for one drum bank (rows in `DrumKind` order): kick on 1 plus two or three more,
    /// snare and/or clap on 5 and 13, one of a few hat patterns, rarely an open hat.
    static func beat<G: RandomNumberGenerator>(using rng: inout G) -> [[Bool]] {
        var pattern = DrumKit.emptyPattern
        func hit(_ drum: DrumKind, _ step: Int) { pattern[drum.rawValue][step] = true }
        func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

        // Kick: step 1, then two or three of 5, 9, 13; sometimes a syncopated one.
        hit(.kick, 0)
        for step in [4, 8, 12].shuffled(using: &rng).prefix(Int.random(in: 2...3, using: &rng)) { hit(.kick, step) }
        if chance(0.35) { hit(.kick, [7, 10, 14].randomElement(using: &rng)!) }

        // Backbeat on 5 and 13: snare, clap or both; rarely one ghost snare.
        for step in [4, 12] {
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: hit(.snare, step)
            case 1: hit(.clap, step)
            default: hit(.snare, step); hit(.clap, step)
            }
        }
        if chance(0.2) { hit(.snare, [3, 7, 11, 14, 15].randomElement(using: &rng)!) }

        // Closed hat: eighths, offbeats only, or sixteenths with a few gaps.
        switch Int.random(in: 0..<3, using: &rng) {
        case 0: for step in stride(from: 0, to: 16, by: 2) { hit(.closedHat, step) }
        case 1: for step in [2, 6, 10, 14] { hit(.closedHat, step) }
        default:
            let gaps = Set((0..<16).shuffled(using: &rng).prefix(Int.random(in: 2...4, using: &rng)))
            for step in 0..<16 where !gaps.contains(step) { hit(.closedHat, step) }
        }

        // Open hat: at most one or two offbeat hits, replacing the closed hat there.
        if chance(0.5) {
            for step in [2, 6, 10, 14].shuffled(using: &rng).prefix(Int.random(in: 1...2, using: &rng)) {
                hit(.openHat, step)
                pattern[DrumKind.closedHat.rawValue][step] = false
            }
        }

        // The extra percussion stays sparse, so the beat stays a beat.
        // Toms: a small fill near the end of the bar, about 30% of the time.
        if chance(0.3) {
            let fill = [12, 13, 14, 15].shuffled(using: &rng).prefix(Int.random(in: 1...2, using: &rng)).sorted()
            for (i, step) in fill.enumerated() { hit(i == 0 ? .tomHi : .tomLo, step) }
        }
        // Rim: one or two offbeat clicks, sometimes.
        if chance(0.3) {
            for step in [3, 7, 10, 11, 15].shuffled(using: &rng).prefix(Int.random(in: 1...2, using: &rng)) { hit(.rim, step) }
        }
        // Cowbell: on a couple of eighths, now and then.
        if chance(0.2) {
            for step in [0, 2, 6, 8, 10].shuffled(using: &rng).prefix(2) { hit(.cowbell, step) }
        }
        // Ride: quarter notes, sometimes, instead of the open hat.
        if chance(0.25) {
            for step in [0, 4, 8, 12] { hit(.ride, step) }
            pattern[DrumKind.openHat.rawValue] = Array(repeating: false, count: SynthPatch.stepCount)
        }
        // Crash: on the downbeat, now and then.
        if chance(0.2) { hit(.crash, 0) }
        // Shaker: offbeat sixteenths or eighths, sometimes.
        if chance(0.25) {
            for step in Bool.random(using: &rng) ? [2, 6, 10, 14] : [1, 3, 5, 7, 9, 11, 13, 15] { hit(.shaker, step) }
        }
        // Clave: the 3-2 son clave, rarely.
        if chance(0.15) {
            for step in [0, 3, 6, 10, 12] { hit(.clave, step) }
        }
        // FX: a single hit near the end of the bar, rarely.
        if chance(0.1) { hit(.fx, [14, 15].randomElement(using: &rng)!) }
        return pattern
    }

    // MARK: - Drum sounds

    /// Tuning (semitones) a random drum sound may get: wide enough to sound different,
    /// narrow enough that nothing turns into a click or a whistle.
    static func tuneRange(_ drum: DrumKind) -> ClosedRange<Float> {
        switch drum {
        case .kick: -5...3
        case .snare, .clap: -4...4
        case .closedHat, .openHat: -3...5
        case .tomLo, .tomHi: -4...4
        case .rim, .cowbell: -3...3
        case .ride: -2...3
        case .crash: -3...3
        case .shaker: -3...4
        case .clave: -4...4
        case .fx: -24...6 // FX's knob reaches -36; this keeps it from turning into a rumble
        }
    }

    /// Decay a random drum sound may get: the middle of the variant's knob range, so it is
    /// neither a near-silent tick nor an endless tail.
    static func decayRange(_ drum: DrumKind, _ variant: Int) -> ClosedRange<Float> {
        let full = DrumVariants.decayRange(drum, variant)
        let span = full.upperBound - full.lowerBound
        return (full.lowerBound + 0.2 * span)...(full.lowerBound + 0.7 * span)
    }

    /// New sounds for every drum: a random variant, tuning (whole semitones) and decay.
    /// Levels, mutes, patterns, banks and the drum bus stay exactly as they are.
    static func drumSounds<G: RandomNumberGenerator>(for kit: DrumKit, using rng: inout G) -> DrumKit {
        var result = kit
        for drum in DrumKind.allCases {
            var voice = result[drum]
            voice.variant = Int.random(in: 0..<DrumVariants.count, using: &rng)
            voice.tune = Float.random(in: tuneRange(drum), using: &rng).rounded()
            voice.decay = Float.random(in: decayRange(drum, voice.variant), using: &rng)
            result[drum] = voice
        }
        return result
    }
}

extension SynthPatch.Drums {
    /// This kit with the sound settings (variant, tune, decay) of `other` and everything else
    /// (levels, mutes, patterns, banks, drum bus) kept: what Undo of "Randomize drum sounds" restores.
    nonisolated func withSounds(from other: DrumKit) -> DrumKit {
        var result = self
        for drum in DrumKind.allCases {
            result[drum].variant = other[drum].variant
            result[drum].tune = other[drum].tune
            result[drum].decay = other[drum].decay
        }
        return result
    }
}

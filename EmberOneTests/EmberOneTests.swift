import Foundation
import Testing
@testable import Ember_One

/// Tests for the external MIDI clock filter (`ExternalClock`) with synthetic tick streams:
/// steady tempos with ±3 ms timestamp jitter, a tempo jump, a ramp, dropped ticks, a pause,
/// outliers, the tempo range and source following. Pure logic, no audio.
///
/// Measured from the first lock on, including while it re-locks after a tempo change.
/// Phase error = how far the clock's prediction of a step tick (made before that tick arrives,
/// exactly what the audio thread schedules with) is from the tick's true, unjittered time.
/// The mapping from true ticks to clock ticks is fixed, so a miscounted tick shows as an error.
struct ExternalClockTests {
    /// Deterministic random numbers, so every run measures the same streams.
    struct SeededRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    struct Measurement {
        var phaseErrors: [Double] = []
        var tempoErrors: [Double] = []
        var phaseMax: Double { (phaseErrors.max() ?? 0) * 1000 }
        var phaseRMS: Double {
            ((phaseErrors.map { $0 * $0 }.reduce(0, +) / Double(max(phaseErrors.count, 1))).squareRoot()) * 1000
        }
        var tempoMax: Double { tempoErrors.max() ?? 0 }
        var summary: String {
            String(format: "%d steps, phase max %.2f ms, rms %.2f ms, tempo max %.3f BPM", phaseErrors.count, phaseMax, phaseRMS, tempoMax)
        }
    }

    static func steady(bpm: Double, seconds: Double = 60) -> [Double] {
        let period = 60 / (bpm * 24)
        return (0..<Int(seconds / period)).map { Double($0) * period }
    }

    static func times(seconds: Double, tempo: (Double) -> Double) -> [Double] {
        var t = 0.0, out: [Double] = []
        while t < seconds {
            out.append(t)
            t += 60 / (tempo(t) * 24)
        }
        return out
    }

    /// Feeds jittered ticks and measures each step tick (every 6th) inside `from...to`.
    static func run(_ times: [Double], jitter: Double = 0.003, drop: Set<Int> = [], seed: UInt64 = 42,
                    from: Double, to: Double = .infinity, tempo: (Double) -> Double,
                    onStep: ((Double, Double, Double) -> Void)? = nil) -> (Measurement, ExternalClock) {
        var random = SeededRandom(state: seed)
        let clock = ExternalClock()
        var offset: Int64?
        var measurement = Measurement()
        var wasLocked = false
        for (n, t) in times.enumerated() {
            // Every step the audio thread would schedule: once locked, also while re-locking
            // after a tempo change (it keeps scheduling with the current estimate then).
            wasLocked = wasLocked || clock.isLocked(at: t)
            let schedules = clock.isLocked(at: t) || (wasLocked && clock.hasPeriod && t - clock.lastTickTime < 4 * clock.period)
            if let offset, schedules, n % 6 == 0, t >= from, t <= to {
                let phase = abs(clock.time(ofTick: Int64(n) + offset) - t)
                let tempoError = abs(clock.tempo - tempo(t))
                measurement.phaseErrors.append(phase)
                measurement.tempoErrors.append(tempoError)
                onStep?(t, phase, tempoError)
            }
            if drop.contains(n) { continue }
            let stamp = t + Double.random(in: -jitter...jitter, using: &random)
            if clock.tick(at: stamp, source: 1) > 0, offset == nil || !clock.hasPeriod {
                offset = clock.lastIndex - Int64(n) // set once, and again only after the clock starts over
            }
        }
        return (measurement, clock)
    }

    static let seeds: [UInt64] = Array(1...10)

    static func worst(_ values: [Double]) -> Double { values.max() ?? 0 }
    static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    @Test(arguments: [90.0, 120.0, 140.0])
    func steadyTempoWithJitter(bpm: Double) {
        let runs = Self.seeds.map { Self.run(Self.steady(bpm: bpm), seed: $0, from: 4, tempo: { _ in bpm }).0 }
        let phaseMax = Self.worst(runs.map(\.phaseMax)), phaseRMS = Self.worst(runs.map(\.phaseRMS))
        let tempoMax = Self.worst(runs.map(\.tempoMax))
        print(String(format: "steady %.0f BPM ±3 ms, worst of %d streams: phase max %.2f ms, phase rms %.2f ms, tempo max %.3f BPM",
                     bpm, runs.count, phaseMax, phaseRMS, tempoMax))
        #expect(runs.allSatisfy { $0.phaseErrors.count > 200 })
        #expect(phaseRMS < 0.5)
        #expect(phaseMax < 1.5)
        #expect(tempoMax < 0.1)
    }

    @Test func abruptTempoChange120To128() {
        let change = 20.0
        let stream = Self.times(seconds: 50) { $0 < change ? 120 : 128 }
        let beat = 60.0 / 128
        var close: [Double] = [], settled: [Double] = []
        for seed in Self.seeds {
            var lastFar = change, lastOff = change
            _ = Self.run(stream, seed: seed, from: change, tempo: { $0 < change ? 120 : 128 }) { t, phase, tempoError in
                if phase > 0.002 || tempoError > 0.5 { lastFar = t }   // within 2 ms and 0.5 BPM
                if phase > 0.001 || tempoError > 0.1 { lastOff = t }   // within 1 ms and 0.1 BPM
            }
            close.append((lastFar - change) / beat)
            settled.append((lastOff - change) / beat)
        }
        print(String(format: "120 -> 128 BPM: within 2 ms / 0.5 BPM for good after %.1f beats (median), %.1f (worst); " +
                     "within 1 ms / 0.1 BPM after %.1f (median), %.1f (worst)",
                     Self.median(close), Self.worst(close), Self.median(settled), Self.worst(settled)))
        #expect(Self.worst(close) <= 2)
        #expect(Self.median(settled) <= 3)
        #expect(Self.worst(settled) <= 10)
    }

    @Test func tempoRamp() {
        let start = 15.0, length = 8 * 60 / 130.0
        let tempo: (Double) -> Double = { t in t < start ? 120 : (t < start + length ? 120 + 20 * (t - start) / length : 140) }
        let stream = Self.times(seconds: 40, tempo: tempo)
        let during = Self.seeds.map { Self.run(stream, seed: $0, from: start, to: start + length, tempo: tempo).0.phaseMax }
        let after = Self.seeds.map { Self.run(stream, seed: $0, from: start + length + 2, tempo: tempo).0 }
        print(String(format: "ramp 120 -> 140 BPM over 8 beats: phase max during the ramp %.2f ms (median), %.2f (worst); " +
                     "2 s later phase max %.2f ms, tempo max %.3f BPM (worst)",
                     Self.median(during), Self.worst(during), Self.worst(after.map(\.phaseMax)), Self.worst(after.map(\.tempoMax))))
        #expect(Self.worst(during) < 8)
        #expect(Self.worst(after.map(\.phaseMax)) < 1.5)
        #expect(Self.worst(after.map(\.tempoMax)) < 0.25)
    }

    @Test func droppedTicks() {
        let stream = Self.steady(bpm: 120)
        let runs = Self.seeds.map { seed in
            var random = SeededRandom(state: seed &+ 100)
            var drop = Set<Int>()
            while drop.count < 12 { drop.insert(Int.random(in: 300..<stream.count, using: &random)) }
            return Self.run(stream, drop: drop, seed: seed, from: 4, tempo: { _ in 120 }).0
        }
        print(String(format: "120 BPM with 12 dropped ticks, worst of %d: phase max %.2f ms, tempo max %.3f BPM",
                     runs.count, Self.worst(runs.map(\.phaseMax)), Self.worst(runs.map(\.tempoMax))))
        #expect(Self.worst(runs.map(\.phaseMax)) < 1.5) // no miscounted ticks (one would be ~21 ms)
        #expect(Self.worst(runs.map(\.tempoMax)) < 0.1)
    }

    @Test func pauseAndRestart() {
        let period = 60.0 / (120 * 24)
        var stream = (0..<480).map { Double($0) * period }
        let resume = stream.last! + 3.0137 // 3 s silence, then the clock restarts with a new phase
        stream += (0..<1440).map { resume + Double($0) * period }
        var relock: [Double] = [], rms: [Double] = []
        for seed in Self.seeds {
            var relocked: Double?
            let (m, clock) = Self.run(stream, seed: seed, from: resume, tempo: { _ in 120 }) { t, _, _ in
                if relocked == nil { relocked = t - resume }
            }
            relock.append(relocked ?? .infinity)
            rms.append(m.phaseRMS)
            #expect(clock.isLocked)
        }
        print(String(format: "pause 3 s and restart: steps follow the clock again after %.2f s (worst), then phase rms %.2f ms (worst)",
                     Self.worst(relock), Self.worst(rms)))
        #expect(Self.worst(relock) <= 1.0)
        #expect(Self.worst(rms) < 0.5)
    }

    @Test func clockGoesQuiet() {
        let clock = ExternalClock()
        for t in Self.steady(bpm: 120, seconds: 3) { clock.tick(at: t, source: 1) }
        #expect(clock.isLocked(at: 3.0))
        #expect(!clock.isLocked(at: 3.5)) // no tick for half a second
    }

    @Test func singleOutlierIsIgnored() {
        let clock = ExternalClock()
        let stream = Self.steady(bpm: 120, seconds: 10)
        for (n, t) in stream.enumerated() {
            clock.tick(at: n == 300 ? t + 0.008 : t, source: 1) // one tick 8 ms late (38% of a tick)
        }
        #expect(abs(clock.time(ofTick: clock.lastIndex) - stream.last!) < 0.0005)
        #expect(abs(clock.tempo - 120) < 0.05)
    }

    @Test func tempoOutsideRangeIsIgnored() {
        let clock = ExternalClock()
        for t in Self.steady(bpm: 400, seconds: 2) { clock.tick(at: t, source: 1) } // faster than 300 BPM
        #expect(!clock.hasPeriod)
        let slow = ExternalClock()
        for t in Self.steady(bpm: 15, seconds: 4) { slow.tick(at: t, source: 1) } // slower than 20 BPM
        #expect(!slow.hasPeriod)
    }

    @Test func followsOneSourceUntilItGoesQuiet() {
        let clock = ExternalClock()
        for t in Self.steady(bpm: 120, seconds: 2) {
            clock.tick(at: t, source: 1)
            clock.tick(at: t + 0.007, source: 2) // a second clock at the same time is ignored
        }
        #expect(clock.source == 1)
        #expect(abs(clock.tempo - 120) < 0.05)
        // Source 1 is silent for over 2 s: source 2 takes over.
        for t in Self.steady(bpm: 100, seconds: 2) { clock.tick(at: 4.5 + t, source: 2) }
        #expect(clock.source == 2)
        #expect(abs(clock.tempo - 100) < 0.1)
    }
}

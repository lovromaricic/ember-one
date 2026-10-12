import Foundation

// Synthesised drums for the rhythm machine. Runs on the audio thread: no allocation, locks
// or I/O after init. Every sound is built from sine/square oscillators, white noise and a
// state-variable filter, shaped by fast exponential envelopes. Each drum has five variants
// ("recipes"); a variant only affects hits that start after it was chosen, so switching
// never cuts a ringing hit or the rhythm.

/// Per-variant knob ranges and natural lengths, shared by the UI and the synth.
nonisolated enum DrumVariants {
    static var count: Int { 5 }

    /// Decay knob range (seconds) for a drum's variant.
    static func decayRange(_ drum: DrumKind, _ variant: Int) -> ClosedRange<Float> {
        switch (drum, variant) {
        case (.kick, 1): 0.4...1.5      // Deep
        case (.kick, 2): 0.08...0.5     // Hard
        case (.kick, 3): 0.06...0.4     // Punch
        case (.kick, 4): 0.5...1.5      // Boom
        case (.kick, _): 0.15...0.8     // House
        case (.snare, 1): 0.15...0.8    // Fat
        case (.snare, 2): 0.1...0.7     // Electro
        case (.snare, 3): 0.05...0.15   // Rimshot
        case (.snare, 4): 0.1...0.5     // Lo-fi
        case (.snare, _): 0.08...0.35   // Crisp
        case (.clap, 1): 0.05...0.18    // Tight
        case (.clap, 2): 0.3...1        // Room
        case (.clap, 3): 0.05...0.25    // Snap
        case (.clap, 4): 0.15...0.6     // Wide
        case (.clap, _): 0.1...0.5      // House
        case (.closedHat, 1): 0.02...0.15   // Soft
        case (.closedHat, 2): 0.02...0.15   // Metallic
        case (.closedHat, 3): 0.01...0.04   // Tick
        case (.closedHat, 4): 0.03...0.2    // Noisy
        case (.closedHat, _): 0.02...0.12   // Crisp
        case (.openHat, 1): 0.08...0.3      // Short
        case (.openHat, 2): 0.15...0.9      // Metallic
        case (.openHat, 3): 0.3...1.5       // Washy
        case (.openHat, 4): 0.1...0.6       // Soft
        case (.openHat, _): 0.15...0.8      // Long
        case (.tomLo, 1): 0.15...1.2        // Deep
        case (.tomLo, 2): 0.05...0.3        // Tight
        case (.tomLo, 3): 0.1...0.8         // Electro
        case (.tomLo, 4): 0.1...0.7         // Soft
        case (.tomLo, _): 0.08...0.6        // Classic
        case (.tomHi, 1): 0.1...0.9         // Deep
        case (.tomHi, 2): 0.04...0.25       // Tight
        case (.tomHi, 3): 0.08...0.6        // Electro
        case (.tomHi, 4): 0.08...0.5        // Soft
        case (.tomHi, _): 0.06...0.45       // Classic
        case (.rim, 1): 0.02...0.15         // Wood
        case (.rim, 2): 0.01...0.08         // Sharp
        case (.rim, 3): 0.02...0.12         // Snap
        case (.rim, 4): 0.02...0.3          // Soft
        case (.rim, _): 0.015...0.12        // Classic
        case (.cowbell, 1): 0.1...0.8       // High
        case (.cowbell, 2): 0.1...1.0       // Low
        case (.cowbell, 3): 0.05...0.25     // Short
        case (.cowbell, 4): 0.1...0.8       // Dry
        case (.cowbell, _): 0.1...0.8       // Classic
        case (.ride, 1): 0.3...2.5          // Bright
        case (.ride, 2): 0.3...3.0          // Dark
        case (.ride, 3): 0.2...2.0          // Bell
        case (.ride, 4): 0.5...3.0          // Wash
        case (.ride, _): 0.3...2.5          // Classic
        }
    }

    /// The length a variant starts with when it is chosen.
    static func defaultDecay(_ drum: DrumKind, _ variant: Int) -> Float {
        switch (drum, variant) {
        case (.kick, 1): 0.9
        case (.kick, 2): 0.25
        case (.kick, 3): 0.18
        case (.kick, 4): 1.2
        case (.kick, _): 0.4
        case (.snare, 1): 0.35
        case (.snare, 2): 0.3
        case (.snare, 3): 0.06
        case (.snare, 4): 0.22
        case (.snare, _): 0.18
        case (.clap, 1): 0.08
        case (.clap, 2): 0.6
        case (.clap, 3): 0.1
        case (.clap, 4): 0.3
        case (.clap, _): 0.22
        case (.closedHat, 1): 0.05
        case (.closedHat, 2): 0.05
        case (.closedHat, 3): 0.015
        case (.closedHat, 4): 0.08
        case (.closedHat, _): 0.04
        case (.openHat, 1): 0.15
        case (.openHat, 2): 0.35
        case (.openHat, 3): 0.7
        case (.openHat, 4): 0.25
        case (.openHat, _): 0.3
        case (.tomLo, 1): 0.45
        case (.tomLo, 2): 0.12
        case (.tomLo, 3): 0.3
        case (.tomLo, 4): 0.25
        case (.tomLo, _): 0.25
        case (.tomHi, 1): 0.3
        case (.tomHi, 2): 0.09
        case (.tomHi, 3): 0.22
        case (.tomHi, 4): 0.18
        case (.tomHi, _): 0.18
        case (.rim, 1): 0.05
        case (.rim, 2): 0.025
        case (.rim, 3): 0.04
        case (.rim, 4): 0.07
        case (.rim, _): 0.04
        case (.cowbell, 1): 0.28
        case (.cowbell, 2): 0.35
        case (.cowbell, 3): 0.12
        case (.cowbell, 4): 0.3
        case (.cowbell, _): 0.3
        case (.ride, 1): 0.8
        case (.ride, 2): 1.1
        case (.ride, 3): 0.7
        case (.ride, 4): 1.4
        case (.ride, _): 0.9
        }
    }
}

/// One sounding drum hit, with the recipe of the variant it was started with.
nonisolated struct DrumHit {
    var isActive = false
    var age = 0                 // samples since the hit started
    var gain: Float = 1         // variant loudness trim

    var amp: Float = 0          // main envelope (kick body, noise)
    var ampMul: Float = 1
    var tone: Float = 0         // snare drum-head envelope
    var toneMul: Float = 1
    var pitch: Float = 0        // pitch-drop envelope (kick, snare)
    var pitchMul: Float = 1
    var click: Float = 0        // kick attack click
    var clickMul: Float = 1
    var choke: Float = 1        // open hat fade-out when a closed hat cuts it
    var chokeMul: Float = 1

    var phase: Float = 0
    var phase2: Float = 0
    var startFrequency: Float = 0
    var endFrequency: Float = 0
    var frequency2: Float = 0
    var tone2Mix: Float = 0
    var noiseLevel: Float = 1
    var softClip: Float = 0     // kick drive (0 = clean)

    // Clap bursts.
    var burst: Float = 0
    var burstMul: Float = 1
    var burstsLeft = 0
    var burstSpacing = 1
    var nextBurst = 0
    var tailStart = 0
    var tailLevel: Float = 0

    // Lo-fi snare: sample-and-hold and amplitude steps.
    var crush = false
    var holdLeft = 0
    var held: Float = 0

    // Metallic hats: six detuned square oscillators.
    var metal = false
    var metalPhases: (Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0)
    var metalRatio: Float = 1

    // Wide clap: the right channel gets its own noise.
    var wide = false

    // State-variable filter: mode 0 = high-pass, 1 = band-pass, 2 = low-pass.
    var filterMode: UInt8 = 0
    var a1: Float = 0
    var a2: Float = 0
    var a3: Float = 0
    var k: Float = 1
    var ic1: Float = 0
    var ic2: Float = 0
    var ic1R: Float = 0
    var ic2R: Float = 0

    var loudness: Float { max(amp, max(tone, burst)) * choke }
}

nonisolated final class DrumSynth {
    /// Hits per drum that can ring at once, so a new hit never cuts the previous tail abruptly.
    static var voicesPerDrum: Int { 3 }

    private let hits: UnsafeMutablePointer<DrumHit>
    private let sampleRate: Float
    private var noiseState: UInt32 = 0x9E37_79B9
    private var noiseStateR: UInt32 = 0x6C07_8965

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let count = DrumKind.count * Self.voicesPerDrum
        hits = .allocate(capacity: count)
        hits.initialize(repeating: DrumHit(), count: count)
    }

    deinit { hits.deallocate() }

    // MARK: - Triggering

    /// Starts a hit. `tune` is in semitones, `decay` in seconds (time to fade by ~40 dB).
    func trigger(_ drum: Int, variant: Int, tune: Float, decay: Float) {
        let sr = sampleRate
        if drum == DrumKind.closedHat.rawValue {
            // A closed hat chokes a ringing open hat, with a 4 ms fade instead of a hard cut.
            let base = DrumKind.openHat.rawValue * Self.voicesPerDrum
            for v in 0..<Self.voicesPerDrum where hits[base + v].isActive {
                hits[base + v].chokeMul = exp(-1 / (0.004 * sr))
            }
        }

        // Use a silent voice, otherwise the quietest one.
        let base = drum * Self.voicesPerDrum
        var chosen = base
        var quietest = Float.greatestFiniteMagnitude
        for v in base..<(base + Self.voicesPerDrum) {
            if !hits[v].isActive { chosen = v; break }
            if hits[v].loudness < quietest { quietest = hits[v].loudness; chosen = v }
        }

        var hit = DrumHit()
        hit.isActive = true
        let ratio = exp2(tune / 12)
        hit.amp = 1
        hit.ampMul = envelopeMul(seconds: max(decay, 0.005) / 4.6)

        switch drum {
        case DrumKind.kick.rawValue:
            setupKick(&hit, variant: variant, ratio: ratio)
        case DrumKind.snare.rawValue:
            setupSnare(&hit, variant: variant, ratio: ratio)
        case DrumKind.clap.rawValue:
            setupClap(&hit, variant: variant, ratio: ratio)
        case DrumKind.closedHat.rawValue:
            setupClosedHat(&hit, variant: variant, ratio: ratio)
        case DrumKind.openHat.rawValue:
            setupOpenHat(&hit, variant: variant, ratio: ratio)
        case DrumKind.tomLo.rawValue, DrumKind.tomHi.rawValue:
            setupTom(&hit, high: drum == DrumKind.tomHi.rawValue, variant: variant, ratio: ratio)
        case DrumKind.rim.rawValue:
            setupRim(&hit, variant: variant, ratio: ratio)
        case DrumKind.cowbell.rawValue:
            setupCowbell(&hit, variant: variant, ratio: ratio, decay: decay)
        default:
            setupRide(&hit, variant: variant, ratio: ratio, decay: decay)
        }
        hits[chosen] = hit
    }

    private func envelopeMul(seconds: Float) -> Float {
        exp(-1 / (max(seconds, 0.0005) * sampleRate))
    }

    /// Kick: sine with a fast pitch drop, a short click and some soft clipping.
    private func setupKick(_ hit: inout DrumHit, variant: Int, ratio: Float) {
        // (start Hz, end Hz, pitch drop time, click, soft clip, gain)
        let recipe: (Float, Float, Float, Float, Float, Float) = switch variant {
        case 1: (120, 42, 0.05, 0.05, 1.0, 1.0)     // Deep: long, soft sub
        case 2: (220, 55, 0.02, 0.45, 4.0, 0.8)     // Hard: short, distorted
        case 3: (260, 80, 0.015, 0.3, 2.0, 0.9)     // Punch: short, mid-heavy
        case 4: (150, 45, 0.12, 0.05, 1.2, 1.0)     // Boom: long, slow pitch drop
        default: (180, 50, 0.03, 0.25, 1.5, 1.0)    // House: punchy, short click, gentle clip
        }
        hit.startFrequency = recipe.0 * ratio
        hit.endFrequency = recipe.1 * ratio
        hit.pitch = 1
        hit.pitchMul = envelopeMul(seconds: recipe.2)
        hit.click = recipe.3
        hit.clickMul = envelopeMul(seconds: 0.002)
        hit.softClip = recipe.4
        hit.gain = recipe.5
    }

    /// Snare: one or two drum-head tones plus filtered noise (the wires).
    private func setupSnare(_ hit: inout DrumHit, variant: Int, ratio: Float) {
        // (tone 1 Hz, tone 2 Hz, tone 2 mix, tone time, noise filter Hz, filter mode, noise level, gain)
        let recipe: (Float, Float, Float, Float, Float, UInt8, Float, Float) = switch variant {
        case 1: (140, 240, 0.5, 0.1, 1200, 0, 0.7, 1.0)    // Fat: deeper, longer body
        case 2: (200, 0, 0, 0.03, 1500, 0, 1.1, 0.9)       // Electro: mostly noise
        case 3: (420, 1700, 0.6, 0.015, 4000, 0, 0.3, 1.4) // Rimshot: short click
        case 4: (170, 300, 0.5, 0.06, 1000, 0, 0.8, 1.0)   // Lo-fi: rougher, crushed
        default: (180, 330, 0.6, 0.05, 2000, 0, 0.8, 1.0)  // Crisp: two tones + bright noise
        }
        hit.startFrequency = recipe.0 * ratio
        hit.frequency2 = recipe.1 * ratio
        hit.tone2Mix = recipe.2
        hit.tone = 1
        hit.toneMul = envelopeMul(seconds: recipe.3)
        hit.pitch = 1
        hit.pitchMul = envelopeMul(seconds: 0.01)
        setFilter(&hit, cutoff: recipe.4 * ratio, k: 1.4, mode: recipe.5)
        hit.noiseLevel = recipe.6
        hit.gain = recipe.7
        hit.crush = variant == 4
    }

    /// Clap: a few short noise bursts a few ms apart through a band-pass, then a tail.
    private func setupClap(_ hit: inout DrumHit, variant: Int, ratio: Float) {
        // (bursts, spacing s, band-pass Hz, k, tail level, gain)
        let recipe: (Int, Float, Float, Float, Float, Float) = switch variant {
        case 1: (2, 0.005, 1300, 0.8, 0.5, 1.1)     // Tight: very short
        case 2: (4, 0.010, 900, 0.8, 0.8, 0.9)      // Room: longer tail
        case 3: (1, 0.008, 2000, 1.0, 0.4, 1.3)     // Snap: one sharp hit
        case 4: (4, 0.009, 1100, 0.8, 0.75, 1.0)    // Wide: stereo
        default: (4, 0.008, 1000, 0.8, 0.75, 1.0)   // House: 4 bursts, ~1 kHz, short tail
        }
        let spacing = max(1, Int(recipe.1 * sampleRate))
        hit.burst = 1
        hit.burstMul = envelopeMul(seconds: 0.0035)
        hit.burstsLeft = recipe.0 - 1
        hit.burstSpacing = spacing
        hit.nextBurst = spacing
        hit.tailStart = recipe.0 * spacing
        hit.tailLevel = recipe.4
        hit.amp = 0
        setFilter(&hit, cutoff: recipe.2 * ratio, k: recipe.3, mode: 1)
        hit.gain = recipe.5
        hit.wide = variant == 4
    }

    private func setupClosedHat(_ hit: inout DrumHit, variant: Int, ratio: Float) {
        // (filter Hz, mode, k, metallic, gain)
        let recipe: (Float, UInt8, Float, Bool, Float) = switch variant {
        case 1: (5000, 1, 2.0, false, 1.6)      // Soft: wide band-pass, gentler
        case 2: (5000, 0, 1.2, true, 2.6)       // Metallic: square cluster
        case 3: (9000, 0, 1.2, false, 1.3)      // Tick: very short, very high
        case 4: (3000, 0, 1.2, false, 0.8)      // Noisy: more body
        default: (7000, 0, 1.2, false, 1.0)     // Crisp: high-pass noise
        }
        setFilter(&hit, cutoff: recipe.0 * ratio, k: recipe.2, mode: recipe.1)
        hit.metal = recipe.3
        hit.metalRatio = ratio
        hit.gain = recipe.4
    }

    private func setupOpenHat(_ hit: inout DrumHit, variant: Int, ratio: Float) {
        let recipe: (Float, UInt8, Float, Bool, Float) = switch variant {
        case 1: (6500, 0, 1.2, false, 1.0)      // Short
        case 2: (5000, 0, 1.2, true, 2.6)       // Metallic
        case 3: (5000, 1, 2.0, false, 2.4)      // Washy: long and murky
        case 4: (7000, 1, 2.0, false, 1.6)      // Soft
        default: (6500, 0, 1.2, false, 1.0)     // Long
        }
        setFilter(&hit, cutoff: recipe.0 * ratio, k: recipe.2, mode: recipe.1)
        hit.metal = recipe.3
        hit.metalRatio = ratio
        hit.gain = recipe.4
    }

    /// Toms: a sine that sweeps down from ~2.5× its pitch to the base pitch, and a noise click.
    private func setupTom(_ hit: inout DrumHit, high: Bool, variant: Int, ratio: Float) {
        // (start multiple, sweep time s, click, gain)
        let recipe: (Float, Float, Float, Float) = switch variant {
        case 1: (2.0, 0.07, 0.15, 1.0)    // Deep: slower, rounder sweep
        case 2: (1.8, 0.025, 0.35, 1.0)   // Tight: short, little sweep
        case 3: (4.0, 0.06, 0.2, 0.9)     // Electro: big "pew" sweep
        case 4: (1.5, 0.04, 0.0, 1.0)     // Soft: barely any sweep, no click
        default: (2.5, 0.04, 0.3, 1.0)    // Classic
        }
        let base: Float = (high ? 150 : 90) * ratio
        hit.startFrequency = base * recipe.0
        hit.endFrequency = base
        hit.pitch = 1
        hit.pitchMul = envelopeMul(seconds: recipe.1 / 4.6)
        hit.click = recipe.2
        hit.clickMul = envelopeMul(seconds: 0.0015)
        hit.gain = recipe.3
        hit.softClip = 1.2
    }

    /// Rimshot: two short detuned tones (sine and triangle) and a burst of high-passed noise.
    private func setupRim(_ hit: inout DrumHit, variant: Int, ratio: Float) {
        // (tone 1 Hz, tone 2 Hz, noise burst, high-pass Hz, gain)
        let recipe: (Float, Float, Float, Float, Float) = switch variant {
        case 1: (1200, 380, 0.3, 3000, 1.0)     // Wood: lower, rounder
        case 2: (2200, 620, 0.5, 6000, 0.9)     // Sharp: higher, shorter
        case 3: (1700, 480, 0.9, 4000, 0.9)     // Snap: more noise
        case 4: (1500, 430, 0.2, 3000, 0.8)     // Soft
        default: (1700, 480, 0.5, 4000, 1.0)    // Classic
        }
        hit.startFrequency = recipe.0 * ratio
        hit.frequency2 = recipe.1 * ratio
        hit.click = recipe.2
        hit.clickMul = envelopeMul(seconds: 0.004)
        setFilter(&hit, cutoff: recipe.3 * ratio, k: 1.2, mode: 0)
        hit.gain = recipe.4
    }

    /// Cowbell: two square waves through a band-pass; a fast first drop, then the ring.
    private func setupCowbell(_ hit: inout DrumHit, variant: Int, ratio: Float, decay: Float) {
        // (square 1 Hz, square 2 Hz, band-pass Hz, k, gain)
        let recipe: (Float, Float, Float, Float, Float) = switch variant {
        case 1: (720, 1070, 2000, 0.9, 0.9)     // High
        case 2: (400, 600, 1100, 0.9, 1.1)      // Low
        case 3: (540, 800, 1500, 0.9, 1.0)      // Short
        case 4: (540, 800, 1500, 1.8, 1.1)      // Dry: wider band
        default: (540, 800, 1500, 0.9, 1.0)     // Classic
        }
        hit.startFrequency = recipe.0 * ratio
        hit.frequency2 = recipe.1 * ratio
        setFilter(&hit, cutoff: recipe.2 * ratio, k: recipe.3, mode: 1)
        hit.tone = 1                                              // the fast first drop
        hit.toneMul = envelopeMul(seconds: max(decay, 0.02) * 0.12 / 4.6)
        hit.gain = recipe.4
    }

    /// Ride: the hats' six-square metal cluster plus high-passed noise, a short bright ping,
    /// and a slow tail that rings longer and softer than the open hat.
    private func setupRide(_ hit: inout DrumHit, variant: Int, ratio: Float, decay: Float) {
        // (high-pass Hz, ping Hz, ping level, metal ratio, noise level, gain)
        let recipe: (Float, Float, Float, Float, Float, Float) = switch variant {
        case 1: (8000, 6000, 0.6, 1.5, 0.35, 0.9)     // Bright
        case 2: (4500, 4000, 0.25, 1.1, 0.25, 1.1)    // Dark
        case 3: (6000, 2600, 0.9, 1.3, 0.2, 0.9)      // Bell: strong ping
        case 4: (6000, 5000, 0.2, 1.3, 0.55, 1.0)     // Wash: more noise
        default: (7000, 5000, 0.45, 1.3, 0.3, 1.0)    // Classic
        }
        setFilter(&hit, cutoff: recipe.0 * ratio, k: 1.2, mode: 0)
        hit.startFrequency = recipe.1 * ratio
        hit.click = recipe.2
        hit.clickMul = envelopeMul(seconds: 0.03 / 4.6)
        hit.metal = true
        hit.metalRatio = recipe.3 * ratio
        hit.noiseLevel = recipe.4
        hit.tone = 1                                              // the slow tail
        hit.toneMul = envelopeMul(seconds: max(decay, 0.05) * 2.5 / 4.6)
        hit.gain = recipe.5
    }

    private func setFilter(_ hit: inout DrumHit, cutoff: Float, k: Float, mode: UInt8) {
        let fc = min(max(cutoff, 20), sampleRate * 0.45)
        let g = tan(.pi * fc / sampleRate)
        hit.filterMode = mode
        hit.k = k
        hit.a1 = 1 / (1 + g * (g + k))
        hit.a2 = g * hit.a1
        hit.a3 = g * hit.a2
    }

    /// Fades every ringing hit out over ~10 ms (the drum track was switched off).
    func fadeOutAll() {
        let mul = envelopeMul(seconds: 0.01 / 4.6)
        for v in 0..<(DrumKind.count * Self.voicesPerDrum) where hits[v].isActive {
            hits[v].chokeMul = min(hits[v].chokeMul, mul)
        }
    }

    // MARK: - Rendering

    /// Adds `count` samples of all ringing drums to `left`/`right`. `levelStart`/`levelStep`
    /// hold one level ramp per drum, so level knobs never click.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int,
                levelStart: UnsafePointer<Float>, levelStep: UnsafePointer<Float>) {
        let sr = sampleRate
        for drum in 0..<DrumKind.count {
            let mix = Self.mixGain(drum)
            for v in (drum * Self.voicesPerDrum)..<((drum + 1) * Self.voicesPerDrum) where hits[v].isActive {
                var hit = hits[v]
                for i in 0..<count {
                    let level = (levelStart[drum] + levelStep[drum] * Float(i + 1)) * mix * hit.gain
                    var l: Float
                    var r: Float
                    switch drum {
                    case DrumKind.kick.rawValue:
                        let frequency = hit.endFrequency + (hit.startFrequency - hit.endFrequency) * hit.pitch
                        hit.phase += frequency / sr
                        if hit.phase >= 1 { hit.phase -= 1 }
                        var s = sin(2 * .pi * hit.phase) * hit.amp + noise() * hit.click * 0.5
                        if hit.softClip > 0 { s = tanh(hit.softClip * s) / tanh(hit.softClip) }
                        hit.pitch *= hit.pitchMul
                        hit.click *= hit.clickMul
                        l = s
                        r = s
                    case DrumKind.snare.rawValue:
                        let bend = 1 + 0.3 * hit.pitch
                        hit.phase += hit.startFrequency * bend / sr
                        if hit.phase >= 1 { hit.phase -= 1 }
                        hit.phase2 += hit.frequency2 * bend / sr
                        if hit.phase2 >= 1 { hit.phase2 -= 1 }
                        let body = (sin(2 * .pi * hit.phase) + hit.tone2Mix * sin(2 * .pi * hit.phase2)) * hit.tone * 0.6
                        var s = body + filter(&hit, noise()) * hit.amp * hit.noiseLevel
                        if hit.crush {
                            // Lo-fi: hold each value for 4 samples and round to coarse steps.
                            if hit.holdLeft == 0 {
                                hit.held = (s * 12).rounded() / 12
                                hit.holdLeft = 4
                            }
                            hit.holdLeft -= 1
                            s = hit.held
                        }
                        hit.tone *= hit.toneMul
                        hit.pitch *= hit.pitchMul
                        l = s
                        r = s
                    case DrumKind.clap.rawValue:
                        if hit.burstsLeft > 0 && hit.age == hit.nextBurst {
                            hit.burst = 1
                            hit.burstsLeft -= 1
                            hit.nextBurst += hit.burstSpacing
                        }
                        if hit.age == hit.tailStart { hit.amp = hit.tailLevel }
                        let envelope = max(hit.burst * 0.9, hit.amp) * 1.8
                        l = filter(&hit, noise()) * envelope
                        r = hit.wide ? filterRight(&hit, noiseRight()) * envelope : l
                        hit.burst *= hit.burstMul
                    case DrumKind.closedHat.rawValue, DrumKind.openHat.rawValue:
                        let source = hit.metal ? metallic(&hit) * 0.6 + noise() * 0.25 : noise()
                        let s = filter(&hit, source) * hit.amp * hit.choke
                        hit.choke *= hit.chokeMul
                        l = s
                        r = s
                    case DrumKind.tomLo.rawValue, DrumKind.tomHi.rawValue:
                        let frequency = hit.endFrequency + (hit.startFrequency - hit.endFrequency) * hit.pitch
                        hit.phase += frequency / sr
                        if hit.phase >= 1 { hit.phase -= 1 }
                        let s = sin(2 * .pi * hit.phase) * hit.amp + noise() * hit.click * 0.4
                        hit.pitch *= hit.pitchMul
                        hit.click *= hit.clickMul
                        l = Self.softClip(s, hit.softClip)
                        r = l
                    case DrumKind.rim.rawValue:
                        hit.phase += hit.startFrequency / sr
                        if hit.phase >= 1 { hit.phase -= 1 }
                        hit.phase2 += hit.frequency2 / sr
                        if hit.phase2 >= 1 { hit.phase2 -= 1 }
                        let triangle = 4 * abs(hit.phase2 - 0.5) - 1
                        let tones = (sin(2 * .pi * hit.phase) * 0.55 + triangle * 0.45) * hit.amp
                        let s = tones + filter(&hit, noise()) * hit.click
                        hit.click *= hit.clickMul
                        l = Self.softClip(s, 1.5)
                        r = l
                    case DrumKind.cowbell.rawValue:
                        hit.phase += hit.startFrequency / sr
                        if hit.phase >= 1 { hit.phase -= 1 }
                        hit.phase2 += hit.frequency2 / sr
                        if hit.phase2 >= 1 { hit.phase2 -= 1 }
                        let squares = ((hit.phase < 0.5 ? 1 : -1) + (hit.phase2 < 0.5 ? 1 : -1)) * Float(0.5)
                        let envelope = 0.55 * hit.amp + 0.45 * hit.tone * hit.amp
                        let s = filter(&hit, squares) * envelope * 2
                        hit.tone *= hit.toneMul
                        l = Self.softClip(s, 1.5)
                        r = l
                    case DrumKind.ride.rawValue:
                        hit.phase += hit.startFrequency / sr
                        if hit.phase >= 1 { hit.phase -= 1 }
                        let source = metallic(&hit) * 0.5 + noise() * hit.noiseLevel
                        // Body fades with the decay knob; a quieter tail fades 2.5× slower.
                        let envelope = 0.7 * hit.amp + 0.3 * hit.tone
                        let ping = sin(2 * .pi * hit.phase) * hit.click
                        let s = filter(&hit, source) * envelope + ping
                        hit.tone *= hit.toneMul
                        hit.click *= hit.clickMul
                        l = Self.softClip(s, 1.5)
                        r = l
                    default:
                        l = 0
                        r = 0
                    }
                    if drum < DrumKind.closedHat.rawValue || drum > DrumKind.openHat.rawValue {
                        // Hats apply their choke above; the others only fade when the track stops.
                        l *= hit.choke
                        r *= hit.choke
                        hit.choke *= hit.chokeMul
                    }
                    hit.amp *= hit.ampMul
                    hit.age += 1
                    left[i] += l * level
                    right[i] += r * level
                }
                let tailPending = drum == DrumKind.clap.rawValue && hit.age <= hit.tailStart
                if hit.choke < 0.0001 || (hit.loudness < 0.0001 && !tailPending) {
                    hit.isActive = false
                }
                hits[v] = hit
            }
        }
    }

    /// Balances the drums against each other at equal knob levels.
    @inline(__always)
    private static func mixGain(_ drum: Int) -> Float {
        switch drum {
        case DrumKind.kick.rawValue: 0.9
        case DrumKind.snare.rawValue: 0.7
        case DrumKind.clap.rawValue: 1.1
        case DrumKind.tomLo.rawValue, DrumKind.tomHi.rawValue: 0.7
        case DrumKind.rim.rawValue: 0.6
        case DrumKind.cowbell.rawValue: 0.55
        case DrumKind.ride.rawValue: 0.8
        default: 0.8
        }
    }

    /// Gentle saturation that keeps a voice below full scale (`drive` 0 = clean).
    @inline(__always)
    private static func softClip(_ x: Float, _ drive: Float) -> Float {
        drive > 0 ? tanh(drive * x) / tanh(drive) : x
    }

    /// Six square oscillators at classic metallic ratios (the 808 hat recipe).
    @inline(__always)
    private func metallic(_ hit: inout DrumHit) -> Float {
        let base = hit.metalRatio / sampleRate
        var p = hit.metalPhases
        var sum: Float = 0
        p.0 += 205.3 * 2 * base; if p.0 >= 1 { p.0 -= 1 }; sum += p.0 < 0.5 ? 1 : -1
        p.1 += 304.4 * 2 * base; if p.1 >= 1 { p.1 -= 1 }; sum += p.1 < 0.5 ? 1 : -1
        p.2 += 369.6 * 2 * base; if p.2 >= 1 { p.2 -= 1 }; sum += p.2 < 0.5 ? 1 : -1
        p.3 += 522.7 * 2 * base; if p.3 >= 1 { p.3 -= 1 }; sum += p.3 < 0.5 ? 1 : -1
        p.4 += 540.0 * 2 * base; if p.4 >= 1 { p.4 -= 1 }; sum += p.4 < 0.5 ? 1 : -1
        p.5 += 800.0 * 2 * base; if p.5 >= 1 { p.5 -= 1 }; sum += p.5 < 0.5 ? 1 : -1
        hit.metalPhases = p
        return sum / 6
    }

    @inline(__always)
    private func noise() -> Float {
        noiseState ^= noiseState << 13
        noiseState ^= noiseState >> 17
        noiseState ^= noiseState << 5
        return Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
    }

    @inline(__always)
    private func noiseRight() -> Float {
        noiseStateR ^= noiseStateR << 13
        noiseStateR ^= noiseStateR >> 17
        noiseStateR ^= noiseStateR << 5
        return Float(Int32(bitPattern: noiseStateR)) / Float(Int32.max)
    }

    /// One filter step on the left/mono state, returning the output for the hit's mode.
    @inline(__always)
    private func filter(_ hit: inout DrumHit, _ x: Float) -> Float {
        let v3 = x - hit.ic2
        let v1 = hit.a1 * hit.ic1 + hit.a2 * v3
        let v2 = hit.ic2 + hit.a2 * hit.ic1 + hit.a3 * v3
        hit.ic1 = 2 * v1 - hit.ic1
        hit.ic2 = 2 * v2 - hit.ic2
        return Self.filterOutput(mode: hit.filterMode, x: x, band: v1, low: v2, k: hit.k)
    }

    /// The same filter on separate state, for the wide clap's right channel.
    @inline(__always)
    private func filterRight(_ hit: inout DrumHit, _ x: Float) -> Float {
        let v3 = x - hit.ic2R
        let v1 = hit.a1 * hit.ic1R + hit.a2 * v3
        let v2 = hit.ic2R + hit.a2 * hit.ic1R + hit.a3 * v3
        hit.ic1R = 2 * v1 - hit.ic1R
        hit.ic2R = 2 * v2 - hit.ic2R
        return Self.filterOutput(mode: hit.filterMode, x: x, band: v1, low: v2, k: hit.k)
    }

    @inline(__always)
    private static func filterOutput(mode: UInt8, x: Float, band: Float, low: Float, k: Float) -> Float {
        switch mode {
        case 1: band
        case 2: low
        default: x - k * band - low
        }
    }
}

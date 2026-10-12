import Foundation
import Synchronization

// Everything in this file runs (or is read) on the real-time audio thread, so it is
// `nonisolated` and avoids allocation, locks and I/O inside `SynthDSP.render`. All buffers
// are allocated up front in the initialisers, and constants are computed properties
// (a `static let` is initialised lazily, which could happen on the audio thread).

/// A message from the UI to the audio thread.
nonisolated struct SynthEvent {
    enum Kind: UInt8 { case parameter, noteOn, noteOff, allNotesOff, stepNote, drumStep, play, stop, keyDown, keyUp, drumPreview, midi,
                       stagedDrumStep, commitDrumSteps, stagedStepNote, commitPattern,
                       clockMode }
    var kind: Kind
    var index: Int32  // parameter raw value, MIDI note, step number, drum step slot, or a `MIDIControl`
    var value: Float  // parameter value, velocity, step note (-1 = rest) or drum step on (1) / off (0)
}

/// Performance controls from a MIDI controller (`SynthEvent.Kind.midi`, `index`).
nonisolated enum MIDIControl: Int32 {
    case pitchBend = 0       // value: semitones
    case modWheel = 1        // value: 0...1
    case sustain = 2         // value: 0 or 1
    case modDestination = 3  // value: 0 = LFO amount, 1 = filter cutoff
}

/// What the audio thread reports back to the UI. Written by the audio thread only.
nonisolated final class SynthMonitor: @unchecked Sendable {
    /// Sequencer step currently playing, or -1 when stopped.
    let currentStep = Atomic<Int>(-1)
    /// Drum step currently playing, or -1 when stopped.
    let currentDrumStep = Atomic<Int>(-1)
    /// Note the sequencer played on the latest step (-1 for a rest).
    let lastSequencerNote = Atomic<Int>(-1)
    /// Master clock step within the bar (0...15), or -1 when stopped.
    let clockStep = Atomic<Int>(-1)
    /// Sequencer bank (0...7 = A...H) that is playing.
    let playingBank = Atomic<Int>(0)
    /// Drum bank (0...7 = A...H) that is playing.
    let playingDrumBank = Atomic<Int>(0)
    /// 1 while a track has been switched on and waits for the next bar to start.
    let sequencerArmed = Atomic<Int>(0)
    let drumsArmed = Atomic<Int>(0)
    /// MIDI clock: 0 = internal, 1 = waiting for clock, 2 = receiving, 3 = clock lost.
    let clockStatus = Atomic<Int>(0)
    /// Detected external tempo in hundredths of a BPM (0 when none).
    let clockTempo = Atomic<Int>(0)
    /// External clock mode: 1 while the transport runs or waits for the clock to start it.
    let clockTransport = Atomic<Int>(0)
#if DEBUG
    /// Host time (seconds, as bits) when the latest step was scheduled to sound, and its step
    /// number since the grid's origin (for the synthetic clock's sync log).
    let lastStepHostTime = Atomic<UInt64>(0)
    let lastStepIndex = Atomic<Int>(-1)
#endif
}

/// Lock-free single-producer (UI) / single-consumer (audio) ring buffer.
/// Storage is allocated once up front, so pushing and popping never allocate.
nonisolated final class SynthEventQueue: @unchecked Sendable {
    private static var capacity: Int { 4096 } // power of two
    private let slots: UnsafeMutablePointer<SynthEvent>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)

    init() {
        slots = .allocate(capacity: Self.capacity)
        slots.initialize(repeating: SynthEvent(kind: .allNotesOff, index: 0, value: 0), count: Self.capacity)
    }

    deinit {
        slots.deallocate()
    }

    /// UI thread only. Returns false if the audio thread has fallen far behind.
    @discardableResult
    func push(_ event: SynthEvent) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        guard write - read < Self.capacity else { return false }
        slots[write & (Self.capacity - 1)] = event
        writeIndex.store(write + 1, ordering: .releasing)
        return true
    }

    /// Audio thread only.
    func pop() -> SynthEvent? {
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        guard read != write else { return nil }
        let event = slots[read & (Self.capacity - 1)]
        readIndex.store(read + 1, ordering: .releasing)
        return event
    }
}

/// Attack–decay–sustain–release envelope with linear segments.
nonisolated struct Envelope {
    enum Stage { case idle, attack, decay, sustain, release }

    var stage = Stage.idle
    var level: Float = 0
    private var releaseStep: Float = 0

    /// Starts (or restarts) the attack from the current level, so retriggering doesn't click.
    mutating func gateOn() {
        stage = .attack
    }

    mutating func gateOff(releaseSamples: Float) {
        guard stage != .idle else { return }
        stage = .release
        releaseStep = level / max(releaseSamples, 1)
    }

    mutating func next(attackStep: Float, decayStep: Float, sustain: Float) -> Float {
        switch stage {
        case .idle:
            break
        case .attack:
            level += attackStep
            if level >= 1 {
                level = 1
                stage = .decay
            }
        case .decay:
            level -= decayStep
            if level <= sustain {
                level = sustain
                stage = .sustain
            }
        case .sustain:
            level = sustain // follows the knob while held
        case .release:
            level -= releaseStep
            if level <= 0 {
                level = 0
                stage = .idle
            }
        }
        return level
    }
}

nonisolated struct Voice {
    var note: Int32 = -1
    var velocity: Float = 0
    var gate = false
    var startOrder: UInt64 = 0
    /// Started by the sequencer (so switching the sequencer off can fade exactly these).
    var fromSequencer = false
    /// Key released while the sustain pedal is down: keeps sounding until the pedal is up.
    var sustained = false
    var phase1: Float = 0
    var phase2: Float = 0
    var amp = Envelope()
    var filterEnv = Envelope()
    // State of the low-pass filter (two integrators).
    var ic1: Float = 0
    var ic2: Float = 0

    var isActive: Bool { amp.stage != .idle }
}

// MARK: - Effects

/// Reads a circular buffer `delay` samples behind `write`, with linear interpolation.
@inline(__always)
nonisolated private func readDelayed(_ buffer: UnsafeMutablePointer<Float>, mask: Int, write: Int, delay: Float) -> Float {
    var position = Float(write) - delay
    if position < 0 { position += Float(mask + 1) }
    let i0 = Int(position)
    let fraction = position - Float(i0)
    let a = buffer[i0 & mask]
    let b = buffer[(i0 + 1) & mask]
    return a + (b - a) * fraction
}

nonisolated private func powerOfTwo(atLeast n: Int) -> Int {
    var size = 1
    while size < n { size <<= 1 }
    return size
}

/// Two slowly wobbling copies of the signal, one per side: classic stereo chorus.
nonisolated final class Chorus {
    private let buffer: UnsafeMutablePointer<Float>
    private let mask: Int
    private var write = 0
    private var phase: Float = 0
    private let sampleRate: Float

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let size = powerOfTwo(atLeast: Int(0.05 * sampleRate))
        mask = size - 1
        buffer = .allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
    }

    deinit { buffer.deallocate() }

    @inline(__always)
    func process(_ x: Float, rate: Float, mix: Float) -> (Float, Float) {
        buffer[write] = x
        phase += rate / sampleRate
        if phase >= 1 { phase -= 1 }
        let base = 0.012 * sampleRate
        let depth = 0.004 * sampleRate
        let wetLeft = readDelayed(buffer, mask: mask, write: write, delay: base + depth * sin(2 * .pi * phase))
        let wetRight = readDelayed(buffer, mask: mask, write: write, delay: base + depth * cos(2 * .pi * phase))
        write = (write + 1) & mask
        // mix 0 = untouched dry signal, mix 1 = equal parts dry and chorus.
        let dry = 1 - 0.5 * mix
        let wet = 0.5 * mix
        return (x * dry + wetLeft * wet, x * dry + wetRight * wet)
    }
}

/// Ping-pong delay: echoes alternate left and right.
nonisolated final class StereoDelay {
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let mask: Int
    private var write = 0
    private var currentDelay: Float
    private let sampleRate: Float

    init(sampleRate: Float, maxSeconds: Float, initialTime: Float) {
        self.sampleRate = sampleRate
        let size = powerOfTwo(atLeast: Int(maxSeconds * sampleRate) + 4)
        mask = size - 1
        left = .allocate(capacity: size)
        left.initialize(repeating: 0, count: size)
        right = .allocate(capacity: size)
        right.initialize(repeating: 0, count: size)
        currentDelay = initialTime * sampleRate
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    @inline(__always)
    /// Works as a send effect: `mix` sets how much of the synth goes in, `send` is extra input
    /// (the drum bus). The echoes are added to `l`/`r`.
    func process(_ l: inout Float, _ r: inout Float, time: Float, feedback: Float, mix: Float, send: Float) {
        // Glide to a new time instead of jumping, so turning the knob never clicks.
        let target = min(max(time * sampleRate, 1), Float(mask - 2))
        currentDelay += (target - currentDelay) * 0.0003
        let echoLeft = readDelayed(left, mask: mask, write: write, delay: currentDelay)
        let echoRight = readDelayed(right, mask: mask, write: write, delay: currentDelay)
        left[write] = (l + r) * 0.5 * mix + send + echoRight * feedback
        right[write] = echoLeft * feedback
        write = (write + 1) & mask
        l += echoLeft
        r += echoRight
    }
}

/// Freeverb-style reverb: eight parallel comb filters and four all-passes per side.
nonisolated final class Reverb {
    private static func combLength(_ i: Int) -> Int {
        switch i { case 0: 1116; case 1: 1188; case 2: 1277; case 3: 1356; case 4: 1422; case 5: 1491; case 6: 1557; default: 1617 }
    }
    private static func allpassLength(_ i: Int) -> Int {
        switch i { case 0: 556; case 1: 441; case 2: 341; default: 225 }
    }
    private static var combCount: Int { 8 }
    private static var allpassCount: Int { 4 }
    private static var stereoSpread: Int { 23 }

    // 16 combs (8 left, 8 right) then 8 all-passes (4 left, 4 right), all in one buffer.
    private let storage: UnsafeMutablePointer<Float>
    private let offsets: UnsafeMutablePointer<Int>
    private let lengths: UnsafeMutablePointer<Int>
    private let positions: UnsafeMutablePointer<Int>
    private let combFilter: UnsafeMutablePointer<Float>

    init(sampleRate: Float) {
        let scale = sampleRate / 44_100
        let lineCount = 2 * Self.combCount + 2 * Self.allpassCount
        offsets = .allocate(capacity: lineCount)
        lengths = .allocate(capacity: lineCount)
        positions = .allocate(capacity: lineCount)
        positions.initialize(repeating: 0, count: lineCount)
        combFilter = .allocate(capacity: 2 * Self.combCount)
        combFilter.initialize(repeating: 0, count: 2 * Self.combCount)

        var total = 0
        for line in 0..<lineCount {
            let isComb = line < 2 * Self.combCount
            let index = isComb ? line % Self.combCount : (line - 2 * Self.combCount) % Self.allpassCount
            let isRight = isComb ? line >= Self.combCount : line >= 2 * Self.combCount + Self.allpassCount
            let base = isComb ? Self.combLength(index) : Self.allpassLength(index)
            let length = max(1, Int(Float(base + (isRight ? Self.stereoSpread : 0)) * scale))
            offsets[line] = total
            lengths[line] = length
            total += length
        }
        storage = .allocate(capacity: total)
        storage.initialize(repeating: 0, count: total)
    }

    deinit {
        storage.deallocate()
        offsets.deallocate()
        lengths.deallocate()
        positions.deallocate()
        combFilter.deallocate()
    }

    @inline(__always)
    /// Send effect like `StereoDelay.process`: synth in at `mix`, plus `send` (the drum bus).
    func process(_ l: inout Float, _ r: inout Float, size: Float, mix: Float, send: Float) {
        let input = ((l + r) * mix + 2 * send) * 0.015
        let feedback = 0.7 + 0.28 * size
        let damp: Float = 0.25
        var wetLeft: Float = 0
        var wetRight: Float = 0

        for comb in 0..<(2 * Self.combCount) {
            let base = storage + offsets[comb]
            let position = positions[comb]
            let output = base[position]
            combFilter[comb] = output * (1 - damp) + combFilter[comb] * damp
            base[position] = input + combFilter[comb] * feedback
            positions[comb] = position + 1 == lengths[comb] ? 0 : position + 1
            if comb < Self.combCount { wetLeft += output } else { wetRight += output }
        }
        for allpass in 0..<(2 * Self.allpassCount) {
            let line = 2 * Self.combCount + allpass
            let base = storage + offsets[line]
            let position = positions[line]
            let buffered = base[position]
            if allpass < Self.allpassCount {
                base[position] = wetLeft + buffered * 0.5
                wetLeft = buffered - wetLeft
            } else {
                base[position] = wetRight + buffered * 0.5
                wetRight = buffered - wetRight
            }
            positions[line] = position + 1 == lengths[line] ? 0 : position + 1
        }
        l += wetLeft
        r += wetRight
    }
}

// MARK: - Synth

/// The synth's sound generator. Owned by `SynthEngine`; `render` is called on the audio thread.
nonisolated final class SynthDSP {
    static var voiceCount: Int { 8 }
    /// Pitch, LFO, filter coefficients and smoothing are updated every this many samples.
    static var controlBlock: Int { 32 }
    /// The limiter keeps every output sample at or below this level.
    static var limiterCeiling: Float { 0.95 }
    /// Sequencer notes are held for this fraction of a step.
    static var gateLength: Double { 0.5 }

    let sampleRate: Float
    private let queue: SynthEventQueue
    /// Second lock-free queue whose only producer is the MIDI input thread.
    private let midiQueue: SynthEventQueue?
    /// Timestamped MIDI clock, Start, Continue and Stop from the CoreMIDI receive thread.
    private let clockQueue: ClockEventQueue?

    // MIDI performance controls (targets, and values gliding towards them).
    private var bendTarget: Float = 0
    private var bend: Float = 0
    private var modTarget: Float = 0
    private var mod: Float = 0
    private var modToCutoff = false
    private var sustainDown = false
    private let monitor: SynthMonitor

    /// Latest values from the UI.
    private let params: UnsafeMutablePointer<Float>
    /// Values gliding towards `params` (for parameters with `isSmoothed`).
    private let smoothed: UnsafeMutablePointer<Float>
    /// `smoothed` at the start of the current block, for per-sample ramps.
    private let blockStart: UnsafeMutablePointer<Float>
    private let smoothFlags: UnsafeMutablePointer<Bool>

    /// Sequencer note per bank and step (bank * 16 + step), -1 = rest.
    private let steps: UnsafeMutablePointer<Int32>
    private let voices: UnsafeMutablePointer<Voice>
    private let mono: UnsafeMutablePointer<Float>
    /// Drum bus for the current block (stereo: `drumBus` is left, `drumBusRight` right).
    private let drumBus: UnsafeMutablePointer<Float>
    private let drumBusRight: UnsafeMutablePointer<Float>
    /// Drum bus compressor level follower.
    private var drumCompEnvelope: Float = 0
    private let drumCompAttack: Float
    private let drumCompRelease: Float
    /// Drum patterns of all banks: (bank * drums + drum) * 16 + step → 1 = hit.
    private let drumSteps: UnsafeMutablePointer<UInt8>
    /// A whole new set of drum banks (from a preset), filled step by step and swapped in at once
    /// on step 1 of the next bar while playing (at once when stopped). Same layout as `drumSteps`.
    private let stagedDrumSteps: UnsafeMutablePointer<UInt8>
    private var drumSwapPending = false
    /// A whole new set of sequencer banks and a tempo (from a pattern preset), swapped in with
    /// the staged drums on step 1 of the next bar while playing. Same layout as `steps`.
    private let stagedSteps: UnsafeMutablePointer<Int32>
    private var patternSwapPending = false
    private var stagedTempo: Float = 120
    /// Per-drum level ramps for the current block.
    private let drumLevelStart: UnsafeMutablePointer<Float>
    private let drumLevelStep: UnsafeMutablePointer<Float>
    private let drums: DrumSynth

    // Key mode (transpose / arp). Fixed 128-entry tables, one per MIDI note.
    /// Press order of each held key (0 = not held).
    private let heldKeys: UnsafeMutablePointer<UInt64>
    /// Key mode each held key was pressed in, so its release is handled the same way.
    private let keyPressMode: UnsafeMutablePointer<UInt8>
    /// Arp chord: notes the arpeggio cycles through (kept after release with Hold).
    private let chord: UnsafeMutablePointer<UInt8>
    /// Scratch list of arp notes for one step (up to 128 notes × 3 octaves).
    private let arpNotes: UnsafeMutablePointer<Int32>
    private var heldKeyCount = 0
    private var keyCounter: UInt64 = 0
    /// Key that sets the transposition (MIDI note), or -1 for none.
    private var transposeKey: Int32 = -1
    private var arpIndex = 0
    private var randomState: UInt32 = 0x2545_F491

    private let chorus: Chorus
    private let delay: StereoDelay
    private let reverb: Reverb

    private var noteCounter: UInt64 = 0
    private var lfoPhase: Float = 0
    private var pumpPhase: Float = 0
    private var limiterGain: Float = 1
    private let limiterRelease: Float

    // Waveform crossfades: a new waveform fades in over ~10 ms instead of switching mid-cycle.
    private var wave1 = Waveform.saw, previousWave1 = Waveform.saw, wave1Fade: Float = 1
    private var wave2 = Waveform.saw, previousWave2 = Waveform.saw, wave2Fade: Float = 1

    // Sequencer clock, counted in samples on this thread.
    private var isPlaying = false
    private var nextStep = 0
    /// Steps since Play; its parity decides swing for melody and drums alike.
    private var tick = 0
    private var samplesToNextStep: Double = 0
    private var samplesToNoteOff: Double = .infinity
    private var sequencerNote: Int32 = -1

    // Tracks on the master clock. A track switched on while playing waits ("armed") for step 1
    // of the next bar; switching off is immediate.
    private var sequencerActive = true
    private var sequencerArmed = false
    private var drumsActive = true
    private var drumsArmed = false
    /// Bank the sequencer plays; a new selection waits for the end of the pattern while playing.
    private var playingBank = 0
    /// Bank the drums play; a new selection waits for the end of the bar while playing.
    private var playingDrumBank = 0

    // External MIDI clock. When it is on, the same step code runs, but the moment of every
    // step comes from the filtered clock instead of the tempo knob.
    private let externalClock = ExternalClock()
    private let hostTicksToSeconds: Double
    /// The step grid follows the external clock.
    private var clockExternal = false
    /// Selected clock source; a change while playing applies at the next step boundary.
    private var clockExternalRequested = false
    /// User latency compensation (s), added to every step time.
    private var clockOffset = 0.0
    /// External tick index of step 0 of the running grid.
    private var gridOrigin: Int64 = 0
    private var hasGridOrigin = false
    /// What the transport waits for at the next accepted tick.
    private enum ClockWait { case none, start, resume, localStart, align }
    private var clockWait = ClockWait.none
    /// Ticks since the grid origin when the transport stopped (for Continue).
    private var stoppedTicks: Int64 = 0
    private var hasStoppedPosition = false
    /// Paused because the clock went quiet without a Stop.
    private var clockLost = false
    /// Place the next step exactly on the grid (after Start, Continue or a mode switch).
    private var clockHardSync = false
    /// While waiting for a tick, the next step is pushed this far away.
    private static var waitingSamples: Double { 1e9 }

    init(sampleRate: Double, queue: SynthEventQueue, midiQueue: SynthEventQueue? = nil, clockQueue: ClockEventQueue? = nil,
         monitor: SynthMonitor, initialValues: [Float], initialSteps: [Int], initialDrumSteps: [Bool]) {
        self.sampleRate = Float(sampleRate)
        self.queue = queue
        self.midiQueue = midiQueue
        self.clockQueue = clockQueue
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        hostTicksToSeconds = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        self.monitor = monitor

        let count = SynthParam.count
        params = .allocate(capacity: count)
        smoothed = .allocate(capacity: count)
        blockStart = .allocate(capacity: count)
        smoothFlags = .allocate(capacity: count)
        for param in SynthParam.allCases {
            let value = param.rawValue < initialValues.count ? initialValues[param.rawValue] : 0
            params[param.rawValue] = value
            smoothed[param.rawValue] = value
            blockStart[param.rawValue] = value
            smoothFlags[param.rawValue] = param.isSmoothed
        }
        wave1 = Waveform(rawValue: Int(params[SynthParam.osc1Wave.rawValue])) ?? .saw
        previousWave1 = wave1
        wave2 = Waveform(rawValue: Int(params[SynthParam.osc2Wave.rawValue])) ?? .saw
        previousWave2 = wave2

        let stepSlots = SynthPatch.bankCount * SynthPatch.stepCount
        steps = .allocate(capacity: stepSlots)
        for step in 0..<stepSlots {
            steps[step] = Int32(step < initialSteps.count ? initialSteps[step] : -1)
        }
        stagedSteps = .allocate(capacity: stepSlots)
        stagedSteps.initialize(repeating: -1, count: stepSlots)
        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        mono = .allocate(capacity: Self.controlBlock)
        drumBus = .allocate(capacity: Self.controlBlock)
        drumBus.initialize(repeating: 0, count: Self.controlBlock)
        drumBusRight = .allocate(capacity: Self.controlBlock)
        drumBusRight.initialize(repeating: 0, count: Self.controlBlock)
        drumCompAttack = 1 - exp(-1 / (0.003 * Float(sampleRate)))   // 3 ms
        drumCompRelease = 1 - exp(-1 / (0.1 * Float(sampleRate)))    // 100 ms
        let drumStepCount = SynthPatch.bankCount * DrumKind.count * SynthPatch.stepCount
        drumSteps = .allocate(capacity: drumStepCount)
        stagedDrumSteps = .allocate(capacity: drumStepCount)
        stagedDrumSteps.initialize(repeating: 0, count: drumStepCount)
        for i in 0..<drumStepCount {
            drumSteps[i] = i < initialDrumSteps.count && initialDrumSteps[i] ? 1 : 0
        }
        drumLevelStart = .allocate(capacity: DrumKind.count)
        drumLevelStart.initialize(repeating: 0, count: DrumKind.count)
        drumLevelStep = .allocate(capacity: DrumKind.count)
        drumLevelStep.initialize(repeating: 0, count: DrumKind.count)
        drums = DrumSynth(sampleRate: Float(sampleRate))
        heldKeys = .allocate(capacity: 128)
        heldKeys.initialize(repeating: 0, count: 128)
        keyPressMode = .allocate(capacity: 128)
        keyPressMode.initialize(repeating: 0, count: 128)
        chord = .allocate(capacity: 128)
        chord.initialize(repeating: 0, count: 128)
        arpNotes = .allocate(capacity: 128 * 3)
        arpNotes.initialize(repeating: 0, count: 128 * 3)
        mono.initialize(repeating: 0, count: Self.controlBlock)

        chorus = Chorus(sampleRate: self.sampleRate)
        delay = StereoDelay(sampleRate: self.sampleRate, maxSeconds: SynthParam.delayTime.range.upperBound + 0.1,
                            initialTime: params[SynthParam.delayTime.rawValue])
        reverb = Reverb(sampleRate: self.sampleRate)
        limiterRelease = 1 - exp(-1 / (0.15 * Float(sampleRate))) // ~150 ms recovery
    }

    deinit {
        params.deallocate()
        smoothed.deallocate()
        blockStart.deallocate()
        smoothFlags.deallocate()
        steps.deallocate()
        voices.deallocate()
        mono.deallocate()
        drumBus.deallocate()
        drumBusRight.deallocate()
        drumSteps.deallocate()
        stagedDrumSteps.deallocate()
        stagedSteps.deallocate()
        drumLevelStart.deallocate()
        drumLevelStep.deallocate()
        heldKeys.deallocate()
        keyPressMode.deallocate()
        chord.deallocate()
        arpNotes.deallocate()
    }

    // MARK: - Rendering

    /// Fills `left` and `right` with `frameCount` samples. Blocks are cut exactly at sequencer
    /// step and gate boundaries, so the rhythm is sample-accurate and never drifts.
    /// `hostTime` is the host time of the buffer's first sample (0 if unknown).
    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, hostTime: UInt64 = 0) {
        drainEvents()
        let bufferTime = Double(hostTime != 0 ? hostTime : mach_absolute_time()) * hostTicksToSeconds
        if clockExternal || clockExternalRequested {
            followExternalClock(frameCount: frameCount, bufferTime: bufferTime)
        } else if let clockQueue {
            while clockQueue.pop() != nil {} // internal clock: incoming clock is ignored
        }
        var frame = 0
        while frame < frameCount {
            if isPlaying {
                if samplesToNoteOff <= 0 {
                    releaseSequencerNote()
                }
                if samplesToNextStep <= 0, clockExternalRequested != clockExternal {
                    switchClockSource() // a source change takes effect on a step boundary
                }
                while samplesToNextStep <= 0 {
#if DEBUG
                    if clockExternal {
                        monitor.lastStepHostTime.store((bufferTime + Double(frame) / Double(sampleRate)).bitPattern, ordering: .relaxed)
                        monitor.lastStepIndex.store(tick, ordering: .relaxed)
                    }
#endif
                    advanceSequencer()
                }
            }
            var count = min(Self.controlBlock, frameCount - frame)
            if isPlaying {
                count = min(count, max(1, Int(samplesToNextStep.rounded(.up))))
                if samplesToNoteOff.isFinite {
                    count = min(count, max(1, Int(samplesToNoteOff.rounded(.up))))
                }
            }
            renderBlock(left: left + frame, right: right + frame, count: count)
            if isPlaying {
                samplesToNextStep -= Double(count)
                samplesToNoteOff -= Double(count)
            }
            frame += count
        }
    }

    private func renderBlock(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) {
        let sr = sampleRate
        let blockLength = Float(count)
        updateSmoothing(count: count)

        // MIDI pitch bend and mod wheel glide (~5 ms) so a jump from the controller never clicks.
        let midiGlide = 1 - exp(-blockLength / (0.005 * sr))
        bend += (bendTarget - bend) * midiGlide
        mod += (modTarget - mod) * midiGlide

        // LFO (sine) at control rate.
        let lfo = sin(2 * .pi * lfoPhase)
        lfoPhase += param(.lfoRate) * blockLength / sr
        if lfoPhase >= 1 { lfoPhase -= floor(lfoPhase) }
        var lfoAmount = smooth(.lfoAmount)
        if !modToCutoff { lfoAmount += (1 - lfoAmount) * mod } // mod wheel adds LFO depth
        let lfoToPitch = param(.lfoDestination) < 0.5
        let pitchModSemitones = lfoToPitch ? lfo * lfoAmount * 2 : 0  // up to ±2 semitones
        let cutoffModOctaves = lfoToPitch ? 0 : lfo * lfoAmount * 3   // up to ±3 octaves

        // Oscillators: waveform crossfades and pitch ratios.
        let fadeStep = blockLength / (0.01 * sr)
        let fadePerSample = fadeStep / blockLength
        let target1 = Waveform(rawValue: Int(param(.osc1Wave))) ?? .saw
        if target1 != wave1 { previousWave1 = wave1; wave1 = target1; wave1Fade = 0 }
        let fade1 = wave1Fade
        wave1Fade = min(1, wave1Fade + fadeStep)
        let target2 = Waveform(rawValue: Int(param(.osc2Wave))) ?? .saw
        if target2 != wave2 { previousWave2 = wave2; wave2 = target2; wave2Fade = 0 }
        let fade2 = wave2Fade
        wave2Fade = min(1, wave2Fade + fadeStep)

        let ratio1 = exp2((param(.osc1Octave) * 12 + smooth(.osc1Detune) / 100 + pitchModSemitones + bend) / 12)
        let ratio2 = exp2((param(.osc2Octave) * 12 + smooth(.osc2Detune) / 100 + pitchModSemitones + bend) / 12)
        let level1Start = rampStart(.osc1Level), level1Step = (smooth(.osc1Level) - level1Start) / blockLength
        let level2Start = rampStart(.osc2Level), level2Step = (smooth(.osc2Level) - level2Start) / blockLength

        // Envelope rates per sample.
        let ampAttack = 1 / max(param(.ampAttack) * sr, 1)
        let ampSustain = smooth(.ampSustain)
        let ampDecay = (1 - ampSustain) / max(param(.ampDecay) * sr, 1)
        let filterAttack = 1 / max(param(.filterAttack) * sr, 1)
        let filterSustain = smooth(.filterSustain)
        let filterDecay = (1 - filterSustain) / max(param(.filterDecay) * sr, 1)

        // Filter: k = 1/Q, from Q 0.5 (no resonance) up to Q 20 (singing).
        let baseCutoff = smooth(.cutoff) * (modToCutoff ? exp2(4 * mod) : 1) // mod wheel opens up to 4 octaves
        let envAmountOctaves = smooth(.filterEnvAmount) * 5
        let k = 2 - 1.95 * smooth(.resonance)
        let maxCutoff = sr * 0.45

        for i in 0..<count {
            mono[i] = 0
            drumBus[i] = 0
            drumBusRight[i] = 0
        }
        for drum in 0..<DrumKind.count {
            let level = SynthParam.kickLevel.rawValue + drum * 4
            drumLevelStart[drum] = blockStart[level]
            drumLevelStep[drum] = (smoothed[level] - blockStart[level]) / blockLength
        }
        drums.render(left: drumBus, right: drumBusRight, count: count, levelStart: drumLevelStart, levelStep: drumLevelStep)

        for v in 0..<Self.voiceCount where voices[v].isActive {
            var voice = voices[v]
            let frequency = 440 * exp2((Float(voice.note) - 69) / 12)
            let dt1 = min(frequency * ratio1 / sr, 0.5)
            let dt2 = min(frequency * ratio2 / sr, 0.5)

            let cutoff = min(max(baseCutoff * exp2(envAmountOctaves * voice.filterEnv.level + cutoffModOctaves), 20), maxCutoff)
            // Topology-preserving state-variable filter coefficients (stable under modulation).
            let g = tan(.pi * cutoff / sr)
            let a1 = 1 / (1 + g * (g + k))
            let a2 = g * a1
            let a3 = g * a2

            for i in 0..<count {
                let ramp = Float(i + 1)
                var osc1 = Self.oscillator(wave1, phase: voice.phase1, dt: dt1)
                if fade1 < 1 {
                    let f = min(1, fade1 + fadePerSample * ramp)
                    osc1 = osc1 * f + Self.oscillator(previousWave1, phase: voice.phase1, dt: dt1) * (1 - f)
                }
                var osc2 = Self.oscillator(wave2, phase: voice.phase2, dt: dt2)
                if fade2 < 1 {
                    let f = min(1, fade2 + fadePerSample * ramp)
                    osc2 = osc2 * f + Self.oscillator(previousWave2, phase: voice.phase2, dt: dt2) * (1 - f)
                }
                let osc = osc1 * (level1Start + level1Step * ramp) + osc2 * (level2Start + level2Step * ramp)
                voice.phase1 += dt1
                if voice.phase1 >= 1 { voice.phase1 -= 1 }
                voice.phase2 += dt2
                if voice.phase2 >= 1 { voice.phase2 -= 1 }

                let v3 = osc * 0.5 - voice.ic2
                let v1 = a1 * voice.ic1 + a2 * v3
                let v2 = voice.ic2 + a2 * voice.ic1 + a3 * v3
                voice.ic1 = 2 * v1 - voice.ic1
                voice.ic2 = 2 * v2 - voice.ic2

                _ = voice.filterEnv.next(attackStep: filterAttack, decayStep: filterDecay, sustain: filterSustain)
                let amp = voice.amp.next(attackStep: ampAttack, decayStep: ampDecay, sustain: ampSustain)
                mono[i] += v2 * amp * voice.velocity
            }
            voices[v] = voice
        }

        // Effects chain: Drive → Chorus → Delay → Reverb → Pump → master → limiter.
        let driveStart = rampStart(.driveAmount), driveStep = (smooth(.driveAmount) - driveStart) / blockLength
        let chorusStart = rampStart(.chorusMix), chorusStep = (smooth(.chorusMix) - chorusStart) / blockLength
        let delayMixStart = rampStart(.delayMix), delayMixStep = (smooth(.delayMix) - delayMixStart) / blockLength
        let reverbMixStart = rampStart(.reverbMix), reverbMixStep = (smooth(.reverbMix) - reverbMixStart) / blockLength
        let pumpStart = rampStart(.pumpAmount), pumpStep = (smooth(.pumpAmount) - pumpStart) / blockLength
        let masterStart = rampStart(.masterVolume), masterStep = (smooth(.masterVolume) - masterStart) / blockLength
        let chorusRate = param(.chorusRate)
        let delayTime = param(.delayTime)
        let delayFeedback = smooth(.delayFeedback)
        let reverbSize = smooth(.reverbSize)
        let pumpIncrement = Self.pumpBeats(Int(param(.pumpRate))) * param(.seqTempo) / 60 / sr
        let drumVolumeStart = rampStart(.drumVolume), drumVolumeStep = (smooth(.drumVolume) - drumVolumeStart) / blockLength
        let drumDelayStart = rampStart(.drumDelaySend), drumDelayStep = (smooth(.drumDelaySend) - drumDelayStart) / blockLength
        let drumReverbStart = rampStart(.drumReverbSend), drumReverbStep = (smooth(.drumReverbSend) - drumReverbStart) / blockLength
        let drumCompStart = rampStart(.drumComp), drumCompStep = (smooth(.drumComp) - drumCompStart) / blockLength
        let drumDriveStart = rampStart(.drumDrive), drumDriveStep = (smooth(.drumDrive) - drumDriveStart) / blockLength

        for i in 0..<count {
            let ramp = Float(i + 1)
            var x = mono[i] * 0.6 // leaves headroom for chords; the limiter catches the rest

            // Drive: soft saturation, crossfaded in so 0 is exactly clean.
            let drive = driveStart + driveStep * ramp
            if drive > 0.0001 {
                let gain = 1 + 15 * drive
                let shaped = tanh(x * gain) / sqrt(gain)
                x += (shaped - x) * drive
            }

            // Drum bus: gentle glue compression and saturation, its own volume, and sends.
            var drumLeft = drumBus[i] * 0.6
            var drumRight = drumBusRight[i] * 0.6
            let comp = drumCompStart + drumCompStep * ramp
            let level = max(abs(drumLeft), abs(drumRight))
            drumCompEnvelope += (level - drumCompEnvelope) * (level > drumCompEnvelope ? drumCompAttack : drumCompRelease)
            if comp > 0.0001 {
                // Threshold falls and ratio rises with the knob; a little make-up gain keeps the level.
                let threshold = 1 - 0.7 * comp
                let ratio = 1 + 3 * comp
                var gain: Float = 1
                if drumCompEnvelope > threshold {
                    gain = (threshold + (drumCompEnvelope - threshold) / ratio) / drumCompEnvelope
                }
                gain *= 1 + 0.5 * comp
                drumLeft *= gain
                drumRight *= gain
            }
            let saturation = drumDriveStart + drumDriveStep * ramp
            if saturation > 0.0001 {
                // Soft clipping, crossfaded in so 0 is exactly clean.
                let g = 1 + 6 * saturation
                drumLeft += (tanh(drumLeft * g) / tanh(g) - drumLeft) * saturation
                drumRight += (tanh(drumRight * g) / tanh(g) - drumRight) * saturation
            }
            let drumVolume = drumVolumeStart + drumVolumeStep * ramp
            drumLeft *= drumVolume
            drumRight *= drumVolume
            let drum = (drumLeft + drumRight) * 0.5

            var (l, r) = chorus.process(x, rate: chorusRate, mix: chorusStart + chorusStep * ramp)
            delay.process(&l, &r, time: delayTime, feedback: delayFeedback, mix: delayMixStart + delayMixStep * ramp,
                          send: drum * (drumDelayStart + drumDelayStep * ramp))
            reverb.process(&l, &r, size: reverbSize, mix: reverbMixStart + reverbMixStep * ramp,
                           send: drum * (drumReverbStart + drumReverbStep * ramp))

            // Pump: a quick dip at every beat division that swells back, like sidechain compression.
            pumpPhase += pumpIncrement
            if pumpPhase >= 1 { pumpPhase -= 1 }
            let pump = (pumpStart + pumpStep * ramp) * Self.pumpShape(pumpPhase)
            // The dry drums join after the pump, so the pump ducks the synth but not the kick.
            let master = masterStart + masterStep * ramp
            l = (l * (1 - pump) + drumLeft) * master
            r = (r * (1 - pump) + drumRight) * master

            if !l.isFinite { l = 0 }
            if !r.isFinite { r = 0 }
            // Peak limiter (linked stereo): gain drops instantly on a peak and recovers slowly,
            // so no sample ever exceeds the ceiling.
            let peak = max(abs(l), abs(r))
            let target = peak > Self.limiterCeiling ? Self.limiterCeiling / peak : 1
            if target < limiterGain {
                limiterGain = target
            } else {
                limiterGain += (target - limiterGain) * limiterRelease
            }
            left[i] = l * limiterGain
            right[i] = r * limiterGain
        }
    }

    /// Moves every smoothed parameter part of the way to its target (~20 ms time constant).
    private func updateSmoothing(count: Int) {
        let coefficient = 1 - exp(-Float(count) / (0.02 * sampleRate))
        for p in 0..<SynthParam.count {
            blockStart[p] = smoothed[p]
            if smoothFlags[p] {
                smoothed[p] += (params[p] - smoothed[p]) * coefficient
            } else {
                smoothed[p] = params[p]
            }
        }
    }

    /// Duck depth over one pump cycle: drops in ~2% of the cycle, then swells back.
    @inline(__always)
    static func pumpShape(_ phase: Float) -> Float {
        let attack: Float = 0.02
        if phase < attack { return phase / attack }
        let recovery = 1 - (phase - attack) / (1 - attack)
        return recovery * recovery
    }

    /// Pump cycles per beat for each `pumpRate` setting (1/2, 1/4, 1/8, 1/16).
    @inline(__always)
    static func pumpBeats(_ index: Int) -> Float {
        switch index {
        case 0: 0.5
        case 2: 2
        case 3: 4
        default: 1
        }
    }

    /// One oscillator sample at `phase` (0..<1). Saw and square use PolyBLEP to round off
    /// their jumps, which removes most of the harsh aliasing at high notes.
    @inline(__always)
    static func oscillator(_ wave: Waveform, phase t: Float, dt: Float) -> Float {
        switch wave {
        case .sine:
            return sin(2 * .pi * t)
        case .saw:
            return 2 * t - 1 - polyBLEP(t, dt)
        case .square:
            var t2 = t + 0.5
            if t2 >= 1 { t2 -= 1 }
            return (t < 0.5 ? 1 : -1) + polyBLEP(t, dt) - polyBLEP(t2, dt)
        case .triangle:
            // Its harmonics fall off fast, so the naive shape aliases very little.
            return 4 * abs(t - 0.5) - 1
        }
    }

    /// Polynomial band-limited step correction around a discontinuity at phase 0.
    @inline(__always)
    static func polyBLEP(_ t: Float, _ dt: Float) -> Float {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    @inline(__always) private func param(_ p: SynthParam) -> Float { params[p.rawValue] }
    @inline(__always) private func smooth(_ p: SynthParam) -> Float { smoothed[p.rawValue] }
    @inline(__always) private func rampStart(_ p: SynthParam) -> Float { blockStart[p.rawValue] }

    // MARK: - Sequencer

    private var sequenceLength: Int {
        min(max(Int(param(.seqLength)), 1), SynthPatch.stepCount)
    }

    /// Length of step `index` in samples. Swing lengthens even steps and shortens odd ones,
    /// which pushes every second sixteenth later.
    private func stepDuration(_ tick: Int) -> Double {
        let sixteenth = clockExternal && externalClock.hasPeriod
            ? 6 * externalClock.period * Double(sampleRate)
            : 60 / Double(max(param(.seqTempo), 20)) / 4 * Double(sampleRate)
        let swing = Double(param(.seqSwing))
        return tick % 2 == 0 ? sixteenth * (1 + swing) : sixteenth * (1 - swing)
    }

    /// One tick of the master clock: both tracks read the same step, so they never drift apart.
    private func advanceSequencer() {
        // A pattern preset takes over at the start of a bar, before this step's length is known.
        if tick % SynthPatch.stepCount == 0 { applyStagedPattern() }
        let duration = stepDuration(tick)
        let clockStep = tick % SynthPatch.stepCount
        monitor.clockStep.store(clockStep, ordering: .relaxed)

        // Armed tracks join on step 1 of the bar.
        if clockStep == 0 {
            if sequencerArmed {
                sequencerArmed = false
                sequencerActive = true
                nextStep = 0
                monitor.sequencerArmed.store(0, ordering: .relaxed)
            }
            if drumsArmed {
                drumsArmed = false
                drumsActive = true
                monitor.drumsArmed.store(0, ordering: .relaxed)
            }
        }

        releaseSequencerNote()
        if sequencerActive {
            if nextStep >= sequenceLength { nextStep = 0 }
            // A newly selected bank takes over when the pattern starts again.
            if nextStep == 0 { applyBank() }
            let step = nextStep
            monitor.currentStep.store(step, ordering: .relaxed)
            let note = keyModeNote(forStep: steps[playingBank * SynthPatch.stepCount + step])
            monitor.lastSequencerNote.store(Int(note), ordering: .relaxed)
            if note >= 0 {
                noteOn(note, velocity: 0.85, fromSequencer: true)
                sequencerNote = note
                samplesToNoteOff = samplesToNextStep + duration * Self.gateLength
            }
            nextStep = step + 1 >= sequenceLength ? 0 : step + 1
        } else {
            monitor.currentStep.store(-1, ordering: .relaxed)
            applyBank() // nothing is playing on this track, so a new bank applies at once
        }
        samplesToNextStep += duration
        triggerDrums(clockStep)
        tick += 1
    }

    /// Fires every drum with a hit on the master clock's step.
    private func triggerDrums(_ step: Int) {
        guard drumsActive else {
            monitor.currentDrumStep.store(-1, ordering: .relaxed)
            // Nothing is playing on this track, so new banks apply at once.
            applyStagedDrumSteps()
            applyDrumBank()
            return
        }
        // New drum banks from a preset, and a newly selected bank, take over on step 1 of the next bar.
        if step == 0 {
            applyStagedDrumSteps()
            applyDrumBank()
        }
        monitor.currentDrumStep.store(step, ordering: .relaxed)
        let bankBase = playingDrumBank * DrumKind.count * SynthPatch.stepCount
        for drum in 0..<DrumKind.count where drumSteps[bankBase + drum * SynthPatch.stepCount + step] != 0 {
            let base = SynthParam.kickLevel.rawValue + drum * 4
            guard params[base + 3] < 0.5 else { continue } // muted
            drums.trigger(drum, variant: Int(params[SynthParam.kickVariant.rawValue + drum]), tune: params[base + 1], decay: params[base + 2])
        }
    }

    private func applyBank() {
        let selected = min(max(Int(param(.seqBank)), 0), SynthPatch.bankCount - 1)
        if selected != playingBank {
            playingBank = selected
            monitor.playingBank.store(selected, ordering: .relaxed)
        }
    }

    /// Copies staged sequencer banks and tempo (and the staged drums) over the playing ones.
    private func applyStagedPattern() {
        guard patternSwapPending else { return }
        patternSwapPending = false
        steps.update(from: stagedSteps, count: SynthPatch.bankCount * SynthPatch.stepCount)
        params[SynthParam.seqTempo.rawValue] = stagedTempo
        applyStagedDrumSteps()
    }

    /// Copies staged drum banks over the playing ones (fixed-size copy, no allocation).
    private func applyStagedDrumSteps() {
        guard drumSwapPending else { return }
        drumSwapPending = false
        drumSteps.update(from: stagedDrumSteps, count: SynthPatch.bankCount * DrumKind.count * SynthPatch.stepCount)
    }

    private func applyDrumBank() {
        let selected = min(max(Int(param(.drumBank)), 0), SynthPatch.bankCount - 1)
        if selected != playingDrumBank {
            playingDrumBank = selected
            monitor.playingDrumBank.store(selected, ordering: .relaxed)
        }
    }

    /// Follows the on/off switches and the bank selection after new parameter values arrive.
    private func updateTracks() {
        let sequencerOn = param(.seqEnabled) >= 0.5
        if !sequencerOn, sequencerActive || sequencerArmed {
            sequencerActive = false
            sequencerArmed = false
            monitor.sequencerArmed.store(0, ordering: .relaxed)
            monitor.currentStep.store(-1, ordering: .relaxed)
            silenceSequencer()
        } else if sequencerOn, !sequencerActive, !sequencerArmed {
            if isPlaying {
                sequencerArmed = true
                monitor.sequencerArmed.store(1, ordering: .relaxed)
            } else {
                sequencerActive = true
            }
        }

        let drumsOn = param(.drumsEnabled) >= 0.5
        if !drumsOn, drumsActive || drumsArmed {
            drumsActive = false
            drumsArmed = false
            monitor.drumsArmed.store(0, ordering: .relaxed)
            monitor.currentDrumStep.store(-1, ordering: .relaxed)
            drums.fadeOutAll()
        } else if drumsOn, !drumsActive, !drumsArmed {
            if isPlaying {
                drumsArmed = true
                monitor.drumsArmed.store(1, ordering: .relaxed)
            } else {
                drumsActive = true
            }
        }

        if !isPlaying || !sequencerActive { applyBank() }
        if !isPlaying || !drumsActive {
            applyStagedDrumSteps()
            applyDrumBank()
        }
    }

    /// Fades out every note the sequencer started, over ~15 ms (no click, no long tail).
    private func silenceSequencer() {
        sequencerNote = -1
        samplesToNoteOff = .infinity
        let fade = 0.015 * sampleRate
        for v in 0..<Self.voiceCount where voices[v].isActive && voices[v].fromSequencer {
            voices[v].gate = false
            voices[v].amp.gateOff(releaseSamples: fade)
            voices[v].filterEnv.gateOff(releaseSamples: fade)
        }
    }

    /// Starts the transport from the first step (melody and drums together).
    private func startTransport() {
        releaseSequencerNote()
        isPlaying = true
        nextStep = 0
        tick = 0
        // Both tracks start together on step 1 if they are switched on.
        sequencerActive = param(.seqEnabled) >= 0.5
        drumsActive = param(.drumsEnabled) >= 0.5
        sequencerArmed = false
        drumsArmed = false
        monitor.sequencerArmed.store(0, ordering: .relaxed)
        monitor.drumsArmed.store(0, ordering: .relaxed)
        applyStagedPattern()
        applyBank()
        applyStagedDrumSteps()
        applyDrumBank()
        arpIndex = 0
        samplesToNextStep = 0
        pumpPhase = 0
    }

    private func stopTransport() {
        releaseSequencerNote()
        isPlaying = false
        sequencerActive = param(.seqEnabled) >= 0.5
        drumsActive = param(.drumsEnabled) >= 0.5
        sequencerArmed = false
        drumsArmed = false
        monitor.sequencerArmed.store(0, ordering: .relaxed)
        monitor.drumsArmed.store(0, ordering: .relaxed)
        monitor.currentStep.store(-1, ordering: .relaxed)
        monitor.currentDrumStep.store(-1, ordering: .relaxed)
        monitor.clockStep.store(-1, ordering: .relaxed)
        applyStagedPattern()
        applyBank()
        applyStagedDrumSteps()
        applyDrumBank()
    }

    // MARK: - External MIDI clock

    /// Reads the clock events of this buffer, runs the transport commands, notices a lost
    /// clock, and steers the next step onto the external grid.
    private func followExternalClock(frameCount: Int, bufferTime: Double) {
        if let clockQueue {
            while let event = clockQueue.pop() {
                let time = Double(event.hostTime) * hostTicksToSeconds
                switch event.kind {
                case .tick:
                    guard externalClock.tick(at: time, source: event.source) > 0 else { continue }
                    clockLost = false // receiving again; a paused transport waits for Continue or Play
                    if clockExternal { resolveClockWait() }
                case .start:
                    guard clockExternal, externalClock.follows(event.source, at: time) else { continue }
                    if isPlaying { stopForExternalClock(keepPosition: false) }
                    hasStoppedPosition = false
                    clockWait = .start
                case .continue:
                    guard clockExternal, externalClock.follows(event.source, at: time) else { continue }
                    if !isPlaying { clockWait = hasStoppedPosition ? .resume : .start }
                case .stop:
                    guard clockExternal, externalClock.follows(event.source, at: time) else { continue }
                    clockWait = .none
                    if isPlaying { stopForExternalClock(keepPosition: true) }
                }
            }
        }

        let receiving = externalClock.hasPeriod && bufferTime - externalClock.lastTickTime < 1
        if clockExternal, isPlaying, !receiving {
            // Ticks stopped for over a second without a Stop: pause and keep the position.
            clockLost = true
            stopForExternalClock(keepPosition: true)
        }
        monitor.clockStatus.store(!clockExternal ? 0 : (receiving ? 2 : (clockLost ? 3 : 1)), ordering: .relaxed)
        monitor.clockTempo.store(receiving ? Int((externalClock.tempo * 100).rounded()) : 0, ordering: .relaxed)
        monitor.clockTransport.store(isPlaying || clockWait != .none ? 1 : 0, ordering: .relaxed)

        guard clockExternal, isPlaying, clockWait == .none, hasGridOrigin, externalClock.hasPeriod else { return }
        let rate = Double(sampleRate)
        let stepSeconds = 6 * externalClock.period
        var desired = (externalStepTime(tick) - bufferTime) * rate
        if desired < -0.5 * stepSeconds * rate {
            // Behind the grid by over half a step (a tempo jump or missing ticks): skip to the
            // next step boundary instead of rushing through the missed steps.
            let behind = Int((bufferTime - externalStepTime(tick)) / stepSeconds) + 1
            skipSteps(behind)
            desired = (externalStepTime(tick) - bufferTime) * rate
        }
        let error = desired - samplesToNextStep
        if clockHardSync || abs(error) > stepSeconds * rate {
            samplesToNextStep = max(desired, 0)
            clockHardSync = false
        } else {
            // Small corrections are spread out: at most 5% of the buffer per buffer.
            let slew = 0.05 * Double(frameCount)
            samplesToNextStep += min(max(error, -slew), slew)
        }
    }

    /// When step `step` of the running grid should sound (host seconds), swing included.
    private func externalStepTime(_ step: Int) -> Double {
        var time = externalClock.time(ofTick: gridOrigin + 6 * Int64(step)) + clockOffset
        if step % 2 == 1 { time += Double(param(.seqSwing)) * 6 * externalClock.period }
        return time
    }

    /// Runs what was waiting for the clock, on the tick just accepted.
    private func resolveClockWait() {
        let index = externalClock.lastIndex
        switch clockWait {
        case .none:
            return
        case .start:
            gridOrigin = index
            hasGridOrigin = true
            startTransport()
        case .resume:
            gridOrigin = index - stoppedTicks
            hasGridOrigin = true
            resumeTransport()
        case .localStart:
            // Play keeps the phase of a grid the clock already set up: start on its next step.
            if hasGridOrigin, (index - gridOrigin) % 6 != 0 { return }
            gridOrigin = index
            hasGridOrigin = true
            startTransport()
        case .align:
            // Switched to the external clock while playing: the position carries on, and the
            // next step lands on the next step boundary of a grid the clock set up before.
            if hasGridOrigin, (index - gridOrigin) % 6 != 0 { return }
            gridOrigin = index - 6 * Int64(tick)
            hasGridOrigin = true
        }
        clockWait = .none
        clockHardSync = true
    }

    /// Changes between the internal and external clock (at a step boundary while playing).
    private func switchClockSource() {
        clockExternal = clockExternalRequested
        clockLost = false
        if clockExternal {
            if isPlaying {
                clockWait = .align // keep the position, continue on the next incoming tick
                samplesToNextStep = Self.waitingSamples
            }
        } else {
            clockWait = .none
            if samplesToNextStep >= Self.waitingSamples { samplesToNextStep = 0 }
            monitor.clockStatus.store(0, ordering: .relaxed)
            monitor.clockTempo.store(0, ordering: .relaxed)
            monitor.clockTransport.store(0, ordering: .relaxed)
        }
    }

    /// Stops sequencer and drums at once (external Stop, local Stop or lost clock); nothing
    /// keeps sounding. With `keepPosition`, Continue picks up where it stopped.
    private func stopForExternalClock(keepPosition: Bool) {
        if keepPosition, hasGridOrigin {
            stoppedTicks = max(0, externalClock.lastIndex - gridOrigin + 1)
            hasStoppedPosition = true
        } else {
            hasStoppedPosition = false
        }
        stopTransport()
        silenceSequencer()
        drums.fadeOutAll()
    }

    /// Like `startTransport`, but from where the transport stopped.
    private func resumeTransport() {
        releaseSequencerNote()
        isPlaying = true
        sequencerActive = param(.seqEnabled) >= 0.5
        drumsActive = param(.drumsEnabled) >= 0.5
        sequencerArmed = false
        drumsArmed = false
        monitor.sequencerArmed.store(0, ordering: .relaxed)
        monitor.drumsArmed.store(0, ordering: .relaxed)
        samplesToNextStep = 0
    }

    /// Moves the position on by `count` steps without playing them.
    private func skipSteps(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            tick += 1
            nextStep = nextStep + 1 >= sequenceLength ? 0 : nextStep + 1
        }
    }

    // MARK: - Key mode

    private var keyMode: Int { Int(param(.keyMode)) }
    private var holdOn: Bool { param(.keyHold) >= 0.5 }

    private func keyDown(_ note: Int32, velocity: Float) {
        guard note >= 0, note < 128 else { return }
        // With the sequencer switched off, keys just play the synth.
        let mode = param(.seqEnabled) >= 0.5 ? keyMode : KeyMode.off.rawValue
        let n = Int(note)
        let wasIdle = heldKeyCount == 0
        if heldKeys[n] == 0 { heldKeyCount += 1 }
        keyCounter &+= 1
        heldKeys[n] = keyCounter
        keyPressMode[n] = UInt8(mode)

        switch mode {
        case KeyMode.transpose.rawValue:
            // Every press sets the transposition and restarts the pattern from step 1.
            transposeKey = note
            if clockExternal {
                if !isPlaying { clockWait = .localStart } // starts in step with the external clock
            } else {
                startTransport()
            }
        case KeyMode.arp.rawValue:
            // A fresh press (no keys held) starts a new chord, replacing a held one.
            if wasIdle {
                for i in 0..<128 { chord[i] = 0 }
            }
            chord[n] = 1
            if wasIdle {
                if clockExternal {
                    if !isPlaying { clockWait = .localStart }
                } else {
                    startTransport()
                }
            }
        default:
            noteOn(note, velocity: velocity)
        }
    }

    private func keyUp(_ note: Int32) {
        guard note >= 0, note < 128 else { return }
        let n = Int(note)
        guard heldKeys[n] != 0 else { return }
        heldKeys[n] = 0
        heldKeyCount -= 1

        switch Int(keyPressMode[n]) {
        case KeyMode.transpose.rawValue:
            if heldKeyCount > 0 {
                // Fall back to the most recently pressed key that is still held.
                var latest: UInt64 = 0
                for i in 0..<128 where heldKeys[i] > latest && Int(keyPressMode[i]) == KeyMode.transpose.rawValue {
                    latest = heldKeys[i]
                    transposeKey = Int32(i)
                }
            } else if !holdOn {
                stopTransport()
            }
        case KeyMode.arp.rawValue:
            if !holdOn {
                chord[n] = 0
                if heldKeyCount == 0 { stopTransport() }
            }
        default:
            playerNoteOff(note)
        }
    }

    /// The note a pattern step plays in the current key mode, or -1 for a rest.
    private func keyModeNote(forStep stepNote: Int32) -> Int32 {
        guard stepNote >= 0 else { return -1 }
        switch keyMode {
        case KeyMode.transpose.rawValue:
            guard transposeKey >= 0 else { return stepNote }
            return min(max(stepNote + transposeKey - 60, 0), 127)
        case KeyMode.arp.rawValue:
            return nextArpNote()
        default:
            return stepNote
        }
    }

    /// Next note of the arpeggio over the chord, spread across the octave range.
    private func nextArpNote() -> Int32 {
        let octaves = min(max(Int(param(.arpOctaves)), 1), 3)
        var count = 0
        for octave in 0..<octaves {
            for note in 0..<128 where chord[note] != 0 {
                let shifted = note + 12 * octave
                if shifted < 128 {
                    arpNotes[count] = Int32(shifted)
                    count += 1
                }
            }
        }
        guard count > 0 else { return -1 }
        // Ascending order across octaves (a wide chord's copies interleave). In-place insertion sort.
        if count > 1 {
            for i in 1..<count {
                let value = arpNotes[i]
                var j = i - 1
                while j >= 0 && arpNotes[j] > value {
                    arpNotes[j + 1] = arpNotes[j]
                    j -= 1
                }
                arpNotes[j + 1] = value
            }
        }
        let index: Int
        switch Int(param(.arpDirection)) {
        case ArpDirection.down.rawValue:
            index = count - 1 - arpIndex % count
        case ArpDirection.upDown.rawValue:
            let period = max(1, 2 * count - 2)
            let position = arpIndex % period
            index = position < count ? position : period - position
        case ArpDirection.random.rawValue:
            randomState ^= randomState << 13
            randomState ^= randomState >> 17
            randomState ^= randomState << 5
            index = Int(randomState % UInt32(count))
        default:
            index = arpIndex % count
        }
        arpIndex += 1
        return arpNotes[index]
    }

    private func releaseSequencerNote() {
        if sequencerNote >= 0 {
            noteOff(sequencerNote)
            sequencerNote = -1
        }
        samplesToNoteOff = .infinity
    }

    // MARK: - Events

    private func drainEvents() {
        defer { updateTracks() }
        while let event = queue.pop() {
            handle(event)
        }
        if let midiQueue {
            while let event = midiQueue.pop() {
                handle(event)
            }
        }
    }

    private func handle(_ event: SynthEvent) {
            switch event.kind {
            case .parameter:
                if event.index >= 0, Int(event.index) < SynthParam.count {
                    params[Int(event.index)] = event.value
                }
            case .noteOn:
                noteOn(event.index, velocity: event.value)
            case .noteOff:
                playerNoteOff(event.index)
            case .midi:
                switch MIDIControl(rawValue: event.index) {
                case .pitchBend: bendTarget = event.value
                case .modWheel: modTarget = min(max(event.value, 0), 1)
                case .modDestination: modToCutoff = event.value >= 0.5
                case .sustain:
                    sustainDown = event.value >= 0.5
                    if !sustainDown {
                        for v in 0..<Self.voiceCount where voices[v].sustained {
                            voices[v].sustained = false
                            release(v)
                        }
                    }
                case nil: break
                }
            case .allNotesOff:
                for v in 0..<Self.voiceCount where voices[v].gate {
                    voices[v].sustained = false
                    release(v)
                }
                // A controller may have gone away mid-gesture: centre the bend, drop the pedal.
                sustainDown = false
                bendTarget = 0
                modTarget = 0
                sequencerNote = -1
                // Forget held keys (the app went to the background, or a controller was unplugged
                // mid-press). A pattern those keys were driving stops too, as on a normal release.
                let keysDroveSequencer = heldKeyCount > 0 && keyMode != KeyMode.off.rawValue
                    && param(.seqEnabled) >= 0.5 && !holdOn
                for note in 0..<128 { heldKeys[note] = 0 }
                heldKeyCount = 0
                if keysDroveSequencer { stopTransport() }
            case .drumPreview:
                // One hit of the drum's current sound, even if the drum is muted.
                let drum = Int(event.index)
                if drum >= 0, drum < DrumKind.count {
                    let base = SynthParam.kickLevel.rawValue + drum * 4
                    drums.trigger(drum, variant: Int(params[SynthParam.kickVariant.rawValue + drum]),
                                  tune: params[base + 1], decay: params[base + 2])
                }
            case .drumStep:
                if event.index >= 0, Int(event.index) < SynthPatch.bankCount * DrumKind.count * SynthPatch.stepCount {
                    let on: UInt8 = event.value >= 0.5 ? 1 : 0
                    drumSteps[Int(event.index)] = on
                    // An edit made while a swap waits must survive the swap.
                    if drumSwapPending { stagedDrumSteps[Int(event.index)] = on }
                }
            case .stagedDrumStep:
                if event.index >= 0, Int(event.index) < SynthPatch.bankCount * DrumKind.count * SynthPatch.stepCount {
                    stagedDrumSteps[Int(event.index)] = event.value >= 0.5 ? 1 : 0
                }
            case .commitDrumSteps:
                drumSwapPending = true
                // Nothing playing on the drum track: swap now (and pick up the new bank with it).
                if !isPlaying || !drumsActive {
                    applyStagedDrumSteps()
                    applyDrumBank()
                }
            case .stepNote:
                if event.index >= 0, Int(event.index) < SynthPatch.bankCount * SynthPatch.stepCount {
                    steps[Int(event.index)] = Int32(event.value)
                    // An edit made while a pattern swap waits must survive the swap.
                    if patternSwapPending { stagedSteps[Int(event.index)] = Int32(event.value) }
                }
            case .stagedStepNote:
                if event.index >= 0, Int(event.index) < SynthPatch.bankCount * SynthPatch.stepCount {
                    stagedSteps[Int(event.index)] = Int32(event.value)
                }
            case .commitPattern:
                // value = tempo; index 1 = staged drums come along.
                patternSwapPending = true
                stagedTempo = min(max(event.value, SynthParam.seqTempo.range.lowerBound), SynthParam.seqTempo.range.upperBound)
                if event.index == 1 { drumSwapPending = true }
                if !isPlaying {
                    applyStagedPattern()
                    applyBank()
                    applyDrumBank()
                }
            case .play:
                if clockExternal {
                    if !isPlaying { clockWait = .localStart } // starts on the next step of the clock
                } else {
                    startTransport()
                }
            case .stop:
                if clockExternal {
                    clockWait = .none
                    if isPlaying { stopForExternalClock(keepPosition: false) }
                } else {
                    stopTransport()
                }
            case .clockMode:
                clockExternalRequested = event.index == 1
                clockOffset = Double(event.value) / 1000
                if !isPlaying, clockExternalRequested != clockExternal {
                    switchClockSource()
                }
            case .keyDown:
                keyDown(event.index, velocity: event.value)
            case .keyUp:
                keyUp(event.index)
            }
    }

    private func noteOn(_ note: Int32, velocity: Float, fromSequencer: Bool = false) {
        // Same note already sounding → retrigger it; else a free voice; else steal the oldest,
        // preferring voices that are already fading out.
        var chosen = -1
        for v in 0..<Self.voiceCount where voices[v].isActive && voices[v].note == note {
            chosen = v
            break
        }
        if chosen < 0 {
            for v in 0..<Self.voiceCount where !voices[v].isActive {
                chosen = v
                break
            }
        }
        if chosen < 0 {
            var oldest = UInt64.max
            var oldestReleasing = UInt64.max
            var releasing = -1
            for v in 0..<Self.voiceCount {
                let order = voices[v].startOrder
                if !voices[v].gate, order < oldestReleasing {
                    oldestReleasing = order
                    releasing = v
                }
                if order < oldest {
                    oldest = order
                    chosen = v
                }
            }
            if releasing >= 0 { chosen = releasing }
        }

        if !voices[chosen].isActive {
            voices[chosen].ic1 = 0
            voices[chosen].ic2 = 0
        }
        noteCounter &+= 1
        voices[chosen].note = note
        voices[chosen].velocity = velocity
        voices[chosen].gate = true
        voices[chosen].startOrder = noteCounter
        voices[chosen].fromSequencer = fromSequencer
        voices[chosen].sustained = false
        voices[chosen].amp.gateOn()
        voices[chosen].filterEnv.gateOn()
    }

    /// Key released by a player (screen or MIDI): held on while the sustain pedal is down.
    private func playerNoteOff(_ note: Int32) {
        for v in 0..<Self.voiceCount where voices[v].gate && voices[v].note == note && !voices[v].fromSequencer {
            if sustainDown {
                voices[v].sustained = true
            } else {
                release(v)
            }
        }
    }

    private func noteOff(_ note: Int32) {
        for v in 0..<Self.voiceCount where voices[v].gate && voices[v].note == note {
            release(v)
        }
    }

    private func release(_ v: Int) {
        voices[v].gate = false
        voices[v].amp.gateOff(releaseSamples: param(.ampRelease) * sampleRate)
        voices[v].filterEnv.gateOff(releaseSamples: param(.filterRelease) * sampleRate)
    }
}

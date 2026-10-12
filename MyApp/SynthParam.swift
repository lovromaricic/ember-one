import Foundation

nonisolated enum Waveform: Int, CaseIterable, Codable {
    case sine, saw, square, triangle

    /// Unknown values (e.g. a waveform added in a later version) fall back to saw.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = Waveform(rawValue: raw) ?? .saw
    }
}

/// How the keyboard drives the sequencer.
nonisolated enum KeyMode: Int, CaseIterable, Codable {
    /// Keys play notes (and write into a selected step) — the sequencer runs on its own.
    case off
    /// Holding a key plays the pattern shifted so that C4 maps to the key.
    case transpose
    /// Held keys form a chord that the pattern's note steps step through.
    case arp

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = KeyMode(rawValue: raw) ?? .off
    }
}

nonisolated enum ArpDirection: Int, CaseIterable, Codable {
    case up, down, upDown, random

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = ArpDirection(rawValue: raw) ?? .up
    }
}

/// The five drums of the rhythm machine, in row order.
nonisolated enum DrumKind: Int, CaseIterable, Codable {
    case kick, snare, clap, closedHat, openHat

    static var count: Int { 5 }
}

nonisolated enum LFODestination: Int, CaseIterable, Codable {
    case pitch, cutoff

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = LFODestination(rawValue: raw) ?? .pitch
    }
}

/// Every continuous sound setting the audio thread knows about. The raw value indexes the
/// parameter arrays on both threads; the values themselves live in `SynthPatch`.
/// This type only describes ranges and units for knobs and the DSP.
nonisolated enum SynthParam: Int, CaseIterable {
    case osc1Wave, osc1Level, osc1Octave, osc1Detune
    case osc2Wave, osc2Level, osc2Octave, osc2Detune
    case cutoff, resonance, filterEnvAmount
    case ampAttack, ampDecay, ampSustain, ampRelease
    case filterAttack, filterDecay, filterSustain, filterRelease
    case lfoDestination, lfoRate, lfoAmount
    case masterVolume
    case delayTime, delayFeedback, delayMix
    case reverbSize, reverbMix
    case chorusRate, chorusMix
    case driveAmount
    case pumpAmount, pumpRate
    case seqTempo, seqSwing, seqLength
    // Drums: level, tune, decay and mute for each drum, then the drum bus.
    case kickLevel, kickTune, kickDecay, kickMute
    case snareLevel, snareTune, snareDecay, snareMute
    case clapLevel, clapTune, clapDecay, clapMute
    case closedHatLevel, closedHatTune, closedHatDecay, closedHatMute
    case openHatLevel, openHatTune, openHatDecay, openHatMute
    case drumVolume, drumReverbSend, drumDelaySend
    // Key mode: how the keyboard drives the sequencer.
    case keyMode, arpDirection, arpOctaves, keyHold
    // Drum sound variant per drum, then the drum bus compressor and saturator.
    case kickVariant, snareVariant, clapVariant, closedHatVariant, openHatVariant
    case drumComp, drumDrive
    // Tracks on the master clock, and the sequencer bank (A...H) selected for playing.
    case seqEnabled, drumsEnabled, seqBank
    // Drum bank (A...H) selected for playing.
    case drumBank

    enum Unit { case percent, bipolarPercent, octave, cents, hertz, seconds, choice, bpm, steps, division, semitones }

    /// Number of parameters. Computed rather than `allCases.count`, which builds an array.
    static var count: Int { drumBank.rawValue + 1 }

    /// The four parameters of one drum: level, tune, decay, mute (in that order from `drumBase`).
    static func drumBase(_ drum: DrumKind) -> Int { kickLevel.rawValue + drum.rawValue * 4 }
    static func drumLevel(_ drum: DrumKind) -> SynthParam { SynthParam(rawValue: drumBase(drum))! }
    static func drumTune(_ drum: DrumKind) -> SynthParam { SynthParam(rawValue: drumBase(drum) + 1)! }
    static func drumDecay(_ drum: DrumKind) -> SynthParam { SynthParam(rawValue: drumBase(drum) + 2)! }
    static func drumMute(_ drum: DrumKind) -> SynthParam { SynthParam(rawValue: drumBase(drum) + 3)! }
    static func drumVariant(_ drum: DrumKind) -> SynthParam { SynthParam(rawValue: kickVariant.rawValue + drum.rawValue)! }

    /// Parameters of the drum machine (stored in `DrumKit`, not in presets).
    var isDrumParam: Bool {
        switch self {
        case .drumVolume, .drumReverbSend, .drumDelaySend, .drumsEnabled, .drumComp, .drumDrive, .drumBank,
             .kickVariant, .snareVariant, .clapVariant, .closedHatVariant, .openHatVariant: true
        default: drum != nil
        }
    }

    /// Which drum a drum parameter belongs to, if any.
    var drum: DrumKind? {
        guard rawValue >= SynthParam.kickLevel.rawValue, rawValue <= SynthParam.openHatMute.rawValue else { return nil }
        return DrumKind(rawValue: (rawValue - SynthParam.kickLevel.rawValue) / 4)
    }

    /// Pump speeds, as fractions of a whole note, indexed by the `pumpRate` value.
    static let pumpDivisions: [(label: String, perBeat: Float)] = [("1/2", 0.5), ("1/4", 1), ("1/8", 2), ("1/16", 4)]

    var range: ClosedRange<Float> {
        switch self {
        case .osc1Wave, .osc2Wave: 0...3
        case .osc1Octave, .osc2Octave: -2...2
        case .osc1Detune, .osc2Detune: -50...50
        case .cutoff: 20...20_000
        case .filterEnvAmount: -1...1
        case .ampAttack, .ampDecay, .filterAttack, .filterDecay: 0.001...5
        case .ampRelease, .filterRelease: 0.001...8
        case .lfoDestination: 0...1
        case .lfoRate: 0.05...20
        case .delayTime: 0.02...1.5
        case .delayFeedback: 0...0.9
        case .chorusRate: 0.1...5
        case .pumpRate: 0...3
        case .seqTempo: 60...200
        case .seqSwing: 0...0.6
        case .seqLength: 4...16
        case .kickTune, .snareTune, .clapTune, .closedHatTune, .openHatTune: -12...12
        case .kickDecay: 0.05...1.5
        case .snareDecay, .clapDecay: 0.05...1
        case .closedHatDecay: 0.01...0.3
        case .openHatDecay: 0.05...1.5
        case .keyMode: 0...2
        case .kickVariant, .snareVariant, .clapVariant, .closedHatVariant, .openHatVariant: 0...4
        case .seqBank, .drumBank: 0...7
        case .arpDirection: 0...3
        case .arpOctaves: 1...3
        default: 0...1
        }
    }

    /// Frequencies and times feel natural on a logarithmic knob.
    var isLogarithmic: Bool {
        switch self {
        case .cutoff, .lfoRate, .ampAttack, .ampDecay, .ampRelease, .filterAttack, .filterDecay, .filterRelease,
             .delayTime, .chorusRate, .kickDecay, .snareDecay, .clapDecay, .closedHatDecay, .openHatDecay: true
        default: false
        }
    }

    var step: Float? {
        switch self {
        case .osc1Wave, .osc2Wave, .osc1Octave, .osc2Octave, .lfoDestination, .pumpRate, .seqTempo, .seqLength,
             .kickMute, .snareMute, .clapMute, .closedHatMute, .openHatMute,
             .keyMode, .arpDirection, .arpOctaves, .keyHold,
             .kickVariant, .snareVariant, .clapVariant, .closedHatVariant, .openHatVariant,
             .seqEnabled, .drumsEnabled, .seqBank, .drumBank: 1
        default: nil
        }
    }

    /// Levels and tone settings glide to new values on the audio thread, so turning a knob
    /// or switching presets never clicks.
    var isSmoothed: Bool {
        switch self {
        case .osc1Level, .osc2Level, .osc1Detune, .osc2Detune, .cutoff, .resonance, .filterEnvAmount,
             .ampSustain, .filterSustain, // a held note follows the sustain level, so it must glide
             .lfoAmount, .masterVolume, .delayFeedback, .delayMix, .reverbSize, .reverbMix,
             .chorusMix, .driveAmount, .pumpAmount,
             .kickLevel, .snareLevel, .clapLevel, .closedHatLevel, .openHatLevel,
             .drumVolume, .drumReverbSend, .drumDelaySend, .drumComp, .drumDrive: true
        default: false
        }
    }

    var unit: Unit {
        switch self {
        case .osc1Octave, .osc2Octave: .octave
        case .osc1Detune, .osc2Detune: .cents
        case .cutoff, .lfoRate, .chorusRate: .hertz
        case .ampAttack, .ampDecay, .ampRelease, .filterAttack, .filterDecay, .filterRelease, .delayTime: .seconds
        case .filterEnvAmount: .bipolarPercent
        case .osc1Wave, .osc2Wave, .lfoDestination: .choice
        case .seqTempo: .bpm
        case .seqLength: .steps
        case .pumpRate: .division
        case .kickTune, .snareTune, .clapTune, .closedHatTune, .openHatTune: .semitones
        case .kickDecay, .snareDecay, .clapDecay, .closedHatDecay, .openHatDecay: .seconds
        case .kickMute, .snareMute, .clapMute, .closedHatMute, .openHatMute,
             .keyMode, .arpDirection, .arpOctaves, .keyHold,
             .kickVariant, .snareVariant, .clapVariant, .closedHatVariant, .openHatVariant,
             .seqEnabled, .drumsEnabled, .seqBank, .drumBank: .choice
        default: .percent
        }
    }

    func clamped(_ value: Float) -> Float {
        var v = min(max(value, range.lowerBound), range.upperBound)
        if let step { v = (v / step).rounded() * step }
        return v
    }

    /// Knob position 0...1 → parameter value, optionally over a narrower range (e.g. per drum variant).
    func value(fromNormalized n: Float, in knobRange: ClosedRange<Float>? = nil) -> Float {
        let n = min(max(n, 0), 1)
        let r = knobRange ?? range
        let lo = r.lowerBound, hi = r.upperBound
        return clamped(isLogarithmic ? lo * pow(hi / lo, n) : lo + (hi - lo) * n)
    }

    /// Parameter value → knob position 0...1, optionally over a narrower range.
    func normalized(_ value: Float, in knobRange: ClosedRange<Float>? = nil) -> Float {
        let r = knobRange ?? range
        let lo = r.lowerBound, hi = r.upperBound
        let v = min(max(value, lo), hi)
        return isLogarithmic ? log(v / lo) / log(hi / lo) : (v - lo) / (hi - lo)
    }
}

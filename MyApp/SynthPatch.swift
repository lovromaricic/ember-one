import Foundation

/// Preset categories, in the order the browser shows them.
nonisolated enum PresetCategory: String, CaseIterable, Codable {
    case bass, lead, pad, pluck, arp, fx, cinematic

    var title: String {
        switch self {
        case .bass: String(localized: "Bass")
        case .lead: String(localized: "Lead")
        case .pad: String(localized: "Pad")
        case .pluck: String(localized: "Pluck")
        case .arp: String(localized: "Arp")
        case .fx: String(localized: "FX")
        case .cinematic: String(localized: "Cinematic")
        }
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PresetCategory(rawValue: raw) ?? .lead
    }
}

/// The complete sound: everything the UI shows and the audio engine plays.
/// Codable for presets. Decoding is lenient: unknown fields are ignored and missing
/// fields keep their defaults, so presets survive future additions in both directions.
nonisolated struct SynthPatch: Codable, Equatable {
    static let stepCount = 16
    /// Sequencer banks A...H.
    static let bankCount = 8

    struct Oscillator: Codable, Equatable {
        var wave: Waveform = .saw
        var level: Float = 0.8
        var octave: Int = 0
        var detune: Float = 0
    }

    struct Filter: Codable, Equatable {
        var cutoff: Float = 2000
        var resonance: Float = 0.3
        var envAmount: Float = 0.5
    }

    struct Envelope: Codable, Equatable {
        var attack: Float
        var decay: Float
        var sustain: Float
        var release: Float
    }

    struct LFO: Codable, Equatable {
        var destination: LFODestination = .pitch
        var rate: Float = 5
        var amount: Float = 0
    }

    struct Effects: Codable, Equatable {
        var delayTime: Float = 0.375
        var delayFeedback: Float = 0.35
        var delayMix: Float = 0
        var reverbSize: Float = 0.6
        var reverbMix: Float = 0
        var chorusRate: Float = 0.8
        var chorusMix: Float = 0
        var driveAmount: Float = 0
        var pumpAmount: Float = 0
        /// Index into `SynthParam.pumpDivisions` (0 = 1/2 … 3 = 1/16).
        var pumpRate: Int = 1
    }

    /// The rhythm machine: sound of each drum, the drum bus and the 16-step pattern.
    struct Drums: Codable, Equatable {
        struct Voice: Codable, Equatable {
            var level: Float
            /// Semitones up or down from the drum's natural pitch.
            var tune: Float = 0
            /// Seconds for the hit to fade out.
            var decay: Float
            var muted = false
            /// Sound variant, 0...4 (see `DrumVariants`). 0 is each drum's classic sound.
            var variant = 0
        }

        var kick = Voice(level: 0.9, decay: 0.45)
        var snare = Voice(level: 0.7, decay: 0.2)
        var clap = Voice(level: 0.6, decay: 0.25)
        var closedHat = Voice(level: 0.5, decay: 0.06)
        var openHat = Voice(level: 0.45, decay: 0.35)
        var tomLo = Voice(level: 0.7, decay: 0.25)
        var tomHi = Voice(level: 0.65, decay: 0.18)
        var rim = Voice(level: 0.55, decay: 0.04)
        var cowbell = Voice(level: 0.5, decay: 0.3)
        var ride = Voice(level: 0.4, decay: 0.9)
        var volume: Float = 0.8
        var reverbSend: Float = 0
        var delaySend: Float = 0
        /// Gentle glue compression and saturation on the drum bus (0 = off).
        var comp: Float = 0.3
        var drive: Float = 0.2
        /// Eight banks (A...H), each one row of 16 steps per drum in `DrumKind` order. Empty by default.
        var banks: [[[Bool]]] = Drums.emptyBanks
        /// Bank shown for editing and selected for playing (0...7 = A...H).
        var activeBank = 0
        /// The drum track on the master clock (off = silent, the clock keeps running).
        var enabled = true

        static var emptyPattern: [[Bool]] {
            Array(repeating: Array(repeating: false, count: SynthPatch.stepCount), count: DrumKind.count)
        }
        static var emptyBanks: [[[Bool]]] { Array(repeating: emptyPattern, count: SynthPatch.bankCount) }

        /// The pattern of the active bank.
        var pattern: [[Bool]] {
            get { banks.indices.contains(activeBank) ? banks[activeBank] : Self.emptyPattern }
            set { if banks.indices.contains(activeBank) { banks[activeBank] = newValue } }
        }

        subscript(drum: DrumKind) -> Voice {
            get {
                switch drum {
                case .kick: kick
                case .snare: snare
                case .clap: clap
                case .closedHat: closedHat
                case .openHat: openHat
                case .tomLo: tomLo
                case .tomHi: tomHi
                case .rim: rim
                case .cowbell: cowbell
                case .ride: ride
                }
            }
            set {
                switch drum {
                case .kick: kick = newValue
                case .snare: snare = newValue
                case .clap: clap = newValue
                case .closedHat: closedHat = newValue
                case .openHat: openHat = newValue
                case .tomLo: tomLo = newValue
                case .tomHi: tomHi = newValue
                case .rim: rim = newValue
                case .cowbell: cowbell = newValue
                case .ride: ride = newValue
                }
            }
        }

        var isEmpty: Bool { !pattern.contains { $0.contains(true) } }
    }

    struct Sequencer: Codable, Equatable {
        var tempo: Float = 120
        var swing: Float = 0
        var length: Int = 16
        /// Eight banks (A...H) of 16 steps each: MIDI note per step, nil = rest.
        var banks: [[Int?]] = Sequencer.emptyBanks
        /// Bank shown for editing and selected for playing (0...7 = A...H).
        var activeBank = 0
        /// The sequencer track on the master clock (off = silent, the clock keeps running).
        var enabled = true
        var keyMode = KeyMode.off
        var arpDirection = ArpDirection.up
        /// Octave range of the arpeggio, 1...3.
        var arpOctaves = 1
        /// Keep playing after the keys are released.
        var hold = false

        static var emptyBank: [Int?] { Array(repeating: nil, count: SynthPatch.stepCount) }
        static var emptyBanks: [[Int?]] { Array(repeating: emptyBank, count: SynthPatch.bankCount) }

        /// The steps of the active bank.
        var steps: [Int?] {
            get { banks.indices.contains(activeBank) ? banks[activeBank] : Self.emptyBank }
            set { if banks.indices.contains(activeBank) { banks[activeBank] = newValue } }
        }
    }

    var name = "Init"
    var category = PresetCategory.lead
    /// Short description for the preset list, "Type · character". Optional, so older files decode.
    var tag: String?
    /// The drum machine as it was when a user preset was saved (sounds and all 8 banks).
    /// Only in saved presets; nil in factory presets and presets from before this, which
    /// leave the current drums alone when loaded. The engine keeps its drums separately.
    var drumKit: DrumKit?
    var osc1 = Oscillator(wave: .saw, level: 0.8)
    var osc2 = Oscillator(wave: .square, level: 0.5, detune: 7)
    var filter = Filter()
    var ampEnvelope = Envelope(attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.4)
    var filterEnvelope = Envelope(attack: 0.01, decay: 0.4, sustain: 0.3, release: 0.5)
    var lfo = LFO()
    var masterVolume: Float = 0.7
    var effects = Effects()
    var sequencer = Sequencer()

    init() {}

    // MARK: - Parameter access

    /// Reads any parameter as a Float (what knobs and the audio thread use).
    func value(for param: SynthParam) -> Float {
        switch param {
        case .osc1Wave: Float(osc1.wave.rawValue)
        case .osc1Level: osc1.level
        case .osc1Octave: Float(osc1.octave)
        case .osc1Detune: osc1.detune
        case .osc2Wave: Float(osc2.wave.rawValue)
        case .osc2Level: osc2.level
        case .osc2Octave: Float(osc2.octave)
        case .osc2Detune: osc2.detune
        case .cutoff: filter.cutoff
        case .resonance: filter.resonance
        case .filterEnvAmount: filter.envAmount
        case .ampAttack: ampEnvelope.attack
        case .ampDecay: ampEnvelope.decay
        case .ampSustain: ampEnvelope.sustain
        case .ampRelease: ampEnvelope.release
        case .filterAttack: filterEnvelope.attack
        case .filterDecay: filterEnvelope.decay
        case .filterSustain: filterEnvelope.sustain
        case .filterRelease: filterEnvelope.release
        case .lfoDestination: Float(lfo.destination.rawValue)
        case .lfoRate: lfo.rate
        case .lfoAmount: lfo.amount
        case .masterVolume: masterVolume
        case .delayTime: effects.delayTime
        case .delayFeedback: effects.delayFeedback
        case .delayMix: effects.delayMix
        case .reverbSize: effects.reverbSize
        case .reverbMix: effects.reverbMix
        case .chorusRate: effects.chorusRate
        case .chorusMix: effects.chorusMix
        case .driveAmount: effects.driveAmount
        case .pumpAmount: effects.pumpAmount
        case .pumpRate: Float(effects.pumpRate)
        case .seqTempo: sequencer.tempo
        case .seqSwing: sequencer.swing
        case .seqLength: Float(sequencer.length)
        case .keyMode: Float(sequencer.keyMode.rawValue)
        case .arpDirection: Float(sequencer.arpDirection.rawValue)
        case .arpOctaves: Float(sequencer.arpOctaves)
        case .keyHold: sequencer.hold ? 1 : 0
        case .seqEnabled: sequencer.enabled ? 1 : 0
        case .seqBank: Float(sequencer.activeBank)
        default:
            0 // drum parameters live in `DrumKit`, not in the patch
        }
    }

    /// Writes any parameter from a Float, clamped to its range.
    mutating func setValue(_ newValue: Float, for param: SynthParam) {
        let v = param.clamped(newValue)
        switch param {
        case .osc1Wave: osc1.wave = Waveform(rawValue: Int(v)) ?? .saw
        case .osc1Level: osc1.level = v
        case .osc1Octave: osc1.octave = Int(v)
        case .osc1Detune: osc1.detune = v
        case .osc2Wave: osc2.wave = Waveform(rawValue: Int(v)) ?? .saw
        case .osc2Level: osc2.level = v
        case .osc2Octave: osc2.octave = Int(v)
        case .osc2Detune: osc2.detune = v
        case .cutoff: filter.cutoff = v
        case .resonance: filter.resonance = v
        case .filterEnvAmount: filter.envAmount = v
        case .ampAttack: ampEnvelope.attack = v
        case .ampDecay: ampEnvelope.decay = v
        case .ampSustain: ampEnvelope.sustain = v
        case .ampRelease: ampEnvelope.release = v
        case .filterAttack: filterEnvelope.attack = v
        case .filterDecay: filterEnvelope.decay = v
        case .filterSustain: filterEnvelope.sustain = v
        case .filterRelease: filterEnvelope.release = v
        case .lfoDestination: lfo.destination = LFODestination(rawValue: Int(v)) ?? .pitch
        case .lfoRate: lfo.rate = v
        case .lfoAmount: lfo.amount = v
        case .masterVolume: masterVolume = v
        case .delayTime: effects.delayTime = v
        case .delayFeedback: effects.delayFeedback = v
        case .delayMix: effects.delayMix = v
        case .reverbSize: effects.reverbSize = v
        case .reverbMix: effects.reverbMix = v
        case .chorusRate: effects.chorusRate = v
        case .chorusMix: effects.chorusMix = v
        case .driveAmount: effects.driveAmount = v
        case .pumpAmount: effects.pumpAmount = v
        case .pumpRate: effects.pumpRate = Int(v)
        case .seqTempo: sequencer.tempo = v
        case .seqSwing: sequencer.swing = v
        case .seqLength: sequencer.length = Int(v)
        case .keyMode: sequencer.keyMode = KeyMode(rawValue: Int(v)) ?? .off
        case .arpDirection: sequencer.arpDirection = ArpDirection(rawValue: Int(v)) ?? .up
        case .arpOctaves: sequencer.arpOctaves = Int(v)
        case .keyHold: sequencer.hold = v >= 0.5
        case .seqEnabled: sequencer.enabled = v >= 0.5
        case .seqBank: sequencer.activeBank = Int(v)
        default:
            break // drum parameters live in `DrumKit`
        }
    }

    /// Every parameter clamped into range and the step list at the right length,
    /// so a hand-edited or damaged preset can't push odd values to the audio thread.
    func sanitized() -> SynthPatch {
        var patch = self
        for param in SynthParam.allCases where !param.isDrumParam {
            patch.setValue(value(for: param), for: param)
        }
        var banks = Sequencer.emptyBanks
        for (bank, steps) in sequencer.banks.prefix(Self.bankCount).enumerated() {
            for (step, note) in steps.prefix(Self.stepCount).enumerated() {
                banks[bank][step] = note.map { min(max($0, 0), 127) }
            }
        }
        patch.sequencer.banks = banks
        patch.drumKit = drumKit?.sanitized()
        return patch
    }

    /// The sound settings without the name and category, for "has this been edited?" checks.
    func hasSameSound(as other: SynthPatch) -> Bool {
        var a = self, b = other
        a.name = ""; b.name = ""
        a.category = .lead; b.category = .lead
        a.tag = nil; b.tag = nil
        a.drumKit = nil; b.drumKit = nil
        return a == b
    }

    // MARK: - Lenient decoding

    private enum CodingKeys: String, CodingKey {
        // "drums" from older presets is ignored: the drum machine is global app state now.
        case name, category, tag, drumKit, osc1, osc2, filter, ampEnvelope, filterEnvelope, lfo, masterVolume, effects, sequencer
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SynthPatch()
        name = c.lenient(.name, default: d.name)
        category = c.lenient(.category, default: d.category)
        tag = try? c.decodeIfPresent(String.self, forKey: .tag)
        drumKit = try? c.decodeIfPresent(DrumKit.self, forKey: .drumKit)
        osc1 = c.lenient(.osc1, default: d.osc1)
        osc2 = c.lenient(.osc2, default: d.osc2)
        filter = c.lenient(.filter, default: d.filter)
        ampEnvelope = c.lenient(.ampEnvelope, default: d.ampEnvelope)
        filterEnvelope = c.lenient(.filterEnvelope, default: d.filterEnvelope)
        lfo = c.lenient(.lfo, default: d.lfo)
        masterVolume = c.lenient(.masterVolume, default: d.masterVolume)
        effects = c.lenient(.effects, default: d.effects)
        sequencer = c.lenient(.sequencer, default: d.sequencer)
    }
}

// Nested types: every field optional with a default.

nonisolated extension SynthPatch.Oscillator {
    private enum CodingKeys: String, CodingKey { case wave, level, octave, detune }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        wave = c.lenient(.wave, default: d.wave)
        level = c.lenient(.level, default: d.level)
        octave = c.lenient(.octave, default: d.octave)
        detune = c.lenient(.detune, default: d.detune)
    }
}

nonisolated extension SynthPatch.Filter {
    private enum CodingKeys: String, CodingKey { case cutoff, resonance, envAmount }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        cutoff = c.lenient(.cutoff, default: d.cutoff)
        resonance = c.lenient(.resonance, default: d.resonance)
        envAmount = c.lenient(.envAmount, default: d.envAmount)
    }
}

nonisolated extension SynthPatch.Envelope {
    private enum CodingKeys: String, CodingKey { case attack, decay, sustain, release }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attack = c.lenient(.attack, default: 0.01)
        decay = c.lenient(.decay, default: 0.3)
        sustain = c.lenient(.sustain, default: 0.7)
        release = c.lenient(.release, default: 0.4)
    }
}

nonisolated extension SynthPatch.LFO {
    private enum CodingKeys: String, CodingKey { case destination, rate, amount }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        destination = c.lenient(.destination, default: d.destination)
        rate = c.lenient(.rate, default: d.rate)
        amount = c.lenient(.amount, default: d.amount)
    }
}

nonisolated extension SynthPatch.Effects {
    private enum CodingKeys: String, CodingKey {
        case delayTime, delayFeedback, delayMix, reverbSize, reverbMix, chorusRate, chorusMix, driveAmount, pumpAmount, pumpRate
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        delayTime = c.lenient(.delayTime, default: d.delayTime)
        delayFeedback = c.lenient(.delayFeedback, default: d.delayFeedback)
        delayMix = c.lenient(.delayMix, default: d.delayMix)
        reverbSize = c.lenient(.reverbSize, default: d.reverbSize)
        reverbMix = c.lenient(.reverbMix, default: d.reverbMix)
        chorusRate = c.lenient(.chorusRate, default: d.chorusRate)
        chorusMix = c.lenient(.chorusMix, default: d.chorusMix)
        driveAmount = c.lenient(.driveAmount, default: d.driveAmount)
        pumpAmount = c.lenient(.pumpAmount, default: d.pumpAmount)
        pumpRate = c.lenient(.pumpRate, default: d.pumpRate)
    }
}

nonisolated extension SynthPatch.Sequencer {
    private enum CodingKeys: String, CodingKey {
        case tempo, swing, length, banks, activeBank, enabled, keyMode, arpDirection, arpOctaves, hold
    }
    /// Presets from before banks stored one pattern under "steps".
    private enum LegacyKeys: String, CodingKey { case steps }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        tempo = c.lenient(.tempo, default: d.tempo)
        swing = c.lenient(.swing, default: d.swing)
        length = c.lenient(.length, default: d.length)
        if let saved: [[Int?]] = c.lenient(.banks, default: nil) {
            banks = saved
        } else {
            // Older presets: their pattern becomes bank A, B...H start empty.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            banks = Self.emptyBanks
            banks[0] = legacy.lenient(.steps, default: Self.emptyBank)
        }
        activeBank = min(max(c.lenient(.activeBank, default: 0), 0), SynthPatch.bankCount - 1)
        enabled = c.lenient(.enabled, default: true)
        // Presets from before key mode: off, up, one octave, no hold.
        keyMode = c.lenient(.keyMode, default: d.keyMode)
        arpDirection = c.lenient(.arpDirection, default: d.arpDirection)
        arpOctaves = c.lenient(.arpOctaves, default: d.arpOctaves)
        hold = c.lenient(.hold, default: d.hold)
    }
}

nonisolated extension SynthPatch.Drums {
    private enum CodingKeys: String, CodingKey {
        case kick, snare, clap, closedHat, openHat, tomLo, tomHi, rim, cowbell, ride
        case volume, reverbSend, delaySend, comp, drive, banks, activeBank, enabled
    }
    /// Kits from before drum banks stored one pattern under "pattern".
    private enum LegacyKeys: String, CodingKey { case pattern }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        kick = c.lenient(.kick, default: d.kick)
        snare = c.lenient(.snare, default: d.snare)
        clap = c.lenient(.clap, default: d.clap)
        closedHat = c.lenient(.closedHat, default: d.closedHat)
        openHat = c.lenient(.openHat, default: d.openHat)
        // Missing in kits saved before the five extra drums: their defaults.
        tomLo = c.lenient(.tomLo, default: d.tomLo)
        tomHi = c.lenient(.tomHi, default: d.tomHi)
        rim = c.lenient(.rim, default: d.rim)
        cowbell = c.lenient(.cowbell, default: d.cowbell)
        ride = c.lenient(.ride, default: d.ride)
        volume = c.lenient(.volume, default: d.volume)
        reverbSend = c.lenient(.reverbSend, default: d.reverbSend)
        delaySend = c.lenient(.delaySend, default: d.delaySend)
        comp = c.lenient(.comp, default: d.comp)
        drive = c.lenient(.drive, default: d.drive)
        if let saved: [[[Bool]]] = c.lenient(.banks, default: nil) {
            banks = saved
        } else {
            // Older kits: their pattern becomes bank A, B...H start empty.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            banks = Self.emptyBanks
            banks[0] = legacy.lenient(.pattern, default: Self.emptyPattern)
        }
        activeBank = min(max(c.lenient(.activeBank, default: 0), 0), SynthPatch.bankCount - 1)
        enabled = c.lenient(.enabled, default: true)
    }
}

nonisolated extension SynthPatch.Drums.Voice {
    private enum CodingKeys: String, CodingKey { case level, tune, decay, muted, variant }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = c.lenient(.level, default: 0.7)
        tune = c.lenient(.tune, default: 0)
        decay = c.lenient(.decay, default: 0.3)
        muted = c.lenient(.muted, default: false)
        // Presets from before drum variants: the first (classic) variant.
        variant = min(max(c.lenient(.variant, default: 0), 0), 4)
    }
}

nonisolated extension KeyedDecodingContainer {
    /// Decodes a field if it's present and readable; otherwise returns `fallback`.
    func lenient<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// The drum machine's settings. Global app state, saved separately from presets.
typealias DrumKit = SynthPatch.Drums

nonisolated extension SynthPatch.Drums {
    func value(for param: SynthParam) -> Float {
        switch param {
        case .drumVolume: return volume
        case .drumReverbSend: return reverbSend
        case .drumDelaySend: return delaySend
        case .drumsEnabled: return enabled ? 1 : 0
        case .drumComp: return comp
        case .drumDrive: return drive
        case .drumBank: return Float(activeBank)
        default:
            if let drum = param.variantDrum { return Float(self[drum].variant) }
            guard let drum = param.drum else { return 0 }
            let voice = self[drum]
            switch param {
            case SynthParam.drumLevel(drum): return voice.level
            case SynthParam.drumTune(drum): return voice.tune
            case SynthParam.drumDecay(drum): return voice.decay
            default: return voice.muted ? 1 : 0
            }
        }
    }

    mutating func setValue(_ newValue: Float, for param: SynthParam) {
        let v = param.clamped(newValue)
        switch param {
        case .drumVolume: volume = v
        case .drumReverbSend: reverbSend = v
        case .drumDelaySend: delaySend = v
        case .drumsEnabled: enabled = v >= 0.5
        case .drumComp: comp = v
        case .drumDrive: drive = v
        case .drumBank: activeBank = Int(v)
        default:
            if let drum = param.variantDrum {
                self[drum].variant = Int(v)
                return
            }
            guard let drum = param.drum else { return }
            switch param {
            case SynthParam.drumLevel(drum): self[drum].level = v
            case SynthParam.drumTune(drum): self[drum].tune = v
            case SynthParam.drumDecay(drum): self[drum].decay = v
            default: self[drum].muted = v >= 0.5
            }
        }
    }

    /// Every value in range and every bank at the right size (a damaged file can't push odd values).
    func sanitized() -> DrumKit {
        var kit = self
        for param in SynthParam.allCases where param.isDrumParam {
            kit.setValue(value(for: param), for: param)
        }
        var banks = Self.emptyBanks
        for (bank, pattern) in self.banks.prefix(SynthPatch.bankCount).enumerated() {
            for (row, steps) in pattern.prefix(DrumKind.count).enumerated() {
                for (step, on) in steps.prefix(SynthPatch.stepCount).enumerated() { banks[bank][row][step] = on }
            }
        }
        kit.banks = banks
        return kit
    }
}

/// The value the audio thread uses for a parameter: drum parameters come from the drum kit,
/// everything else from the patch.
nonisolated func audioValue(_ param: SynthParam, patch: SynthPatch, drums: DrumKit) -> Float {
    param.isDrumParam ? drums.value(for: param) : patch.value(for: param)
}

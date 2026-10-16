import Foundation

/// Built-in presets, inspired by French house, disco and funk. Names are localized (String Catalog). Each one sets only what differs
/// from `SynthPatch()`, so the recipe is easy to read and tweak.
///
/// Patterns are written as note names separated by spaces: "C3", "D#4", "." for a rest,
/// and "C4*8" to repeat a note on eight steps. Pads repeat their note on every step: the
/// sequencer retriggers from the current level, so with a long release they sustain smoothly.
nonisolated enum FactoryPresets {
    static var all: [SynthPatch] {
        [
            // Bass
            // Rubbery, short square/saw bass with a quick filter snap and a swung groove.
            make("Funk bass", .bass, tag: "Bass · rubbery snap") { p in
                p.osc1 = .init(wave: .square, level: 0.8, octave: -1, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.5, octave: -1, detune: -5)
                p.filter = .init(cutoff: 350, resonance: 0.55, envAmount: 0.55)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.18, sustain: 0.1, release: 0.1)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.25, sustain: 0.6, release: 0.08)
                p.effects.driveAmount = 0.25
                p.sequencer = sequence(tempo: 112, swing: 0.18, "C3 . C3 C4 . C3 D#3 . F3 . C3 . A#2 . C3 G2")
            },
            // Squelchy, screaming single-saw bass with high resonance, drive and a little echo.
            make("Acid bass", .bass, tag: "Bass · squelchy acid") { p in
                p.osc1 = .init(wave: .saw, level: 0.9, octave: -1, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0, octave: 0, detune: 0)
                p.filter = .init(cutoff: 250, resonance: 0.9, envAmount: 0.8)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.22, sustain: 0, release: 0.15)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.3, sustain: 0.8, release: 0.05)
                p.effects.driveAmount = 0.45
                p.effects.delayMix = 0.15
                p.effects.delayTime = 0.357
                p.effects.delayFeedback = 0.3
                p.sequencer = sequence(tempo: 126, "C3 C3 C4 C3 D#3 C3 . G3 C3 C4 . A#2 C3 F3 C3 D#4")
            },
            // Classic disco bass jumping between octaves; warm and wide with light chorus.
            make("Disco octave bass", .bass, tag: "Bass · octave bounce") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: -1, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.45, octave: 0, detune: 4)
                p.filter = .init(cutoff: 900, resonance: 0.25, envAmount: 0.35)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.15, sustain: 0.3, release: 0.1)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.2, sustain: 0.5, release: 0.06)
                p.effects.chorusMix = 0.25
                p.effects.chorusRate = 0.6
                p.sequencer = sequence(tempo: 120, "C3 C4 C3 C4 A#2 A#3 A#2 A#3 G#2 G#3 G#2 G#3 G2 G3 G2 G3")
            },
            // Clean sine/triangle sub you feel more than hear; best on headphones.
            make("Deep sub bass", .bass, tag: "Bass · clean sub") { p in
                p.osc1 = .init(wave: .sine, level: 0.9, octave: -1, detune: 0)
                p.osc2 = .init(wave: .triangle, level: 0.3, octave: -1, detune: 0)
                p.filter = .init(cutoff: 600, resonance: 0.1, envAmount: 0.1)
                p.ampEnvelope = .init(attack: 0.005, decay: 0.4, sustain: 0.9, release: 0.15)
                p.effects.driveAmount = 0.15
                p.sequencer = sequence(tempo: 122, "C3 . . . . . C3 . D#3 . . . F3 . G3 .")
            },
            // Off-beat house bass with a resonant square tone that breathes with the pump.
            make("Resonant house bass", .bass, tag: "Bass · pumping off-beat") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: -1, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.6, octave: -1, detune: 10)
                p.filter = .init(cutoff: 180, resonance: 0.75, envAmount: 0.65)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.3, sustain: 0.15, release: 0.2)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.3, sustain: 0.7, release: 0.1)
                p.effects.pumpAmount = 0.45
                p.effects.pumpRate = 1
                p.sequencer = sequence(tempo: 124, ". . C3 . . . C3 . . . D#3 . . . C3 C3")
            },

            // Lead
            // Two saws detuned apart, thickened with chorus and a dotted echo.
            make("Fat detuned lead", .lead, tag: "Lead · wide detuned") { p in
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -12)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: 0, detune: 12)
                p.filter = .init(cutoff: 3500, resonance: 0.2, envAmount: 0.3)
                p.ampEnvelope = .init(attack: 0.01, decay: 0.3, sustain: 0.8, release: 0.3)
                p.effects.chorusMix = 0.5
                p.effects.chorusRate = 0.7
                p.effects.delayMix = 0.25
                p.effects.delayTime = 0.381
                p.effects.delayFeedback = 0.35
                p.effects.reverbMix = 0.2
                p.sequencer = sequence(tempo: 118, "C5 . D#5 . G5 . . C5 . A#4 . G4 . . . .")
            },
            // Aggressive saw that zaps open on every note via the filter envelope.
            make("Sharp saw lead", .lead, tag: "Lead · bright zap") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.3, octave: 1, detune: 0)
                p.filter = .init(cutoff: 400, resonance: 0.6, envAmount: 0.9)
                p.filterEnvelope = .init(attack: 0.005, decay: 0.45, sustain: 0.2, release: 0.3)
                p.ampEnvelope = .init(attack: 0.003, decay: 0.4, sustain: 0.7, release: 0.25)
                p.effects.driveAmount = 0.3
                p.effects.delayMix = 0.2
                p.effects.delayTime = 0.25
                p.sequencer = sequence(tempo: 122, "C5 C5 . C5 . D#5 . F5 . . G5 . F5 . D#5 .")
            },
            // Square lead with an LFO-driven wah, like a talk box.
            make("Robot wah lead", .lead, tag: "Lead · talk-box wah") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.45, octave: 1, detune: 3)
                p.filter = .init(cutoff: 1500, resonance: 0.45, envAmount: 0.2)
                p.lfo = .init(destination: .cutoff, rate: 6, amount: 0.35)
                p.ampEnvelope = .init(attack: 0.005, decay: 0.2, sustain: 0.9, release: 0.2)
                p.effects.chorusMix = 0.2
                p.sequencer = sequence(tempo: 110, "G4 . G4 A#4 . C5 . . A#4 . G4 . F4 . G4 .")
            },
            // Soft, flute-like tone with vibrato and a long echo.
            make("Vibrato sine lead", .lead, tag: "Lead · soft flute") { p in
                p.osc1 = .init(wave: .sine, level: 0.9, octave: 0, detune: 0)
                p.osc2 = .init(wave: .triangle, level: 0.3, octave: 1, detune: 0)
                p.filter = .init(cutoff: 8000, resonance: 0.1, envAmount: 0)
                p.lfo = .init(destination: .pitch, rate: 5.5, amount: 0.15)
                p.ampEnvelope = .init(attack: 0.05, decay: 0.3, sustain: 0.85, release: 0.4)
                p.effects.delayMix = 0.3
                p.effects.delayTime = 0.45
                p.effects.delayFeedback = 0.45
                p.effects.reverbMix = 0.25
                p.sequencer = sequence(tempo: 100, "E5 . . . G5 . . . A5 . . . G5 . E5 .")
            },
            // Short, punchy square stabs with swing.
            make("Funky square lead", .lead, tag: "Lead · punchy stabs") { p in
                p.osc1 = .init(wave: .square, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.4, octave: -1, detune: 0)
                p.filter = .init(cutoff: 1200, resonance: 0.35, envAmount: 0.5)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0.25, release: 0.1)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.15, sustain: 0.4, release: 0.1)
                p.effects.driveAmount = 0.35
                p.sequencer = sequence(tempo: 108, swing: 0.2, "C5 . C5 . . D#5 C5 . F5 . . C5 . . A#4 .")
            },

            // Pad
            // Slowly opening saw pad with a filter sweep, reverb and pump.
            make("Filter house pad", .pad, tag: "Pad · slow filter sweep") { p in
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -9)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: 0, detune: 9)
                p.filter = .init(cutoff: 700, resonance: 0.35, envAmount: 0.3)
                p.filterEnvelope = .init(attack: 1.2, decay: 1.5, sustain: 0.6, release: 1.5)
                p.lfo = .init(destination: .cutoff, rate: 0.15, amount: 0.35)
                p.ampEnvelope = .init(attack: 0.6, decay: 1, sustain: 0.85, release: 1.8)
                p.effects.chorusMix = 0.5
                p.effects.reverbMix = 0.45
                p.effects.reverbSize = 0.8
                p.effects.pumpAmount = 0.5
                p.effects.pumpRate = 1
                p.sequencer = sequence(tempo: 124, "C4*8 D#4*8")
            },
            // Bright string-machine pad with heavy chorus.
            make("Disco strings pad", .pad, tag: "Strings · bright chorus") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.4, octave: 1, detune: 7)
                p.filter = .init(cutoff: 2500, resonance: 0.1, envAmount: 0.2)
                p.ampEnvelope = .init(attack: 0.25, decay: 0.5, sustain: 0.8, release: 1.2)
                p.effects.chorusMix = 0.8
                p.effects.chorusRate = 0.9
                p.effects.reverbMix = 0.35
                p.sequencer = sequence(tempo: 120, "A3*8 F3*8")
            },
            // Very soft, dreamy triangle/sine pad with lots of space.
            make("Warm ethereal pad", .pad, tag: "Pad · soft and dreamy") { p in
                p.osc1 = .init(wave: .triangle, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .sine, level: 0.4, octave: 1, detune: 0)
                p.filter = .init(cutoff: 1800, resonance: 0.15, envAmount: 0.1)
                p.lfo = .init(destination: .pitch, rate: 4, amount: 0.05)
                p.ampEnvelope = .init(attack: 1, decay: 1, sustain: 0.9, release: 2.5)
                p.effects.reverbMix = 0.6
                p.effects.reverbSize = 0.9
                p.effects.delayMix = 0.2
                p.effects.delayTime = 0.5
                p.effects.delayFeedback = 0.5
                p.sequencer = sequence(tempo: 96, "E4*16")
            },
            // Sustained chord that pumps hard on eighth notes.
            make("Pumping pad", .pad, tag: "Pad · eighth-note pump") { p in
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -6)
                p.osc2 = .init(wave: .square, level: 0.5, octave: 0, detune: 6)
                p.filter = .init(cutoff: 1200, resonance: 0.25, envAmount: 0.15)
                p.ampEnvelope = .init(attack: 0.3, decay: 0.5, sustain: 0.9, release: 1)
                p.effects.pumpAmount = 0.8
                p.effects.pumpRate = 2
                p.effects.chorusMix = 0.3
                p.effects.reverbMix = 0.3
                p.sequencer = sequence(tempo: 126, "G3*16")
            },

            // Pluck
            // Short, chirpy resonant plucks with a rhythmic echo.
            make("Acid pluck", .pluck, tag: "Pluck · resonant chirp") { p in
                p.osc1 = .init(wave: .saw, level: 0.9, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0, octave: 0, detune: 0)
                p.filter = .init(cutoff: 300, resonance: 0.8, envAmount: 0.75)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0, release: 0.1)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.2, sustain: 0, release: 0.15)
                p.effects.delayMix = 0.3
                p.effects.delayTime = 0.352
                p.effects.delayFeedback = 0.4
                p.sequencer = sequence(tempo: 128, "C4 . C5 . G4 . C5 D#4 . C4 . A#4 . G4 . .")
            },
            // Short scratchy plucks like a funk rhythm guitar, with swing.
            make("Funk guitar pluck", .pluck, tag: "Pluck · scratchy funk") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.3, octave: 1, detune: 0)
                p.filter = .init(cutoff: 1500, resonance: 0.3, envAmount: 0.5)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.08, sustain: 0, release: 0.08)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.15, sustain: 0, release: 0.1)
                p.effects.chorusMix = 0.35
                p.sequencer = sequence(tempo: 106, swing: 0.25, "E4 . E4 E4 . . E4 . E4 . . E4 E4 . G4 .")
            },
            // High crystal tones like drops, with a ping-pong echo.
            make("Glass drops pluck", .pluck, tag: "Bell · glassy echoes") { p in
                p.osc1 = .init(wave: .sine, level: 0.9, octave: 0, detune: 0)
                p.osc2 = .init(wave: .triangle, level: 0.35, octave: 1, detune: 0)
                p.filter = .init(cutoff: 6000, resonance: 0.1, envAmount: 0)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.35, sustain: 0, release: 0.4)
                p.effects.delayMix = 0.45
                p.effects.delayTime = 0.375
                p.effects.delayFeedback = 0.55
                p.effects.reverbMix = 0.4
                p.sequencer = sequence(tempo: 120, "C6 . . G5 . . E5 . . C6 . . D6 . . .")
            },

            // Arp
            // Fast minor arpeggio that slowly opens and closes over time.
            make("House arp", .arp, tag: "Arp · minor filter swell") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.35, octave: 1, detune: 0)
                p.filter = .init(cutoff: 900, resonance: 0.5, envAmount: 0.45)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.1, sustain: 0.1, release: 0.1)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0.3, release: 0.08)
                p.lfo = .init(destination: .cutoff, rate: 0.1, amount: 0.5)
                p.effects.delayMix = 0.25
                p.effects.delayTime = 0.363
                p.effects.pumpAmount = 0.3
                p.sequencer = sequence(tempo: 124, "C4 D#4 G4 C5 D#5 C5 G4 D#4 A#3 D4 F4 A#4 D5 A#4 F4 D4")
            },
            // Cheerful disco arpeggio jumping octaves.
            make("Disco octave arp", .arp, tag: "Arp · octave jumps") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.6, octave: 0, detune: 8)
                p.filter = .init(cutoff: 2200, resonance: 0.2, envAmount: 0.25)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0.3, release: 0.1)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.1, sustain: 0.5, release: 0.06)
                p.effects.chorusMix = 0.4
                p.effects.reverbMix = 0.2
                p.sequencer = sequence(tempo: 118, "A3 A4 E4 A4 A3 A4 E4 A4 F3 F4 C4 F4 G3 G4 D4 G4")
            },

            // FX
            // “Pew-pew” laser shots with a fast warble and long space echoes.
            make("Laser sweep", .fx, tag: "FX · laser zaps") { p in
                // Each note is a "zap": the resonant filter snaps open and closes again while
                // a fast pitch wobble and long ping-pong echoes bounce it around the room.
                p.osc1 = .init(wave: .saw, level: 0.9, octave: 0, detune: 0)
                p.osc2 = .init(wave: .sine, level: 0.3, octave: 2, detune: 0)
                p.filter = .init(cutoff: 300, resonance: 0.95, envAmount: 1)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.6, sustain: 0, release: 0.4)
                p.lfo = .init(destination: .pitch, rate: 12, amount: 0.6)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.4, sustain: 0.3, release: 0.6)
                p.effects.delayMix = 0.5
                p.effects.delayTime = 0.3
                p.effects.delayFeedback = 0.7
                p.effects.reverbMix = 0.5
                p.effects.reverbSize = 0.9
                p.sequencer = sequence(tempo: 120, "C5 . . . G5 . . . C6 . . . . . . .")
            },

            // MARK: French electro

            // Bass
            // Hard, overdriven twin-saw bass that snaps open on every note and ducks to a four-on-the-floor kick.
            make("Dirty saw bass", .bass, tag: "Bass · overdriven saw") { p in
                p.osc1 = .init(wave: .saw, level: 0.9, octave: -1, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.8, octave: -1, detune: 12)
                p.filter = .init(cutoff: 400, resonance: 0.5, envAmount: 0.7)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.25, sustain: 0.2, release: 0.1)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.3, sustain: 0.8, release: 0.08)
                p.effects.driveAmount = 0.85
                p.effects.chorusMix = 0.2
                p.effects.chorusRate = 2.5
                p.effects.pumpAmount = 0.55
                p.effects.pumpRate = 1
                p.sequencer = sequence(tempo: 122, "C3 C3 C4 C3 C3 C3 D#3 C3 C3 C3 C4 C3 G2 G2 A#2 C3")
            },
            // Square and sub-octave saw at full drive with a screaming resonant snap: harsh and percussive.
            make("Grinding square bass", .bass, tag: "Bass · harsh grind") { p in
                p.osc1 = .init(wave: .square, level: 0.85, octave: -1, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.6, octave: -2, detune: 7)
                p.filter = .init(cutoff: 250, resonance: 0.75, envAmount: 0.8)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.15, sustain: 0, release: 0.08)
                p.ampEnvelope = .init(attack: 0.002, decay: 0.2, sustain: 0.6, release: 0.05)
                p.effects.driveAmount = 1
                p.effects.pumpAmount = 0.35
                p.sequencer = sequence(tempo: 124, "C3 . C3 C3 . C3 . D#3 C3 . C3 C3 . F3 . G3")
            },
            // Sustained fuzz chopped into sixteenths by a deep pump; hold a key to transpose the riff.
            make("Gated fuzz bass", .bass, tag: "Bass · gated fuzz") { p in
                p.osc1 = .init(wave: .saw, level: 0.85, octave: -1, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.8, octave: -1, detune: 9)
                p.filter = .init(cutoff: 900, resonance: 0.2, envAmount: 0.3)
                p.ampEnvelope = .init(attack: 0.005, decay: 0.5, sustain: 1, release: 0.15)
                p.effects.driveAmount = 0.95
                p.effects.pumpAmount = 0.85
                p.effects.pumpRate = 3
                p.sequencer = sequence(tempo: 118, "C3*4 C3*4 A#2*4 G2*4")
                p.sequencer.keyMode = .transpose
            },

            // Lead
            // A saw stacked with a detuned saw an octave up, fast chorus and a dotted echo: huge and bright.
            make("Stacked saw lead", .lead, tag: "Lead · huge octave stack") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: -10)
                p.osc2 = .init(wave: .saw, level: 0.6, octave: 1, detune: 11)
                p.filter = .init(cutoff: 3000, resonance: 0.3, envAmount: 0.4)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.3, sustain: 0.5, release: 0.3)
                p.ampEnvelope = .init(attack: 0.005, decay: 0.3, sustain: 0.85, release: 0.25)
                p.effects.chorusMix = 0.6
                p.effects.chorusRate = 2.8
                p.effects.driveAmount = 0.4
                p.effects.delayMix = 0.25
                p.effects.delayTime = 0.363
                p.effects.pumpAmount = 0.3
                p.sequencer = sequence(tempo: 124, "C5 . C5 D#5 . C5 G5 . F5 . D#5 . C5 . A#4 .")
            },
            // Long notes that scream as a resonant filter rips open, with a subtle wah wobble on top.
            make("Screaming filter lead", .lead, tag: "Lead · screaming filter") { p in
                p.osc1 = .init(wave: .square, level: 0.75, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: 0, detune: 7)
                p.filter = .init(cutoff: 300, resonance: 0.85, envAmount: 1)
                p.filterEnvelope = .init(attack: 0.02, decay: 0.6, sustain: 0.35, release: 0.3)
                p.ampEnvelope = .init(attack: 0.005, decay: 0.3, sustain: 0.9, release: 0.2)
                p.lfo = .init(destination: .cutoff, rate: 6, amount: 0.15)
                p.effects.driveAmount = 0.6
                p.effects.delayMix = 0.2
                p.sequencer = sequence(tempo: 120, "C5 . . . . . . . D#5 . . . G5 . F5 .")
            },
            // Staccato, buzzing saw with a harsh two-octave overtone, pumping in eighths; keys transpose the riff.
            make("Buzzing octave lead", .lead, tag: "Lead · staccato buzz") { p in
                p.osc1 = .init(wave: .saw, level: 0.85, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.3, octave: 2, detune: 15)
                p.filter = .init(cutoff: 5000, resonance: 0.2, envAmount: 0.2)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0.3, release: 0.05)
                p.effects.driveAmount = 0.8
                p.effects.chorusMix = 0.4
                p.effects.chorusRate = 4
                p.effects.pumpAmount = 0.5
                p.effects.pumpRate = 2
                p.sequencer = sequence(tempo: 126, "C5 C5 C6 C5 . C5 A#4 C5 C5 C5 G5 C5 . C5 D#5 F5")
                p.sequencer.keyMode = .transpose
            },

            // Pad
            // A wide saw pad sliced into hard sixteenth gates by a full-depth pump.
            make("Gated pad", .pad, tag: "Pad · hard gate") { p in
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -8)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: 0, detune: 12)
                p.filter = .init(cutoff: 1500, resonance: 0.3, envAmount: 0.1)
                p.ampEnvelope = .init(attack: 0.05, decay: 0.5, sustain: 0.9, release: 0.3)
                p.effects.pumpAmount = 0.95
                p.effects.pumpRate = 3
                p.effects.chorusMix = 0.5
                p.effects.chorusRate = 1.5
                p.effects.reverbMix = 0.4
                p.sequencer = sequence(tempo: 124, "C4*8 G#3*8")
            },
            // Bright string-machine pad that breathes on every beat, with fast chorus and a big room.
            make("Sidechain string pad", .pad, tag: "Strings · sidechain pulse") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.35, octave: 1, detune: 9)
                p.filter = .init(cutoff: 2200, resonance: 0.15, envAmount: 0.15)
                p.ampEnvelope = .init(attack: 0.4, decay: 0.6, sustain: 0.85, release: 1.4)
                p.effects.chorusMix = 0.75
                p.effects.chorusRate = 2.2
                p.effects.pumpAmount = 0.7
                p.effects.pumpRate = 1
                p.effects.reverbMix = 0.5
                p.effects.reverbSize = 0.85
                p.sequencer = sequence(tempo: 122, "F3*8 D#3*8")
            },
            // Low, gritty detuned saws under a slow, deep filter sweep that opens and closes over many bars.
            make("Dark sweep pad", .pad, tag: "Pad · dark slow sweep") { p in
                p.osc1 = .init(wave: .saw, level: 0.75, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: -1, detune: 14)
                p.filter = .init(cutoff: 250, resonance: 0.55, envAmount: 0.2)
                p.lfo = .init(destination: .cutoff, rate: 0.08, amount: 0.7)
                p.ampEnvelope = .init(attack: 1.2, decay: 1, sustain: 0.9, release: 2)
                p.effects.driveAmount = 0.35
                p.effects.reverbMix = 0.55
                p.effects.delayMix = 0.2
                p.effects.delayTime = 0.5
                p.sequencer = sequence(tempo: 110, "A3*16")
            },

            // Pluck
            // Very short, hard square chops with a resonant snap and grit, pumping with the beat.
            make("Hard chop pluck", .pluck, tag: "Pluck · hard chop") { p in
                p.osc1 = .init(wave: .square, level: 0.9, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0, octave: 0, detune: 0)
                p.filter = .init(cutoff: 500, resonance: 0.6, envAmount: 0.8)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.06, sustain: 0, release: 0.05)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.09, sustain: 0, release: 0.05)
                p.effects.driveAmount = 0.5
                p.effects.pumpAmount = 0.4
                p.effects.delayMix = 0.2
                p.effects.delayTime = 0.1875
                p.sequencer = sequence(tempo: 126, "C4 . C4 C5 . C4 . D#4 . C4 C5 . G4 . F4 .")
            },
            // Metallic, ringing zaps from a screaming filter and a high detuned overtone, echoing in eighths.
            make("Metal zap pluck", .pluck, tag: "Pluck · metallic ring") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .sine, level: 0.4, octave: 2, detune: 15)
                p.filter = .init(cutoff: 2000, resonance: 0.9, envAmount: 0.6)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.04, sustain: 0, release: 0.05)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0, release: 0.1)
                p.effects.delayMix = 0.35
                p.effects.delayTime = 0.25
                p.effects.delayFeedback = 0.45
                p.sequencer = sequence(tempo: 120, "G4 . . G5 . . G4 . D5 . . G4 . F5 . .")
            },
            // Wide unison-saw stabs with fast chorus and room, like a chopped chord; keys transpose them.
            make("Detuned stab pluck", .pluck, tag: "Stab · wide unison") { p in
                p.osc1 = .init(wave: .saw, level: 0.75, octave: 0, detune: -12)
                p.osc2 = .init(wave: .saw, level: 0.75, octave: 0, detune: 12)
                p.filter = .init(cutoff: 1200, resonance: 0.25, envAmount: 0.5)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.15, sustain: 0, release: 0.15)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.25, sustain: 0, release: 0.2)
                p.effects.chorusMix = 0.5
                p.effects.chorusRate = 3
                p.effects.reverbMix = 0.3
                p.effects.pumpAmount = 0.5
                p.sequencer = sequence(tempo: 124, "C4 . . C4 . . C4 . . . C4 . . C4 . .")
                p.sequencer.keyMode = .transpose
            },

            // Arp
            // Driving sixteenth arpeggio over two octaves of the chord you hold, with a pumping beat.
            make("Electro 16th arp", .arp, tag: "Arp · driving 16ths") { p in
                p.osc1 = .init(wave: .square, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.4, octave: 1, detune: 7)
                p.filter = .init(cutoff: 700, resonance: 0.6, envAmount: 0.6)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.08, sustain: 0.1, release: 0.05)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.1, sustain: 0.3, release: 0.05)
                p.effects.pumpAmount = 0.5
                p.effects.delayMix = 0.2
                p.effects.delayTime = 0.363
                p.sequencer = sequence(tempo: 124, "C4*16")
                p.sequencer.keyMode = .arp
                p.sequencer.arpOctaves = 2
            },
            // Galloping up-and-down arpeggio of fat detuned saws with grit and fast chorus.
            make("Gallop arp", .arp, tag: "Arp · galloping saws") { p in
                p.osc1 = .init(wave: .saw, level: 0.75, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: 0, detune: 10)
                p.filter = .init(cutoff: 1400, resonance: 0.45, envAmount: 0.4)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.1, sustain: 0.2, release: 0.08)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0.4, release: 0.06)
                p.effects.driveAmount = 0.45
                p.effects.chorusMix = 0.4
                p.effects.chorusRate = 3.5
                p.sequencer = sequence(tempo: 120, "C4 . C4 C4 C4 . C4 C4 C4 . C4 C4 C4 . C4 C4")
                p.sequencer.keyMode = .arp
                p.sequencer.arpDirection = .upDown
            },
            // Squelchy acid line that jumps randomly across three octaves of the held chord, with a long echo.
            make("Random acid arp", .arp, tag: "Arp · random acid") { p in
                p.osc1 = .init(wave: .saw, level: 0.9, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0, octave: 0, detune: 0)
                p.filter = .init(cutoff: 300, resonance: 0.85, envAmount: 0.7)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.15, sustain: 0, release: 0.1)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.2, sustain: 0.5, release: 0.08)
                p.effects.driveAmount = 0.6
                p.effects.delayMix = 0.3
                p.effects.delayTime = 0.375
                p.effects.delayFeedback = 0.5
                p.sequencer = sequence(tempo: 126, "C4 C4 . C4 C4 . C4 C4 C4 . C4 . C4 C4 . C4")
                p.sequencer.keyMode = .arp
                p.sequencer.arpDirection = .random
                p.sequencer.arpOctaves = 3
            },

            // FX
            // Hold a key: the filter and volume rise slowly over a few seconds, like a build-up before a drop.
            make("Riser sweep", .fx, tag: "FX · build-up riser") { p in
                p.osc1 = .init(wave: .saw, level: 0.75, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.75, octave: 0, detune: 15)
                p.filter = .init(cutoff: 100, resonance: 0.8, envAmount: 1)
                p.filterEnvelope = .init(attack: 4, decay: 0.1, sustain: 1, release: 1)
                p.ampEnvelope = .init(attack: 2, decay: 0.5, sustain: 1, release: 1)
                p.effects.reverbMix = 0.5
                p.effects.reverbSize = 0.9
                p.sequencer = sequence(tempo: 124, "C4*16")
            },
            // A two-tone police-style siren: the pitch swings up and down, bouncing through a long echo.
            make("Siren wobble", .fx, tag: "FX · siren") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.6, octave: 0, detune: 12)
                p.filter = .init(cutoff: 3000, resonance: 0.2, envAmount: 0)
                p.lfo = .init(destination: .pitch, rate: 3, amount: 1)
                p.ampEnvelope = .init(attack: 0.01, decay: 0.3, sustain: 1, release: 0.5)
                p.effects.delayMix = 0.3
                p.effects.delayFeedback = 0.5
                p.sequencer = sequence(tempo: 120, "A4 . . . . . . . A4 . . . . . . .")
            },
            // Distorted square stuttering in sixteenths with a fast filter flutter: glitchy, robotic bursts.
            make("Stutter glitch", .fx, tag: "FX · glitchy stutter") { p in
                p.osc1 = .init(wave: .square, level: 0.85, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.4, octave: -1, detune: 7)
                p.filter = .init(cutoff: 1200, resonance: 0.6, envAmount: 0.3)
                p.lfo = .init(destination: .cutoff, rate: 12, amount: 0.8)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.2, sustain: 0.8, release: 0.05)
                p.effects.driveAmount = 0.9
                p.effects.pumpAmount = 0.95
                p.effects.pumpRate = 3
                p.sequencer = sequence(tempo: 128, "C5 . . C5 . . C5 . C5 . . C5 . C5 . .")
            },

            // MARK: Cinematic (CS-80 inspired)
            // No glide, pulse-width, delayed vibrato or aftertouch exist here; see each note.

            // Classic CS-80 brass: two detuned saws swell in, the filter blooms and settles.
            make("Rain Brass", .cinematic, tag: "Brass · slow swell") { p in
                p.osc1 = .init(wave: .saw, level: 0.75, octave: 0, detune: -9)
                p.osc2 = .init(wave: .saw, level: 0.75, octave: 0, detune: 9)
                p.filter = .init(cutoff: 550, resonance: 0.15, envAmount: 0.55)
                p.filterEnvelope = .init(attack: 0.5, decay: 1.2, sustain: 0.45, release: 1.5)
                p.ampEnvelope = .init(attack: 0.4, decay: 0.8, sustain: 0.85, release: 1.8)
                p.lfo = .init(destination: .pitch, rate: 5, amount: 0.04)
                p.effects.chorusMix = 0.5
                p.effects.chorusRate = 0.5
                p.effects.reverbMix = 0.45
                p.effects.reverbSize = 0.85
            },
            // Softer, rounder brass for melodies: saw + triangle, mellow filter, gentle vibrato.
            make("Distant Horn", .cinematic, tag: "Brass · soft horn") { p in
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -4)
                p.osc2 = .init(wave: .triangle, level: 0.6, octave: 0, detune: 4)
                p.filter = .init(cutoff: 420, resonance: 0.1, envAmount: 0.4)
                p.filterEnvelope = .init(attack: 0.7, decay: 1.5, sustain: 0.5, release: 1.5)
                p.ampEnvelope = .init(attack: 0.6, decay: 1, sustain: 0.9, release: 1.5)
                p.lfo = .init(destination: .pitch, rate: 5.2, amount: 0.08)
                p.effects.delayMix = 0.15
                p.effects.delayTime = 0.5
                p.effects.reverbMix = 0.4
                p.effects.reverbSize = 0.8
            },
            // Huge, slow pad: detuned saws, very slow swell and tail, a slowly breathing filter.
            make("Off-World Pad", .cinematic, tag: "Pad · huge and slow") { p in
                p.masterVolume = 0.6 // level-matched to the other factory presets
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -7)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: 0, detune: 8)
                p.filter = .init(cutoff: 850, resonance: 0.2, envAmount: 0.25)
                p.filterEnvelope = .init(attack: 2.5, decay: 3, sustain: 0.6, release: 4)
                p.ampEnvelope = .init(attack: 1.8, decay: 2, sustain: 1, release: 6)
                p.lfo = .init(destination: .cutoff, rate: 0.12, amount: 0.12)
                p.effects.chorusMix = 0.6
                p.effects.chorusRate = 0.4
                p.effects.reverbMix = 0.65
                p.effects.reverbSize = 0.95
            },
            // Smooth solo lead: saw + square, warm filter, slow vibrato (no glide or vibrato delay here).
            make("Neon Lead", .cinematic, tag: "Lead · singing vibrato") { p in
                p.masterVolume = 0.58 // level-matched to the other factory presets
                p.osc1 = .init(wave: .saw, level: 0.75, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.4, octave: 0, detune: 5)
                p.filter = .init(cutoff: 1300, resonance: 0.3, envAmount: 0.35)
                p.filterEnvelope = .init(attack: 0.15, decay: 0.8, sustain: 0.5, release: 0.8)
                p.ampEnvelope = .init(attack: 0.08, decay: 0.5, sustain: 0.9, release: 0.9)
                p.lfo = .init(destination: .pitch, rate: 4.5, amount: 0.1)
                p.effects.delayMix = 0.3
                p.effects.delayTime = 0.45
                p.effects.delayFeedback = 0.4
                p.effects.reverbMix = 0.35
            },
            // Lush string ensemble: two close saws through heavy, slow chorus and a big room.
            make("Pyramid Strings", .cinematic, tag: "Strings · lush chorus") { p in
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -6)
                p.osc2 = .init(wave: .saw, level: 0.6, octave: 1, detune: 6)
                p.filter = .init(cutoff: 2600, resonance: 0.05, envAmount: 0.1)
                p.filterEnvelope = .init(attack: 0.8, decay: 1, sustain: 0.8, release: 2.5)
                p.ampEnvelope = .init(attack: 0.7, decay: 1, sustain: 0.95, release: 2.5)
                p.effects.chorusMix = 0.9
                p.effects.chorusRate = 0.9
                p.effects.reverbMix = 0.5
                p.effects.reverbSize = 0.85
            },
            // Deep, round bass: saw an octave down over a sine sub, short soft filter blip.
            make("Replicant Bass", .cinematic, tag: "Bass · deep and round") { p in
                p.osc1 = .init(wave: .saw, level: 0.6, octave: -1, detune: 0)
                p.osc2 = .init(wave: .sine, level: 0.8, octave: -1, detune: 0)
                p.filter = .init(cutoff: 220, resonance: 0.2, envAmount: 0.45)
                p.filterEnvelope = .init(attack: 0.005, decay: 0.35, sustain: 0.15, release: 0.3)
                p.ampEnvelope = .init(attack: 0.005, decay: 0.5, sustain: 0.85, release: 0.4)
                p.effects.reverbMix = 0.15
            },
            // Evolving drone: square and saw drifting apart, a very slow resonant filter wave.
            make("Spinner Drift", .cinematic, tag: "Drone · slow drift") { p in
                p.masterVolume = 0.5 // level-matched to the other factory presets
                p.osc1 = .init(wave: .square, level: 0.6, octave: 0, detune: -4)
                p.osc2 = .init(wave: .saw, level: 0.6, octave: 0, detune: 11)
                p.filter = .init(cutoff: 500, resonance: 0.45, envAmount: 0.1)
                p.filterEnvelope = .init(attack: 2, decay: 3, sustain: 0.7, release: 4)
                p.ampEnvelope = .init(attack: 2.5, decay: 2, sustain: 1, release: 5)
                p.lfo = .init(destination: .cutoff, rate: 0.07, amount: 0.45)
                p.effects.chorusMix = 0.4
                p.effects.chorusRate = 0.3
                p.effects.delayMix = 0.2
                p.effects.delayTime = 0.75
                p.effects.delayFeedback = 0.5
                p.effects.reverbMix = 0.6
                p.effects.reverbSize = 0.9
            },
            // Dreamy bell-like electric piano: sine + triangle an octave up, quick decay, echoes.
            make("Memory Bells", .cinematic, tag: "Keys · bell-like") { p in
                p.osc1 = .init(wave: .sine, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .triangle, level: 0.45, octave: 1, detune: 7)
                p.filter = .init(cutoff: 4000, resonance: 0.1, envAmount: 0.2)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.6, sustain: 0.1, release: 1)
                p.ampEnvelope = .init(attack: 0.002, decay: 1.6, sustain: 0.2, release: 1.8)
                p.effects.chorusMix = 0.4
                p.effects.chorusRate = 0.7
                p.effects.delayMix = 0.3
                p.effects.delayTime = 0.5
                p.effects.delayFeedback = 0.45
                p.effects.reverbMix = 0.45
                p.effects.reverbSize = 0.85
            },
            // Hollow, vowel-like pad: two squares (fixed 50% pulse) with a soft resonant peak.
            make("Dusk Choir", .cinematic, tag: "Choir · hollow vowel") { p in
                p.masterVolume = 0.46 // level-matched to the other factory presets
                p.osc1 = .init(wave: .square, level: 0.65, octave: 0, detune: -8)
                p.osc2 = .init(wave: .square, level: 0.5, octave: 1, detune: 8)
                p.filter = .init(cutoff: 1100, resonance: 0.35, envAmount: 0.15)
                p.filterEnvelope = .init(attack: 1, decay: 1.5, sustain: 0.8, release: 3)
                p.ampEnvelope = .init(attack: 1, decay: 1, sustain: 1, release: 3)
                p.lfo = .init(destination: .pitch, rate: 4.5, amount: 0.05)
                p.effects.chorusMix = 0.7
                p.effects.chorusRate = 0.6
                p.effects.reverbMix = 0.65
                p.effects.reverbSize = 0.9
            },
            // Dramatic sweep: a resonant filter opens over about 3.5 seconds; resonance kept moderate.
            make("Cold Sweep", .cinematic, tag: "Sweep · dark to bright") { p in
                p.masterVolume = 0.42 // level-matched to the other factory presets
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -10)
                p.osc2 = .init(wave: .saw, level: 0.7, octave: 0, detune: 10)
                p.filter = .init(cutoff: 120, resonance: 0.75, envAmount: 0.9)
                p.filterEnvelope = .init(attack: 3.5, decay: 2, sustain: 0.7, release: 3)
                p.ampEnvelope = .init(attack: 0.8, decay: 1, sustain: 1, release: 3)
                p.effects.reverbMix = 0.55
                p.effects.reverbSize = 0.9
            },

            // MARK: Pattern presets (sound + sequencer + drums, original patterns)
            // Loading one swaps the sequencer banks, tempo and drums in on the next bar.

            // Tight, dry octave bass pulsing in straight sixteenths over a mechanical electro beat.
            make("Robot Pulse", .bass, tag: "Bass · robotic pulse") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.6, octave: -1, detune: 5)
                p.filter = .init(cutoff: 300, resonance: 0.35, envAmount: 0.6)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.16, sustain: 0.1, release: 0.1)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.22, sustain: 0.7, release: 0.08)
                p.lfo = .init(destination: .pitch, rate: 5, amount: 0)
                p.sequencer = sequence(tempo: 112, "A1 A1 A2 A1 A1 A1 A2 A1 C2 C2 C3 C2 G1 G1 G2 G1")
                p.drumKit = drumPattern { kit in
                    kit.kick = .init(level: 0.9, decay: 0.18, variant: 3)        // Punch
                    kit.snare = .init(level: 0.65, decay: 0.2, variant: 2)       // Electro
                    kit.closedHat = .init(level: 0.45, decay: 0.05, variant: 2)  // Metallic
                    kit.comp = 0.2
                    kit.drive = 0.1
                    hits(&kit, .kick, 1, 5, 9, 13)
                    hits(&kit, .snare, 5, 13)
                    hits(&kit, .closedHat, 3, 7, 11, 15)
                }
            },
            // Bright, rolling minor arpeggio (Am, F, G) with an echo, over a steady train-like beat.
            make("Neon Express", .arp, tag: "Arp · rolling express") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.6, octave: 0, detune: 7)
                p.filter = .init(cutoff: 2500, resonance: 0.25, envAmount: 0.4)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.22, sustain: 0.3, release: 0.2)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.25, sustain: 0.4, release: 0.2)
                p.lfo = .init(destination: .pitch, rate: 5, amount: 0)
                p.effects.delayTime = 0.375   // dotted eighth at 120 BPM
                p.effects.delayFeedback = 0.3
                p.effects.delayMix = 0.25
                p.effects.chorusMix = 0.2
                p.effects.chorusRate = 0.5
                p.sequencer = sequence(tempo: 120, "A3 C4 E4 C4 A3 C4 E4 C4 F3 A3 C4 A3 G3 B3 D4 B3")
                p.drumKit = drumPattern { kit in
                    kit.kick = .init(level: 0.9, decay: 0.18, variant: 3)        // Punch
                    kit.clap = .init(level: 0.6, decay: 0.1, variant: 3)         // Snap
                    kit.closedHat = .init(level: 0.4, decay: 0.05, variant: 2)   // Metallic
                    kit.openHat = .init(level: 0.35, decay: 0.15, variant: 1)    // Short
                    kit.comp = 0.2
                    kit.drive = 0.1
                    hits(&kit, .kick, 1, 5, 9, 13)
                    hits(&kit, .clap, 5, 13)
                    hits(&kit, .closedHat, 2, 4, 6, 8, 10, 12, 14, 16)
                    hits(&kit, .openHat, 16)
                }
            },
            // Clear, toy-like square melody with a gentle vibrato and echo; sparse beat, rim clicks at the end.
            make("Radio Wave", .lead, tag: "Lead · toy radio") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: 0, detune: 0)
                p.osc2 = .init(wave: .triangle, level: 0.4, octave: 1, detune: 0)
                p.filter = .init(cutoff: 3500, resonance: 0.1, envAmount: 0.1)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.3, sustain: 0.8, release: 0.25)
                p.ampEnvelope = .init(attack: 0.008, decay: 0.3, sustain: 0.7, release: 0.25)
                p.lfo = .init(destination: .pitch, rate: 5.5, amount: 0.05)
                p.effects.delayTime = 0.45    // dotted eighth at 100 BPM
                p.effects.delayFeedback = 0.35
                p.effects.delayMix = 0.3
                p.sequencer = sequence(tempo: 100, "A4 . C5 . E5 . C5 . D5 . . C5 . B4 . .")
                p.drumKit = drumPattern { kit in
                    kit.kick = .init(level: 0.85, decay: 0.18, variant: 3)       // Punch
                    kit.clap = .init(level: 0.55, decay: 0.1, variant: 3)        // Snap
                    kit.closedHat = .init(level: 0.25, decay: 0.03, variant: 3)  // Tick, quiet (no per-step accent)
                    kit.snare = .init(level: 0.5, tune: 7, decay: 0.06, variant: 3) // Rimshot tuned up: stands in for a tom
                    kit.comp = 0.2
                    kit.drive = 0.1
                    hits(&kit, .kick, 1, 9, 11)
                    hits(&kit, .clap, 5, 13)
                    hits(&kit, .closedHat, 1, 3, 5, 7, 9, 11, 13, 15)
                    hits(&kit, .snare, 15, 16)
                }
            },
            // Gritty, driven octave bass with gaps, over a heavy dry beat with metallic hits.
            make("Dark Pulse", .bass, tag: "Bass · gritty pulse") { p in
                p.osc1 = .init(wave: .saw, level: 0.8, octave: 0, detune: 0)
                p.osc2 = .init(wave: .square, level: 0.6, octave: -1, detune: -6)
                p.filter = .init(cutoff: 450, resonance: 0.45, envAmount: 0.5)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.14, sustain: 0.2, release: 0.08)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.2, sustain: 0.8, release: 0.06)
                p.lfo = .init(destination: .pitch, rate: 5, amount: 0)
                p.effects.driveAmount = 0.3
                p.sequencer = sequence(tempo: 118, "E1 E1 . E2 E1 . G1 . E1 E1 . E2 D1 . F1 G1")
                p.drumKit = drumPattern { kit in
                    kit.kick = .init(level: 0.95, decay: 0.25, variant: 2)          // Hard
                    kit.snare = .init(level: 0.7, decay: 0.25, variant: 2)          // Electro
                    kit.closedHat = .init(level: 0.4, decay: 0.05, variant: 2)      // Metallic
                    kit.openHat = .init(level: 0.35, tune: 5, decay: 0.15, variant: 2) // short metallic clang (no tom)
                    kit.comp = 0.3
                    kit.drive = 0.2
                    hits(&kit, .kick, 1, 4, 9, 11)
                    hits(&kit, .snare, 5, 13)
                    hits(&kit, .closedHat, 3, 7, 11, 15)
                    hits(&kit, .openHat, 14, 16)
                }
            },
            // Short, bright plucks bouncing through Em, Em7, C and Dm with chorus and a quick echo.
            make("Bright Bounce", .pluck, tag: "Pluck · bright bounce") { p in
                p.osc1 = .init(wave: .square, level: 0.7, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.6, octave: 0, detune: 5)
                p.filter = .init(cutoff: 3000, resonance: 0.15, envAmount: 0.35)
                p.filterEnvelope = .init(attack: 0.001, decay: 0.12, sustain: 0.2, release: 0.12)
                p.ampEnvelope = .init(attack: 0.001, decay: 0.16, sustain: 0.05, release: 0.12)
                p.lfo = .init(destination: .pitch, rate: 5, amount: 0)
                p.effects.chorusMix = 0.25
                p.effects.chorusRate = 0.8
                p.effects.delayTime = 0.227   // an eighth note at 132 BPM
                p.effects.delayFeedback = 0.25
                p.effects.delayMix = 0.2
                p.sequencer = sequence(tempo: 132, "E4 G4 B4 G4 E4 G4 B4 D5 C4 E4 G4 E4 D4 F4 A4 F4")
                p.drumKit = drumPattern { kit in
                    kit.kick = .init(level: 0.9, decay: 0.18, variant: 3)        // Punch
                    kit.clap = .init(level: 0.6, decay: 0.1, variant: 3)         // Snap
                    kit.closedHat = .init(level: 0.4, decay: 0.04, variant: 0)   // Crisp
                    kit.openHat = .init(level: 0.35, decay: 0.15, variant: 1)    // Short
                    kit.comp = 0.2
                    kit.drive = 0.1
                    hits(&kit, .kick, 1, 5, 9, 13)
                    hits(&kit, .clap, 5, 13)
                    hits(&kit, .closedHat, 2, 4, 6, 8, 10, 12, 14, 16)
                    hits(&kit, .openHat, 4, 8, 12)
                }
            },
            // Dark, wide saw pad slowly swelling through Em, Bm, G and A over a soft half-time beat.
            // Each chord note repeats on its four steps: the sequencer has no long notes, and a
            // repeated note keeps swelling instead of restarting, so it holds like one long note.
            make("Velvet Hymn", .pad, tag: "Pad · velvet slow") { p in
                p.osc1 = .init(wave: .saw, level: 0.9, octave: 0, detune: 0)
                p.osc2 = .init(wave: .saw, level: 0.9, octave: 0, detune: 9)
                p.masterVolume = 1   // level-matched: the slow swell is quieter than the other loops
                p.filter = .init(cutoff: 1200, resonance: 0.15, envAmount: 0.25)
                p.filterEnvelope = .init(attack: 0.6, decay: 0.8, sustain: 0.6, release: 0.9)
                p.ampEnvelope = .init(attack: 0.5, decay: 0.6, sustain: 0.8, release: 1.4)
                p.lfo = .init(destination: .cutoff, rate: 0.3, amount: 0.15)
                p.effects.chorusMix = 0.6
                p.effects.chorusRate = 0.4
                p.effects.reverbSize = 0.85
                p.effects.reverbMix = 0.45
                p.effects.delayTime = 0.556   // a quarter note at 108 BPM
                p.effects.delayFeedback = 0.3
                p.effects.delayMix = 0.15
                p.sequencer = sequence(tempo: 108, "E3 E3 E3 E3 B3 B3 B3 B3 G3 G3 G3 G3 A3 A3 A3 A3")
                p.drumKit = drumPattern { kit in
                    kit.kick = .init(level: 0.7, decay: 0.4, variant: 0)          // House, softer
                    kit.snare = .init(level: 0.45, decay: 0.22, variant: 4)       // Lo-fi, soft
                    kit.closedHat = .init(level: 0.25, decay: 0.05, variant: 1)   // Soft
                    kit.clap = .init(level: 0.25, tune: -12, decay: 0.08, variant: 1) // low, quiet thud (no tom)
                    kit.comp = 0.15
                    kit.drive = 0
                    hits(&kit, .kick, 1, 11)
                    hits(&kit, .snare, 9)
                    hits(&kit, .closedHat, 3, 7, 11, 15)
                    hits(&kit, .clap, 14)
                }
            },
            // Slow, haunting film-score theme (in the spirit of early-80s Vangelis): brassy detuned saws
            // with a swelling filter, vibrato and a huge reverb. The lead runs over all 8 banks (Dm, Bbmaj7,
            // Gm, A, two bars each); play the chords on the keys. Drum banks: A slow pulse, B with a crash
            // swell, C a big impact, D tom fill, E ending hit.
            make("Glass City", .cinematic, tag: "Theme · 8-bank film score") { p in
                p.osc1 = .init(wave: .saw, level: 0.7, octave: 0, detune: -8)
                p.osc2 = .init(wave: .saw, level: 0.6, octave: 0, detune: 8)
                p.filter = .init(cutoff: 1400, resonance: 0.2, envAmount: 0.45)
                p.filterEnvelope = .init(attack: 0.35, decay: 1.2, sustain: 0.5, release: 2.0)
                p.ampEnvelope = .init(attack: 0.06, decay: 1.0, sustain: 0.8, release: 2.2)
                p.lfo = .init(destination: .pitch, rate: 5.2, amount: 0.05)
                p.effects.delayTime = 0.643   // dotted eighth at 70 BPM
                p.effects.delayFeedback = 0.45
                p.effects.delayMix = 0.25
                p.effects.reverbSize = 0.95
                p.effects.reverbMix = 0.45
                p.effects.chorusRate = 0.4
                p.effects.chorusMix = 0.6
                p.sequencer = sequence(tempo: 70, "D5 . . . . . E5 . F5 . . . E5 . . .")
                let lead = [
                    "D5 . . . . . . . A4 . . . . . . .",
                    "D5 . . . . . F5 . A5 . . . G5 . . .",
                    "F5 . . . . . . . D5 . . . . . . .",
                    "D5 . . . . . A#4 . D5 . . . G5 . . .",
                    "F5 . . . . . . . D5 . . . . . . .",
                    "C#5 . . . . . E5 . A5 . . . G5 . . .",
                    "E5 . . . . . . . C#5 . . . . . . .",
                ]
                for (i, bank) in lead.enumerated() { p.sequencer.banks[i + 1] = parse(bank) }
                p.drumKit = drumPattern { kit in
                    kit.kick = .init(level: 0.9, tune: -3, decay: 1.4, variant: 4)     // Boom
                    kit.tomLo = .init(level: 0.75, tune: -3, decay: 1.0, variant: 1)   // Deep, timpani-like
                    kit.tomHi = .init(level: 0.65, tune: -2, decay: 0.8, variant: 1)
                    kit.crash = .init(level: 0.4, tune: -2, decay: 2.8, variant: 4)    // Wash
                    kit.fx = .init(level: 0.45, tune: -6, decay: 1.6, variant: 2)      // Drop: a deep impact
                    kit.volume = 0.8
                    kit.reverbSend = 0.55
                    kit.delaySend = 0.1
                    kit.comp = 0.3
                    kit.drive = 0
                    hits(&kit, .kick, 1, 11)
                    hits(&kit, .tomLo, 13)
                    hits(&kit, bank: 1, .kick, 1, 11)
                    hits(&kit, bank: 1, .tomLo, 13)
                    hits(&kit, bank: 1, .crash, 1)
                    hits(&kit, bank: 2, .kick, 1, 11)
                    hits(&kit, bank: 2, .fx, 1)
                    hits(&kit, bank: 2, .crash, 1)
                    hits(&kit, bank: 3, .kick, 1)
                    hits(&kit, bank: 3, .tomLo, 9, 13, 15)
                    hits(&kit, bank: 3, .tomHi, 11, 14, 16)
                    hits(&kit, bank: 4, .kick, 1)
                    hits(&kit, bank: 4, .crash, 1)
                    hits(&kit, bank: 4, .fx, 1)
                }
            },
        ]
    }

    // MARK: - Helpers

    /// A drum kit for a pattern preset: everything in bank A, the other banks empty, A active.
    private static func drumPattern(_ configure: (inout DrumKit) -> Void) -> DrumKit {
        var kit = DrumKit()
        configure(&kit)
        kit.activeBank = 0
        return kit
    }

    /// Turns on `drum` at the given steps (1...16) in bank A.
    private static func hits(_ kit: inout DrumKit, _ drum: DrumKind, _ steps: Int...) {
        for step in steps where (1...SynthPatch.stepCount).contains(step) {
            kit.banks[0][drum.rawValue][step - 1] = true
        }
    }

    /// Turns on `drum` at the given steps (1...16) in another bank (0 = A ... 7 = H).
    private static func hits(_ kit: inout DrumKit, bank: Int, _ drum: DrumKind, _ steps: Int...) {
        for step in steps where (1...SynthPatch.stepCount).contains(step) {
            kit.banks[bank][drum.rawValue][step - 1] = true
        }
    }

    private static func make(_ name: LocalizedStringResource, _ category: PresetCategory, tag: LocalizedStringResource, _ configure: (inout SynthPatch) -> Void) -> SynthPatch {
        var patch = SynthPatch()
        patch.name = String(localized: name)
        patch.category = category
        patch.tag = String(localized: tag)
        configure(&patch)
        return patch
    }

    private static func sequence(tempo: Float, swing: Float = 0, _ pattern: String) -> SynthPatch.Sequencer {
        var sequencer = SynthPatch.Sequencer()
        sequencer.tempo = tempo
        sequencer.swing = swing
        let notes = parse(pattern)
        sequencer.length = min(max(notes.count, 4), SynthPatch.stepCount)
        sequencer.steps = Array((notes + Array(repeating: nil, count: SynthPatch.stepCount)).prefix(SynthPatch.stepCount))
        return sequencer
    }

    /// "C3 . D#3 C4*4" → [48, nil, 51, 60, 60, 60, 60]
    static func parse(_ pattern: String) -> [Int?] {
        let names = ["C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11]
        var steps: [Int?] = []
        for token in pattern.split(separator: " ") {
            let parts = token.split(separator: "*")
            let repeats = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            let symbol = String(parts[0])
            var note: Int?
            if symbol != ".", let octave = Int(symbol.drop { !$0.isNumber && $0 != "-" }),
               let pitch = names[String(symbol.prefix { !$0.isNumber && $0 != "-" })] {
                note = (octave + 1) * 12 + pitch
            }
            steps += Array(repeating: note, count: repeats)
        }
        return steps
    }
}

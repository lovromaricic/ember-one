import Testing
@testable import Ember_One

/// The Drums tab's two dice: "Randomize pattern" changes only the selected bank's steps,
/// "Randomize drum sounds" changes only each drum's variant, tuning and decay. Pure functions,
/// the same ones the buttons and their Undo use.
struct DrumRandomizerTests {
    struct SeededRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    /// A kit with non-default sounds, levels, mutes, bus settings and patterns in two banks.
    static func sampleKit() -> DrumKit {
        var kit = DrumKit()
        kit.kick = .init(level: 0.83, tune: 2, decay: 0.3, muted: false, variant: 3)
        kit.snare = .init(level: 0.61, tune: -1, decay: 0.2, muted: true, variant: 2)
        kit.clap = .init(level: 0.44, tune: 0, decay: 0.15, muted: false, variant: 1)
        kit.closedHat = .init(level: 0.37, tune: 3, decay: 0.05, muted: false, variant: 4)
        kit.openHat = .init(level: 0.29, tune: -2, decay: 0.4, muted: false, variant: 0)
        kit.volume = 0.72
        kit.reverbSend = 0.2
        kit.delaySend = 0.1
        kit.comp = 0.35
        kit.drive = 0.15
        kit.banks[0][0][0] = true
        kit.banks[0][1][4] = true
        kit.banks[2][3][6] = true
        kit.activeBank = 2
        return kit
    }

    static func sounds(_ kit: DrumKit) -> [[Float]] {
        DrumKind.allCases.map { [Float(kit[$0].variant), kit[$0].tune, kit[$0].decay] }
    }

    static func levelsAndMutes(_ kit: DrumKit) -> [[Float]] {
        DrumKind.allCases.map { [kit[$0].level, kit[$0].muted ? 1 : 0] }
    }

    @Test func patternRandomizeLeavesSoundsUnchanged() {
        var random = SeededRandom(state: 3)
        let before = Self.sampleKit()
        for _ in 0..<50 {
            var kit = before
            let bank = kit.activeBank
            kit.banks[bank] = PatternRandomizer.beat(using: &random) // what the pattern dice does
            #expect(Self.sounds(kit) == Self.sounds(before))
            #expect(Self.levelsAndMutes(kit) == Self.levelsAndMutes(before))
            #expect(kit.volume == before.volume && kit.comp == before.comp && kit.drive == before.drive)
            #expect(kit.reverbSend == before.reverbSend && kit.delaySend == before.delaySend)
            // Other banks are untouched.
            for other in kit.banks.indices where other != bank { #expect(kit.banks[other] == before.banks[other]) }
        }
    }

    @Test func patternUndoRestoresTheBank() {
        var random = SeededRandom(state: 4)
        let original = Self.sampleKit()
        let bank = original.activeBank
        let saved = original.banks[bank] // what the button keeps for Undo
        var kit = original
        kit.banks[bank] = PatternRandomizer.beat(using: &random)
        kit.banks[bank] = saved          // Undo
        #expect(kit == original)
    }

    @Test func soundRandomizeLeavesPatternAndLevelsUnchanged() {
        var random = SeededRandom(state: 5)
        let before = Self.sampleKit()
        var changed = false
        for _ in 0..<50 {
            let kit = PatternRandomizer.drumSounds(for: before, using: &random)
            #expect(kit.banks == before.banks)
            #expect(kit.activeBank == before.activeBank)
            #expect(Self.levelsAndMutes(kit) == Self.levelsAndMutes(before))
            #expect(kit.volume == before.volume && kit.comp == before.comp && kit.drive == before.drive)
            #expect(kit.reverbSend == before.reverbSend && kit.delaySend == before.delaySend)
            #expect(kit.enabled == before.enabled)
            changed = changed || Self.sounds(kit) != Self.sounds(before)
        }
        #expect(changed)
    }

    @Test func soundUndoRestoresOnlyTheSounds() {
        var random = SeededRandom(state: 6)
        let original = Self.sampleKit()
        var kit = PatternRandomizer.drumSounds(for: original, using: &random)
        // The user changes something else before tapping Undo: it must survive the Undo.
        kit.banks[0][4][15] = true
        kit.kick.level = 0.5
        let undone = kit.withSounds(from: original)
        #expect(Self.sounds(undone) == Self.sounds(original))
        #expect(undone.banks == kit.banks)
        #expect(undone.kick.level == 0.5)
    }

    @Test func randomSoundsStayInSafeRanges() {
        var random = SeededRandom(state: 7)
        for _ in 0..<500 {
            let kit = PatternRandomizer.drumSounds(for: DrumKit(), using: &random)
            for drum in DrumKind.allCases {
                let voice = kit[drum]
                #expect((0..<DrumVariants.count).contains(voice.variant))
                #expect(PatternRandomizer.tuneRange(drum).contains(voice.tune))
                #expect(voice.tune == voice.tune.rounded())
                #expect(PatternRandomizer.decayRange(drum, voice.variant).contains(voice.decay))
                // Inside the drum's own knob range too, so the knobs show it correctly.
                #expect(DrumVariants.decayRange(drum, voice.variant).contains(voice.decay))
                #expect(SynthParam.drumTune(drum).range.contains(voice.tune))
            }
        }
    }
}

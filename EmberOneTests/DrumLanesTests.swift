import Foundation
import Testing
@testable import Ember_One

/// The ten-lane drum kit: kits saved with five lanes still load, the five extra lanes
/// (Tom Lo, Tom Hi, Rim, Cowbell, Ride) are saved with presets, and banks, Copy, Paste,
/// Clear, both Randomize buttons and their Undo cover all ten lanes.
struct DrumLanesTests {
    typealias SeededRandom = DrumRandomizerTests.SeededRandom

    static let newDrums: [DrumKind] = [.tomLo, .tomHi, .rim, .cowbell, .ride]

    /// A kit with non-default sounds and steps on all ten lanes, in two banks.
    static func fullKit() -> DrumKit {
        var kit = DrumRandomizerTests.sampleKit()
        kit.tomLo = .init(level: 0.66, tune: -3, decay: 0.4, muted: false, variant: 1)
        kit.tomHi = .init(level: 0.58, tune: 2, decay: 0.2, muted: true, variant: 2)
        kit.rim = .init(level: 0.47, tune: 1, decay: 0.05, muted: false, variant: 3)
        kit.cowbell = .init(level: 0.39, tune: -2, decay: 0.5, muted: false, variant: 4)
        kit.ride = .init(level: 0.33, tune: 3, decay: 1.4, muted: false, variant: 1)
        for (i, drum) in newDrums.enumerated() {
            kit.banks[0][drum.rawValue][i * 3] = true
            kit.banks[5][drum.rawValue][15 - i] = true
        }
        return kit
    }

    /// The kit as an app from before the extra drums saved it: five voices, five rows per bank.
    static func fiveLaneJSON(_ kit: DrumKit) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(kit)) as? [String: Any])
        for drum in newDrums { object[String(describing: drum)] = nil }
        let banks = try #require(object["banks"] as? [[[Bool]]])
        object["banks"] = banks.map { Array($0.prefix(DrumKind.originalCount)) }
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func rows(_ kit: DrumKit, _ drums: [DrumKind]) -> [[[Bool]]] {
        kit.banks.map { bank in drums.map { bank[$0.rawValue] } }
    }

    // MARK: - Loading and saving

    @Test func kitHasTenLanesInOrder() {
        #expect(DrumKind.allCases == [.kick, .snare, .clap, .closedHat, .openHat, .tomLo, .tomHi, .rim, .cowbell, .ride])
        #expect(DrumKit().banks.count == SynthPatch.bankCount)
        #expect(DrumKit().banks.allSatisfy { $0.count == 10 && $0.allSatisfy { $0.count == SynthPatch.stepCount } })
    }

    @Test func fiveLaneKitLoadsWithEmptyNewLanes() throws {
        var old = DrumRandomizerTests.sampleKit()
        old.banks[7][2][9] = true
        let data = try Self.fiveLaneJSON(old)
        // Every load path decodes, then sanitizes.
        let kit = try JSONDecoder().decode(DrumKit.self, from: data).sanitized()

        #expect(kit.banks.count == SynthPatch.bankCount)
        #expect(kit.banks.allSatisfy { $0.count == DrumKind.count && $0.allSatisfy { $0.count == SynthPatch.stepCount } })
        // The old five lanes and sounds come back exactly.
        let oldDrums = Array(DrumKind.allCases.prefix(DrumKind.originalCount))
        #expect(Self.rows(kit, oldDrums) == Self.rows(old, oldDrums))
        for drum in oldDrums { #expect(kit[drum] == old[drum]) }
        #expect(kit.activeBank == old.activeBank && kit.volume == old.volume && kit.drive == old.drive)
        // The new lanes are empty, with the default sounds.
        for drum in Self.newDrums {
            #expect(kit.banks.allSatisfy { !$0[drum.rawValue].contains(true) })
            #expect(kit[drum] == DrumKit()[drum])
        }
    }

    @Test func singlePatternKitLoadsWithEmptyNewLanes() throws {
        // The oldest format: one five-row pattern under "pattern", no banks.
        var pattern = Array(repeating: Array(repeating: false, count: 16), count: 5)
        pattern[0][0] = true
        pattern[4][14] = true
        let data = try JSONSerialization.data(withJSONObject: ["pattern": pattern, "kick": ["level": 0.8, "decay": 0.4]])
        let kit = try JSONDecoder().decode(DrumKit.self, from: data).sanitized()
        #expect(kit.banks[0].count == DrumKind.count)
        #expect(kit.banks[0][0][0] && kit.banks[0][4][14])
        #expect(kit.banks.joined().joined().filter { $0 }.count == 2)
        for drum in Self.newDrums { #expect(kit[drum] == DrumKit()[drum]) }
    }

    @Test func newLanesAreSavedAndRestoredInPresets() throws {
        var patch = SynthPatch()
        patch.name = "Ten lanes"
        patch.drumKit = Self.fullKit()
        let data = try JSONEncoder().encode(patch)
        let loaded = try JSONDecoder().decode(SynthPatch.self, from: data).sanitized()
        #expect(loaded.drumKit == Self.fullKit())

        // The drum kit file (DrumKitStore) uses the same encoding.
        let kit = try JSONDecoder().decode(DrumKit.self, from: JSONEncoder().encode(Self.fullKit())).sanitized()
        #expect(kit == Self.fullKit())
    }

    @Test func newDrumParametersReadAndWrite() {
        var kit = DrumKit()
        for drum in Self.newDrums {
            kit.setValue(0.42, for: .drumLevel(drum))
            kit.setValue(5, for: .drumTune(drum))
            kit.setValue(1, for: .drumMute(drum))
            kit.setValue(3, for: .drumVariant(drum))
            #expect(kit[drum].level == 0.42 && kit[drum].tune == 5 && kit[drum].muted && kit[drum].variant == 3)
            #expect(kit.value(for: .drumVariant(drum)) == 3)
            #expect(SynthParam.drumLevel(drum).drum == drum)
            #expect(SynthParam.drumVariant(drum).variantDrum == drum)
            #expect(SynthParam.drumDecay(drum).range == drum.decayKnobRange)
        }
        // Each new drum has its own parameters, apart from the old drums' and from each other.
        let indexes = DrumKind.allCases.flatMap { drum in
            [SynthParam.drumLevel(drum), .drumTune(drum), .drumDecay(drum), .drumMute(drum), .drumVariant(drum)].map(\.rawValue)
        }
        #expect(Set(indexes).count == indexes.count)
        // Old parameter numbers (stored by MIDI Learn) didn't move.
        #expect(SynthParam.kickLevel.rawValue == SynthParam.drumBaseIndex(0))
        #expect(SynthParam.openHatVariant.rawValue == SynthParam.drumVariantIndex(4))
    }

    // MARK: - Banks, Copy, Paste, Clear (the engine's own methods; no audio is started)

    @MainActor
    @Test func copyPasteClearAndBanksCoverTenLanes() async throws {
        let saved = try? Data(contentsOf: DrumKitStore.url)
        let synth = SynthEngine()
        synth.loadDrums(Self.fullKit())

        // Copy bank A (the buttons store `drumBankPattern`) and paste it into bank D.
        synth.drumBankClipboard = synth.drumBankPattern(0)
        #expect(synth.drumBankClipboard?.count == DrumKind.count)
        synth.setDrumBankPattern(3, try #require(synth.drumBankClipboard))
        #expect(synth.drums.banks[3] == Self.fullKit().banks[0])
        for drum in Self.newDrums { #expect(synth.drums.banks[3][drum.rawValue].contains(true)) }

        // Pasting a five-row clipboard (e.g. from an older build) leaves the new lanes empty.
        synth.setDrumBankPattern(4, Array(Self.fullKit().banks[0].prefix(5)))
        #expect(synth.drums.banks[4].count == DrumKind.count)
        for drum in Self.newDrums { #expect(!synth.drums.banks[4][drum.rawValue].contains(true)) }

        // Clear empties all ten lanes of that bank only.
        synth.setDrumBankPattern(0, DrumKit.emptyPattern)
        #expect(synth.drums.banks[0].allSatisfy { !$0.contains(true) && $0.count == SynthPatch.stepCount })
        #expect(synth.drums.banks[0].count == DrumKind.count)
        #expect(synth.drums.banks[5] == Self.fullKit().banks[5])

        // Switching banks shows that bank's ten lanes.
        synth.selectDrumBank(5)
        #expect(synth.drums.pattern == Self.fullKit().banks[5])
        for drum in Self.newDrums { #expect(synth.drums.pattern[drum.rawValue].contains(true)) }

        // The engine saves the kit shortly after a change: put the app's own kit back.
        try await Task.sleep(for: .milliseconds(600))
        if let saved { try saved.write(to: DrumKitStore.url, options: .atomic) } else { try? FileManager.default.removeItem(at: DrumKitStore.url) }
    }

    // MARK: - Randomize and Undo

    @Test func randomPatternUsesNewLanesSparselyAndInPlace() {
        var random = SeededRandom(state: 11)
        var used = Set<DrumKind>()
        for _ in 0..<2000 {
            let beat = PatternRandomizer.beat(using: &random)
            #expect(beat.count == DrumKind.count)
            #expect(beat.allSatisfy { $0.count == SynthPatch.stepCount })
            func steps(_ drum: DrumKind) -> [Int] { beat[drum.rawValue].indices.filter { beat[drum.rawValue][$0] } }
            #expect(steps(.tomLo).allSatisfy { (12...15).contains($0) })
            #expect(steps(.tomHi).allSatisfy { (12...15).contains($0) })
            #expect(steps(.tomLo).count + steps(.tomHi).count <= 2)
            #expect(Set(steps(.rim)).isSubset(of: [3, 7, 10, 11, 15]) && steps(.rim).count <= 2)
            #expect(Set(steps(.cowbell)).isSubset(of: [0, 2, 6, 8, 10]) && steps(.cowbell).count <= 2)
            #expect(steps(.ride).isEmpty || steps(.ride) == [0, 4, 8, 12])
            if !steps(.ride).isEmpty { #expect(steps(.openHat).isEmpty) } // ride replaces the open hat
            // Kick on 1 and a backbeat as before.
            #expect(beat[DrumKind.kick.rawValue][0])
            for drum in Self.newDrums where !steps(drum).isEmpty { used.insert(drum) }
        }
        #expect(used == Set(Self.newDrums))
    }

    @Test func randomPatternLeavesNewSoundsUnchanged() {
        var random = SeededRandom(state: 12)
        let before = Self.fullKit()
        for _ in 0..<50 {
            var kit = before
            kit.banks[kit.activeBank] = PatternRandomizer.beat(using: &random)
            for drum in DrumKind.allCases { #expect(kit[drum] == before[drum]) }
            for other in kit.banks.indices where other != kit.activeBank { #expect(kit.banks[other] == before.banks[other]) }
        }
    }

    @Test func randomSoundsChangeNewDrumsOnlyInTheirScope() {
        var random = SeededRandom(state: 13)
        let before = Self.fullKit()
        var variantsSeen: [DrumKind: Set<Int>] = [:]
        for _ in 0..<300 {
            let kit = PatternRandomizer.drumSounds(for: before, using: &random)
            #expect(kit.banks == before.banks)
            for drum in Self.newDrums {
                let voice = kit[drum]
                #expect(voice.level == before[drum].level && voice.muted == before[drum].muted)
                #expect(PatternRandomizer.tuneRange(drum).contains(voice.tune))
                #expect(SynthParam.drumTune(drum).range.contains(voice.tune))
                #expect(PatternRandomizer.decayRange(drum, voice.variant).contains(voice.decay))
                #expect(DrumVariants.decayRange(drum, voice.variant).contains(voice.decay))
                #expect(drum.decayKnobRange.contains(voice.decay))
                variantsSeen[drum, default: []].insert(voice.variant)
            }
        }
        for drum in Self.newDrums { #expect(variantsSeen[drum] == Set(0..<DrumVariants.count)) }
    }

    @Test func patternUndoRestoresAllTenLanes() {
        var random = SeededRandom(state: 14)
        let original = Self.fullKit()
        var kit = original
        let bank = 0
        let saved = kit.banks[bank] // what the button keeps for Undo
        kit.banks[bank] = PatternRandomizer.beat(using: &random)
        kit.banks[bank] = saved     // Undo
        #expect(kit == original)
        for drum in Self.newDrums { #expect(kit.banks[bank][drum.rawValue].contains(true)) }
    }

    @Test func soundUndoRestoresAllTenDrums() {
        var random = SeededRandom(state: 15)
        let original = Self.fullKit()
        let randomized = PatternRandomizer.drumSounds(for: original, using: &random)
        #expect(Self.newDrums.contains { randomized[$0] != original[$0] })
        let undone = randomized.withSounds(from: original)
        #expect(undone == original)
    }

    @MainActor
    @Test func clearUndoRestoresAllTenLanes() async throws {
        let saved = try? Data(contentsOf: DrumKitStore.url)
        let synth = SynthEngine()
        synth.loadDrums(Self.fullKit())
        let before = synth.drumBankPattern(0) // what Clear keeps for Undo
        synth.setDrumBankPattern(0, DrumKit.emptyPattern)
        synth.setDrumBankPattern(0, before)   // Undo
        #expect(synth.drums.banks == Self.fullKit().banks)

        try await Task.sleep(for: .milliseconds(600))
        if let saved { try saved.write(to: DrumKitStore.url, options: .atomic) } else { try? FileManager.default.removeItem(at: DrumKitStore.url) }
    }
}

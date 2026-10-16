import Testing
@testable import Ember_One

/// The "Glass City" factory preset: a slow film-score theme spread over all eight banks.
struct GlassCityPresetTests {
    static func preset() throws -> SynthPatch {
        try #require(FactoryPresets.all.first { $0.name == "Glass City" })
    }

    @Test func soundAndTempo() throws {
        let p = try Self.preset()
        #expect(p.category == .cinematic)
        #expect(p.sequencer.tempo == 70)
        #expect(p.sanitized() == p) // every value is in range
    }

    @Test func leadRunsOverAllEightBanks() throws {
        let p = try Self.preset()
        #expect(p.sequencer.banks.count == SynthPatch.bankCount)
        #expect(p.sequencer.banks.allSatisfy { $0.count == SynthPatch.stepCount && $0.contains { $0 != nil } })
        #expect(p.sequencer.banks[0][0] == 74) // D5, the theme's first note
        #expect(p.sequencer.activeBank == 0)
    }

    @Test func drumBanks() throws {
        let kit = try #require(try Self.preset().drumKit)
        for bank in 0..<5 { #expect(kit.banks[bank].contains { $0.contains(true) }) }
        for bank in 5..<8 { #expect(!kit.banks[bank].contains { $0.contains(true) }) }
        #expect(kit.activeBank == 0)
        #expect(kit.banks[2][DrumKind.fx.rawValue][0]) // bank C: the big impact
    }
}

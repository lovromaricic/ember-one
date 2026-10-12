import Testing
@testable import Ember_One

/// The sequencer's Randomize button: pressing it again and again keeps the melody in the
/// preset's register and key instead of creeping up (or down) an octave at a time.
struct MelodyRandomizerTests {
    typealias SeededRandom = DrumRandomizerTests.SeededRandom

    /// Presses the dice `times` times, starting from `steps`, like the button does.
    static func roll(_ steps: [Int?], category: PresetCategory, times: Int, seed: UInt64) -> [[Int?]] {
        var random = SeededRandom(state: seed)
        var current = steps
        var results: [[Int?]] = []
        for _ in 0..<times {
            let root = PatternRandomizer.root(for: current, category: category)
            current = PatternRandomizer.melody(root: root, using: &random)
            results.append(current)
        }
        return results
    }

    @Test(arguments: [PresetCategory.lead, .bass], [UInt64(1), 2, 3, 4, 5])
    func repeatedRandomizeDoesNotDrift(category: PresetCategory, seed: UInt64) {
        let home = category == .bass ? 33 : 57
        let rolls = Self.roll(Array(repeating: nil, count: 16), category: category, times: 300, seed: seed)
        for steps in rolls {
            let notes = steps.compactMap { $0 }
            // Root ±6, the octave above it, and an occasional octave jump either way.
            #expect(notes.allSatisfy { $0 >= home - 6 - 12 && $0 <= home + 5 + 24 })
        }
        // The first note (the root) stays put after hundreds of presses.
        #expect(rolls.map { $0[0]! }.allSatisfy { abs($0 - home) <= 6 })
    }

    @Test func keepsTheKeyOfTheBank() {
        // A riff in E (most frequent note E5) is re-rolled in E, in the lead register.
        let riff: [Int?] = [76, nil, 76, 79, nil, 76, 81, nil, 76, nil, nil, nil, nil, nil, nil, nil]
        let root = PatternRandomizer.root(for: riff, category: .lead)
        #expect(root % 12 == 76 % 12)
        #expect(abs(root - 57) <= 6)
        // Bass: same key, bass register.
        let bassRoot = PatternRandomizer.root(for: riff, category: .bass)
        #expect(bassRoot % 12 == 76 % 12 && abs(bassRoot - 33) <= 6)
    }

    @Test func emptyBankStartsOnA() {
        #expect(PatternRandomizer.root(for: Array(repeating: nil, count: 16), category: .lead) == 57)
        #expect(PatternRandomizer.root(for: Array(repeating: nil, count: 16), category: .bass) == 33)
    }
}

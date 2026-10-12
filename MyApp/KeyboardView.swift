import SwiftUI

/// One-octave keyboard (C to the next C). Each key is its own touch target,
/// so several fingers can hold several keys at once.
struct KeyboardView: View {
    /// MIDI note of the leftmost C.
    let baseNote: Int
    let noteOn: (Int) -> Void
    let noteOff: (Int) -> Void

    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11, 12]
    /// Black key semitone offset and the white key it sits after.
    private static let blackKeys: [(offset: Int, afterWhite: Int)] = [(1, 0), (3, 1), (6, 3), (8, 4), (10, 5)]

    var body: some View {
        GeometryReader { geo in
            let whiteWidth = geo.size.width / CGFloat(Self.whiteOffsets.count)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Self.whiteOffsets, id: \.self) { offset in
                        PianoKey(note: baseNote + offset, isBlack: false, noteOn: noteOn, noteOff: noteOff)
                            .padding(.horizontal, 1)
                            .frame(width: whiteWidth)
                    }
                }
                ForEach(Self.blackKeys, id: \.offset) { key in
                    PianoKey(note: baseNote + key.offset, isBlack: true, noteOn: noteOn, noteOff: noteOff)
                        .frame(width: whiteWidth * 0.62, height: geo.size.height * 0.6)
                        .offset(x: whiteWidth * CGFloat(key.afterWhite + 1) - whiteWidth * 0.31)
                }
            }
        }
    }
}

private struct PianoKey: View {
    let note: Int
    let isBlack: Bool
    let noteOn: (Int) -> Void
    let noteOff: (Int) -> Void

    /// Resets automatically if the touch is cancelled, so a note can't get stuck.
    @GestureState private var isPressed = false
    /// The note that started sounding, in case the octave changes while the key is held.
    @State private var soundingNote: Int?

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
            .fill(fill)
            .overlay(alignment: .bottom) {
                if note % 12 == 0 {
                    Text(verbatim: "C\(note / 12 - 1)")
                        .font(Retro.label(10))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.bottom, 6)
                }
            }
            .overlay {
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .stroke(.black.opacity(0.6), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isBlack ? 0.5 : 0), radius: 2, y: 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, pressed, _ in pressed = true }
            )
            .onChange(of: isPressed) { _, pressed in
                if pressed {
                    soundingNote = note
                    noteOn(note)
                } else if let soundingNote {
                    noteOff(soundingNote)
                    self.soundingNote = nil
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Key \(Self.noteName(note))"))
            .accessibilityAddTraits(.isButton)
    }

    static func noteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[note % 12])\(note / 12 - 1)"
    }

    private var fill: some ShapeStyle {
        if isBlack {
            return isPressed ? AnyShapeStyle(Retro.accent) : AnyShapeStyle(LinearGradient(colors: [.black, Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
        }
        return isPressed ? AnyShapeStyle(Retro.accent.opacity(0.85)) : AnyShapeStyle(LinearGradient(colors: [Retro.cream, .white], startPoint: .top, endPoint: .bottom))
    }
}

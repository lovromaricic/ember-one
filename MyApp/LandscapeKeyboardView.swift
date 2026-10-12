import SwiftUI
import UIKit

/// Keyboard shown in landscape, below the transport bar. One touch layer follows every finger, so chords
/// work and sliding across the keys plays each key and releases the one before.
struct LandscapeKeyboardView: View {
    /// Octaves shown (plus the top C).
    static let octaves = 2

    /// MIDI note of the leftmost C.
    let baseNote: Int
    let noteOn: (Int) -> Void
    let noteOff: (Int) -> Void

    /// Keys held right now, for the orange light.
    @State private var pressed: Set<Int> = []

    private static let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
    /// Black key semitone offset and the white key (within the octave) it sits after.
    private static let blackKeys: [(offset: Int, afterWhite: Int)] = [(1, 0), (3, 1), (6, 3), (8, 4), (10, 5)]
    /// Black keys reach this far down the white keys.
    private static let blackHeight: CGFloat = 0.6
    private static let blackWidth: CGFloat = 0.62

    /// Every white key's note, left to right (all octaves, then the top C).
    private var whiteNotes: [Int] {
        (0..<Self.octaves).flatMap { octave in Self.whiteOffsets.map { baseNote + octave * 12 + $0 } }
            + [baseNote + Self.octaves * 12]
    }

    /// Every black key: its note and the white key index it sits after.
    private var blackNotes: [(note: Int, afterWhite: Int)] {
        (0..<Self.octaves).flatMap { octave in
            Self.blackKeys.map { (baseNote + octave * 12 + $0.offset, octave * 7 + $0.afterWhite) }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let whites = whiteNotes
            let blacks = blackNotes
            let whiteWidth = geo.size.width / CGFloat(whites.count)
            let blackWidth = whiteWidth * Self.blackWidth
            let blackHeight = geo.size.height * Self.blackHeight
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whites, id: \.self) { note in
                        KeyShape(note: note, isBlack: false, isPressed: pressed.contains(note))
                            .padding(.horizontal, 1)
                            .frame(width: whiteWidth)
                    }
                }
                ForEach(blacks, id: \.note) { key in
                    KeyShape(note: key.note, isBlack: true, isPressed: pressed.contains(key.note))
                        .frame(width: blackWidth, height: blackHeight)
                        .offset(x: whiteWidth * CGFloat(key.afterWhite + 1) - blackWidth / 2)
                }
                KeyTouchSurface(
                    note: { point in
                        // Black keys sit on top, so they win in their area.
                        if point.y < blackHeight {
                            for key in blacks {
                                let left = whiteWidth * CGFloat(key.afterWhite + 1) - blackWidth / 2
                                if point.x >= left, point.x < left + blackWidth { return key.note }
                            }
                        }
                        let index = Int(point.x / whiteWidth)
                        return whites.indices.contains(index) && point.y >= 0 && point.y <= geo.size.height ? whites[index] : nil
                    },
                    press: { note in
                        pressed.insert(note)
                        noteOn(note)
                    },
                    release: { note in
                        pressed.remove(note)
                        noteOff(note)
                    }
                )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Keyboard")
    }
}

private struct KeyShape: View {
    let note: Int
    let isBlack: Bool
    let isPressed: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Retro.buttonRadius, bottomTrailingRadius: Retro.buttonRadius)
        shape
            .fill(fill)
            .overlay(alignment: .bottom) {
                if note % 12 == 0 {
                    Text(verbatim: "C\(note / 12 - 1)")
                        .font(Retro.label(11))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.bottom, 8)
                }
            }
            .overlay { shape.stroke(.black.opacity(0.6), lineWidth: 1) }
            .shadow(color: .black.opacity(isBlack ? 0.5 : 0), radius: 2, y: 2)
    }

    private var fill: some ShapeStyle {
        if isBlack {
            return isPressed ? AnyShapeStyle(Retro.accent) : AnyShapeStyle(LinearGradient(colors: [.black, Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
        }
        return isPressed ? AnyShapeStyle(Retro.accent.opacity(0.85)) : AnyShapeStyle(LinearGradient(colors: [Retro.cream, .white], startPoint: .top, endPoint: .bottom))
    }
}

/// Transparent multi-touch layer over the keys: maps each finger to the key under it.
private struct KeyTouchSurface: UIViewRepresentable {
    let note: (CGPoint) -> Int?
    let press: (Int) -> Void
    let release: (Int) -> Void

    func makeUIView(context: Context) -> KeyTouchView {
        let view = KeyTouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: KeyTouchView, context: Context) {
        view.note = note
        view.press = press
        view.release = release
    }
}

private final class KeyTouchView: UIView {
    var note: (CGPoint) -> Int? = { _ in nil }
    var press: (Int) -> Void = { _ in }
    var release: (Int) -> Void = { _ in }

    /// Key under each finger.
    private var touchNotes: [ObjectIdentifier: Int] = [:]
    /// Fingers on each key, so two fingers on one key play it once and release it with the last.
    private var fingers: [Int: Int] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { move(touch, to: note(touch.location(in: self))) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { move(touch, to: note(touch.location(in: self))) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { move(touch, to: nil) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { move(touch, to: nil) }
    }

    /// Leaving the screen (e.g. rotating back to portrait) releases every key.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        let held = Array(fingers.keys)
        touchNotes.removeAll()
        fingers.removeAll()
        held.forEach(release)
    }

    /// Points a finger at a new key (or none): the old key is released first, then the new one plays.
    private func move(_ touch: UITouch, to newNote: Int?) {
        let id = ObjectIdentifier(touch)
        let oldNote = touchNotes[id]
        guard oldNote != newNote else { return }
        if let oldNote {
            let count = (fingers[oldNote] ?? 1) - 1
            fingers[oldNote] = count > 0 ? count : nil
            if count <= 0 { release(oldNote) }
        }
        touchNotes[id] = newNote
        if let newNote {
            let count = (fingers[newNote] ?? 0) + 1
            fingers[newNote] = count
            if count == 1 { press(newNote) }
        }
    }
}

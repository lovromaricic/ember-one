import SwiftUI
import UIKit

/// Colours of the retro panel.
enum Retro {
    /// Also the launch screen colour: keep in sync with Assets.xcassets/LaunchBackground.
    static let panel = Color(red: 0.13, green: 0.11, blue: 0.10)
    static let section = Color(red: 0.20, green: 0.17, blue: 0.15)
    static let sectionEdge = Color(red: 0.33, green: 0.28, blue: 0.24)
    static let cream = Color(red: 0.93, green: 0.89, blue: 0.80)
    static let accent = Color(red: 0.95, green: 0.55, blue: 0.16)
    static let knobTop = Color(red: 0.32, green: 0.30, blue: 0.28)
    static let knobBottom = Color(red: 0.10, green: 0.09, blue: 0.09)

    /// Corner radius and border width shared by every button, so their shapes stay identical.
    static let buttonRadius: CGFloat = 6
    static let buttonBorder: CGFloat = 1

    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

/// A titled panel section, like a printed area on a hardware synth. An optional accessory
/// (e.g. a small toggle) sits at the right end of the title row as an overlay, so it never
/// makes the header taller than in other sections.
struct SynthSection<Content: View, Accessory: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    /// Off inside the tab panel, which draws one box around the tab row and the tab's content.
    @Environment(\.drawsSectionBox) private var drawsBox

    init(title: LocalizedStringKey?, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        if drawsBox {
            sectionContent
                // Fills the row height when the row asks for equal heights (see `equalHeightRow`).
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(10)
                .background(Retro.section, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(Retro.sectionEdge, lineWidth: 1)
                }
        } else {
            sectionContent
        }
    }

    private var sectionContent: some View {
        VStack(spacing: 8) {
            if let title {
                Text(title)
                    .textCase(.uppercase)
                    .font(Retro.label(11))
                    .tracking(2)
                    .foregroundStyle(Retro.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) { accessory }
            }
            content
        }
    }
}

extension EnvironmentValues {
    /// Whether `SynthSection` draws its own rounded box (see the tab panel in `ContentView`).
    @Entry var drawsSectionBox = true
}

extension SynthSection where Accessory == EmptyView {
    init(title: LocalizedStringKey?, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

/// A small button for a section header. It looks tiny but answers to a 44 × 44 pt area
/// around it; because it lives in the header's overlay, that area doesn't affect the layout.
struct HeaderPillButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Retro.label(8))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Retro.accent, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension EnvironmentValues {
    /// Default knob diameter; the main screen sets it from the screen width so the panel
    /// fits narrow phones (iPhone SE) as well as large ones.
    @Entry var knobSize: CGFloat = 36
}

/// Rotary knob: drag up/down to turn, double-tap to reset.
struct Knob: View {
    let param: SynthParam
    let label: LocalizedStringKey
    @Binding var value: Float
    var size: CGFloat = 46
    /// Narrower travel than the parameter's full range (e.g. a drum variant's decay range).
    var range: ClosedRange<Float>? = nil

    @State private var dragStart: Float?
    /// The finger has moved far enough to count as turning (a still touch never changes the value).
    @State private var isTurning = false
    @State private var learnTimer: Task<Void, Never>?
    @State private var learnStartedByThisTouch = false
    @Environment(MIDIManager.self) private var midi: MIDIManager?

    /// Knob travel: 270°, from 7 o'clock to 5 o'clock.
    private let sweep = 270.0
    /// Movement (pt) before a touch turns the knob; also cancels touch-and-hold MIDI learn.
    private static var turnThreshold: CGFloat { 4 }

    private var isLearning: Bool { midi?.learningParam == param }
    private var isLinked: Bool { midi?.mapping(for: param) != nil }

    var body: some View {
        let position = Double(param.normalized(value, in: range))
        VStack(spacing: 3) {
            Text(label)
                .font(Retro.label(9))
                .foregroundStyle(Retro.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12) // same height even when a long label shrinks, so rows align
                .overlay(alignment: .leading) {
                    if isLinked {
                        // Linked to a MIDI controller.
                        Circle().fill(Retro.accent).frame(width: 4, height: 4).offset(x: -6)
                    }
                }

            ZStack {
                // Scale ticks around the knob.
                ForEach(0..<11) { tick in
                    Capsule()
                        .fill(Retro.cream.opacity(0.45))
                        .frame(width: 1.5, height: 4)
                        .offset(y: -size / 2 - 5)
                        .rotationEffect(.degrees(-sweep / 2 + sweep * Double(tick) / 10))
                }
                // Lit arc showing the current setting.
                Circle()
                    .trim(from: 0, to: position * sweep / 360)
                    .stroke(Retro.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(90 + (360 - sweep) / 2))
                    .frame(width: size + 6, height: size + 6)
                // Knob body.
                Circle()
                    .fill(LinearGradient(colors: [Retro.knobTop, Retro.knobBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 1.5))
                    .overlay(Circle().inset(by: size * 0.16).stroke(.white.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                    .frame(width: size, height: size)
                // Pointer line.
                Capsule()
                    .fill(Retro.cream)
                    .frame(width: 3, height: size * 0.3)
                    .offset(y: -size * 0.24)
                    .rotationEffect(.degrees(-sweep / 2 + sweep * position))
                // MIDI learn: a blinking ring until a controller is moved.
                if isLearning {
                    Circle()
                        .stroke(Retro.accent, lineWidth: 3)
                        .frame(width: size + 12, height: size + 12)
                        .phaseAnimator([1.0, 0.15]) { ring, opacity in
                            ring.opacity(opacity)
                        } animation: { _ in .easeInOut(duration: 0.35) }
                }
            }
            .frame(width: size + 14, height: size + 14)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStart == nil {
                            // Touch down: start the touch-and-hold timer for MIDI learn.
                            dragStart = param.normalized(value, in: range)
                            isTurning = false
                            learnStartedByThisTouch = false
                            scheduleLearn()
                        }
                        let distance = hypot(drag.translation.width, drag.translation.height)
                        if !isTurning, distance >= Self.turnThreshold, !learnStartedByThisTouch {
                            isTurning = true
                            learnTimer?.cancel()
                        }
                        guard isTurning, let start = dragStart else { return }
                        // 160 pt of vertical drag turns the knob from minimum to maximum.
                        value = param.value(fromNormalized: start - Float(drag.translation.height) / 160, in: range)
                    }
                    .onEnded { _ in
                        learnTimer?.cancel()
                        dragStart = nil
                        isTurning = false
                    }
            )
            .onTapGesture(count: 2) { value = audioValue(param, patch: SynthPatch(), drums: DrumKit()) }

            Text(Self.format(value, unit: param.unit))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Retro.cream.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Self.format(value, unit: param.unit))
        .accessibilityAction(named: Text("Link to MIDI controller")) { midi?.beginLearn(param) }
        .accessibilityAdjustableAction { direction in
            let delta: Float = direction == .increment ? 0.05 : -0.05
            value = param.value(fromNormalized: param.normalized(value, in: range) + delta, in: range)
        }
    }

    /// After half a second of a still touch, MIDI learn starts for this knob.
    private func scheduleLearn() {
        learnTimer?.cancel()
        guard midi != nil else { return }
        learnTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, !isTurning, dragStart != nil else { return }
            learnStartedByThisTouch = true
            midi?.beginLearn(param)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    static func format(_ value: Float, unit: SynthParam.Unit) -> String {
        switch unit {
        case .percent:
            return "\(Int((value * 100).rounded()))%"
        case .bipolarPercent:
            let percent = Int((value * 100).rounded())
            return percent > 0 ? "+\(percent)%" : "\(percent)%"
        case .octave:
            let octave = Int(value.rounded())
            return octave > 0 ? "+\(octave)" : "\(octave)"
        case .cents:
            let cents = Int(value.rounded())
            return cents > 0 ? "+\(cents) ct" : "\(cents) ct"
        case .hertz:
            if value >= 1000 { return String(format: "%.1f kHz", value / 1000) }
            return value >= 10 ? "\(Int(value.rounded())) Hz" : String(format: "%.1f Hz", value)
        case .seconds:
            return value < 1 ? "\(Int((value * 1000).rounded())) ms" : String(format: "%.2f s", value)
        case .choice:
            return "\(Int(value))"
        case .bpm:
            return "\(Int(value.rounded())) BPM"
        case .steps:
            return "\(Int(value.rounded()))"
        case .semitones:
            let semitones = value.rounded()
            return semitones > 0 ? String(format: "+%.0f st", semitones) : String(format: "%.0f st", semitones)
        case .division:
            let index = min(max(Int(value.rounded()), 0), SynthParam.pumpDivisions.count - 1)
            return SynthParam.pumpDivisions[index].label
        }
    }
}

/// Retro push-button row where exactly one option is selected.
struct RetroSegmented<Option: Hashable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let accessibilityName: (Option) -> Text
    @ViewBuilder let label: (Option, Bool) -> Label

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    label(option, isSelected)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            isSelected ? Retro.accent : Retro.knobBottom,
                            in: RoundedRectangle(cornerRadius: Retro.buttonRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(.black.opacity(0.6), lineWidth: Retro.buttonBorder)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityName(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

extension Waveform {
    var name: String {
        switch self {
        case .sine: String(localized: "Sine")
        case .saw: String(localized: "Saw")
        case .square: String(localized: "Square")
        case .triangle: String(localized: "Triangle")
        }
    }
}

/// Small drawing of one and a half periods of a waveform, for the selector buttons.
struct WaveShape: Shape {
    let wave: Waveform

    func path(in rect: CGRect) -> Path {
        // Points in "periods" (x: 0...1.5) and amplitude (y: -1...1, up is positive).
        let points: [(x: Double, y: Double)] = switch wave {
        case .sine: (0...36).map { i in let x = Double(i) / 24; return (x, sin(2 * .pi * x)) }
        case .saw: [(0, -1), (1, 1), (1, -1), (1.5, 0)]
        case .square: [(0, 1), (0.5, 1), (0.5, -1), (1, -1), (1, 1), (1.5, 1)]
        case .triangle: [(0, -1), (0.5, 1), (1, -1), (1.5, 1)]
        }
        var path = Path()
        path.addLines(points.map { point in
            CGPoint(x: rect.minX + rect.width * point.x / 1.5, y: rect.midY - rect.height / 2 * point.y)
        })
        return path
    }
}

extension View {
    /// Makes every section in an HStack as tall as the tallest one.
    func equalHeightRow() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}

import CoreAudioKit
import SwiftUI

/// A 5-pin DIN socket, the classic MIDI symbol: an outline ring with five filled pins.
struct DINIcon: View {
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: 1.6)
            DINPins().fill(color)
        }
    }
}

private struct DINPins: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Key notch at the top.
        path.addRect(CGRect(x: c.x - r * 0.14, y: c.y - r, width: r * 0.28, height: r * 0.3))
        // Five pins on the lower half circle.
        let pin = r * 0.14
        for angle in [180.0, 135, 90, 45, 0] {
            let a = angle * .pi / 180
            let p = CGPoint(x: c.x + cos(a) * r * 0.55, y: c.y + sin(a) * r * 0.55)
            path.addEllipse(in: CGRect(x: p.x - pin, y: p.y - pin, width: 2 * pin, height: 2 * pin))
        }
        return path
    }
}

/// Preset-bar button: dim without a controller, lit with a dot when one is connected,
/// and a short flash while messages arrive.
struct MIDIStatusButton: View {
    let midi: MIDIManager
    let action: () -> Void

    @State private var flash = false

    var body: some View {
        Button(action: action) {
            DINIcon(color: midi.isConnected ? Retro.accent : Retro.cream.opacity(0.35))
                .frame(width: 18, height: 18)
                .overlay(alignment: .topTrailing) {
                    if midi.isConnected {
                        Circle().fill(Retro.accent).frame(width: 5, height: 5).offset(x: 4, y: -3)
                    }
                }
                .frame(width: 34, height: 36)
                .background(flash ? Retro.accent.opacity(0.45) : Retro.section, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: 1) }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -5) // the 44 pt touch area overlaps its neighbours' gaps, not the layout
        .accessibilityLabel("MIDI")
        .accessibilityValue(midi.isConnected ? Text("Controller connected") : Text("No controller"))
        .onChange(of: midi.activity) { _, _ in
            flash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                flash = false
            }
        }
    }
}

/// Shown while a knob waits for a controller to be moved.
struct MIDILearnBanner: View {
    let midi: MIDIManager

    var body: some View {
        if let param = midi.learningParam {
            HStack(spacing: 8) {
                DINIcon(color: Retro.accent).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MIDI learn: \(param.displayName)")
                        .font(Retro.label(11))
                        .foregroundStyle(Retro.cream)
                    Text("Move a knob or slider on your controller")
                        .font(.system(size: 10))
                        .foregroundStyle(Retro.cream.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let mapping = midi.mapping(for: param) {
                    Button("Unlink") {
                        midi.removeMapping(mapping)
                        midi.cancelLearn()
                    }
                    .font(Retro.label(10))
                    .foregroundStyle(Retro.cream)
                    .frame(minHeight: 44)
                }
                Button("Cancel") { midi.cancelLearn() }
                    .font(Retro.label(10))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(Retro.accent, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .background(Retro.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Retro.accent, lineWidth: 1.5) }
            .padding(.horizontal, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// MIDI settings: devices, channel, velocity, pitch bend range, mod wheel and learned links.
/// Same dark "clean cards" look as the Presets sheet.
struct MIDISheet: View {
    @Bindable var midi: MIDIManager
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeveloper = false

    @ScaledMetric(relativeTo: .caption) private var headerSize: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var hintSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var valueSize: CGFloat = 15

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("Devices")
                        card { devicesRows }

                        sectionHeader("Input")
                        card { inputRows }

                        sectionHeader("Learned controls")
                        card { learnedRows }
                        footnote("Links are kept for the app, not for a preset.")

                        // Hidden helper for testing without hardware: touch and hold the last footnote.
                        if showsDeveloper {
                            sectionHeader("Developer")
                            card {
                                Toggle("Simulate a controller", isOn: $midi.simulatesController)
                                    .font(.system(size: titleSize, weight: .medium))
                                    .foregroundStyle(Retro.cream)
                                    .rowPadding()
                                hairline
                                Button("Send test messages") { midi.sendTestMessages() }
                                    .font(.system(size: titleSize, weight: .medium))
                                    .foregroundStyle(Retro.accent.opacity(midi.simulatesController ? 1 : 0.4))
                                    .disabled(!midi.simulatesController)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .rowPadding()
                            }
                        }
                        footnote("MIDI clock, start and stop are ignored for now.")
                            .onLongPressGesture(minimumDuration: 1.5) { withAnimation { showsDeveloper.toggle() } }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(PresetSheetStyle.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { _ in
                BluetoothMIDIView()
                    .navigationTitle("Bluetooth MIDI")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(PresetSheetStyle.background)
        .sensoryFeedback(.impact(weight: .light), trigger: midi.settings)
        .tint(Retro.accent)
        .preferredColorScheme(.dark)
        .onAppear { if midi.simulatesController { showsDeveloper = true } }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("MIDI")
                .font(.headline.bold())
                .foregroundStyle(Retro.cream)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Retro.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Retro.section, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                        .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: Retro.buttonBorder) }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    // MARK: - Devices

    @ViewBuilder private var devicesRows: some View {
        if midi.devices.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                statusDot(on: false)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No controller connected")
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(Retro.cream)
                    Text("Plug one in over USB or pair a Bluetooth controller.")
                        .font(.system(size: hintSize))
                        .foregroundStyle(PresetSheetStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .rowPadding()
        }
        ForEach(midi.devices) { device in
            if device.id != midi.devices.first?.id { hairline }
            HStack(spacing: 12) {
                statusDot(on: true)
                Text(device.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(Retro.cream)
                Spacer(minLength: 0)
            }
            .rowPadding()
            .accessibilityElement(children: .combine)
        }
        if let error = midi.setupError {
            hairline
            Text(error)
                .font(.system(size: hintSize))
                .foregroundStyle(.red)
                .rowPadding()
        }
        hairline
        NavigationLink(value: "bluetooth") {
            HStack {
                Text("Connect Bluetooth MIDI")
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundStyle(Retro.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PresetSheetStyle.muted)
            }
            .rowPadding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusDot(on: Bool) -> some View {
        Circle()
            .fill(on ? Retro.accent : PresetSheetStyle.muted.opacity(0.6))
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }

    // MARK: - Input

    @ViewBuilder private var inputRows: some View {
        choiceRow("Channel", value: midi.settings.channel == 0 ? String(localized: "Omni") : "\(midi.settings.channel)") {
            Picker("Channel", selection: $midi.settings.channel) {
                Text("Omni").tag(0)
                ForEach(1...16, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
        }
        hairline
        choiceRow("Velocity sensitivity", value: velocityTitle(midi.settings.velocity)) {
            Picker("Velocity sensitivity", selection: $midi.settings.velocity) {
                Text("Off").tag(VelocitySensitivity.off)
                Text("Soft").tag(VelocitySensitivity.soft)
                Text("Normal").tag(VelocitySensitivity.normal)
                Text("Hard").tag(VelocitySensitivity.hard)
            }
        }
        hairline
        bendRow
        hairline
        choiceRow("Mod wheel", value: midi.settings.modWheel == .lfoAmount ? String(localized: "LFO amount") : String(localized: "Filter cutoff")) {
            Picker("Mod wheel", selection: $midi.settings.modWheel) {
                Text("LFO amount").tag(ModWheelTarget.lfoAmount)
                Text("Filter cutoff").tag(ModWheelTarget.cutoff)
            }
        }
    }

    private func velocityTitle(_ velocity: VelocitySensitivity) -> String {
        switch velocity {
        case .off: String(localized: "Off")
        case .soft: String(localized: "Soft")
        case .normal: String(localized: "Normal")
        case .hard: String(localized: "Hard")
        }
    }

    /// Label on the left, the current value as a pill on the right that opens the choices.
    private func choiceRow<Choices: View>(_ title: LocalizedStringKey, value: String, @ViewBuilder choices: () -> Choices) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(Retro.cream)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Menu {
                choices()
            } label: {
                HStack(spacing: 5) {
                    Text(value)
                        .font(.system(size: valueSize, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Retro.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(PresetSheetStyle.pill, in: RoundedRectangle(cornerRadius: 10))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(value))
        }
        .rowPadding(vertical: 4)
    }

    /// Pitch bend range with − and + in one pill (same 1...12 range as before).
    private var bendRow: some View {
        let range = midi.settings.bendRange
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pitch bend range")
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundStyle(Retro.cream)
                Text("±\(range) semitones")
                    .font(.system(size: hintSize))
                    .foregroundStyle(PresetSheetStyle.muted)
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton("minus", label: "Decrease pitch bend range", enabled: range > 1) { midi.settings.bendRange -= 1 }
                Rectangle()
                    .fill(PresetSheetStyle.hairline)
                    .frame(width: 1, height: 18)
                stepButton("plus", label: "Increase pitch bend range", enabled: range < 12) { midi.settings.bendRange += 1 }
            }
            .background(PresetSheetStyle.pill, in: RoundedRectangle(cornerRadius: 10).inset(by: 6))
        }
        .rowPadding(vertical: 2)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Retro.accent.opacity(enabled ? 1 : 0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - Learned controls

    @ViewBuilder private var learnedRows: some View {
        if midi.mappings.isEmpty {
            Text("Touch and hold a knob, then move a control on your controller to link them.")
                .font(.system(size: hintSize))
                .foregroundStyle(PresetSheetStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowPadding()
        }
        ForEach(midi.mappings) { mapping in
            if mapping.id != midi.mappings.first?.id { hairline }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SynthParam(rawValue: mapping.param)?.displayName ?? "–")
                        .font(.system(size: titleSize, weight: .medium))
                        .foregroundStyle(Retro.cream)
                    Text("\(mapping.deviceName) · CC \(mapping.cc)")
                        .font(.system(size: hintSize))
                        .foregroundStyle(PresetSheetStyle.muted)
                }
                Spacer()
                Button("Remove", systemImage: "xmark.circle.fill", role: .destructive) {
                    midi.removeMapping(mapping)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(PresetSheetStyle.muted)
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
            }
            .rowPadding(vertical: 4)
        }
        if midi.mappings.count > 1 {
            hairline
            Button("Remove all links", role: .destructive) { midi.removeAllMappings() }
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowPadding()
        }
    }

    // MARK: - Building blocks

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: headerSize, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(PresetSheetStyle.muted)
            .padding(.leading, 4) // 20 pt from the sheet edge with the 16 pt margin
            .padding(.top, 22)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PresetSheetStyle.card, in: RoundedRectangle(cornerRadius: PresetSheetStyle.cardRadius))
    }

    private var hairline: some View {
        Rectangle()
            .fill(PresetSheetStyle.hairline)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
            .foregroundStyle(PresetSheetStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

private extension View {
    /// Inner padding of a row inside a card.
    func rowPadding(vertical: CGFloat = 12) -> some View {
        padding(.horizontal, 16).padding(.vertical, vertical)
    }
}

/// Apple's pairing screen for Bluetooth LE MIDI devices.
struct BluetoothMIDIView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ controller: CABTMIDICentralViewController, context: Context) {}
}

extension SynthParam {
    /// Readable name for lists (e.g. learned MIDI links).
    var displayName: String {
        if let drum {
            let name = switch drum {
            case .kick: String(localized: "Kick")
            case .snare: String(localized: "Snare")
            case .clap: String(localized: "Clap")
            case .closedHat: String(localized: "Closed hat")
            case .openHat: String(localized: "Open hat")
            }
            switch self {
            case SynthParam.drumLevel(drum): return String(localized: "\(name) level")
            case SynthParam.drumTune(drum): return String(localized: "\(name) tune")
            case SynthParam.drumDecay(drum): return String(localized: "\(name) decay")
            default: return String(localized: "\(name) mute")
            }
        }
        return switch self {
        case .osc1Wave: String(localized: "Osc 1 waveform")
        case .osc1Level: String(localized: "Osc 1 level")
        case .osc1Octave: String(localized: "Osc 1 octave")
        case .osc1Detune: String(localized: "Osc 1 detune")
        case .osc2Wave: String(localized: "Osc 2 waveform")
        case .osc2Level: String(localized: "Osc 2 level")
        case .osc2Octave: String(localized: "Osc 2 octave")
        case .osc2Detune: String(localized: "Osc 2 detune")
        case .cutoff: String(localized: "Filter cutoff")
        case .resonance: String(localized: "Filter resonance")
        case .filterEnvAmount: String(localized: "Filter envelope amount")
        case .ampAttack: String(localized: "Amp attack")
        case .ampDecay: String(localized: "Amp decay")
        case .ampSustain: String(localized: "Amp sustain")
        case .ampRelease: String(localized: "Amp release")
        case .filterAttack: String(localized: "Filter attack")
        case .filterDecay: String(localized: "Filter decay")
        case .filterSustain: String(localized: "Filter sustain")
        case .filterRelease: String(localized: "Filter release")
        case .lfoDestination: String(localized: "LFO destination")
        case .lfoRate: String(localized: "LFO rate")
        case .lfoAmount: String(localized: "LFO amount")
        case .masterVolume: String(localized: "Master volume")
        case .delayTime: String(localized: "Delay time")
        case .delayFeedback: String(localized: "Delay feedback")
        case .delayMix: String(localized: "Delay mix")
        case .reverbSize: String(localized: "Reverb size")
        case .reverbMix: String(localized: "Reverb mix")
        case .chorusRate: String(localized: "Chorus rate")
        case .chorusMix: String(localized: "Chorus mix")
        case .driveAmount: String(localized: "Drive")
        case .pumpAmount: String(localized: "Pump amount")
        case .pumpRate: String(localized: "Pump rate")
        case .seqTempo: String(localized: "Tempo")
        case .seqSwing: String(localized: "Swing")
        case .seqLength: String(localized: "Steps")
        case .drumVolume: String(localized: "Drum volume")
        case .drumReverbSend: String(localized: "Drum reverb send")
        case .drumDelaySend: String(localized: "Drum delay send")
        case .drumComp: String(localized: "Drum comp")
        case .drumDrive: String(localized: "Drum drive")
        default: String(localized: "Parameter \(rawValue)")
        }
    }
}

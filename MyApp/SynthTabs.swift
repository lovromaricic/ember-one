import SwiftUI

enum SynthTab: String, CaseIterable, Identifiable {
    case envelope = "Envelope"
    case sequencer = "Sequencer"
    case effects = "FX"
    case drums = "Drums"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .envelope: "Envelope"
        case .sequencer: "Sequencer"
        case .effects: "FX"
        case .drums: "Drums"
        }
    }
}

/// A knob bound to one parameter of the synth's patch.
struct PatchKnob: View {
    let synth: SynthEngine
    let param: SynthParam
    let label: LocalizedStringKey
    /// Explicit diameter; nil uses the screen-dependent `knobSize` from the environment.
    var size: CGFloat?
    /// Narrower knob travel than the parameter's full range.
    var range: ClosedRange<Float>? = nil

    @Environment(\.knobSize) private var defaultSize

    var body: some View {
        Knob(
            param: param,
            label: label,
            value: Binding(get: { synth.value(param) }, set: { synth.set(param, $0) }),
            size: size ?? defaultSize,
            range: range
        )
        .frame(maxWidth: .infinity)
    }
}

/// Envelope | Sequencer | FX | Drums: the header row of the tab panel, styled like the
/// waveform buttons. Each button is drawn 30 pt high but answers to a 44 pt tall area.
struct TabSelector: View {
    @Binding var selection: SynthTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SynthTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .textCase(.uppercase)
                        .font(.system(size: 9.5, weight: isSelected ? .bold : .semibold, design: .monospaced))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isSelected ? Retro.panel : Retro.cream)
                        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                        .background(isSelected ? Retro.accent : Retro.knobBottom, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                        .overlay {
                            if !isSelected {
                                RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(.black.opacity(0.6), lineWidth: Retro.buttonBorder)
                            }
                        }
                        // 44 pt touch area without changing the 30 pt layout.
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .padding(.vertical, -7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selection)
    }
}

// MARK: - Envelope

struct EnvelopeTab: View {
    let synth: SynthEngine

    var body: some View {
        SynthSection(title: nil) {
            row("▸ AMP (volume)", .ampAttack, .ampDecay, .ampSustain, .ampRelease)
            row("▸ FILTER (cutoff)", .filterAttack, .filterDecay, .filterSustain, .filterRelease)
        }
    }

    private func row(_ title: LocalizedStringKey, _ a: SynthParam, _ d: SynthParam, _ s: SynthParam, _ r: SynthParam) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Retro.label(9))
                .foregroundStyle(Retro.cream.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                PatchKnob(synth: synth, param: a, label: "ATTACK")
                PatchKnob(synth: synth, param: d, label: "DECAY")
                PatchKnob(synth: synth, param: s, label: "SUSTAIN")
                PatchKnob(synth: synth, param: r, label: "RELEASE")
            }
        }
    }
}

// MARK: - Sequencer

struct SequencerTab: View {
    let synth: SynthEngine
    @Binding var selectedStep: Int?

    @State private var undo = UndoOffer()
    /// "Pattern randomized · Undo", shown at the top of the tab panel.
    @Environment(PanelToast.self) private var panelToast
    /// Turns of the dice icon (one per tap).
    @State private var diceTurns = 0.0

    var body: some View {
        SynthSection(title: nil) {
            // Redraws while playing so the running light and blinking follow the audio thread.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !synth.isPlaying)) { context in
                let blink = Int(context.date.timeIntervalSinceReferenceDate * 4) % 2 == 0
                let shownBankPlays = synth.playingBank == synth.patch.sequencer.activeBank
                let playing = synth.isPlaying && shownBankPlays ? synth.currentStep : nil
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        TrackSwitch(
                            title: "Sequencer",
                            isOn: synth.patch.sequencer.enabled,
                            isArmed: synth.isPlaying && synth.sequencerArmed,
                            blink: blink
                        ) { synth.patch.sequencer.enabled.toggle() }
                        Spacer(minLength: 4)
                        bankTools
                    }
                    .overlay(alignment: .trailing) { UndoBanner(offer: $undo) }
                    // Dimmed while the track is off; still editable.
                    Group {
                        stepRow(0..<8, playing: playing)
                        stepRow(8..<16, playing: playing)
                        bankRow(blink: blink)
                    }
                    .opacity(synth.patch.sequencer.enabled ? 1 : 0.45)
                }
            }
            Group {
                if let selectedStep {
                    Text("Keys write into step \(selectedStep + 1) · the same note clears it")
                } else {
                    Text("Tap a step, then a key on the keyboard to enter a note")
                }
            }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Retro.cream.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
            keyModeControls
            HStack(spacing: 0) {
                // The external clock sets the tempo while it is received.
                let external = synth.clockExternal && synth.clockStatus == .receiving
                PatchKnob(synth: synth, param: .seqTempo, label: "TEMPO")
                    .allowsHitTesting(!external)
                    .opacity(external ? 0.4 : 1)
                    .accessibilityHint(external ? Text("Set by the external MIDI clock") : Text(""))
                PatchKnob(synth: synth, param: .seqSwing, label: "SWING")
                PatchKnob(synth: synth, param: .seqLength, label: "STEPS")
            }
        }
    }

    /// Key mode (Off | Transpose | Arp) with Hold; in Arp also direction and octave range.
    private var keyModeControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("KEY MODE")
                    .font(Retro.label(8))
                    .foregroundStyle(Retro.cream.opacity(0.6))
                    .fixedSize()
                RetroSegmented(
                    options: KeyMode.allCases,
                    selection: Binding(get: { synth.patch.sequencer.keyMode }, set: { synth.patch.sequencer.keyMode = $0 }),
                    accessibilityName: { Text("Key mode \(Text($0.title))") }
                ) { mode, isSelected in
                    Text(mode.title)
                        .font(Retro.label(8))
                        .foregroundStyle(isSelected ? Color.black : Retro.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)
                Button {
                    synth.patch.sequencer.hold.toggle()
                } label: {
                    Text("HOLD")
                        .font(Retro.label(8))
                        .foregroundStyle(synth.patch.sequencer.hold ? Color.black : Retro.cream)
                        .frame(width: 44, height: 28)
                        .background(synth.patch.sequencer.hold ? Retro.accent : Retro.knobBottom, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                        .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(.black.opacity(0.6), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hold")
                .accessibilityValue(synth.patch.sequencer.hold ? Text("On") : Text("Off"))
            }
            if synth.patch.sequencer.keyMode == .arp {
                HStack(spacing: 4) {
                    RetroSegmented(
                        options: ArpDirection.allCases,
                        selection: Binding(get: { synth.patch.sequencer.arpDirection }, set: { synth.patch.sequencer.arpDirection = $0 }),
                        accessibilityName: { Text("Arp direction \(Text($0.title))") }
                    ) { direction, isSelected in
                        Image(systemName: direction.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isSelected ? Color.black : Retro.cream)
                    }
                    RetroSegmented(
                        options: [1, 2, 3],
                        selection: Binding(get: { synth.patch.sequencer.arpOctaves }, set: { synth.patch.sequencer.arpOctaves = $0 }),
                        accessibilityName: { Text("Arp range \($0) octaves") }
                    ) { octaves, isSelected in
                        Text("\(octaves) OCT")
                            .font(Retro.label(8))
                            .foregroundStyle(isSelected ? Color.black : Retro.cream)
                    }
                }
            }
        }
    }

    /// Copy, Paste and Clear for the selected bank.
    private var bankTools: some View {
        let bank = synth.patch.sequencer.activeBank
        let letter = Self.bankLetter(bank)
        return HStack(spacing: 2) {
            ToolButton(symbol: "dice", label: "Randomize", accessibility: Text("Randomize pattern"),
                       tint: Retro.accent, rotation: diceTurns * 360) {
                randomizeBank(bank)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: diceTurns)
            ToolButton(symbol: "doc.on.doc", label: "Copy", accessibility: Text("Copy bank \(letter)")) {
                synth.bankClipboard = synth.bankSteps(bank)
            }
            ToolButton(symbol: "doc.on.clipboard", label: "Paste", accessibility: Text("Paste into bank \(letter)")) {
                if let clip = synth.bankClipboard { synth.setBankSteps(bank, clip) }
            }
            .disabled(synth.bankClipboard == nil)
            ToolButton(symbol: "trash", label: "Clear", accessibility: Text("Clear bank \(letter)")) {
                clearBank(bank)
            }
        }
    }

    /// New melody in minor pentatonic for the selected bank (swaps in on the next bar while playing).
    private func randomizeBank(_ bank: Int) {
        let before = synth.bankSteps(bank)
        var rng = SystemRandomNumberGenerator()
        let root = PatternRandomizer.root(for: before, category: synth.patch.category)
        synth.replaceSequencerBank(bank, with: PatternRandomizer.melody(root: root, using: &rng))
        withAnimation(.easeInOut(duration: 0.3)) { diceTurns += 1 }
        withAnimation(.easeOut(duration: 0.2)) {
            panelToast.offer.offer(Text("Pattern randomized"), seconds: 5) { [synth] in synth.replaceSequencerBank(bank, with: before) }
        }
    }

    /// Clears a bank at once and offers a short Undo.
    private func clearBank(_ bank: Int) {
        let before = synth.bankSteps(bank)
        guard before.contains(where: { $0 != nil }) else { return }
        synth.setBankSteps(bank, SynthPatch.Sequencer.emptyBank)
        undo.offer(Text("Bank \(Self.bankLetter(bank)) cleared")) { [synth] in synth.setBankSteps(bank, before) }
    }

    /// A to H. Current bank: orange. A selection waiting for the end of the pattern blinks. Long press is a quiet shortcut for Copy, Paste and Clear.
    private func bankRow(blink: Bool) -> some View {
        BankRow(
            selected: synth.patch.sequencer.activeBank,
            playing: synth.playingBank,
            trackRuns: synth.isPlaying && synth.patch.sequencer.enabled && !synth.sequencerArmed,
            blink: blink,
            canPaste: synth.bankClipboard != nil,
            select: { synth.selectBank($0) },
            copy: { synth.bankClipboard = synth.bankSteps($0) },
            paste: { bank in if let clip = synth.bankClipboard { synth.setBankSteps(bank, clip) } },
            clear: { clearBank($0) }
        )
    }

    static func bankLetter(_ bank: Int) -> String {
        String(UnicodeScalar(UInt8(65 + bank)))
    }

    private func stepRow(_ range: Range<Int>, playing: Int?) -> some View {
        HStack(spacing: 4) {
            ForEach(range, id: \.self) { step in
                StepButton(
                    index: step,
                    note: synth.patch.sequencer.steps[step],
                    isSelected: selectedStep == step,
                    isPlaying: playing == step,
                    isActive: step < synth.patch.sequencer.length
                ) {
                    selectedStep = selectedStep == step ? nil : step
                }
            }
        }
    }
}

/// A to H bank buttons, shared by the Sequencer and the Drums. Current bank: orange.
/// A bank selected while another plays waits for the pattern end and blinks.
/// Long press is a quiet shortcut for Copy, Paste and Clear.
struct BankRow: View {
    let selected: Int
    let playing: Int
    /// The track is running on the clock (playing, switched on and not waiting for the next bar).
    let trackRuns: Bool
    let blink: Bool
    let canPaste: Bool
    let select: (Int) -> Void
    let copy: (Int) -> Void
    let paste: (Int) -> Void
    let clear: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<SynthPatch.bankCount, id: \.self) { bank in
                // Current bank: the one playing (or selected, when nothing plays) — solid orange.
                let current = trackRuns ? playing : selected
                let isPlaying = trackRuns && bank == playing
                let isQueued = trackRuns && bank == selected && bank != playing
                let filled = bank == current || (isQueued && blink)
                let fill = filled ? Retro.accent : Retro.knobBottom
                Button {
                    select(bank)
                } label: {
                    Text(verbatim: SequencerTab.bankLetter(bank))
                        .font(Retro.label(11))
                        .foregroundStyle(filled ? Color.black : Retro.cream)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
                    .background(fill, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                    .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(fill, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { copy(bank) }
                    Button("Paste", systemImage: "doc.on.clipboard") { paste(bank) }
                        .disabled(!canPaste)
                    Button("Clear", systemImage: "trash", role: .destructive) { clear(bank) }
                }
                .accessibilityLabel(Text("Bank \(SequencerTab.bankLetter(bank))"))
                .accessibilityValue(isQueued ? Text("Plays next") : (isPlaying ? Text("Playing") : (bank == selected ? Text("Selected") : Text(""))))
                .accessibilityAddTraits(bank == selected ? .isSelected : [])
            }
        }
    }
}

private struct StepButton: View {
    let index: Int
    let note: Int?
    let isSelected: Bool
    let isPlaying: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(verbatim: "\(index + 1)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(isPlaying ? Color.black.opacity(0.6) : Retro.cream.opacity(0.4))
                Text(verbatim: note.map { Self.noteName($0) } ?? "–")
                    .font(Retro.label(10))
                    .foregroundStyle(isPlaying ? Color.black : (note == nil ? Retro.cream.opacity(0.35) : Retro.cream))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(isPlaying ? Retro.accent : (note == nil ? Retro.knobBottom : Retro.knobTop),
                        in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Retro.buttonRadius)
                    .stroke(isSelected ? Retro.accent : .black.opacity(0.6), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: isPlaying ? Retro.accent.opacity(0.8) : .clear, radius: 6)
            .opacity(isActive ? 1 : 0.3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Step \(index + 1), \(note.map { Self.noteName($0) } ?? String(localized: "rest"))"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func noteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[note % 12])\(note / 12 - 1)"
    }
}

// MARK: - Effects

struct EffectsTab: View {
    let synth: SynthEngine
    @Environment(\.knobSize) private var defaultSize

    var body: some View {
        SynthSection(title: nil) {
            HStack(alignment: .top, spacing: 6) {
                group("DELAY", [(.delayTime, "TIME"), (.delayFeedback, "FDBK"), (.delayMix, "MIX")])
                group("REVERB", [(.reverbSize, "SIZE"), (.reverbMix, "MIX")])
            }
            HStack(alignment: .top, spacing: 6) {
                group("CHORUS", [(.chorusRate, "RATE"), (.chorusMix, "MIX")])
                group("DRIVE", [(.driveAmount, "AMOUNT")])
                group("PUMP", [(.pumpAmount, "AMOUNT"), (.pumpRate, "RATE")])
            }
        }
    }

    private func group(_ title: LocalizedStringKey, _ knobs: [(SynthParam, LocalizedStringKey)]) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(Retro.label(8))
                .tracking(1)
                .foregroundStyle(Retro.accent.opacity(0.8))
            HStack(spacing: 0) {
                ForEach(knobs, id: \.0) { param, label in
                    PatchKnob(synth: synth, param: param, label: label, size: defaultSize - 6)
                }
            }
        }
        .padding(.vertical, 4)
        .background(Retro.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
        .layoutPriority(Double(knobs.count))
    }
}

// MARK: - Transport

/// Play / Stop and the tempo readout, always visible under the tabs.
struct TransportBar: View {
    let synth: SynthEngine

    var body: some View {
        HStack(spacing: 6) {
            transportButton("play.fill", label: "Play", isLit: synth.isPlaying) { synth.play() }
            transportButton("stop.fill", label: "Stop", isLit: false) { synth.stop() }
            // With an external clock coming in, its tempo is shown (muted, EXT) instead.
            let external = synth.clockExternal && synth.clockStatus == .receiving
            VStack(spacing: 0) {
                Text(verbatim: "\(Int((external ? synth.externalTempo : Double(synth.patch.sequencer.tempo)).rounded()))")
                    .font(Retro.label(16))
                    .foregroundStyle(external ? Retro.cream.opacity(0.55) : Retro.accent)
                    .contentTransition(.numericText())
                if external {
                    Text(verbatim: "EXT")
                        .font(Retro.label(7))
                        .foregroundStyle(Retro.accent)
                        .padding(.horizontal, 3)
                        .overlay { RoundedRectangle(cornerRadius: 2).stroke(Retro.accent, lineWidth: 1) }
                        .accessibilityLabel("External clock")
                } else {
                    Text("BPM")
                        .font(Retro.label(8))
                        .foregroundStyle(Retro.cream.opacity(0.6))
                }
            }
            .frame(width: 44)
            .accessibilityElement(children: .combine)
        }
    }

    private func transportButton(_ symbol: String, label: LocalizedStringKey, isLit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(isLit ? Color.black : Retro.cream)
                .frame(width: 46, height: 38)
                .background(isLit ? Retro.accent : Retro.section, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Drums

extension DrumKind {
    /// Full name (popup title, VoiceOver).
    var title: LocalizedStringKey {
        switch self {
        case .kick: "Kick"
        case .snare: "Snare"
        case .clap: "Clap"
        case .closedHat: "Closed hat"
        case .openHat: "Open hat"
        case .tomLo: "Tom Lo"
        case .tomHi: "Tom Hi"
        case .rim: "Rim"
        case .cowbell: "Cowbell"
        case .ride: "Ride"
        }
    }

    /// Name of one of the drum's five sound variants (sentence case).
    func variantName(_ variant: Int) -> LocalizedStringKey {
        switch (self, variant) {
        case (.kick, 1): "Deep"
        case (.kick, 2): "Hard"
        case (.kick, 3): "Punch"
        case (.kick, 4): "Boom"
        case (.kick, _): "House"
        case (.snare, 1): "Fat"
        case (.snare, 2): "Electro"
        case (.snare, 3): "Rimshot"
        case (.snare, 4): "Lo-fi"
        case (.snare, _): "Crisp"
        case (.clap, 1): "Tight"
        case (.clap, 2): "Room"
        case (.clap, 3): "Snap"
        case (.clap, 4): "Wide"
        case (.clap, _): "House"
        case (.closedHat, 1): "Soft"
        case (.closedHat, 2): "Metallic"
        case (.closedHat, 3): "Tick"
        case (.closedHat, 4): "Noisy"
        case (.closedHat, _): "Crisp"
        case (.openHat, 1): "Short"
        case (.openHat, 2): "Metallic"
        case (.openHat, 3): "Washy"
        case (.openHat, 4): "Soft"
        case (.openHat, _): "Long"
        case (.tomLo, 1), (.tomHi, 1): "Deep"
        case (.tomLo, 2), (.tomHi, 2): "Tight"
        case (.tomLo, 3), (.tomHi, 3): "Electro"
        case (.tomLo, 4), (.tomHi, 4): "Soft"
        case (.tomLo, _), (.tomHi, _): "Classic"
        case (.rim, 1): "Wood"
        case (.rim, 2): "Sharp"
        case (.rim, 3): "Snap"
        case (.rim, 4): "Soft"
        case (.rim, _): "Classic"
        case (.cowbell, 1): "High"
        case (.cowbell, 2): "Low"
        case (.cowbell, 3): "Short"
        case (.cowbell, 4): "Dry"
        case (.cowbell, _): "Classic"
        case (.ride, 1): "Bright"
        case (.ride, 2): "Dark"
        case (.ride, 3): "Bell"
        case (.ride, 4): "Wash"
        case (.ride, _): "Classic"
        }
    }

    /// Short row label.
    var shortTitle: LocalizedStringKey {
        switch self {
        case .kick: "KICK"
        case .snare: "SNARE"
        case .clap: "CLAP"
        case .closedHat: "C.HAT"
        case .openHat: "O.HAT"
        case .tomLo: "TOM LO"
        case .tomHi: "TOM HI"
        case .rim: "RIM"
        case .cowbell: "COWBELL"
        case .ride: "RIDE"
        }
    }
}

/// Rhythm machine: one row of steps per drum, 8 steps per page. Its settings are global
/// (`SynthEngine.drums`), so loading a preset never changes them.
struct DrumsTab: View {
    let synth: SynthEngine

    @State private var page = 0
    /// While playing, the shown page follows the running step until a page is picked by hand;
    /// following starts again with the next Play.
    @State private var followsPlayhead = true
    @State private var editing: DrumKind?
    @State private var undo = UndoOffer()
    /// "Pattern randomized · Undo", shown at the top of the tab panel.
    @Environment(PanelToast.self) private var panelToast
    /// Taps of "Randomize drum sounds" (for its haptic and a little bounce).
    @State private var soundTurns = 0.0
    /// Turns of the dice icon (one per tap).
    @State private var diceTurns = 0.0
    @Environment(\.knobSize) private var knobSize

    var body: some View {
        SynthSection(title: nil) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !synth.isPlaying)) { context in
                let blink = Int(context.date.timeIntervalSinceReferenceDate * 4) % 2 == 0
                let clockStep = synth.isPlaying ? synth.currentDrumStep : nil
                let shownPage = followsPlayhead ? (clockStep.map { $0 / 8 } ?? page) : page
                // The running light shows only on the bank that is actually playing.
                let playing = synth.playingDrumBank == synth.drums.activeBank ? clockStep : nil
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        TrackSwitch(
                            title: "Drums",
                            isOn: synth.drums.enabled,
                            isArmed: synth.isPlaying && synth.drumsArmed,
                            blink: blink
                        ) { synth.drums.enabled.toggle() }
                        Spacer(minLength: 4)
                        RetroSegmented(
                            options: [0, 1],
                            selection: Binding(get: { shownPage }, set: { newPage in
                                page = newPage
                                followsPlayhead = false
                            }),
                            accessibilityName: { $0 == 0 ? Text("Steps 1 to 8") : Text("Steps 9 to 16") }
                        ) { page, isSelected in
                            Text(verbatim: page == 0 ? "1–8" : "9–16")
                                .font(Retro.label(9))
                                .foregroundStyle(isSelected ? Color.black : Retro.cream)
                        }
                        .frame(width: 96)
                    }
                    .overlay(alignment: .trailing) { UndoBanner(offer: $undo) }

                    bankTools
                    bankRow(blink: blink)
                        .opacity(synth.drums.enabled ? 1 : 0.45)

                    // Dimmed while the track is off; still editable.
                    VStack(spacing: 4) {
                        ForEach(DrumKind.allCases, id: \.self) { drum in
                            row(drum, page: shownPage, playing: playing)
                        }
                    }
                    .opacity(synth.drums.enabled ? 1 : 0.45)

                    HStack(spacing: 0) {
                        PatchKnob(synth: synth, param: .drumVolume, label: "VOLUME", size: knobSize - 4)
                        PatchKnob(synth: synth, param: .drumReverbSend, label: "REV SEND", size: knobSize - 4)
                        PatchKnob(synth: synth, param: .drumDelaySend, label: "DLY SEND", size: knobSize - 4)
                        PatchKnob(synth: synth, param: .drumComp, label: "COMP", size: knobSize - 4)
                        PatchKnob(synth: synth, param: .drumDrive, label: "DRIVE", size: knobSize - 4)
                    }
                }
            }
        }
        .onChange(of: synth.isPlaying) { _, isPlaying in
            if isPlaying { followsPlayhead = true }
        }
    }

    /// Randomize pattern, Randomize drum sounds, Copy, Paste and Clear for the selected drum
    /// bank: five equal buttons across the row.
    private var bankTools: some View {
        let bank = synth.drums.activeBank
        let letter = SequencerTab.bankLetter(bank)
        return HStack(spacing: 4) {
            ToolButton(symbol: "dice", label: "Randomize pattern", accessibility: Text("Randomize pattern"),
                       tint: Retro.accent, width: nil, rotation: diceTurns * 360) {
                randomizeBank(bank)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: diceTurns)
            ToolButton(symbol: "", label: "Randomize drum sounds", accessibility: Text("Randomize drum sounds"),
                       tint: Retro.accent, width: nil,
                       icon: AnyView(DrumSparkleIcon()
                           .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                           .frame(width: 17, height: 15)
                           .scaleEffect(soundTurns.truncatingRemainder(dividingBy: 2) == 1 ? 1.12 : 1))) {
                randomizeSounds()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: soundTurns)
            ToolButton(symbol: "doc.on.doc", label: "Copy", accessibility: Text("Copy drum bank \(letter)"), width: nil) {
                synth.drumBankClipboard = synth.drumBankPattern(bank)
            }
            ToolButton(symbol: "doc.on.clipboard", label: "Paste", accessibility: Text("Paste into drum bank \(letter)"), width: nil) {
                if let clip = synth.drumBankClipboard { synth.setDrumBankPattern(bank, clip) }
            }
            .disabled(synth.drumBankClipboard == nil)
            ToolButton(symbol: "trash", label: "Clear", accessibility: Text("Clear drum bank \(letter)"), width: nil) {
                clearBank(bank)
            }
        }
        .padding(.vertical, -7) // drawn 30 pt high; the 44 pt touch areas overlap the gaps
    }

    /// New variant, tuning and decay for every drum; levels, mutes and patterns stay. Takes effect
    /// on the next hits, so a running pattern never clicks.
    private func randomizeSounds() {
        let before = synth.drums
        var rng = SystemRandomNumberGenerator()
        synth.drums = PatternRandomizer.drumSounds(for: before, using: &rng)
        withAnimation(.spring(duration: 0.3)) { soundTurns += 1 }
        withAnimation(.easeOut(duration: 0.2)) {
            panelToast.offer.offer(Text("Drum sounds randomized"), seconds: 5) { [synth] in
                synth.drums = synth.drums.withSounds(from: before) // only the sounds go back
            }
        }
    }

    /// New beat for the selected drum bank (swaps in on the next bar while playing).
    private func randomizeBank(_ bank: Int) {
        let before = synth.drumBankPattern(bank)
        var rng = SystemRandomNumberGenerator()
        synth.replaceDrumBank(bank, with: PatternRandomizer.beat(using: &rng))
        withAnimation(.easeInOut(duration: 0.3)) { diceTurns += 1 }
        withAnimation(.easeOut(duration: 0.2)) {
            panelToast.offer.offer(Text("Pattern randomized"), seconds: 5) { [synth] in synth.replaceDrumBank(bank, with: before) }
        }
    }

    /// Clears every drum's steps in a bank at once (sounds stay) and offers a short Undo.
    private func clearBank(_ bank: Int) {
        let before = synth.drumBankPattern(bank)
        guard before.contains(where: { $0.contains(true) }) else { return }
        synth.setDrumBankPattern(bank, DrumKit.emptyPattern)
        undo.offer(Text("Drum bank \(SequencerTab.bankLetter(bank)) cleared")) { [synth] in synth.setDrumBankPattern(bank, before) }
    }

    /// A to H, same as the Sequencer's bank row; drum banks switch at the end of the bar.
    private func bankRow(blink: Bool) -> some View {
        BankRow(
            selected: synth.drums.activeBank,
            playing: synth.playingDrumBank,
            trackRuns: synth.isPlaying && synth.drums.enabled && !synth.drumsArmed,
            blink: blink,
            canPaste: synth.drumBankClipboard != nil,
            select: { synth.selectDrumBank($0) },
            copy: { synth.drumBankClipboard = synth.drumBankPattern($0) },
            paste: { bank in if let clip = synth.drumBankClipboard { synth.setDrumBankPattern(bank, clip) } },
            clear: { clearBank($0) }
        )
    }

    private func row(_ drum: DrumKind, page: Int, playing: Int?) -> some View {
        let muted = synth.drums[drum].muted
        return HStack(spacing: 3) {
            Button {
                synth.drums[drum].muted.toggle()
            } label: {
                Text(verbatim: "M")
                    .font(Retro.label(9))
                    .foregroundStyle(muted ? Color.black : Retro.cream.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(muted ? Retro.accent : Retro.knobBottom, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                    .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(.black.opacity(0.6), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Mute \(Text(drum.title))"))
            .accessibilityValue(muted ? Text("Muted") : Text("Playing"))

            Button {
                editing = drum
            } label: {
                HStack(spacing: 2) {
                    Text(drum.shortTitle)
                        .font(Retro.label(8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 7))
                }
                .foregroundStyle(Retro.cream)
                .frame(width: 50, height: 22)
                .background(Retro.knobBottom, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(Text(drum.title)) sound"))
            .accessibilityHint("Opens level, tune and decay")
            .popover(isPresented: Binding(get: { editing == drum }, set: { if !$0 { editing = nil } })) {
                DrumSoundPopup(synth: synth, drum: drum)
                    .presentationCompactAdaptation(.popover)
            }

            ForEach((page * 8)..<(page * 8 + 8), id: \.self) { step in
                stepCell(drum, step, isPlaying: playing == step)
            }
        }
        .opacity(muted ? 0.55 : 1)
    }

    private func stepCell(_ drum: DrumKind, _ step: Int, isPlaying: Bool) -> some View {
        let isOn = synth.drums.pattern[drum.rawValue][step]
        let isBeat = step % 4 == 0
        return Button {
            synth.toggleDrumStep(drum, step)
        } label: {
            RoundedRectangle(cornerRadius: Retro.buttonRadius)
                .fill(isOn ? Retro.accent : (isPlaying ? Retro.cream.opacity(0.35) : (isBeat ? Retro.knobTop : Retro.knobBottom)))
                .overlay {
                    RoundedRectangle(cornerRadius: Retro.buttonRadius)
                        .stroke(isPlaying ? Retro.cream : .black.opacity(0.6), lineWidth: isPlaying ? 2 : 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(Text(drum.title)) step \(step + 1)"))
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

/// Popup with the sound controls of one drum: variant picker, then level, tune and decay.
private struct DrumSoundPopup: View {
    let synth: SynthEngine
    let drum: DrumKind

    private var variant: Int { synth.drums[drum].variant }

    var body: some View {
        VStack(spacing: 8) {
            Text(drum.title)
                .textCase(.uppercase)
                .font(Retro.label(11))
                .tracking(2)
                .foregroundStyle(Retro.accent)

            // ‹ Variant name ›  with one dot per variant.
            HStack(spacing: 6) {
                variantArrow("chevron.left", label: "Previous sound") { synth.setDrumVariant(drum, variant - 1) }
                VStack(spacing: 4) {
                    Text(drum.variantName(variant))
                        .font(Retro.label(12))
                        .foregroundStyle(Retro.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 5) {
                        ForEach(0..<DrumVariants.count, id: \.self) { index in
                            Circle()
                                .fill(index == variant ? Retro.accent : Retro.cream.opacity(0.25))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(Text(drum.title)) sound"))
                .accessibilityValue(Text("\(Text(drum.variantName(variant))), \(variant + 1) of \(DrumVariants.count)"))
                .accessibilityAdjustableAction { direction in
                    synth.setDrumVariant(drum, variant + (direction == .increment ? 1 : -1))
                }
                variantArrow("chevron.right", label: "Next sound") { synth.setDrumVariant(drum, variant + 1) }
            }

            HStack(spacing: 4) {
                PatchKnob(synth: synth, param: SynthParam.drumLevel(drum), label: "LEVEL", size: 40)
                PatchKnob(synth: synth, param: SynthParam.drumTune(drum), label: "TUNE", size: 40)
                PatchKnob(synth: synth, param: SynthParam.drumDecay(drum), label: "DECAY", size: 40,
                          range: DrumVariants.decayRange(drum, variant))
            }
        }
        .frame(width: 200)
        .padding(12)
        .presentationBackground(Retro.section)
        .preferredColorScheme(.dark)
    }

    private func variantArrow(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Retro.cream)
                .frame(width: 30, height: 30)
                .background(Retro.knobBottom, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .frame(width: 44, height: 44) // larger touch area
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Key mode

extension KeyMode {
    var title: LocalizedStringKey {
        switch self {
        case .off: "OFF"
        case .transpose: "TRANSPOSE"
        case .arp: "ARP"
        }
    }
}

extension ArpDirection {
    var symbol: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .upDown: "arrow.up.arrow.down"
        case .random: "shuffle"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .upDown: "Up-down"
        case .random: "Random"
        }
    }
}

/// Small readout in the transport row saying what the keyboard does right now.
struct KeysIndicator: View {
    let mode: KeyMode
    let hold: Bool
    let editingStep: Int?

    var body: some View {
        VStack(spacing: 1) {
            Text(editingStep == nil ? "KEYS" : "EDIT")
                .font(Retro.label(8))
                .foregroundStyle(Retro.cream.opacity(0.6))
            Group {
                if let editingStep {
                    Text("STEP \(editingStep + 1)")
                } else if mode == .off {
                    Text("PLAY NOTES")
                } else if hold {
                    Text("\(Text(mode.title)) · HOLD")
                } else {
                    Text(mode.title)
                }
            }
            .font(Retro.label(10))
            .foregroundStyle(editingStep != nil || mode != .off ? Retro.accent : Retro.cream.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Track switch

/// On/off switch for a track on the master clock. While it waits for the next bar after being
/// switched on during playback ("armed"), it blinks.
struct TrackSwitch: View {
    let title: LocalizedStringKey
    let isOn: Bool
    let isArmed: Bool
    let blink: Bool
    let action: () -> Void

    var body: some View {
        let lit = isOn && (!isArmed || blink)
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(lit ? Retro.accent : Retro.knobBottom)
                    .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
                    .shadow(color: lit ? Retro.accent.opacity(0.9) : .clear, radius: 4)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(Retro.label(10))
                    .foregroundStyle(Retro.cream)
                Text(isArmed ? "Waiting for bar" : (isOn ? "On" : "Off"))
                    .font(Retro.label(9))
                    .foregroundStyle(isOn ? Retro.accent : Retro.cream.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Retro.knobBottom.opacity(0.6), in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
            .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(.black.opacity(0.6), lineWidth: Retro.buttonBorder) }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isArmed ? Text("Starts at the next bar") : (isOn ? Text("On") : Text("Off")))
    }
}

// MARK: - Small tools

/// A small icon button with a 44 pt touch area.
/// A drum with a small four-point sparkle at its top right ("Randomize drum sounds").
struct DrumSparkleIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        // Drum: top rim (ellipse), sides, bottom curve.
        let left = rect.minX + w * 0.04, right = rect.minX + w * 0.74
        let rimY = rect.minY + h * 0.42, bottomY = rect.minY + h * 0.86, rimH = h * 0.26
        path.addEllipse(in: CGRect(x: left, y: rimY - rimH / 2, width: right - left, height: rimH))
        path.move(to: CGPoint(x: left, y: rimY))
        path.addLine(to: CGPoint(x: left, y: bottomY))
        path.addQuadCurve(to: CGPoint(x: right, y: bottomY), control: CGPoint(x: (left + right) / 2, y: bottomY + rimH))
        path.addLine(to: CGPoint(x: right, y: rimY))
        // Sparkle: four points curving in towards the centre.
        let c = CGPoint(x: rect.minX + w * 0.86, y: rect.minY + h * 0.17), r = w * 0.15
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        return path
    }
}

struct ToolButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let accessibility: Text
    /// Icon colour (cream by default).
    var tint: Color = Retro.cream
    /// Drawn width; nil stretches to share a row equally.
    var width: CGFloat? = 34
    /// Icon rotation in degrees (the dice spins when tapped).
    var rotation: Double = 0
    /// A drawn icon used instead of the SF Symbol.
    var icon: AnyView? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    icon
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
                .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.3))
                .rotationEffect(.degrees(rotation))
                .frame(maxWidth: width ?? .infinity)
                .frame(width: width, height: 30)
                .background(Retro.knobBottom.opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(.black.opacity(0.6), lineWidth: Retro.buttonBorder) }
                .frame(minWidth: width == nil ? 0 : 44, maxWidth: width == nil ? .infinity : nil, minHeight: 44, maxHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .help(Text(label))
    }
}

/// The panel-wide "Pattern randomized · Undo" toast, shared by the Sequencer and Drums tabs
/// and shown at the top of the tab panel (see `ContentView.tabPanel`).
@Observable
final class PanelToast {
    var offer = UndoOffer()

    /// Hides it at once (Undo, a tab switch, or a tap elsewhere on the panel).
    func dismiss() {
        guard offer.message != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) { offer.dismiss() }
    }
}

/// A destructive action that can be taken back for a few seconds.
struct UndoOffer {
    var message: Text?
    var restore: (() -> Void)?
    var id = 0
    /// How long the banner stays.
    var seconds: Double = 4
    /// When it was offered (so the tap that showed it doesn't also dismiss it).
    var shownAt = Date.distantPast

    mutating func offer(_ message: Text, seconds: Double = 4, restore: @escaping () -> Void) {
        self.message = message
        self.restore = restore
        self.seconds = seconds
        shownAt = .now
        id += 1
    }

    mutating func dismiss() {
        message = nil
        restore = nil
    }
}

/// "Bank A cleared · Undo" banner that disappears after a few seconds.
struct UndoBanner: View {
    @Binding var offer: UndoOffer
    var transition: AnyTransition = .opacity

    var body: some View {
        if let message = offer.message {
            HStack(spacing: 8) {
                message
                    .font(Retro.label(9))
                    .foregroundStyle(Retro.cream)
                    .lineLimit(1)
                Button {
                    offer.restore?()
                    offer.dismiss()
                } label: {
                    Text("Undo")
                        .font(Retro.label(10))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(Retro.accent, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .background(Retro.panel, in: RoundedRectangle(cornerRadius: Retro.buttonRadius + 2))
            .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius + 2).stroke(Retro.accent.opacity(0.7), lineWidth: Retro.buttonBorder) }
            .transition(transition)
            .task(id: offer.id) {
                try? await Task.sleep(for: .seconds(offer.seconds))
                if !Task.isCancelled { withAnimation { offer.dismiss() } }
            }
        }
    }
}

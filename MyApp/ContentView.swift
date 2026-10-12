import SwiftUI

struct ContentView: View {
    @State private var synth = SynthEngine()
    @State private var presets = PresetStore()
    @State private var midi = MIDIManager()
    @State private var tab: SynthTab = .envelope
    /// Sequencer step that keyboard presses write into (Sequencer tab only).
    @State private var selectedStep: Int?
    /// Octave number of the keyboard's leftmost C (C4 = middle C).
    @State private var keyboardOctave = 4
    /// Keys pressed while editing a step: they only preview the note, whatever the key mode.
    @State private var previewNotes: Set<Int> = []
    /// Visible height of the scrolling middle part and of the panels above the tabs,
    /// so the tab panel can fill the rest.
    @State private var scrollHeight: CGFloat = 0
    @State private var upperHeight: CGFloat = 0
    /// Keys held on either on-screen keyboard, so they can all be released when the phone rotates.
    @State private var heldKeys: Set<Int> = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Content stays inside the safe area (clear of the Dynamic Island and home indicator);
        // only the panel colour behind it reaches the screen edges.
        GeometryReader { screen in
            let isLandscape = screen.size.width > screen.size.height
            ZStack {
                VStack(spacing: 6) {
                    PresetBar(synth: synth, store: presets, load: load)
                        .padding(.top, 4)

                    // The middle of the panel scrolls only when it doesn't fit (e.g. iPhone SE);
                    // the transport and keyboard below always stay put.
                    ScrollView {
                        VStack(spacing: 6) {
                            VStack(spacing: 6) {
                                HStack(alignment: .top, spacing: 6) {
                                    oscillatorSection("Osc 1", number: 1, wave: .osc1Wave, level: .osc1Level, octave: .osc1Octave, detune: .osc1Detune)
                                    oscillatorSection("Osc 2", number: 2, wave: .osc2Wave, level: .osc2Level, octave: .osc2Octave, detune: .osc2Detune)
                                }
                                HStack(alignment: .top, spacing: 6) {
                                    SynthSection(title: "Filter") {
                                        HStack(spacing: 0) {
                                            PatchKnob(synth: synth, param: .cutoff, label: "CUTOFF")
                                            PatchKnob(synth: synth, param: .resonance, label: "RESO")
                                            PatchKnob(synth: synth, param: .filterEnvAmount, label: "ENV AMT")
                                        }
                                    }
                                    lfoSection
                                    SynthSection(title: "Master") {
                                        PatchKnob(synth: synth, param: .masterVolume, label: "VOLUME")
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                                .equalHeightRow()
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { upperHeight = $0 }

                            // Reaches down to the transport bar when there is room; grows (and the
                            // middle scrolls) when a tab needs more.
                            tabPanel(minHeight: max(scrollHeight - upperHeight - 6, 0))
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
                    .scrollBounceBehavior(.basedOnSize)

                    transportRow
                    KeyboardView(baseNote: (keyboardOctave + 1) * 12, noteOn: keyboardDown, noteOff: keyboardUp)
                        .frame(height: Self.keyboardHeight(forScreenHeight: screen.size.height))
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
                // Narrow phones (iPhone SE, 375 pt) get slightly smaller knobs so every row fits.
                .environment(\.knobSize, screen.size.width < 390 ? 31 : 36)
                // In landscape the normal UI stays alive (all its state kept), just hidden.
                .opacity(isLandscape ? 0 : 1)
                .allowsHitTesting(!isLandscape)
                .accessibilityHidden(isLandscape)

                if isLandscape {
                    // The same transport bar as in portrait, with the keys below it.
                    VStack(spacing: 6) {
                        transportRow
                            .padding(.top, 6)
                        LandscapeKeyboardView(baseNote: landscapeBaseNote, noteOn: keyboardDown, noteOff: keyboardUp)
                            .ignoresSafeArea(edges: .bottom) // keys reach the bottom edge
                            .defersSystemGestures(on: .bottom)
                    }
                    .padding(.horizontal, 6) // the sides stay clear of the Dynamic Island
                }
            }
            .onChange(of: isLandscape) { _, _ in releaseHeldKeys() }
        }
        // Same dark brown as the launch screen, under the status bar and home indicator too.
        .background(Retro.panel.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            // Opens on Rain Brass (falls back to the first factory preset if it's ever missing).
            let startup = presets.factory.first { $0.patch.name == String(localized: "Rain Brass") } ?? presets.factory.first
            if presets.currentID == nil, let startup { load(startup) }
            synth.start()
            midi.start(engine: synth)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                synth.allNotesOff()
                synth.saveDrumsNow()
            }
        }
        .onChange(of: tab) { _, _ in selectedStep = nil }
        .environment(midi)
        .overlay(alignment: .top) {
            MIDILearnBanner(midi: midi)
                .padding(.top, 50)
                .animation(.easeInOut(duration: 0.2), value: midi.learningParam)
        }
        .overlay(alignment: .top) {
            if let message = synth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .padding(10)
                    .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
    }

    /// Keys grow with the screen: about 15% of the usable height, within playable limits.
    static func keyboardHeight(forScreenHeight height: CGFloat) -> CGFloat {
        min(max(height * 0.15, 96), 132)
    }

    /// Switches sound without stopping the sequencer; the audio thread glides to the new values.
    /// Drums change only with presets that saved them; others leave the current drums alone.
    private func load(_ preset: PresetStore.Preset) {
        var patch = preset.patch
        let kit = patch.drumKit
        // Factory presets with drums carry a whole groove: sequencer, tempo and drums swap in
        // together on the next bar.
        if preset.isFactory, kit != nil {
            synth.loadPattern(preset.patch, drums: kit)
            presets.markCurrent(preset)
            return
        }
        patch.drumKit = nil // the engine keeps its drums separately
        synth.patch = patch
        if let kit { synth.loadDrums(kit) } // while playing, the new patterns start on the next bar
        presets.markCurrent(preset)
    }


    /// Landscape keyboard's lowest C: the portrait octave setting, lowered if needed so the
    /// top key stays within MIDI range (0...127).
    private var landscapeBaseNote: Int {
        let highestBase = (127 - LandscapeKeyboardView.octaves * 12) / 12 * 12
        return min((keyboardOctave + 1) * 12, highestBase)
    }

    private func keyboardDown(_ note: Int) {
        heldKeys.insert(note)
        keyDown(note)
    }

    /// Ignores keys already released (e.g. by a rotation).
    private func keyboardUp(_ note: Int) {
        guard heldKeys.remove(note) != nil else { return }
        keyUp(note)
    }

    /// Releases every key held on screen, so nothing hangs when the layout switches.
    private func releaseHeldKeys() {
        let held = heldKeys
        heldKeys.removeAll()
        held.forEach(keyUp)
    }

    /// Step being edited from the keyboard, if any (only in the Sequencer tab).
    private var editingStep: Int? {
        tab == .sequencer ? selectedStep : nil
    }

    /// With a step selected for editing, a key writes (or clears) that step and previews the
    /// note, whatever the key mode. Otherwise the key goes to the synth: in Off it plays the
    /// note, in Transpose and Arp it drives the sequencer and writes nothing.
    private func keyDown(_ note: Int) {
        if let step = editingStep {
            previewNotes.insert(note)
            synth.noteOn(note)
            synth.toggleStep(step, note: note)
        } else {
            synth.keyDown(note)
        }
    }

    private func keyUp(_ note: Int) {
        if previewNotes.remove(note) != nil {
            synth.noteOff(note)
        } else {
            synth.keyUp(note)
        }
    }

    // MARK: - Sections

    /// One box: the tab buttons on top, the selected tab's content below (cross-fades on change).
    /// Same fill, border and corner radius as every `SynthSection`.
    private func tabPanel(minHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            TabSelector(selection: $tab)
            ZStack(alignment: .top) {
                Group {
                    switch tab {
                    case .envelope: EnvelopeTab(synth: synth)
                    case .sequencer: SequencerTab(synth: synth, selectedStep: $selectedStep)
                    case .effects: EffectsTab(synth: synth)
                    case .drums: DrumsTab(synth: synth)
                    }
                }
                .environment(\.drawsSectionBox, false)
                .id(tab)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.15), value: tab)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
        .background(Retro.section, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Retro.sectionEdge, lineWidth: 1) }
    }

    /// Play / Stop, tempo, key mode and octave: above the keyboard in portrait and landscape.
    private var transportRow: some View {
        HStack(spacing: 4) {
            TransportBar(synth: synth)
            KeysIndicator(mode: synth.patch.sequencer.enabled ? synth.patch.sequencer.keyMode : .off, hold: synth.patch.sequencer.hold, editingStep: editingStep)
                .frame(maxWidth: .infinity)
            octaveControls
        }
    }

    private func oscillatorSection(_ title: LocalizedStringKey, number: Int, wave: SynthParam, level: SynthParam, octave: SynthParam, detune: SynthParam) -> some View {
        SynthSection(title: title) {
            RetroSegmented(
                options: Waveform.allCases,
                selection: Binding(
                    get: { Waveform(rawValue: Int(synth.value(wave))) ?? .saw },
                    set: { synth.set(wave, Float($0.rawValue)) }
                ),
                accessibilityName: { Text("Oscillator \(number) waveform: \($0.name)") }
            ) { shape, isSelected in
                WaveShape(wave: shape)
                    .stroke(isSelected ? Color.black : Retro.cream, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 12)
            }
            HStack(spacing: 0) {
                PatchKnob(synth: synth, param: level, label: "LEVEL")
                PatchKnob(synth: synth, param: octave, label: "OCTAVE")
                PatchKnob(synth: synth, param: detune, label: "DETUNE")
            }
        }
    }

    private var lfoSection: some View {
        SynthSection(title: "LFO") {
            HeaderPillButton(title: synth.patch.lfo.destination == .pitch ? "PITCH" : "CUTOFF") {
                synth.patch.lfo.destination = synth.patch.lfo.destination == .pitch ? .cutoff : .pitch
            }
            .accessibilityLabel("LFO destination")
            .accessibilityValue(synth.patch.lfo.destination == .pitch ? Text("Pitch") : Text("Cutoff"))
            .accessibilityHint("Switches what the LFO modulates")
        } content: {
            HStack(spacing: 0) {
                PatchKnob(synth: synth, param: .lfoRate, label: "RATE")
                PatchKnob(synth: synth, param: .lfoAmount, label: "AMOUNT")
            }
        }
    }

    private var octaveControls: some View {
        HStack(spacing: 6) {
            octaveButton("minus", enabled: keyboardOctave > 1) { keyboardOctave -= 1 }
            VStack(spacing: 0) {
                Text(verbatim: "C\(keyboardOctave)")
                    .font(Retro.label(16))
                    .foregroundStyle(Retro.accent)
                Text("OCTAVE")
                    .font(Retro.label(8))
                    .foregroundStyle(Retro.cream.opacity(0.6))
            }
            .frame(width: 50)
            .accessibilityElement(children: .combine)
            octaveButton("plus", enabled: keyboardOctave < 7) { keyboardOctave += 1 }
        }
    }

    private func octaveButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(Retro.cream)
                .frame(width: 46, height: 38)
                .background(Retro.section, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(symbol == "plus" ? Text("Octave up") : Text("Octave down"))
    }
}

#Preview {
    ContentView()
}

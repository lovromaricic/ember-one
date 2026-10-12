import SwiftUI

/// Typing an exact knob value: parsing in the knob's own unit, range limits, and the sheet.
nonisolated enum KnobValueInput {
    /// The unit a typed number is read in, shown as a suffix next to the field.
    struct EditUnit: Equatable {
        let suffix: String
        /// Parameter value = typed number × factor.
        let factor: Float
    }

    /// Edit unit for a parameter at its current value: the unit its label shows
    /// (Hz stays Hz even above 1 kHz, so "2000" means 2000 Hz; "2k" also works).
    static func editUnit(for unit: SynthParam.Unit, value: Float) -> EditUnit {
        switch unit {
        case .percent, .bipolarPercent: EditUnit(suffix: "%", factor: 0.01)
        case .cents: EditUnit(suffix: "ct", factor: 1)
        case .hertz: EditUnit(suffix: "Hz", factor: 1)
        case .seconds: value < 1 ? EditUnit(suffix: "ms", factor: 0.001) : EditUnit(suffix: "s", factor: 1)
        case .bpm: EditUnit(suffix: "BPM", factor: 1)
        case .semitones: EditUnit(suffix: "st", factor: 1)
        case .octave, .steps, .choice, .division: EditUnit(suffix: "", factor: 1)
        }
    }

    /// The current value as editable text (no suffix; the suffix is shown beside the field).
    static func text(for value: Float, unit: SynthParam.Unit, editUnit: EditUnit) -> String {
        if unit == .division {
            let index = min(max(Int(value.rounded()), 0), SynthParam.pumpDivisions.count - 1)
            return SynthParam.pumpDivisions[index].label
        }
        let number = value / editUnit.factor
        let rounded = (number * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
    }

    /// Reads what the user typed: "." or "," as decimal separator, an optional sign, and an
    /// optional unit suffix (k / kHz / Hz, ms / s, %, ct, st, BPM). Returns the value in the
    /// parameter's own units, unclamped, or nil if it isn't a valid entry.
    static func parse(_ input: String, unit: SynthParam.Unit, editUnit: EditUnit) -> Float? {
        var text = input.lowercased().replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }

        if unit == .division {
            return SynthParam.pumpDivisions.firstIndex { $0.label == text }.map(Float.init)
        }

        // Split the number from the suffix.
        var numberPart = ""
        while let c = text.first, c.isNumber || c == "." || ((c == "-" || c == "+") && numberPart.isEmpty) {
            numberPart.append(c)
            text.removeFirst()
        }
        guard let number = Float(numberPart), number.isFinite else { return nil }

        let factor: Float? = switch (unit, text) {
        case (_, ""): editUnit.factor
        case (.hertz, "hz"): 1
        case (.hertz, "k"), (.hertz, "khz"): 1000
        case (.seconds, "ms"): 0.001
        case (.seconds, "s"), (.seconds, "sec"): 1
        case (.percent, "%"), (.bipolarPercent, "%"): 0.01
        case (.cents, "ct"), (.cents, "c"), (.cents, "cents"): 1
        case (.semitones, "st"): 1
        case (.bpm, "bpm"): 1
        default: nil
        }
        guard let factor else { return nil }
        return number * factor
    }

    /// Typed value limited to the knob's range (and rounded to its steps). `limit` is the bound
    /// it was pushed to, if it had to be limited.
    static func limited(_ value: Float, param: SynthParam, range: ClosedRange<Float>) -> (value: Float, limit: Float?) {
        let inRange = min(max(value, range.lowerBound), range.upperBound)
        let result = param.clamped(inRange)
        let limit: Float? = value < range.lowerBound ? range.lowerBound : (value > range.upperBound ? range.upperBound : nil)
        return (result, limit)
    }

    /// "20 – 20000 Hz", "1 – 5000 ms", "-50 – 50 ct"…
    static func rangeText(_ range: ClosedRange<Float>, unit: SynthParam.Unit, editUnit: EditUnit) -> String {
        if unit == .division { return SynthParam.pumpDivisions.map(\.label).joined(separator: ", ") }
        let lo = text(for: range.lowerBound, unit: unit, editUnit: editUnit)
        let hi = text(for: range.upperBound, unit: unit, editUnit: editUnit)
        return editUnit.suffix.isEmpty ? "\(lo) – \(hi)" : "\(lo) – \(hi) \(editUnit.suffix)"
    }
}

/// Sheet for typing a knob's exact value. Same look as the Save preset sheet.
struct KnobValueEditor: View {
    let param: SynthParam
    let range: ClosedRange<Float>
    let current: Float
    let set: (Float) -> Void
    let reset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// The current value starts selected, so typing replaces it.
    @State private var selection: TextSelection?
    @State private var note: String?
    @State private var contentHeight: CGFloat = 260
    @FocusState private var focused: Bool

    @ScaledMetric(relativeTo: .caption) private var hintSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 17

    private var editUnit: KnobValueInput.EditUnit { KnobValueInput.editUnit(for: param.unit, value: current) }
    private var parsed: Float? { KnobValueInput.parse(text, unit: param.unit, editUnit: editUnit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(param.displayName)
                .font(.headline.bold())
                .foregroundStyle(Retro.cream)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Value", text: Binding(get: { text }, set: { text = $0; note = nil }), selection: $selection)
                        .keyboardType(.numbersAndPunctuation) // digits, minus, "." and ","; letters for "k", "ms"
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(apply)
                        .foregroundStyle(Retro.cream)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    if !editUnit.suffix.isEmpty {
                        Text(verbatim: editUnit.suffix)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(PresetSheetStyle.muted)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(PresetSheetStyle.searchFill, in: Capsule())

                Group {
                    if let note {
                        Text(note).foregroundStyle(Retro.accent)
                    } else if !text.isEmpty, parsed == nil {
                        Text("Enter a number.").foregroundStyle(.red)
                    } else {
                        Text(KnobValueInput.rangeText(range, unit: param.unit, editUnit: editUnit))
                            .foregroundStyle(PresetSheetStyle.muted)
                    }
                }
                .font(.system(size: hintSize))
                .padding(.horizontal, 16)
            }

            HStack(spacing: 8) {
                sheetButton("Reset", filled: false) {
                    reset()
                    dismiss()
                }
                .accessibilityLabel(Text("Reset \(param.displayName) to default"))
                sheetButton("Cancel", filled: false) { dismiss() }
                sheetButton("Set", filled: true, action: apply)
                    .disabled(parsed == nil)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(PresetSheetStyle.background)
        .tint(Retro.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            text = KnobValueInput.text(for: current, unit: param.unit, editUnit: editUnit)
            focused = true
        }
        .onChange(of: focused) { _, isFocused in
            // Select everything once the field has focus, so the first key replaces the value.
            guard isFocused else { return }
            Task { @MainActor in
                selection = TextSelection(range: text.startIndex..<text.endIndex)
            }
        }
    }

    /// Sets the value; if it had to be limited, says so briefly before closing.
    private func apply() {
        guard let value = parsed else { return }
        let result = KnobValueInput.limited(value, param: param, range: range)
        set(result.value)
        if let limit = result.limit {
            let shown = KnobValueInput.text(for: limit, unit: param.unit, editUnit: editUnit)
            text = KnobValueInput.text(for: result.value, unit: param.unit, editUnit: editUnit)
            note = String(localized: "Limited to \(shown) \(editUnit.suffix)").trimmingCharacters(in: .whitespaces)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    private func sheetButton(_ title: LocalizedStringKey, filled: Bool, action: @escaping () -> Void) -> some View {
        SheetButton(title: title, filled: filled, size: buttonSize, action: action)
    }
}

private struct SheetButton: View {
    let title: LocalizedStringKey
    let filled: Bool
    let size: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(filled ? (isEnabled ? PresetSheetStyle.background : PresetSheetStyle.muted) : Retro.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(filled ? (isEnabled ? Retro.accent : PresetSheetStyle.card) : Retro.section,
                            in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .overlay {
                    if !filled {
                        RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: Retro.buttonBorder)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

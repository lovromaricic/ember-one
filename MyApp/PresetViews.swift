import SwiftUI

/// Top bar: previous / next preset, the name (tap to browse) and the save button.
struct PresetBar: View {
    let synth: SynthEngine
    let store: PresetStore
    let load: (PresetStore.Preset) -> Void

    @State private var showsBrowser = false
    @State private var showsSave = false
    @State private var showsMIDI = false
    @Environment(MIDIManager.self) private var midi: MIDIManager?

    private var isModified: Bool {
        guard let current = store.current else { return true }
        return !current.patch.hasSameSound(as: synth.patch)
    }

    var body: some View {
        HStack(spacing: 6) {
            arrow("chevron.left", label: "Previous preset") { store.neighbour(offset: -1).map(load) }

            Button {
                showsBrowser = true
            } label: {
                // Left-aligned: the tag keeps its size and a long name ends in "…".
                presetTitle
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(Retro.knobBottom, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the preset list")

            arrow("chevron.right", label: "Next preset") { store.neighbour(offset: 1).map(load) }

            Button {
                showsSave = true
            } label: {
                FloppyIcon()
                    .stroke(Retro.cream, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .frame(width: 18, height: 18)
                    .frame(width: 40, height: 36)
                    .background(Retro.section, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                    .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save preset")

            if let midi {
                MIDIStatusButton(midi: midi) { showsMIDI = true }
            }
        }
        .sheet(isPresented: $showsMIDI) {
            if let midi { MIDISheet(midi: midi) }
        }
        .sheet(isPresented: $showsBrowser) {
            PresetBrowser(store: store) { preset in
                load(preset)
            }
        }
        .sheet(isPresented: $showsSave) {
            PresetNameSheet(
                title: "Save preset",
                initialName: "",
                initialCategory: synth.patch.category,
                validate: { store.validate(name: $0, excluding: store.userPreset(named: $0)?.id) },
                replaces: { store.userPreset(named: $0) != nil }
            ) { name, category, includesDrums in
                // Sound and sequencer always; the drum machine when "Include drums" is on.
                var patch = synth.patch
                patch.drumKit = includesDrums ? synth.drums : nil
                let preset = try store.save(patch, name: name, category: category)
                synth.patch.name = preset.patch.name
                synth.patch.category = preset.patch.category
            }
        }
    }

    private var presetTitle: some View {
        HStack(spacing: 8) {
            Text(synth.patch.category.title.uppercased())
                .font(Retro.label(8))
                .foregroundStyle(.black)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Retro.accent, in: RoundedRectangle(cornerRadius: 3))
                .fixedSize()
                .layoutPriority(1)
            Text(synth.patch.name)
                .font(Retro.label(14))
                .foregroundStyle(Retro.cream)
                .lineLimit(1)
                .truncationMode(.tail)
            if isModified {
                Circle().fill(Retro.accent).frame(width: 6, height: 6)
                    .accessibilityLabel("Modified")
            }
        }
    }

    private func arrow(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(Retro.cream)
                .frame(width: 36, height: 36)
                .background(Retro.section, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Colours and sizes of the preset sheet's "clean cards" look (also used by the MIDI sheet).
enum PresetSheetStyle {
    static let background = Color(red: 33 / 255, green: 26 / 255, blue: 22 / 255)     // #211A16
    static let searchFill = Color(red: 52 / 255, green: 41 / 255, blue: 34 / 255)     // #342922
    static let muted = Color(red: 150 / 255, green: 130 / 255, blue: 111 / 255)       // #96826F
    static let card = Color(red: 48 / 255, green: 38 / 255, blue: 31 / 255)          // #30261F
    static let cardSelected = Color(red: 62 / 255, green: 38 / 255, blue: 20 / 255)   // #3E2614
    static let hairline = Color(red: 66 / 255, green: 53 / 255, blue: 45 / 255)      // #42352D
    static let pill = Color(red: 58 / 255, green: 45 / 255, blue: 37 / 255)          // #3A2D25
    static let cardRadius: CGFloat = 16
    static let cardHeight: CGFloat = 54
    static let cardGap: CGFloat = 6
}

/// Sheet listing every preset as a card: favorites, the factory categories (Cinematic first),
/// then the user's own presets. Tapping a card loads it and keeps the sheet open.
struct PresetBrowser: View {
    let store: PresetStore
    let load: (PresetStore.Preset) -> Void

    private struct PresetGroup: Identifiable {
        let id: String
        let title: String
        let presets: [PresetStore.Preset]
    }

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var renaming: PresetStore.Preset?
    @State private var deleting: PresetStore.Preset?
    @State private var taps = 0
    /// Scrolls the loaded preset into view, in its own section (not in Favorites).
    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let current = store.current else { return }
        let group = current.isFactory ? "factory-\(current.patch.category.rawValue)" : "user"
        proxy.scrollTo("\(group)/\(current.id)", anchor: .center)
    }

    private var factoryOrder: [PresetCategory] {
        [.cinematic] + PresetCategory.allCases.filter { $0 != .cinematic }
    }

    private func matches(_ preset: PresetStore.Preset) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || preset.patch.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private struct Row {
        let id: String
        let title: String
        var preset: PresetStore.Preset?
    }

    private func rows(_ groups: [PresetGroup]) -> [Row] {
        groups.flatMap { group in
            [Row(id: group.id, title: group.title)]
                + group.presets.map { Row(id: "\(group.id)/\($0.id)", title: "", preset: $0) }
        }
    }

    private var groups: [PresetGroup] {
        var groups: [PresetGroup] = []
        let favorites = store.all.filter { store.isFavorite($0) && matches($0) }
        if !favorites.isEmpty {
            groups.append(PresetGroup(id: "favorites", title: String(localized: "Favorites"), presets: favorites))
        }
        for category in factoryOrder {
            let presets = store.factory.filter { $0.patch.category == category && matches($0) }
            if !presets.isEmpty {
                groups.append(PresetGroup(id: "factory-\(category.rawValue)", title: category.title, presets: presets))
            }
        }
        let user = store.user.filter(matches)
        if !user.isEmpty {
            groups.append(PresetGroup(id: "user", title: String(localized: "User"), presets: user))
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PresetSheetStyle.cardGap) {
                        let groups = groups
                        // One flat list of rows, so every card has a stable id to scroll to.
                        ForEach(rows(groups), id: \.id) { row in
                            if let preset = row.preset {
                                card(preset)
                            } else {
                                sectionHeader(row.title)
                            }
                        }
                        if groups.isEmpty {
                            hint("No presets match “\(search)”.")
                        } else if store.user.isEmpty && search.isEmpty {
                            sectionHeader(String(localized: "User"))
                            hint("No presets of your own yet. Save the current sound with the floppy disk button.")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .task {
                    // Wait until the sheet has laid out its rows, then bring the loaded preset into view.
                    try? await Task.sleep(for: .milliseconds(100))
                    scrollToCurrent(proxy)
                }
            }
        }
        .background(PresetSheetStyle.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationBackground(PresetSheetStyle.background)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .sheet(item: $renaming) { preset in
            PresetNameSheet(
                title: "Rename",
                initialName: preset.patch.name,
                initialCategory: preset.patch.category,
                validate: { store.validate(name: $0, excluding: preset.id) },
                offersDrums: false
            ) { name, category, _ in
                try store.rename(preset, to: name, category: category)
            }
        }
        .confirmationDialog(
            "Delete preset “\(deleting?.patch.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleting { store.delete(deleting) }
                deleting = nil
            }
        }
        .tint(Retro.accent)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ZStack {
            Text("Presets")
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
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PresetSheetStyle.muted)
            TextField("Search presets", text: $search, prompt: Text("Search presets").foregroundStyle(PresetSheetStyle.muted))
                .foregroundStyle(Retro.cream)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !search.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(PresetSheetStyle.muted)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(PresetSheetStyle.searchFill, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(PresetSheetStyle.muted)
            .padding(.leading, 4)
            .padding(.top, 18)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(PresetSheetStyle.muted)
            .padding(.horizontal, 4)
    }

    private func subtitle(for preset: PresetStore.Preset) -> String {
        if let tag = preset.patch.tag, !tag.isEmpty { return tag }
        if preset.isFactory { return preset.patch.category.title }
        if let date = preset.savedDate {
            return String(localized: "Saved \(date.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "User preset")
    }

    private func card(_ preset: PresetStore.Preset) -> some View {
        PresetCard(
            name: preset.patch.name,
            subtitle: subtitle(for: preset),
            hasDrums: preset.patch.drumKit != nil,
            isCurrent: preset.id == store.currentID,
            isFavorite: store.isFavorite(preset),
            select: {
                taps += 1
                load(preset)
            },
            toggleFavorite: { store.toggleFavorite(preset) }
        )
        .contextMenu {
            if !preset.isFactory {
                Button("Rename", systemImage: "pencil") { renaming = preset }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = preset }
            }
        }
    }
}

/// One preset in the sheet: name, subtitle and a star.
private struct PresetCard: View {
    let name: String
    let subtitle: String
    /// Saved with the drum machine: a small icon after the subtitle.
    let hasDrums: Bool
    let isCurrent: Bool
    let isFavorite: Bool
    let select: () -> Void
    let toggleFavorite: () -> Void

    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var subtitleSize: CGFloat = 12.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PresetSheetStyle.cardRadius)
        HStack(spacing: 0) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: nameSize, weight: .semibold))
                        .foregroundStyle(isCurrent ? Retro.accent : Retro.cream)
                    HStack(spacing: 5) {
                        Text(subtitle)
                            .font(.system(size: subtitleSize))
                            .foregroundStyle(isCurrent ? Retro.accent : PresetSheetStyle.muted)
                        if hasDrums {
                            Image(systemName: "waveform")
                                .font(.system(size: subtitleSize - 1, weight: .semibold))
                                .foregroundStyle(PresetSheetStyle.muted)
                                .accessibilityLabel("Includes drums")
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: PresetSheetStyle.cardHeight, alignment: .leading)
                .padding(.leading, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityHint("Loads this preset")

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Retro.accent : PresetSheetStyle.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .background(isCurrent ? PresetSheetStyle.cardSelected : PresetSheetStyle.card, in: shape)
        .overlay {
            if isCurrent { shape.strokeBorder(Retro.accent, lineWidth: 1.5) }
        }
    }
}

/// Name + category sheet used for saving and renaming, with live duplicate checking.
/// Same look as the Presets sheet: dark brown, pill name field, category chips, big buttons.
struct PresetNameSheet: View {
    let title: LocalizedStringKey
    let initialName: String
    let initialCategory: PresetCategory
    let validate: (String) -> PresetStore.PresetError?
    /// True when saving under this name replaces one of the user's own presets.
    var replaces: (String) -> Bool = { _ in false }
    /// Shows the "Include drums" switch (saving, not renaming).
    var offersDrums = true
    let commit: (String, PresetCategory, Bool) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: PresetCategory = .lead
    @State private var saveError: String?
    @State private var contentHeight: CGFloat = 300
    /// Last choice of the "Include drums" switch.
    @AppStorage("presetIncludesDrums") private var includesDrums = true
    @FocusState private var nameFocused: Bool

    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var chipSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 17

    var body: some View {
        let problem = validate(name)
        let replacing = problem == nil && replaces(name)
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(Retro.cream)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Preset name", text: $name, prompt: Text("Preset name").foregroundStyle(PresetSheetStyle.muted))
                    .foregroundStyle(Retro.cream)
                    .focused($nameFocused)
                    .submitLabel(.done) // SwiftUI has no "Save" return key; Done saves
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit(save)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(PresetSheetStyle.searchFill, in: Capsule())
                if let message = saveError ?? (name.isEmpty ? nil : problem?.errorDescription) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                } else if replacing {
                    Text("A preset with this name exists. Saving replaces it.")
                        .font(.footnote)
                        .foregroundStyle(Retro.accent)
                        .padding(.horizontal, 16)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .textCase(.uppercase)
                    .font(.system(size: labelSize, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(PresetSheetStyle.muted)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                FlowLayout(spacing: 8) {
                    ForEach(PresetCategory.allCases, id: \.self) { option in
                        chip(option)
                    }
                }
            }

            if offersDrums {
                Toggle(isOn: $includesDrums) {
                    Text("Include drums")
                        .font(.system(size: chipSize, weight: .medium))
                        .foregroundStyle(Retro.cream)
                }
                .tint(Retro.accent)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(PresetSheetStyle.card, in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(size: buttonSize, weight: .semibold))
                        .foregroundStyle(Retro.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 110)
                        .frame(minHeight: 50)
                        .background(Retro.section, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                        .overlay { RoundedRectangle(cornerRadius: Retro.buttonRadius).stroke(Retro.sectionEdge, lineWidth: Retro.buttonBorder) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                let canSave = problem == nil
                Button(action: save) {
                    Text(replacing ? "Replace" : "Save")
                        .font(.system(size: buttonSize, weight: .semibold))
                        .foregroundStyle(canSave ? PresetSheetStyle.background : PresetSheetStyle.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(canSave ? Retro.accent : PresetSheetStyle.card, in: RoundedRectangle(cornerRadius: Retro.buttonRadius))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(PresetSheetStyle.background)
        .sensoryFeedback(.impact(weight: .light), trigger: category)
        .tint(Retro.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            name = initialName
            category = initialCategory
            nameFocused = true
        }
    }

    private func chip(_ option: PresetCategory) -> some View {
        let isSelected = option == category
        let shape = RoundedRectangle(cornerRadius: 12)
        return Button {
            category = option
        } label: {
            Text(option.title)
                .font(.system(size: chipSize, weight: .medium))
                .foregroundStyle(isSelected ? Retro.accent : Retro.cream)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? PresetSheetStyle.cardSelected : PresetSheetStyle.card, in: shape)
                .overlay { if isSelected { shape.strokeBorder(Retro.accent, lineWidth: 1.5) } }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        guard validate(name) == nil else { return }
        do {
            try commit(name, category, offersDrums && includesDrums)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Lays children out left to right and wraps onto new lines when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > maxWidth, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// A 3.5" floppy disk outline: the classic "save" icon.
struct FloppyIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let corner = w * 0.22
        var path = Path()
        // Body with the cut-off top-right corner.
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 2))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 2, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 2), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 2))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        // Metal shutter.
        path.addRect(CGRect(x: rect.minX + w * 0.25, y: rect.minY, width: w * 0.42, height: h * 0.3))
        // Label.
        path.addRect(CGRect(x: rect.minX + w * 0.18, y: rect.minY + h * 0.55, width: w * 0.64, height: h * 0.45))
        return path
    }
}

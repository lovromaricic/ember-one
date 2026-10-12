import Foundation
import Observation

/// Factory presets (from `FactoryPresets.swift`) and the user's own presets, which are stored
/// as one JSON file each in the app's Documents/Presets folder.
@Observable
final class PresetStore {
    struct Preset: Identifiable, Equatable {
        enum Source: Equatable {
            case factory
            case user(URL)
        }

        let id: String
        var patch: SynthPatch
        let source: Source
        /// When a user preset file was last written; nil for factory presets.
        var savedDate: Date? = nil

        var isFactory: Bool { source == .factory }
    }

    enum PresetError: LocalizedError {
        case emptyName, duplicateName, writeFailed

        var errorDescription: String? {
            switch self {
            case .emptyName: String(localized: "Enter a name.")
            case .duplicateName: String(localized: "A preset with that name already exists.")
            case .writeFailed: String(localized: "The preset couldn’t be saved.")
            }
        }
    }

    private(set) var factory: [Preset]
    private(set) var user: [Preset] = []
    /// The preset most recently loaded or saved.
    private(set) var currentID: String?
    /// Starred presets, by `Preset.id`. Kept in UserDefaults.
    private(set) var favoriteIDs: Set<String>

    @ObservationIgnored private static let favoritesKey = "favoritePresetIDs"

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init() {
        factory = FactoryPresets.all.map { patch in
            Preset(id: "factory:\(patch.name)", patch: patch.sanitized(), source: .factory)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? [])
        directory = documents.appendingPathComponent("Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadUserPresets()
    }

    var all: [Preset] { factory + user }

    var current: Preset? { all.first { $0.id == currentID } }

    func markCurrent(_ preset: Preset) {
        currentID = preset.id
    }

    /// The preset `offset` places away from the current one, wrapping around the full list.
    func neighbour(offset: Int) -> Preset? {
        let list = all
        guard !list.isEmpty else { return nil }
        let index = list.firstIndex { $0.id == currentID } ?? (offset > 0 ? -1 : 0)
        return list[((index + offset) % list.count + list.count) % list.count]
    }

    // MARK: - User presets

    /// Reads every preset file. Files that can't be read are skipped instead of crashing,
    /// and decoding ignores fields this version doesn't know.
    func loadUserPresets() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        user = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let patch = try? JSONDecoder().decode(SynthPatch.self, from: data) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return Preset(id: "user:\(url.lastPathComponent)", patch: patch.sanitized(), source: .user(url), savedDate: date)
            }
            .sorted { $0.patch.name.localizedCaseInsensitiveCompare($1.patch.name) == .orderedAscending }
    }

    /// Checks a proposed name: not empty, and not used by any other preset (factory or user).
    func validate(name: String, excluding id: String? = nil) -> PresetError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .emptyName }
        let taken = all.contains { $0.id != id && $0.patch.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return taken ? .duplicateName : nil
    }

    /// The user's own preset with this name (ignoring case and accents), which saving may replace.
    func userPreset(named name: String) -> Preset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return user.first { $0.patch.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// Saves a new user preset, or replaces the user's own preset with the same name (same file,
    /// so it keeps its star). A factory preset's name can't be used.
    @discardableResult
    func save(_ patch: SynthPatch, name: String, category: PresetCategory) throws -> Preset {
        let replaced = userPreset(named: name)
        if let error = validate(name: name, excluding: replaced?.id) { throw error }
        var patch = patch
        patch.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        patch.category = category
        patch.tag = nil   // a tag copied from a factory preset may no longer fit the edited sound
        let url: URL
        if case .user(let existing)? = replaced?.source {
            url = existing
        } else {
            url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        }
        try write(patch, to: url)
        let preset = Preset(id: "user:\(url.lastPathComponent)", patch: patch, source: .user(url))
        loadUserPresets()
        currentID = preset.id
        return preset
    }

    func rename(_ preset: Preset, to name: String, category: PresetCategory) throws {
        guard case .user(let url) = preset.source else { return }
        if let error = validate(name: name, excluding: preset.id) { throw error }
        var patch = preset.patch
        patch.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        patch.category = category
        try write(patch, to: url)
        loadUserPresets()
    }

    func delete(_ preset: Preset) {
        guard case .user(let url) = preset.source else { return }
        try? FileManager.default.removeItem(at: url)
        if currentID == preset.id { currentID = nil }
        if favoriteIDs.contains(preset.id) { toggleFavorite(preset) }
        loadUserPresets()
    }

    // MARK: - Favorites

    func isFavorite(_ preset: Preset) -> Bool {
        favoriteIDs.contains(preset.id)
    }

    func toggleFavorite(_ preset: Preset) {
        if favoriteIDs.remove(preset.id) == nil { favoriteIDs.insert(preset.id) }
        UserDefaults.standard.set(favoriteIDs.sorted(), forKey: Self.favoritesKey)
    }

    private func write(_ patch: SynthPatch, to url: URL) throws {
        do {
            try encoder.encode(patch).write(to: url, options: .atomic)
        } catch {
            throw PresetError.writeFailed
        }
    }
}

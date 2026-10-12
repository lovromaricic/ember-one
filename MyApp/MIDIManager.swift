import CoreMIDI
import Foundation
import Observation
import Synchronization

/// How strongly key velocity affects loudness.
nonisolated enum VelocitySensitivity: Int, CaseIterable, Codable {
    case off, soft, normal, hard

    /// Maps a MIDI velocity (1...127) to a voice level.
    func level(_ velocity: UInt8) -> Float {
        let v = Float(velocity) / 127
        let curved: Float = switch self {
        case .off: 0.8
        case .soft: v.squareRoot()   // light touch already loud
        case .normal: v
        case .hard: v * v            // needs a firm hit to get loud
        }
        return max(curved, 0.05)
    }
}

nonisolated enum ModWheelTarget: Int, CaseIterable, Codable {
    case lfoAmount, cutoff
}

/// Global MIDI settings (not part of presets).
nonisolated struct MIDISettings: Codable, Equatable {
    /// 0 = omni, 1...16 = that channel only.
    var channel = 0
    var velocity = VelocitySensitivity.normal
    /// Pitch bend range in semitones, up and down.
    var bendRange = 2
    var modWheel = ModWheelTarget.lfoAmount
}

/// A controller knob (device + CC number) linked to a synth parameter by MIDI learn.
nonisolated struct MIDIMapping: Codable, Equatable, Identifiable {
    var deviceID: Int32
    var deviceName: String
    var cc: Int
    var param: Int

    var id: String { "\(deviceID)-\(cc)" }
}

/// Settings the MIDI input thread reads without locks.
nonisolated final class MIDIInputSettings: @unchecked Sendable {
    let channel = Atomic<Int>(0)
    let velocity = Atomic<Int>(VelocitySensitivity.normal.rawValue)
    let bendRange = Atomic<Int>(2)
    /// Last time (ms since start) an activity ping was sent to the UI, to throttle them.
    let lastPing = Atomic<Int>(0)
}

/// Connects to every MIDI source, turns incoming messages into synth events, and handles
/// MIDI learn. Notes, pitch bend, mod wheel and sustain go straight from the MIDI input
/// thread to the audio thread through a lock-free queue; learned CCs and the UI state hop to
/// the main actor.
@Observable
final class MIDIManager {
    struct Device: Identifiable, Equatable {
        let id: Int32
        let name: String
    }

    private(set) var devices: [Device] = []
    var settings: MIDISettings {
        didSet { settingsChanged() }
    }
    private(set) var mappings: [MIDIMapping]
    /// Parameter waiting for a controller to be moved (MIDI learn), or nil.
    private(set) var learningParam: SynthParam?
    /// Bumped (at most ~10 times a second) while messages arrive, so the icon can blink.
    private(set) var activity = 0
    /// A simulated controller for testing without hardware.
    var simulatesController = false {
        didSet { simulatedControllerChanged() }
    }
    private(set) var setupError: String?

    var isConnected: Bool { !devices.isEmpty }

    @ObservationIgnored private weak var engine: SynthEngine?
    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    @ObservationIgnored private var connected: Set<MIDIEndpointRef> = []
    @ObservationIgnored private let inputSettings = MIDIInputSettings()
    /// Every MIDI message is handled on this one serial queue, so the MIDI → audio queue
    /// has a single producer.
    @ObservationIgnored private let inputQueue = DispatchQueue(label: "MIDI input", qos: .userInteractive)

    static let simulatedDeviceID: Int32 = -1

    init() {
        let defaults = UserDefaults.standard
        settings = (defaults.data(forKey: "midiSettings").flatMap { try? JSONDecoder().decode(MIDISettings.self, from: $0) }) ?? MIDISettings()
        mappings = (defaults.data(forKey: "midiMappings").flatMap { try? JSONDecoder().decode([MIDIMapping].self, from: $0) }) ?? []
    }

    // MARK: - Setup

    func start(engine: SynthEngine) {
        guard self.engine == nil else { return }
        self.engine = engine
        storeInputSettings()
        sendModWheelTarget()

        let notify: MIDINotifyBlock = Self.makeNotifyBlock { [weak self] in self?.refreshSources() }
        var status = MIDIClientCreateWithBlock("Ember One" as CFString, &client, notify)
        guard status == noErr else {
            setupError = String(localized: "MIDI is not available (\(status)).")
            return
        }
        let receive = Self.makeReceiveBlock(queue: inputQueue) { [weak self] words, deviceID in
            self?.handleWords(words, deviceID: deviceID)
        }
        status = MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &inputPort, receive)
        guard status == noErr else {
            setupError = String(localized: "MIDI input could not be opened (\(status)).")
            return
        }
        refreshSources()
    }

    /// Connects to new sources and notices removed ones. Called at start and on every
    /// MIDI setup change (a device plugged in, paired or unplugged).
    private func refreshSources() {
        var present: [MIDIEndpointRef: Device] = [:]
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            present[source] = Device(id: Self.uniqueID(source), name: Self.name(source))
        }
        for source in present.keys where !connected.contains(source) {
            let refCon = UnsafeMutableRawPointer(bitPattern: Self.refCon(for: present[source]!.id))
            if MIDIPortConnectSource(inputPort, source, refCon) == noErr {
                connected.insert(source)
            }
        }
        let removed = connected.subtracting(present.keys)
        connected.subtract(removed)
        if !removed.isEmpty {
            // A controller went away: nothing may keep sounding, the pedal and bend reset.
            engine?.allNotesOff()
        }
        var list = present.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if simulatesController { list.append(Device(id: Self.simulatedDeviceID, name: String(localized: "Test controller"))) }
        devices = list
    }

    // MARK: - Input (MIDI input queue)

    /// Parses MIDI 1.0 channel voice messages from universal MIDI packet words.
    private nonisolated func handleWords(_ words: [UInt32], deviceID: Int32) {
        for word in words where word >> 28 == 0x2 {
            let status = UInt8((word >> 16) & 0xFF)
            let data1 = UInt8((word >> 8) & 0x7F)
            let data2 = UInt8(word & 0x7F)
            handleMessage(status: status, data1: data1, data2: data2, deviceID: deviceID)
        }
    }

    private nonisolated func handleMessage(status: UInt8, data1: UInt8, data2: UInt8, deviceID: Int32) {
        let channel = Int(status & 0x0F) + 1
        let wanted = inputSettings.channel.load(ordering: .relaxed)
        guard wanted == 0 || wanted == channel else { return }
        guard let queue = midiQueueReference.load() else { return }
        ping()

        switch status & 0xF0 {
        case 0x90 where data2 > 0:
            let curve = VelocitySensitivity(rawValue: inputSettings.velocity.load(ordering: .relaxed)) ?? .normal
            queue.push(SynthEvent(kind: .keyDown, index: Int32(data1), value: curve.level(data2)))
            Task { @MainActor [weak self] in self?.engine?.mirrorKey(Int(data1), down: true) }
        case 0x80, 0x90:
            queue.push(SynthEvent(kind: .keyUp, index: Int32(data1), value: 0))
            Task { @MainActor [weak self] in self?.engine?.mirrorKey(Int(data1), down: false) }
        case 0xE0:
            let value = Int(data2) << 7 | Int(data1)              // 0...16383, centre 8192
            let range = Float(inputSettings.bendRange.load(ordering: .relaxed))
            let semitones = Float(value - 8192) / (value >= 8192 ? 8191 : 8192) * range
            queue.push(SynthEvent(kind: .midi, index: MIDIControl.pitchBend.rawValue, value: semitones))
        case 0xB0:
            switch data1 {
            case 1:
                queue.push(SynthEvent(kind: .midi, index: MIDIControl.modWheel.rawValue, value: Float(data2) / 127))
            case 64:
                queue.push(SynthEvent(kind: .midi, index: MIDIControl.sustain.rawValue, value: data2 >= 64 ? 1 : 0))
            case 120, 123: // all sound off / all notes off
                queue.push(SynthEvent(kind: .allNotesOff, index: 0, value: 0))
            default:
                Task { @MainActor [weak self] in self?.handleControlChange(Int(data1), value: Int(data2), deviceID: deviceID) }
            }
        default:
            break // aftertouch, program change, clock, start/stop: ignored for now
        }
    }

    /// Tells the UI (at most every 100 ms) that messages are arriving.
    private nonisolated func ping() {
        let now = Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        guard now - inputSettings.lastPing.load(ordering: .relaxed) > 100 else { return }
        inputSettings.lastPing.store(now, ordering: .relaxed)
        Task { @MainActor [weak self] in self?.activity &+= 1 }
    }

    /// The engine's MIDI queue, readable from the input thread.
    @ObservationIgnored private nonisolated let midiQueueReference = QueueReference()

    // MARK: - Control changes and MIDI learn (main actor)

    private func handleControlChange(_ cc: Int, value: Int, deviceID: Int32) {
        if let param = learningParam {
            let name = devices.first { $0.id == deviceID }?.name ?? String(localized: "Controller")
            mappings.removeAll { $0.param == param.rawValue || ($0.deviceID == deviceID && $0.cc == cc) }
            mappings.append(MIDIMapping(deviceID: deviceID, deviceName: name, cc: cc, param: param.rawValue))
            learningParam = nil
            saveMappings()
        }
        for mapping in mappings where mapping.deviceID == deviceID && mapping.cc == cc {
            guard let param = SynthParam(rawValue: mapping.param) else { continue }
            // Moves the knob; the audio thread glides to the new value, so it never clicks.
            engine?.set(param, param.value(fromNormalized: Float(value) / 127))
        }
    }

    func beginLearn(_ param: SynthParam) {
        learningParam = param
    }

    func cancelLearn() {
        learningParam = nil
    }

    func mapping(for param: SynthParam) -> MIDIMapping? {
        mappings.first { $0.param == param.rawValue }
    }

    func removeMapping(_ mapping: MIDIMapping) {
        mappings.removeAll { $0.id == mapping.id }
        saveMappings()
    }

    func removeAllMappings() {
        mappings.removeAll()
        saveMappings()
    }

    // MARK: - Settings

    private func settingsChanged() {
        storeInputSettings()
        sendModWheelTarget()
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "midiSettings")
        }
    }

    private func storeInputSettings() {
        inputSettings.channel.store(settings.channel, ordering: .relaxed)
        inputSettings.velocity.store(settings.velocity.rawValue, ordering: .relaxed)
        inputSettings.bendRange.store(settings.bendRange, ordering: .relaxed)
        if let engine { midiQueueReference.store(engine.midiQueue) }
    }

    /// The mod wheel target travels on the MIDI queue too, so it must be sent from the input queue.
    private func sendModWheelTarget() {
        let target: Float = settings.modWheel == .cutoff ? 1 : 0
        let reference = midiQueueReference
        inputQueue.async {
            reference.load()?.push(SynthEvent(kind: .midi, index: MIDIControl.modDestination.rawValue, value: target))
        }
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: "midiMappings")
        }
    }

    // MARK: - Simulated controller

    private func simulatedControllerChanged() {
        refreshSources()
        if simulatesController {
            sendTestMessages()
        } else {
            engine?.allNotesOff() // like unplugging a real one
        }
    }

    /// Sends a short phrase as if from a controller: a chord, a pitch bend up and back, a
    /// mod wheel move and a sweep on CC 74 (useful for MIDI learn).
    func sendTestMessages() {
        let id = Self.simulatedDeviceID
        let channel = UInt8(max(settings.channel, 1) - 1)
        let steps: [(Double, UInt8, UInt8, UInt8)] = [
            (0.00, 0x90 | channel, 60, 100), (0.00, 0x90 | channel, 64, 80), (0.00, 0x90 | channel, 67, 60),
            (0.40, 0xE0 | channel, 0, 96), (0.55, 0xE0 | channel, 0, 127), (0.80, 0xE0 | channel, 0, 64),
            (0.90, 0xB0 | channel, 1, 90), (1.30, 0xB0 | channel, 1, 0),
            (1.40, 0xB0 | channel, 74, 20), (1.55, 0xB0 | channel, 74, 70), (1.70, 0xB0 | channel, 74, 110),
            (2.00, 0x80 | channel, 60, 0), (2.00, 0x80 | channel, 64, 0), (2.00, 0x80 | channel, 67, 0),
        ]
        for (delay, status, data1, data2) in steps {
            inputQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.handleMessage(status: status, data1: data1, data2: data2, deviceID: id)
            }
        }
    }

    // MARK: - CoreMIDI helpers

    private nonisolated static func makeNotifyBlock(_ onChange: @escaping @MainActor () -> Void) -> MIDINotifyBlock {
        { notification in
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
                Task { @MainActor in onChange() }
            default:
                break
            }
        }
    }

    /// Copies the packet words (only valid during the callback) and handles them on `queue`.
    private nonisolated static func makeReceiveBlock(queue: DispatchQueue,
                                                     handler: @escaping @Sendable ([UInt32], Int32) -> Void) -> MIDIReceiveBlock {
        { eventList, refCon in
            let deviceID = Self.deviceID(fromRefCon: refCon)
            var words: [UInt32] = []
            var packet = UnsafeRawPointer(eventList).advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
                .assumingMemoryBound(to: MIDIEventPacket.self)
            for _ in 0..<eventList.pointee.numPackets {
                let count = Int(packet.pointee.wordCount)
                let wordsStart = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
                    .assumingMemoryBound(to: UInt32.self)
                words.append(contentsOf: UnsafeBufferPointer(start: wordsStart, count: min(count, 64)))
                packet = UnsafePointer(MIDIEventPacketNext(packet))
            }
            queue.async { handler(words, deviceID) }
        }
    }

    private nonisolated static func refCon(for id: Int32) -> Int {
        Int(UInt32(bitPattern: id)) | (1 << 40) // never zero, so the pointer is never nil
    }

    private nonisolated static func deviceID(fromRefCon refCon: UnsafeMutableRawPointer?) -> Int32 {
        guard let refCon else { return 0 }
        return Int32(bitPattern: UInt32(truncatingIfNeeded: Int(bitPattern: refCon)))
    }

    private nonisolated static func uniqueID(_ endpoint: MIDIEndpointRef) -> Int32 {
        var id: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
        return id
    }

    private nonisolated static func name(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr, let name {
            return name.takeRetainedValue() as String
        }
        return String(localized: "MIDI device")
    }
}

/// Holds the engine's MIDI queue for the input thread (set once from the main actor).
nonisolated final class QueueReference: @unchecked Sendable {
    private let lock = Mutex<SynthEventQueue?>(nil)

    func store(_ queue: SynthEventQueue) { lock.withLock { $0 = queue } }
    func load() -> SynthEventQueue? { lock.withLock { $0 } }
}

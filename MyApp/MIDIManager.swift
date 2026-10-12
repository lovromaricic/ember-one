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
    /// Follow an external MIDI clock (tempo, Start, Continue, Stop) instead of the tempo knob.
    var clockExternal = false
    /// Shifts the external clock's phase (latency compensation), -50...50 ms.
    var clockOffsetMs = 0
    /// Receive MIDI from a computer over Wi-Fi (RTP-MIDI network session).
    var networkMIDI = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case channel, velocity, bendRange, modWheel, clockExternal, clockOffsetMs, networkMIDI
    }

    /// Settings saved by older versions (without the clock fields) still load.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MIDISettings()
        channel = c.lenient(.channel, default: d.channel)
        velocity = c.lenient(.velocity, default: d.velocity)
        bendRange = c.lenient(.bendRange, default: d.bendRange)
        modWheel = c.lenient(.modWheel, default: d.modWheel)
        clockExternal = c.lenient(.clockExternal, default: d.clockExternal)
        clockOffsetMs = min(max(c.lenient(.clockOffsetMs, default: d.clockOffsetMs), -50), 50)
        networkMIDI = c.lenient(.networkMIDI, default: d.networkMIDI)
    }
}

/// The parts of CoreMIDI's network (RTP-MIDI) session the app uses; a stand-in in tests.
protocol NetworkMIDISessionControl: AnyObject {
    var isEnabled: Bool { get set }
    var connectionPolicy: MIDINetworkConnectionPolicy { get set }
    /// The session's MIDI source: everything the connected computers send arrives here.
    var sourceEndpoint: MIDIEndpointRef { get }
    /// Names of the computers connected to the session, sorted.
    var connectedHosts: [String] { get }
}

final class SystemNetworkMIDISession: NetworkMIDISessionControl {
    private let session = MIDINetworkSession.default()

    var isEnabled: Bool {
        get { session.isEnabled }
        set { session.isEnabled = newValue }
    }
    var connectionPolicy: MIDINetworkConnectionPolicy {
        get { session.connectionPolicy }
        set { session.connectionPolicy = newValue }
    }
    var sourceEndpoint: MIDIEndpointRef { session.sourceEndpoint() }
    var connectedHosts: [String] { session.connections().map(\.host.name).sorted() }
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
    /// Set while the DEBUG test clock runs: clock messages from real devices are ignored.
    let ignoresDeviceClock = Atomic<Bool>(false)
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
        /// What the MIDI screen shows, e.g. "Bluetooth: ..." for a Bluetooth device.
        var label: String

        init(id: Int32, name: String, label: String? = nil) {
            self.id = id
            self.name = name
            self.label = label ?? name
        }
    }

    private(set) var devices: [Device] = []
    var settings: MIDISettings {
        didSet { settingsChanged(from: oldValue) }
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
    /// The synth engine, for showing the external clock's status.
    var clockEngine: SynthEngine? { engine }

    @ObservationIgnored private weak var engine: SynthEngine?
    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inputPort = MIDIPortRef()
    /// Sources the input port listens to, with their device IDs.
    @ObservationIgnored private var connected: [MIDIEndpointRef: Int32] = [:]
    @ObservationIgnored private let inputSettings = MIDIInputSettings()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let networkSession: any NetworkMIDISessionControl
    /// Computers connected to the network session at the last check.
    @ObservationIgnored private var networkHosts: [String] = []
    @ObservationIgnored private var networkObserver: (any NSObjectProtocol)?
    /// `start` has run: the network session follows the toggle from then on.
    @ObservationIgnored private var started = false
    /// Every MIDI message is handled on this one serial queue, so the MIDI → audio queue
    /// has a single producer.
    @ObservationIgnored private let inputQueue = DispatchQueue(label: "MIDI input", qos: .userInteractive)

    static let simulatedDeviceID: Int32 = -1
    /// Source ID of the DEBUG test clock.
    nonisolated static let syntheticClockID: Int32 = -2
#if DEBUG
    /// Test clock for checking MIDI clock sync without hardware (launch argument only).
    @ObservationIgnored private(set) var syntheticClock: SyntheticMIDIClock?
#endif

    init(defaults: UserDefaults = .standard, networkSession: any NetworkMIDISessionControl = SystemNetworkMIDISession()) {
        self.defaults = defaults
        self.networkSession = networkSession
        settings = (defaults.data(forKey: "midiSettings").flatMap { try? JSONDecoder().decode(MIDISettings.self, from: $0) }) ?? MIDISettings()
        mappings = (defaults.data(forKey: "midiMappings").flatMap { try? JSONDecoder().decode([MIDIMapping].self, from: $0) }) ?? []
    }

    // MARK: - Setup

    func start(engine: SynthEngine) {
        guard self.engine == nil else { return }
        self.engine = engine
        started = true
        storeInputSettings()
        sendModWheelTarget()
        engine.setClock(external: settings.clockExternal, offsetMs: settings.clockOffsetMs)

        let notify: MIDINotifyBlock = Self.makeNotifyBlock { [weak self] in self?.refreshSources() }
        var status = MIDIClientCreateWithBlock("Ember One" as CFString, &client, notify)
        guard status == noErr else {
            setupError = String(localized: "MIDI is not available (\(status)).")
            return
        }
        let receive = Self.makeReceiveBlock(queue: inputQueue, clockQueue: engine.clockQueue, settings: inputSettings) { [weak self] words, deviceID in
            self?.handleWords(words, deviceID: deviceID)
        }
        status = MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &inputPort, receive)
        guard status == noErr else {
            setupError = String(localized: "MIDI input could not be opened (\(status)).")
            return
        }
        // Connections to the network session come and go without the session's source changing.
        networkObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(MIDINetworkNotificationSessionDidChange), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.networkSessionChanged() }
        }
        applyNetworkSession()
        refreshSources()
#if DEBUG
        if SyntheticMIDIClock.isRequested {
            inputSettings.ignoresDeviceClock.store(true, ordering: .relaxed)
            let refCon = UnsafeMutableRawPointer(bitPattern: Self.refCon(for: Self.syntheticClockID))
            let clock = SyntheticMIDIClock(engine: engine) { list in receive(list, refCon) }
            syntheticClock = clock
            clock.startLogging()
            if SyntheticMIDIClock.runsScenario { clock.runScenario(midi: self) }
        }
#endif
    }

    /// Connects to new sources and notices removed ones. Called at start and on every
    /// MIDI setup change (a device plugged in, paired or unplugged).
    private func refreshSources() {
        // Every source: USB, Bluetooth, network and other apps' virtual sources. A source
        // that is offline (e.g. a Bluetooth device that went out of range) counts as gone.
        var present: [MIDIEndpointRef: Int32] = [:]
        var listed: [Device] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0, !Self.isOffline(source) else { continue }
            let device = Device(id: Self.uniqueID(source), name: Self.name(source))
            present[source] = device.id
            if let label = label(for: source, name: device.name) {
                listed.append(Device(id: device.id, name: device.name, label: label))
            }
        }
        let changes = Self.sourceChanges(connected: connected, present: present)
        for source in changes.connect {
            let refCon = UnsafeMutableRawPointer(bitPattern: Self.refCon(for: present[source]!))
            if MIDIPortConnectSource(inputPort, source, refCon) == noErr {
                connected[source] = present[source]
            }
        }
        for (source, id) in changes.removed {
            MIDIPortDisconnectSource(inputPort, source) // may already be gone; that's fine
            connected[source] = nil
            // Releases what that controller held (notes, pedal, bend, mod wheel); the on-screen
            // keyboard and other controllers keep playing. Goes through the input queue,
            // after anything that controller sent before it went away.
            inputQueue.async { [weak self] in self?.releaseSource(id) }
        }
        var list = listed.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        if simulatesController { list.append(Device(id: Self.simulatedDeviceID, name: String(localized: "Test controller"))) }
        if list != devices { devices = list }
    }

    /// Sources to connect (new ones) and to drop (gone), given the connected and present ones.
    nonisolated static func sourceChanges(connected: [MIDIEndpointRef: Int32], present: [MIDIEndpointRef: Int32])
        -> (connect: [MIDIEndpointRef], removed: [MIDIEndpointRef: Int32]) {
        let connect = present.keys.filter { connected[$0] == nil }.sorted()
        let removed = connected.filter { source, _ in present[source] == nil }
        return (connect, removed)
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
        guard MIDIMessage.passes(status: status, channelSetting: inputSettings.channel.load(ordering: .relaxed)) else { return }
        guard let queue = midiQueueReference.load() else { return }
        ping()

        let curve = VelocitySensitivity(rawValue: inputSettings.velocity.load(ordering: .relaxed)) ?? .normal
        let bendRange = Float(inputSettings.bendRange.load(ordering: .relaxed))
        guard let message = MIDIMessage(status: status, data1: data1, data2: data2, velocity: curve, bendRange: bendRange) else {
            return // aftertouch and program change are ignored; clock is read in the receive block
        }
        sourceTracker.tracker.record(message, from: deviceID)
        deliver(message, deviceID: deviceID, to: queue)
    }

    /// Notes, pitch bend, mod wheel, sustain and All Notes Off go to the audio thread through
    /// the lock-free MIDI queue; other CCs (MIDI learn) go to the main actor.
    private nonisolated func deliver(_ message: MIDIMessage, deviceID: Int32, to queue: SynthEventQueue) {
        if let event = message.event { queue.push(event) }
        switch message {
        case .noteOn(let note, _):
            Task { @MainActor [weak self] in self?.engine?.mirrorKey(Int(note), down: true) }
        case .noteOff(let note):
            Task { @MainActor [weak self] in self?.engine?.mirrorKey(Int(note), down: false) }
        case .controlChange(let cc, let value):
            Task { @MainActor [weak self] in self?.handleControlChange(cc, value: value, deviceID: deviceID) }
        default:
            break
        }
    }

    /// A source went away: lets go of exactly what it held, as if its keys and pedal were released.
    private nonisolated func releaseSource(_ deviceID: Int32) {
        let messages = sourceTracker.tracker.release(deviceID)
        guard let queue = midiQueueReference.load() else { return }
        for message in messages { deliver(message, deviceID: deviceID, to: queue) }
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
    /// What each source holds; used only on the input queue.
    @ObservationIgnored private nonisolated let sourceTracker = MIDISourceTrackerBox()

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

    private func settingsChanged(from old: MIDISettings) {
        storeInputSettings()
        sendModWheelTarget()
        engine?.setClock(external: settings.clockExternal, offsetMs: settings.clockOffsetMs)
        if settings.networkMIDI != old.networkMIDI, started { applyNetworkSession() }
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: "midiSettings")
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
            defaults.set(data, forKey: "midiMappings")
        }
    }

    // MARK: - Network MIDI

    /// Device ID of the network session's source (what its messages are tagged with).
    var networkSourceID: Int32 { Self.uniqueID(networkSession.sourceEndpoint) }

    /// The session is on only while the toggle is. Its source is connected like any other,
    /// so notes, velocity, bend, CCs and clock from the computer take the usual path.
    private func applyNetworkSession() {
        if settings.networkMIDI {
            // Any computer on the local network may connect (no contact list to manage).
            networkSession.connectionPolicy = .anyone
            networkSession.isEnabled = true
        } else {
            let id = networkSourceID // before the session's source may go away
            networkSession.isEnabled = false
            releaseSource(id: id)
        }
        networkHosts = settings.networkMIDI ? networkSession.connectedHosts : []
        if inputPort != 0 { refreshSources() }
    }

    /// A computer connected or disconnected (or went to sleep and timed out): update the list,
    /// and if one went away, release what the session's source was holding.
    func networkSessionChanged() {
        let hosts = settings.networkMIDI ? networkSession.connectedHosts : []
        if !Set(networkHosts).isSubset(of: hosts) { releaseSource(id: networkSourceID) }
        networkHosts = hosts
        if inputPort != 0 { refreshSources() }
    }

    private func releaseSource(id: Int32) {
        inputQueue.async { [weak self] in self?.releaseSource(id) }
    }

    /// Handles a message as if it came from `deviceID` (for tests).
    func receive(status: UInt8, data1: UInt8, data2: UInt8, from deviceID: Int32) {
        inputQueue.async { [weak self] in self?.handleMessage(status: status, data1: data1, data2: data2, deviceID: deviceID) }
    }

    /// Waits until every message handed to the input queue so far is handled (for tests).
    func waitForInput() {
        inputQueue.sync {}
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
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged: // incl. going offline
                Task { @MainActor in onChange() }
            default:
                break
            }
        }
    }

    /// Copies the packet words (only valid during the callback) and handles them on `queue`.
    /// MIDI clock, Start, Continue and Stop go straight from here (CoreMIDI's receive thread,
    /// the clock queue's only producer) to the audio thread, with the packet's host timestamp.
    private nonisolated static func makeReceiveBlock(queue: DispatchQueue, clockQueue: ClockEventQueue, settings: MIDIInputSettings,
                                                     handler: @escaping @Sendable ([UInt32], Int32) -> Void) -> MIDIReceiveBlock {
        { eventList, refCon in
            let deviceID = Self.deviceID(fromRefCon: refCon)
            let readsClock = deviceID == syntheticClockID || !settings.ignoresDeviceClock.load(ordering: .relaxed)
            var words: [UInt32] = []
            var packet = UnsafeRawPointer(eventList).advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
                .assumingMemoryBound(to: MIDIEventPacket.self)
            for _ in 0..<eventList.pointee.numPackets {
                let count = Int(packet.pointee.wordCount)
                let wordsStart = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
                    .assumingMemoryBound(to: UInt32.self)
                // A zero timestamp means "now".
                let stamp = packet.pointee.timeStamp != 0 ? packet.pointee.timeStamp : mach_absolute_time()
                for i in 0..<min(count, 64) where wordsStart[i] >> 28 == 0x1 { // system messages
                    let kind: ClockEvent.Kind? = switch UInt8((wordsStart[i] >> 16) & 0xFF) {
                    case 0xF8: .tick
                    case 0xFA: .start
                    case 0xFB: .continue
                    case 0xFC: .stop
                    default: nil // song position and the rest are ignored
                    }
                    if let kind, readsClock { clockQueue.push(ClockEvent(kind: kind, source: deviceID, hostTime: stamp)) }
                }
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

    private nonisolated static func isOffline(_ endpoint: MIDIEndpointRef) -> Bool {
        var offline: Int32 = 0
        return MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline) == noErr && offline != 0
    }

    /// The name shown on the MIDI screen, or nil to leave a source off the list.
    private func label(for endpoint: MIDIEndpointRef, name: String) -> String? {
        let isNetworkSession = endpoint == networkSession.sourceEndpoint
        return Self.label(name: name, driver: Self.driverOwner(endpoint), isNetworkSession: isNetworkSession,
                          networkHosts: isNetworkSession && networkSession.isEnabled ? networkSession.connectedHosts : [])
    }

    /// Bluetooth devices get a "Bluetooth: " prefix. The network session is always there on iOS,
    /// so it is listed only while computers are connected to it, under their names.
    nonisolated static func label(name: String, driver: String?, isNetworkSession: Bool, networkHosts: [String]) -> String? {
        if isNetworkSession {
            return networkHosts.isEmpty ? nil : networkHosts.joined(separator: ", ")
        }
        let driver = driver?.lowercased() ?? ""
        if driver.contains("bluetooth") || driver.contains("btle"), !name.localizedCaseInsensitiveContains("bluetooth") {
            return String(localized: "Bluetooth: \(name)")
        }
        return name
    }

    /// The driver behind a source (USB, Bluetooth, network), or nil for another app's virtual source.
    private nonisolated static func driverOwner(_ endpoint: MIDIEndpointRef) -> String? {
        var entity = MIDIEntityRef()
        var device = MIDIDeviceRef()
        guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0,
              MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else { return nil }
        var owner: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(device, kMIDIPropertyDriverOwner, &owner) == noErr, let owner else { return nil }
        return owner.takeRetainedValue() as String
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

/// A MIDI 1.0 channel voice message the synth reacts to.
nonisolated enum MIDIMessage: Equatable {
    /// `level` is the voice level from the velocity curve.
    case noteOn(note: Int32, level: Float)
    case noteOff(note: Int32)
    case pitchBend(semitones: Float)
    /// 0...1
    case modWheel(Float)
    case sustain(Bool)
    /// CC 123 (All Notes Off) and CC 120 (All Sound Off).
    case allNotesOff
    /// Any other CC: for MIDI learn.
    case controlChange(cc: Int, value: Int)

    /// Whether a message's channel passes the channel setting (0 = omni, 1...16).
    static func passes(status: UInt8, channelSetting: Int) -> Bool {
        channelSetting == 0 || channelSetting == Int(status & 0x0F) + 1
    }

    /// Parses one message; nil for the ones the synth ignores (aftertouch, program change...).
    init?(status: UInt8, data1: UInt8, data2: UInt8, velocity: VelocitySensitivity, bendRange: Float) {
        let data1 = data1 & 0x7F, data2 = data2 & 0x7F
        switch status & 0xF0 {
        case 0x90 where data2 > 0:
            self = .noteOn(note: Int32(data1), level: velocity.level(data2))
        case 0x80, 0x90: // Note Off, or Note On with velocity 0
            self = .noteOff(note: Int32(data1))
        case 0xE0:
            let value = Int(data2) << 7 | Int(data1) // 0...16383, centre 8192
            self = .pitchBend(semitones: Float(value - 8192) / (value >= 8192 ? 8191 : 8192) * bendRange)
        case 0xB0:
            switch data1 {
            case 1: self = .modWheel(Float(data2) / 127)
            case 64: self = .sustain(data2 >= 64)
            case 120, 123: self = .allNotesOff
            default: self = .controlChange(cc: Int(data1), value: Int(data2))
            }
        default:
            return nil
        }
    }

    /// The event for the audio thread, or nil for CCs handled on the main actor.
    var event: SynthEvent? {
        switch self {
        case .noteOn(let note, let level): SynthEvent(kind: .keyDown, index: note, value: level)
        case .noteOff(let note): SynthEvent(kind: .keyUp, index: note, value: 0)
        case .pitchBend(let semitones): SynthEvent(kind: .midi, index: MIDIControl.pitchBend.rawValue, value: semitones)
        case .modWheel(let value): SynthEvent(kind: .midi, index: MIDIControl.modWheel.rawValue, value: value)
        case .sustain(let down): SynthEvent(kind: .midi, index: MIDIControl.sustain.rawValue, value: down ? 1 : 0)
        case .allNotesOff: SynthEvent(kind: .allNotesOff, index: 0, value: 0)
        case .controlChange: nil
        }
    }
}

/// What each MIDI source holds right now (keys, sustain pedal, a bent wheel, the mod wheel),
/// so a source that goes away releases exactly that and nothing else keeps sounding.
nonisolated struct MIDISourceTracker {
    private struct State {
        var notes: (UInt64, UInt64) = (0, 0)
        var sustain = false
        var bent = false
        var modded = false
    }

    private var states: [Int32: State] = [:]

    mutating func record(_ message: MIDIMessage, from source: Int32) {
        switch message {
        case .noteOn(let note, _): setNote(note, on: true, source)
        case .noteOff(let note): setNote(note, on: false, source)
        case .sustain(let down): states[source, default: State()].sustain = down
        case .pitchBend(let semitones): states[source, default: State()].bent = semitones != 0
        case .modWheel(let value): states[source, default: State()].modded = value != 0
        case .allNotesOff:
            // The audio thread lets go of every note and resets the pedal, bend and mod wheel.
            states.removeAll(keepingCapacity: true)
        case .controlChange:
            break
        }
    }

    /// Notes the source holds, lowest first.
    func heldNotes(of source: Int32) -> [Int32] {
        guard let state = states[source] else { return [] }
        return (0..<128).filter { Self.isSet($0, state.notes) }.map(Int32.init)
    }

    /// Messages that release everything the source holds (note offs, then pedal up, bend
    /// centred and mod wheel at zero if it moved them). Forgets the source.
    mutating func release(_ source: Int32) -> [MIDIMessage] {
        guard let state = states.removeValue(forKey: source) else { return [] }
        var messages: [MIDIMessage] = (0..<128).filter { Self.isSet($0, state.notes) }.map { .noteOff(note: Int32($0)) }
        if state.sustain { messages.append(.sustain(false)) }
        if state.bent { messages.append(.pitchBend(semitones: 0)) }
        if state.modded { messages.append(.modWheel(0)) }
        return messages
    }

    private mutating func setNote(_ note: Int32, on: Bool, _ source: Int32) {
        guard (0..<128).contains(note) else { return }
        var state = states[source] ?? State()
        let bit = UInt64(1) << UInt64(note % 64)
        if note < 64 {
            state.notes.0 = on ? state.notes.0 | bit : state.notes.0 & ~bit
        } else {
            state.notes.1 = on ? state.notes.1 | bit : state.notes.1 & ~bit
        }
        states[source] = state
    }

    private static func isSet(_ note: Int, _ notes: (UInt64, UInt64)) -> Bool {
        (note < 64 ? notes.0 : notes.1) & (UInt64(1) << UInt64(note % 64)) != 0
    }
}

/// Holds the tracker for the MIDI input queue, its only user.
nonisolated final class MIDISourceTrackerBox: @unchecked Sendable {
    var tracker = MIDISourceTracker()
}

import CoreMIDI
import Foundation
import Testing
@testable import Ember_One

/// Network MIDI (RTP-MIDI over Wi-Fi) without a network: a stand-in session records what the
/// app asks of it, and notes "from the network source" go through the real input path.
@MainActor
struct NetworkMIDITests {
    final class FakeSession: NetworkMIDISessionControl {
        var isEnabled = false
        var connectionPolicy = MIDINetworkConnectionPolicy.noOne
        let sourceEndpoint: MIDIEndpointRef = 0
        var connectedHosts: [String] = []
    }

    static func freshDefaults() -> UserDefaults {
        let name = "NetworkMIDITests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Pops everything the input path has sent to the audio thread so far.
    static func drain(_ engine: SynthEngine, _ midi: MIDIManager) -> [SynthEvent] {
        midi.waitForInput()
        var events: [SynthEvent] = []
        while let event = engine.midiQueue.pop() { events.append(event) }
        return events
    }

    static func notes(_ events: [SynthEvent]) -> [String] {
        events.compactMap { event in
            switch event.kind {
            case .keyDown: "down \(event.index)"
            case .keyUp: "up \(event.index)"
            case .midi where event.index == MIDIControl.sustain.rawValue: "pedal \(Int(event.value))"
            default: nil
            }
        }
    }

    @Test func toggleIsSavedAndRestored() throws {
        let defaults = Self.freshDefaults()
        #expect(!MIDIManager(defaults: defaults, networkSession: FakeSession()).settings.networkMIDI) // off by default

        MIDIManager(defaults: defaults, networkSession: FakeSession()).settings.networkMIDI = true
        #expect(MIDIManager(defaults: defaults, networkSession: FakeSession()).settings.networkMIDI)

        MIDIManager(defaults: defaults, networkSession: FakeSession()).settings.networkMIDI = false
        #expect(!MIDIManager(defaults: defaults, networkSession: FakeSession()).settings.networkMIDI)

        // Settings saved before this option existed load with it off.
        let old = #"{"channel":0,"velocity":2,"bendRange":2,"modWheel":0}"#
        #expect(try !JSONDecoder().decode(MIDISettings.self, from: Data(old.utf8)).networkMIDI)
    }

    @Test func sessionIsEnabledOnlyWhileToggleIsOn() {
        let session = FakeSession()
        session.isEnabled = true // whatever state it was in, the toggle decides
        let midi = MIDIManager(defaults: Self.freshDefaults(), networkSession: session)
        let engine = SynthEngine()
        midi.start(engine: engine)
        #expect(!session.isEnabled)

        midi.settings.networkMIDI = true
        #expect(session.isEnabled)
        #expect(session.connectionPolicy == .anyone)

        midi.settings.networkMIDI = false
        #expect(!session.isEnabled)
    }

    @Test func sessionFollowsSavedToggleAtLaunch() {
        let defaults = Self.freshDefaults()
        MIDIManager(defaults: defaults, networkSession: FakeSession()).settings.networkMIDI = true
        let session = FakeSession()
        let engine = SynthEngine()
        MIDIManager(defaults: defaults, networkSession: session).start(engine: engine)
        #expect(session.isEnabled && session.connectionPolicy == .anyone)
    }

    @Test func turningOffReleasesNetworkNotes() {
        let defaults = Self.freshDefaults()
        let session = FakeSession()
        let midi = MIDIManager(defaults: defaults, networkSession: session)
        let engine = SynthEngine()
        midi.start(engine: engine)
        midi.settings.networkMIDI = true
        _ = Self.drain(engine, midi)

        let network = midi.networkSourceID
        midi.receive(status: 0x90, data1: 60, data2: 100, from: network)
        midi.receive(status: 0x90, data1: 67, data2: 90, from: network)
        midi.receive(status: 0xB0, data1: 64, data2: 127, from: network) // sustain pedal down
        midi.receive(status: 0x90, data1: 48, data2: 90, from: 999)      // a USB keyboard
        #expect(Self.notes(Self.drain(engine, midi)) == ["down 60", "down 67", "pedal 1", "down 48"])

        midi.settings.networkMIDI = false
        // Only the network source's notes and pedal are released; the USB keyboard keeps its note.
        #expect(Self.notes(Self.drain(engine, midi)) == ["up 60", "up 67", "pedal 0"])
        #expect(!session.isEnabled)
    }

    @Test func computerDisconnectingReleasesItsNotes() {
        let session = FakeSession()
        let midi = MIDIManager(defaults: Self.freshDefaults(), networkSession: session)
        let engine = SynthEngine()
        midi.start(engine: engine)
        midi.settings.networkMIDI = true
        session.connectedHosts = ["MacBook Pro"]
        midi.networkSessionChanged()
        _ = Self.drain(engine, midi)

        midi.receive(status: 0x90, data1: 72, data2: 100, from: midi.networkSourceID)
        #expect(Self.notes(Self.drain(engine, midi)) == ["down 72"])

        // Another computer joining releases nothing.
        session.connectedHosts = ["MacBook Pro", "iMac"]
        midi.networkSessionChanged()
        #expect(Self.notes(Self.drain(engine, midi)).isEmpty)

        // The MacBook drops off (sleep, Wi-Fi gone): its held note is released.
        session.connectedHosts = ["iMac"]
        midi.networkSessionChanged()
        #expect(Self.notes(Self.drain(engine, midi)) == ["up 72"])
        #expect(session.isEnabled) // the session itself stays on
    }
}

import CoreMIDI
import Testing
@testable import Ember_One

/// MIDI input without hardware: parsing channel voice messages into what the synth does,
/// releasing exactly what a controller held when it goes away, and the device list logic.
struct MIDIInputTests {
    static func parse(_ status: UInt8, _ data1: UInt8, _ data2: UInt8,
                      velocity: VelocitySensitivity = .normal, bendRange: Float = 2) -> MIDIMessage? {
        MIDIMessage(status: status, data1: data1, data2: data2, velocity: velocity, bendRange: bendRange)
    }

    // MARK: - Parsing

    @Test func noteOnWithVelocity() throws {
        #expect(Self.parse(0x90, 60, 127) == .noteOn(note: 60, level: 1))
        #expect(Self.parse(0x90, 60, 64) == .noteOn(note: 60, level: VelocitySensitivity.normal.level(64)))
        #expect(Self.parse(0x90, 60, 64, velocity: .hard) == .noteOn(note: 60, level: VelocitySensitivity.hard.level(64)))
        #expect(Self.parse(0x90, 60, 64, velocity: .off) == .noteOn(note: 60, level: 0.8))
        let event = try #require(Self.parse(0x90, 61, 100)?.event)
        #expect(event.kind == .keyDown && event.index == 61 && event.value == VelocitySensitivity.normal.level(100))
    }

    @Test func noteOffAndNoteOnWithVelocityZero() throws {
        #expect(Self.parse(0x80, 60, 0) == .noteOff(note: 60))
        #expect(Self.parse(0x80, 60, 90) == .noteOff(note: 60)) // release velocity is ignored
        #expect(Self.parse(0x90, 60, 0) == .noteOff(note: 60))  // running-status style Note Off
        let event = try #require(Self.parse(0x90, 60, 0)?.event)
        #expect(event.kind == .keyUp && event.index == 60)
    }

    @Test func notesKeepTheirNumber() {
        // No octave shift: the on-screen octave setting only moves the on-screen keys.
        for note: UInt8 in [0, 21, 60, 108, 127] {
            #expect(Self.parse(0x90, note, 100)?.event?.index == Int32(note))
        }
    }

    @Test func channelSetting() {
        #expect(MIDIMessage.passes(status: 0x90, channelSetting: 0))  // omni
        #expect(MIDIMessage.passes(status: 0x9F, channelSetting: 0))
        #expect(MIDIMessage.passes(status: 0x93, channelSetting: 4))
        #expect(!MIDIMessage.passes(status: 0x93, channelSetting: 1))
        #expect(Self.parse(0x9F, 60, 100) == .noteOn(note: 60, level: VelocitySensitivity.normal.level(100)))
    }

    @Test func pitchBend() throws {
        #expect(Self.parse(0xE0, 0x00, 0x40) == .pitchBend(semitones: 0))           // centre (8192)
        #expect(Self.parse(0xE0, 0x7F, 0x7F) == .pitchBend(semitones: 2))           // top (16383)
        #expect(Self.parse(0xE0, 0x00, 0x00) == .pitchBend(semitones: -2))          // bottom (0)
        #expect(Self.parse(0xE0, 0x7F, 0x7F, bendRange: 12) == .pitchBend(semitones: 12))
        #expect(Self.parse(0xE0, 0x00, 0x20) == .pitchBend(semitones: -1))          // halfway down (4096)
        let event = try #require(Self.parse(0xE1, 0x7F, 0x7F)?.event)
        #expect(event.kind == .midi && event.index == MIDIControl.pitchBend.rawValue && event.value == 2)
    }

    @Test func modWheel() throws {
        #expect(Self.parse(0xB0, 1, 0) == .modWheel(0))
        #expect(Self.parse(0xB0, 1, 127) == .modWheel(1))
        let event = try #require(Self.parse(0xB0, 1, 127)?.event)
        #expect(event.kind == .midi && event.index == MIDIControl.modWheel.rawValue && event.value == 1)
    }

    @Test func sustainPedal() throws {
        #expect(Self.parse(0xB0, 64, 127) == .sustain(true))
        #expect(Self.parse(0xB0, 64, 64) == .sustain(true))
        #expect(Self.parse(0xB0, 64, 63) == .sustain(false))
        #expect(Self.parse(0xB0, 64, 0) == .sustain(false))
        let event = try #require(Self.parse(0xB0, 64, 127)?.event)
        #expect(event.kind == .midi && event.index == MIDIControl.sustain.rawValue && event.value == 1)
    }

    @Test func allNotesOff() throws {
        #expect(Self.parse(0xB0, 123, 0) == .allNotesOff)
        #expect(Self.parse(0xB0, 120, 0) == .allNotesOff) // All Sound Off
        #expect(try #require(Self.parse(0xB5, 123, 0)?.event).kind == .allNotesOff)
    }

    @Test func otherControllersGoToMIDILearn() {
        #expect(Self.parse(0xB0, 74, 99) == .controlChange(cc: 74, value: 99))
        #expect(Self.parse(0xB0, 74, 99)?.event == nil) // handled on the main actor, not the audio thread
    }

    @Test func ignoredMessages() {
        #expect(Self.parse(0xA0, 60, 50) == nil) // poly aftertouch
        #expect(Self.parse(0xC0, 5, 0) == nil)   // program change
        #expect(Self.parse(0xD0, 50, 0) == nil)  // channel aftertouch
    }

    // MARK: - Releasing a controller that goes away

    @Test func unpluggingReleasesOnlyThatSourcesNotes() {
        var tracker = MIDISourceTracker()
        for message in [Self.parse(0x90, 60, 100)!, Self.parse(0x90, 64, 100)!, Self.parse(0x90, 0, 1)!, Self.parse(0x90, 127, 1)!] {
            tracker.record(message, from: 1)
        }
        tracker.record(Self.parse(0x80, 64, 0)!, from: 1)   // already released
        tracker.record(Self.parse(0x90, 67, 100)!, from: 2) // another controller
        #expect(tracker.heldNotes(of: 1) == [0, 60, 127])

        #expect(tracker.release(1) == [.noteOff(note: 0), .noteOff(note: 60), .noteOff(note: 127)])
        #expect(tracker.release(1).isEmpty) // forgotten
        #expect(tracker.heldNotes(of: 2) == [67])
    }

    @Test func unpluggingLiftsPedalAndCentresWheels() {
        var tracker = MIDISourceTracker()
        tracker.record(.noteOn(note: 48, level: 1), from: 7)
        tracker.record(.sustain(true), from: 7)
        tracker.record(.noteOff(note: 48), from: 7) // held by the pedal
        tracker.record(.pitchBend(semitones: 1.5), from: 7)
        tracker.record(.modWheel(0.6), from: 7)
        #expect(tracker.release(7) == [.sustain(false), .pitchBend(semitones: 0), .modWheel(0)])

        // Pedal up, wheels back at rest: nothing to undo.
        tracker.record(.sustain(true), from: 8)
        tracker.record(.sustain(false), from: 8)
        tracker.record(.pitchBend(semitones: 2), from: 8)
        tracker.record(.pitchBend(semitones: 0), from: 8)
        tracker.record(.modWheel(0), from: 8)
        #expect(tracker.release(8).isEmpty)
    }

    @Test func allNotesOffForgetsWhatWasHeld() {
        var tracker = MIDISourceTracker()
        tracker.record(.noteOn(note: 60, level: 1), from: 1)
        tracker.record(.sustain(true), from: 2)
        tracker.record(.allNotesOff, from: 2) // the audio thread lets go of everything
        #expect(tracker.release(1).isEmpty)
        #expect(tracker.release(2).isEmpty)
    }

    // MARK: - Connecting and disconnecting sources

    @Test func newSourcesConnectAndGoneOnesDisconnect() {
        let connected: [MIDIEndpointRef: Int32] = [10: 1, 11: 2]
        let present: [MIDIEndpointRef: Int32] = [11: 2, 12: 3, 13: 4]
        let changes = MIDIManager.sourceChanges(connected: connected, present: present)
        #expect(changes.connect == [12, 13])
        #expect(changes.removed == [10: 1])

        let nothing = MIDIManager.sourceChanges(connected: present, present: present)
        #expect(nothing.connect.isEmpty && nothing.removed.isEmpty)

        let allGone = MIDIManager.sourceChanges(connected: present, present: [:])
        #expect(allGone.removed == present)
    }

    @Test func deviceLabels() {
        #expect(MIDIManager.label(name: "Arturia KeyStep", driver: "com.apple.AppleMIDIUSBDriver",
                                  isNetworkSession: false, networkHosts: []) == "Arturia KeyStep")
        #expect(MIDIManager.label(name: "WIDI Master", driver: "com.apple.AppleMIDIBluetoothDriver",
                                  isNetworkSession: false, networkHosts: []) == "Bluetooth: WIDI Master")
        #expect(MIDIManager.label(name: "Bluetooth Keys", driver: "com.apple.AppleMIDIBluetoothDriver",
                                  isNetworkSession: false, networkHosts: []) == "Bluetooth Keys")
        #expect(MIDIManager.label(name: "Other App", driver: nil,
                                  isNetworkSession: false, networkHosts: []) == "Other App")
        // The always-present network session is listed only while computers are connected, by their names.
        #expect(MIDIManager.label(name: "Network Session 1", driver: "com.apple.AppleMIDIRTPDriver",
                                  isNetworkSession: true, networkHosts: []) == nil)
        #expect(MIDIManager.label(name: "Network Session 1", driver: "com.apple.AppleMIDIRTPDriver",
                                  isNetworkSession: true, networkHosts: ["MacBook Pro"]) == "MacBook Pro")
    }
}

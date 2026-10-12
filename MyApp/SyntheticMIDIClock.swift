#if DEBUG
import CoreMIDI
import Foundation
import Synchronization

/// DEBUG only, for testing MIDI clock sync without hardware. Enabled with the launch argument
/// `-SyntheticMIDIClock YES`; never created otherwise.
///
/// It builds timestamped MIDI 1.0 packets (24 ticks per quarter note with random timestamp
/// jitter, plus Start, Continue and Stop) and hands them to the app's own CoreMIDI receive
/// block, so parsing, timestamps and the queue to the audio thread are the real path. (A
/// virtual CoreMIDI source would need the background audio mode, which the app doesn't have.)
/// While it runs, clock from real devices is ignored so the clock queue keeps one producer. With `-SyntheticClockScenario YES` it also runs a scripted test and
/// prints, twice a second, how far the step the audio thread scheduled is from the ideal tick.
nonisolated final class SyntheticMIDIClock: @unchecked Sendable {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "SyntheticMIDIClock") }
    static var runsScenario: Bool { UserDefaults.standard.bool(forKey: "SyntheticClockScenario") }

    private struct State {
        var bpm = 120.0
        var jitter = 0.003
        var silentUntil = 0.0
        /// Counts ticks while running (MIDI song position in ticks), like a real device.
        var running = false
        var songTicks: Int64 = 0
        var pending: [UInt8] = []
        /// Ideal (unjittered) host time of each running tick, by song tick.
        var idealTimes: [Int64: Double] = [:]
    }

    private let state = Mutex(State())
    private let deliver: (UnsafePointer<MIDIEventList>) -> Void
    private let secondsPerHostTick: Double
    private var thread: Thread?
    private weak var engine: SynthEngine?

    init(engine: SynthEngine, deliver: @escaping (UnsafePointer<MIDIEventList>) -> Void) {
        self.deliver = deliver
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        secondsPerHostTick = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        self.engine = engine
        if let jitter = UserDefaults.standard.object(forKey: "SyntheticClockJitterMs") as? Double {
            state.withLock { $0.jitter = jitter / 1000 }
        }
        if let bpm = UserDefaults.standard.object(forKey: "SyntheticClockBPM") as? Double {
            state.withLock { $0.bpm = bpm }
        }
        let thread = Thread { [weak self] in self?.run() }
        thread.qualityOfService = .userInteractive
        thread.name = "Synthetic MIDI clock"
        thread.start()
        self.thread = thread
        log("synthetic clock on: \(state.withLock { $0.bpm }) BPM, ±\(state.withLock { $0.jitter } * 1000) ms jitter")
    }

    // MARK: - Controls

    func start() { send(0xFA, "Start") }
    func stop() { send(0xFC, "Stop") }
    func resume() { send(0xFB, "Continue") }
    func setTempo(_ bpm: Double) {
        state.withLock { $0.bpm = bpm }
        log("tempo \(bpm) BPM")
    }
    func silence(_ seconds: Double) {
        let now = hostSeconds()
        state.withLock { $0.silentUntil = now + seconds }
        log("ticks stop for \(seconds) s")
    }

    private func send(_ status: UInt8, _ name: String) {
        state.withLock { $0.pending.append(status) } // sent right before the next tick
        log(name)
    }

    // MARK: - Sender thread

    private func run() {
        var next = hostSeconds() + 0.1
        while true {
            let (bpm, jitter, silentUntil) = state.withLock { ($0.bpm, $0.jitter, $0.silentUntil) }
            let period = 60 / (bpm * 24)
            waitUntil(next)
            let pending = state.withLock { s -> [UInt8] in defer { s.pending.removeAll() }; return s.pending }
            for status in pending {
                emit(status, at: next)
                state.withLock { s in
                    if status == 0xFA { s.running = true; s.songTicks = 0; s.idealTimes.removeAll() }
                    if status == 0xFB { s.running = true }
                    if status == 0xFC { s.running = false }
                }
            }
            if next >= silentUntil {
                emit(0xF8, at: next + Double.random(in: -jitter...jitter))
                state.withLock { s in
                    if s.running {
                        s.idealTimes[s.songTicks] = next
                        s.songTicks += 1
                    }
                }
            }
            next += period
        }
    }

    private func emit(_ status: UInt8, at time: Double) {
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        let word = UInt32(0x1000_0000) | UInt32(status) << 16
        var words = [word]
        MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, MIDITimeStamp(time / secondsPerHostTick), 1, &words)
        deliver(&list)
    }

    private func hostSeconds() -> Double { Double(mach_absolute_time()) * secondsPerHostTick }

    private func waitUntil(_ time: Double) {
        mach_wait_until(UInt64(max(time, 0) / secondsPerHostTick))
    }

    // MARK: - Sync log and scenario

    /// Prints status, tempo, and the latest step's distance from its ideal tick time.
    @MainActor func startLogging() {
        Task { @MainActor [weak self] in
            var lastBank = -1, lastStep = -1
            var tick = 0
            while let self, let engine = self.engine {
                tick += 1
                let bank = engine.playingBank
                let step = engine.currentStep ?? -1
                if bank != lastBank {
                    if lastBank >= 0 { self.log("sequencer bank \(lastBank) -> \(bank) at step \(step + 1)") }
                    lastBank = bank
                }
                if tick % 100 == 0 { // every 0.5 s
                    let (index, time) = engine.debugLastStep
                    let ideal = self.state.withLock { $0.idealTimes[Int64(index) * 6] }
                    let error = ideal.map { String(format: "%+.2f ms", (time - $0) * 1000) } ?? "–"
                    self.log("status \(engine.clockStatus) tempo \(String(format: "%.2f", engine.externalTempo)) " +
                             "playing \(engine.isPlaying) step# \(index) vs ideal tick: \(error)")
                }
                lastStep = step
                try? await Task.sleep(for: .milliseconds(5))
            }
            _ = lastStep
        }
    }

    /// Start, tempo jump, Stop, Continue, lost clock, Continue, a bank change, switching to
    /// the internal clock and back, and Stop.
    @MainActor func runScenario(midi: MIDIManager) {
        midi.settings.clockExternal = true
        let steps: [(Double, @MainActor () -> Void)] = [
            (3, { self.start() }),
            (11, { self.setTempo(128) }),
            (17, { self.stop() }),
            (20, { self.resume() }),
            (24, { self.engine?.selectBank(1); self.log("selected sequencer bank B") }),
            (27, { self.silence(3) }),
            (33, { self.resume() }),
            (37, { midi.settings.clockExternal = false; self.log("clock source -> Internal (playing)") }),
            (41, { midi.settings.clockExternal = true; self.log("clock source -> External (playing)") }),
            (45, { self.engine?.selectBank(0); self.log("selected sequencer bank A") }),
            (49, { self.stop() }),
            (51, { self.log("scenario done") }),
        ]
        for (delay, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { action() } }
        }
    }

    private nonisolated func log(_ message: String) {
        print(String(format: "[clock %.3f] ", hostSeconds()) + message)
        fflush(stdout)
    }
}
#endif

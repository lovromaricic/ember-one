import Foundation
import Synchronization

/// One MIDI System Real-Time message with the host time it was stamped with by CoreMIDI.
nonisolated struct ClockEvent {
    enum Kind: UInt8 { case tick, start, `continue`, stop }
    var kind: Kind
    /// Endpoint the message came from (several sources may send clock; one is followed).
    var source: Int32
    /// Host time (mach ticks) of the message.
    var hostTime: UInt64
}

/// Lock-free single-producer (the CoreMIDI receive thread) / single-consumer (the audio
/// thread) ring of clock events. Storage is allocated once, so pushing and popping never allocate.
nonisolated final class ClockEventQueue: @unchecked Sendable {
    private static var capacity: Int { 1024 } // power of two; ~20 s of ticks at 120 BPM
    private let slots: UnsafeMutablePointer<ClockEvent>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)

    init() {
        slots = .allocate(capacity: Self.capacity)
        slots.initialize(repeating: ClockEvent(kind: .tick, source: 0, hostTime: 0), count: Self.capacity)
    }

    deinit { slots.deallocate() }

    /// Producer thread only. Drops the event if the consumer has fallen far behind.
    @discardableResult
    func push(_ event: ClockEvent) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        guard write - read < Self.capacity else { return false }
        slots[write & (Self.capacity - 1)] = event
        writeIndex.store(write + 1, ordering: .releasing)
        return true
    }

    /// Consumer thread only.
    func pop() -> ClockEvent? {
        let read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        guard read < write else { return nil }
        let event = slots[read & (Self.capacity - 1)]
        readIndex.store(read + 1, ordering: .releasing)
        return event
    }
}

/// Follows an external MIDI clock (24 ticks per quarter note) from timestamped ticks.
///
/// Tempo and phase come from a least-squares line through the timestamps of the recent ticks
/// (up to `maxWindow`), which averages out timestamp jitter far better than following each
/// tick. Every tick is first compared with the line's prediction: intervals far from the
/// median of recent ones are rejected as outliers, missing ticks are counted in, and a lasting
/// bias in the prediction error means the tempo changed, so the window restarts from the most
/// recent ticks and the estimate follows within a beat or two.
/// Pure logic in seconds: no CoreMIDI, no audio, no allocation after `init`.
nonisolated final class ExternalClock {
    /// Tick period limits: 300 BPM and 20 BPM.
    static let shortestTick = 60.0 / (300 * 24)
    static let longestTick = 60.0 / (20 * 24)
    /// Intervals deviating more than this from the median of recent ones are discarded.
    static let outlierTolerance = 0.25
    /// Another source may take over after the followed one has been silent this long (s).
    static let sourceTimeout = 2.0
    /// Ticks fitted as consecutive before counting starts.
    static let acquisitionTicks = 6

    struct Tuning {
        /// Most ticks in the fit (192 = 8 beats): longer is steadier, shorter follows faster.
        var maxWindow = 192
        /// Ticks kept when a tempo change is detected.
        var windowAfterChange = 8
        /// While the tempo keeps moving (accelerando), the fit stays at most this long; it
        /// grows back to `maxWindow` by one tick per tick once changes stop being detected.
        var windowWhileChanging = 48
        /// Prediction errors averaged to detect a tempo jump, and the mean error (in jitter
        /// deviations) that counts as one.
        var biasTicks = 6
        var biasThreshold = 2.0
        /// The same over a longer stretch, with a lower threshold: catches gradual tempo
        /// changes (accelerando, ritardando) without reacting to jitter.
        var driftTicks = 24
        var driftThreshold = 1.0
        /// Smallest jitter assumed (s), so a perfectly clean clock still tolerates rounding.
        var minimumJitter = 0.0002
    }
    let tuning: Tuning

    private static let historyCapacity = 24
    private let history: UnsafeMutablePointer<Double>
    private let scratch: UnsafeMutablePointer<Double>
    private var historyCount = 0
    private var historyNext = 0

    // Fit window: tick indices and raw times, oldest first from `windowStart`.
    private let windowCapacity: Int
    private let windowIndex: UnsafeMutablePointer<Int64>
    private let windowTime: UnsafeMutablePointer<Double>
    private var windowStart = 0
    private var windowCount = 0
    /// Current limit on the fit length (shorter while the tempo is moving).
    private var windowLimit = 0
    // Recent prediction errors (ring), for tempo-change detection.
    private let errors: UnsafeMutablePointer<Double>
    private var errorCount = 0
    private var errorNext = 0
    private let driftErrors: UnsafeMutablePointer<Double>
    private var driftCount = 0
    private var driftNext = 0
    /// Smoothed squared prediction error: the jitter of this source.
    private var jitterVariance = 0.0

    // Followed source.
    private var hasSource = false
    private(set) var source: Int32 = 0
    private var lastSourceTime = -Double.greatestFiniteMagnitude

    // Estimate.
    private var hasFirstTick = false
    private(set) var hasPeriod = false
    /// Index of the last accepted tick (counts dropped ticks too), and its fitted time.
    private(set) var lastIndex: Int64 = -1
    private var lastTime = 0.0
    /// Estimated seconds per tick.
    private(set) var period = 0.5 / 24
    /// The fit's slope before limiting it to the tempo range.
    private var fittedSlope = 0.0
    /// Raw time of the last accepted tick (for intervals and the lost-clock check).
    private(set) var lastTickTime = -Double.greatestFiniteMagnitude
    private var rejectedInARow = 0
    /// Diagnostics: tempo changes detected and ticks rejected so far.
    private(set) var tempoChanges = 0
    private(set) var rejectedTicks = 0

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
        history = .allocate(capacity: Self.historyCapacity)
        history.initialize(repeating: 0, count: Self.historyCapacity)
        scratch = .allocate(capacity: Self.historyCapacity)
        scratch.initialize(repeating: 0, count: Self.historyCapacity)
        windowCapacity = max(tuning.maxWindow, 8)
        windowLimit = windowCapacity
        windowIndex = .allocate(capacity: windowCapacity)
        windowIndex.initialize(repeating: 0, count: windowCapacity)
        windowTime = .allocate(capacity: windowCapacity)
        windowTime.initialize(repeating: 0, count: windowCapacity)
        errors = .allocate(capacity: max(tuning.biasTicks, 1))
        errors.initialize(repeating: 0, count: max(tuning.biasTicks, 1))
        driftErrors = .allocate(capacity: max(tuning.driftTicks, 1))
        driftErrors.initialize(repeating: 0, count: max(tuning.driftTicks, 1))
    }

    deinit {
        history.deallocate()
        scratch.deallocate()
        windowIndex.deallocate()
        windowTime.deallocate()
        errors.deallocate()
        driftErrors.deallocate()
    }

    /// Tempo in BPM (0 until two ticks have been seen).
    var tempo: Double { hasPeriod ? 60 / (period * 24) : 0 }
    /// True once a beat of steady ticks is in the fit.
    var isLocked: Bool { hasPeriod && windowCount >= 24 }

    /// Locked and the clock hasn't gone quiet: no tick is overdue by more than a few periods.
    func isLocked(at time: Double) -> Bool {
        isLocked && time - lastTickTime < 4 * period
    }

    /// Fitted time of tick `index` (past or future), extrapolated along the estimated tempo.
    func time(ofTick index: Int64) -> Double {
        lastTime + Double(index - lastIndex) * period
    }

    /// Forgets everything (another clock source, or switching modes).
    func reset() {
        hasSource = false
        hasFirstTick = false
        hasPeriod = false
        clearWindow()
        historyCount = 0
        historyNext = 0
        rejectedInARow = 0
        jitterVariance = 0
        lastTickTime = -Double.greatestFiniteMagnitude
    }

    /// Whether a message from `source` at `time` should be followed: the first source that
    /// sends clock or Start is followed until it has been silent for `sourceTimeout`.
    func follows(_ source: Int32, at time: Double) -> Bool {
        if hasSource, source != self.source {
            guard time - lastSourceTime > Self.sourceTimeout else { return false }
            reset() // the old source went quiet: start over with the new one
        }
        hasSource = true
        self.source = source
        lastSourceTime = time
        return true
    }

    /// Feeds one clock tick. Returns how many ticks the clock advanced (0 = ignored; more
    /// than 1 when ticks were dropped in between).
    @discardableResult
    func tick(at time: Double, source: Int32) -> Int {
        guard follows(source, at: time) else { return 0 }
        guard hasFirstTick else {
            restart(at: time)
            return 1
        }
        let interval = time - lastTickTime
        guard interval > 0 else { return 0 }

        // Acquisition: the first ticks are taken as consecutive and fitted together, so the
        // first tempo comes from several intervals instead of a single jittery one.
        if windowCount < Self.acquisitionTicks {
            guard (Self.shortestTick * 0.5...Self.longestTick * 1.5).contains(interval) else {
                restart(at: time)
                return 1
            }
            remember(interval)
            accept(index: lastIndex + 1, time: time)
            // Only a tempo between 20 and 300 BPM counts; anything else starts over.
            let inRange = (Self.shortestTick...Self.longestTick).contains(fittedSlope)
            if windowCount == Self.acquisitionTicks, !inRange {
                restart(at: time)
                return 1
            }
            hasPeriod = inRange
            return 1
        }

        // How many ticks since the last one (dropped ticks give 2 or 3), counted from the raw
        // interval against the fitted tempo: neither builds up error while the tempo changes.
        // Then: is this tick an outlier? Only if its interval is far from the median of recent
        // intervals AND it is far from where the fitted line expects it (25% of a tick, or 4×
        // the measured jitter at fast tempos where jitter alone can exceed that).
        let ticks = max(1, Int((interval / period).rounded()))
        let deviation = abs(time - self.time(ofTick: lastIndex + Int64(ticks)))
        let tolerance = max(Self.outlierTolerance * period, 4 * jitterVariance.squareRoot())
        let medianRatio = interval / (historyCount >= 4 ? median() : period)
        let oddInterval = abs(medianRatio - Double(ticks)) > Self.outlierTolerance * Double(ticks)
        if ticks > 4 || (oddInterval && deviation > tolerance) {
            rejectedInARow += 1
            rejectedTicks += 1
            // A long gap or a tempo jump beyond the tolerance: lock again from here.
            if rejectedInARow >= 6 || interval > 8 * period {
                restart(at: time)
                return 1
            }
            return 0
        }
        rejectedInARow = 0
        let single = interval / Double(ticks)
        guard (Self.shortestTick * 0.75...Self.longestTick * 1.25).contains(single) else { return 0 }
        remember(single)

        // Prediction error of the current line; a lasting bias means the tempo moved.
        let index = lastIndex + Int64(ticks)
        let error = time - self.time(ofTick: index)
        if windowCount >= 12 {
            jitterVariance += 0.02 * (error * error - jitterVariance)
        }
        errors[errorNext] = error
        errorNext = (errorNext + 1) % max(tuning.biasTicks, 1)
        errorCount = min(errorCount + 1, max(tuning.biasTicks, 1))
        driftErrors[driftNext] = error
        driftNext = (driftNext + 1) % max(tuning.driftTicks, 1)
        driftCount = min(driftCount + 1, max(tuning.driftTicks, 1))
        if windowCount > tuning.windowAfterChange * 2 {
            let jitter = max(jitterVariance.squareRoot(), tuning.minimumJitter)
            var jump = false, drift = false
            if errorCount == tuning.biasTicks {
                var sum = 0.0
                for i in 0..<errorCount { sum += errors[i] }
                jump = abs(sum / Double(errorCount)) > tuning.biasThreshold * jitter
            }
            if driftCount == tuning.driftTicks {
                var sum = 0.0
                for i in 0..<driftCount { sum += driftErrors[i] }
                drift = abs(sum / Double(driftCount)) > tuning.driftThreshold * jitter
            }
            if jump || drift {
                keepRecent(tuning.windowAfterChange)
                windowLimit = min(tuning.windowWhileChanging, windowCapacity)
                tempoChanges += 1
            }
        }
        accept(index: index, time: time)
        return ticks
    }

    // MARK: - Helpers

    private func restart(at time: Double) {
        hasFirstTick = true
        hasPeriod = false
        historyCount = 0
        historyNext = 0
        rejectedInARow = 0
        clearWindow()
        lastIndex += 1
        lastTime = time
        lastTickTime = time
        append(index: lastIndex, time: time)
    }

    /// Adds a tick to the fit and refits the line.
    private func accept(index: Int64, time: Double) {
        append(index: index, time: time)
        lastTickTime = time
        fit()
    }

    private func append(index: Int64, time: Double) {
        windowLimit = min(windowLimit + 1, windowCapacity)
        while windowCount >= windowLimit, windowCount > 0 {
            windowStart = (windowStart + 1) % windowCapacity
            windowCount -= 1
        }
        let slot = (windowStart + windowCount) % windowCapacity
        windowIndex[slot] = index
        windowTime[slot] = time
        windowCount += 1
    }

    private func clearWindow() {
        windowLimit = windowCapacity
        windowStart = 0
        windowCount = 0
        errorCount = 0
        errorNext = 0
        driftCount = 0
        driftNext = 0
    }

    /// Drops all but the newest `count` ticks from the fit (after a tempo change).
    private func keepRecent(_ count: Int) {
        guard windowCount > count else { return }
        windowStart = (windowStart + windowCount - count) % windowCapacity
        windowCount = count
        errorCount = 0
        errorNext = 0
        driftCount = 0
        driftNext = 0
    }

    /// Least-squares line through the window (relative to the newest tick, for precision).
    private func fit() {
        let newest = (windowStart + windowCount - 1) % windowCapacity
        let newestIndex = windowIndex[newest]
        let newestTime = windowTime[newest]
        guard windowCount >= 2 else {
            lastIndex = newestIndex
            lastTime = newestTime
            return
        }
        var sx = 0.0, sy = 0.0
        for i in 0..<windowCount {
            let slot = (windowStart + i) % windowCapacity
            sx += Double(windowIndex[slot] - newestIndex)
            sy += windowTime[slot] - newestTime
        }
        let n = Double(windowCount)
        let mx = sx / n, my = sy / n
        var sxx = 0.0, sxy = 0.0
        for i in 0..<windowCount {
            let slot = (windowStart + i) % windowCapacity
            let dx = Double(windowIndex[slot] - newestIndex) - mx
            sxx += dx * dx
            sxy += dx * (windowTime[slot] - newestTime - my)
        }
        guard sxx > 0 else { return }
        let slope = sxy / sxx
        fittedSlope = slope
        period = min(max(slope, Self.shortestTick), Self.longestTick)
        lastIndex = newestIndex
        lastTime = newestTime + my - slope * mx
    }

    private func remember(_ interval: Double) {
        history[historyNext] = interval
        historyNext = (historyNext + 1) % Self.historyCapacity
        historyCount = min(historyCount + 1, Self.historyCapacity)
    }

    /// Median of the recent intervals (insertion sort into preallocated scratch space).
    private func median() -> Double {
        let n = historyCount
        for i in 0..<n {
            let value = history[i]
            var j = i
            while j > 0, scratch[j - 1] > value {
                scratch[j] = scratch[j - 1]
                j -= 1
            }
            scratch[j] = value
        }
        return n % 2 == 1 ? scratch[n / 2] : (scratch[n / 2 - 1] + scratch[n / 2]) / 2
    }
}

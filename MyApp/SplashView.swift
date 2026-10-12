import SwiftUI

// Timeline of the splash, in seconds from its first frame.
private enum SplashTiming {
    static let knobFadeIn = 0.4          // 0.0 – 0.4: knob fades in and grows
    static let sweepStart = 0.3          // 0.3 – 1.2: orange arc sweeps, pointer turns
    static let sweepDuration = 0.9
    static let titleStart = 0.7          // 0.7 – 1.2: title and tagline fade in
    static let titleFadeIn = 0.5
    static let hold = 0.8                // 1.2 – 2.0: everything stays still, so the title can be read
    static let fadeOutStart = titleStart + titleFadeIn + hold   // 2.0 – 2.5: splash fades out
    static let fadeOutDuration = 0.5
    static let skipFadeOut = 0.25        // after a tap

    // Reduce Motion: no sweep, just a short fade in, a pause and a fade out.
    static let reducedFadeIn = 0.2
    static let reducedHold = 0.6
    static let reducedFadeOut = 0.3
}

private enum SplashLook {
    static let knobScaleStart: CGFloat = 0.9
    /// How much of the knob's 270° travel the arc ends on (about 2/3, like the app icon).
    static let sweepTarget: Double = 0.67
    static let sweepDegrees: Double = 270
    static let pointerCream = Color(red: 246 / 255, green: 236 / 255, blue: 214 / 255)
    static let track = Color(red: 0.27, green: 0.20, blue: 0.16)
}

/// Animated launch splash: the Ember One knob turns up, then the splash fades away.
/// Tapping skips it. Calls `onFinished` once it is fully transparent.
struct SplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var knobShown = false
    @State private var sweep: Double = 0
    @State private var titleShown = false
    @State private var opacity: Double = 1
    @State private var finishing = false

    var body: some View {
        ZStack {
            Retro.panel
            // Soft orange glow; it fades in with the knob so the handover from the plain
            // launch screen colour has no jump.
            RadialGradient(colors: [Retro.accent.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 340)
                .opacity(knobShown ? 1 : 0)

            VStack(spacing: 36) {
                SplashKnob(sweep: sweep)
                    .frame(width: 220, height: 220)
                    .scaleEffect(knobShown ? 1 : SplashLook.knobScaleStart)
                    .opacity(knobShown ? 1 : 0)

                VStack(spacing: 10) {
                    Text(verbatim: "EMBER ONE")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .tracking(8)
                        .foregroundStyle(Retro.cream)
                    Text(verbatim: "ANALOG SYNTHESIZER")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(5)
                        .foregroundStyle(Retro.accent)
                }
                .opacity(titleShown ? 1 : 0)
                .accessibilityElement(children: .combine)
            }
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .contentShape(Rectangle())
        .onTapGesture { finish(after: 0, duration: SplashTiming.skipFadeOut) }
        .task { run() }
    }

    private func run() {
        if reduceMotion {
            sweep = SplashLook.sweepTarget
            titleShown = true
            withAnimation(.easeOut(duration: SplashTiming.reducedFadeIn)) { knobShown = true }
            finish(after: SplashTiming.reducedFadeIn + SplashTiming.reducedHold, duration: SplashTiming.reducedFadeOut)
            return
        }
        withAnimation(.easeOut(duration: SplashTiming.knobFadeIn)) { knobShown = true }
        withAnimation(.easeOut(duration: SplashTiming.sweepDuration).delay(SplashTiming.sweepStart)) {
            sweep = SplashLook.sweepTarget
        }
        withAnimation(.easeOut(duration: SplashTiming.titleFadeIn).delay(SplashTiming.titleStart)) { titleShown = true }
        finish(after: SplashTiming.fadeOutStart, duration: SplashTiming.fadeOutDuration)
    }

    /// Fades the splash out (once) and reports when it is gone.
    private func finish(after delay: Double, duration: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !finishing else { return }
            finishing = true
            withAnimation(.easeInOut(duration: duration)) { opacity = 0 } completion: {
                onFinished()
            }
        }
    }
}

/// The icon's knob, drawn in code. `sweep` is 0…1 of the 270° travel.
private struct SplashKnob: View {
    var sweep: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let ringWidth = size * 0.07
            let ringDiameter = size - ringWidth
            let bodyDiameter = size * 0.66
            let startAngle = 90 + (360 - SplashLook.sweepDegrees) / 2   // gap at the bottom
            ZStack {
                // Track and orange arc.
                Circle()
                    .trim(from: 0, to: SplashLook.sweepDegrees / 360)
                    .stroke(SplashLook.track, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: ringDiameter, height: ringDiameter)
                Circle()
                    .trim(from: 0, to: sweep * SplashLook.sweepDegrees / 360)
                    .stroke(Retro.accent, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: ringDiameter, height: ringDiameter)
                    .shadow(color: Retro.accent.opacity(0.5), radius: ringWidth * 0.6)

                // Knob body.
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.22, green: 0.19, blue: 0.17), Retro.knobBottom],
                                         center: .center, startRadius: 0, endRadius: bodyDiameter / 2))
                    .overlay(Circle().stroke(Retro.sectionEdge.opacity(0.9), lineWidth: max(1.5, size * 0.006)))
                    .overlay(Circle().inset(by: size * 0.03).stroke(.black.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: size * 0.06, y: size * 0.02)
                    .frame(width: bodyDiameter, height: bodyDiameter)

                // Pointer, turning with the arc.
                Capsule()
                    .fill(SplashLook.pointerCream)
                    .frame(width: size * 0.045, height: bodyDiameter * 0.3)
                    .offset(y: -bodyDiameter * 0.24)
                    .rotationEffect(.degrees(-SplashLook.sweepDegrees / 2 + SplashLook.sweepDegrees * sweep))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SplashView {}
}

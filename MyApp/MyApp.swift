import SwiftUI

@main struct MyApp: App {
    /// True on every cold start; it stays false while the app lives on in the background.
    @State private var showsSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Loads presets and starts audio and MIDI as soon as it appears, i.e. while
                // the splash is still playing on top.
                ContentView()
                if showsSplash {
                    SplashView { showsSplash = false }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .background(Retro.panel.ignoresSafeArea())
        }
    }
}

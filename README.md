# Ember One

An analog-style synthesizer for iPhone with a step sequencer, drum machine, presets and MIDI support.

## Screenshots

| | | |
|:---:|:---:|:---:|
| <img src="docs/screenshots/main.png" width="295" alt="Main screen"> | <img src="docs/screenshots/presets.png" width="295" alt="Presets"> | <img src="docs/screenshots/midi.png" width="295" alt="MIDI"> |
| Main screen | Presets | MIDI |



| | | |
|:---:|:---:|:---:|
https://github.com/user-attachments/assets/26dd78c4-aeab-4e5b-84cc-de215ee0c821 | https://github.com/user-attachments/assets/1218a38a-b715-47a7-aef7-c1aad8e0a67a  | https://github.com/user-attachments/assets/6fcc68c4-8ea9-4f74-920b-7102953590aa  |
| Demo 1 | Demo 2 | Demo 3 |







## Features

- Two oscillators (sine, saw, square, triangle) with level, octave and detune
- Low-pass filter with resonance and envelope amount
- LFO for pitch or filter cutoff
- Amp and filter envelopes
- FX: chorus, delay, reverb, drive and pump
- 16-step sequencer with banks A–H, key mode (transpose, arpeggiator), hold and a Randomize button
- Drum machine with fourteen synthesised drums (kick, snare, clap, hats, toms, rim, cowbell, ride, crash, shaker, clave, FX), sound variants, banks A–H and Randomize for patterns and sounds
- Presets with categories, favorites and search; your own presets can include the drums
- MIDI controller support (USB, Bluetooth and Wi-Fi network MIDI) with MIDI learn
- Sync to external MIDI clock (tempo, start and stop), e.g. from Ableton Live
- Full-width keyboard in landscape

## Requirements

- Xcode 27
- iOS 26 or later

## How to run

1. Open `MyApp.xcodeproj` in Xcode.
2. Choose an iPhone or a simulator as the run destination.
3. Press Run.

## Built with

SwiftUI and AVAudioEngine.

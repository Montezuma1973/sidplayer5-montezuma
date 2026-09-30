# SIDPLAY 5 - UI & UX Enhancement Roadmap

This roadmap tracks ongoing and planned user interface and user experience enhancements for SIDPLAY 5. Each item is tackled sequentially and updated upon completion.

---

## 🕹️ Milestone 1: Retro Visuals & Display Enhancements

- [x] **1.0 Interactive Retro Visualizers**
  - [x] Amiga Boing Ball (1984 demo 3D checkered sphere with physics, squash/stretch, shadow, and purple grid).
  - [x] Commodore Datasette C-60 Cassette Tape with spinning dual reels, tape thickness tracking, mechanical counter, and audio-reactive LED.
  - [x] Commodore 1541 5.25" Floppy Drive with rotating spindle clamp, black floppy disk, steady Power LED, and audio-reactive Drive Activity LED.
  - [x] Classic Equalizer Spectrum Bars with neon glow.
  - [x] Auto-detection mode (Amiga MOD tunes → Boing Ball, C64 SID tunes → Cassette Tape).
  - [x] Seamless click-to-cycle and right-click context menu with persistent user preference.

- [x] **1.1 CRT Monitor & Scanlines Display Overlay**
  - [x] Authentic raster scanline shader/drawing overlay on the visualizer panel.
  - [x] CRT glass curvature vignette, subtle bloom, and corner rounded bezels (Commodore 1084S monitor aesthetic).
  - [x] Switchable phosphor color profiles:
    - *Commodore 1084S Full Color* (authentic RGB shadow mask)
    - *Amber Phosphor* (warm vintage monochrome)
    - *Green Phosphor* (classic green monochrome screen)
    - *C64 Cyan / Deep Blue* (classic VIC-II monitor vibe)
  - [x] Quick toggle via right-click menu, double-click, or `C` key (profile cycle with `P` key).

- [x] **1.2 Retro Hardware Silicon Badges**
  - [x] Illuminated silicon chip badges in the status toolbar indicating active audio hardware:
    - `[ MOS 6581 ]` / `[ MOS 8580 ]` / `[ 2x SID ]` for Commodore 64 SID tunes (with emerald green & electric cyan LEDs).
    - `[ PAULA 8364 ]` for Amiga tracker modules (with warm amber LED).
  - [x] Clickable chip badge in the status bar to directly open the SID model selector popover or Amiga hardware specifications.
  - [x] Integrated silicon DIP-chip badges rendered directly across all retro visualizers (Boing Ball, Datasette Cassette, 1541 Floppy, and Spectrum Bars).
  - [x] Dynamic tooltips and status update on the bottom toolbar chip button.

- [ ] **1.3 Authentic System Color Themes**
  - [ ] Commodore 64 Classic theme (Deep blue `#40318d` / Light blue `#887ecb` borders and PETSCII accents).
  - [ ] Amiga Workbench 1.3 theme (Iconic high-contrast blue, orange, white, and black).
  - [ ] Amiga Workbench 3.1 theme (Clean chisel grey/charcoal aesthetics).

---

## 🎛️ Milestone 2: Multi-Channel Audio Mixer & Tracker Matrix

- [ ] **2.1 Channel Mute & Solo Matrix Strip**
  - [ ] Real-time mute/solo buttons for individual audio channels:
    - Voices 1, 2, and 3 for SID tunes (plus Voice 4-6 for dual SID).
    - Channels 1, 2, 3, and 4 (up to 8 channels) for Amiga MOD / XM / S3M / IT tunes.
  - [ ] Real-time per-channel VU meters / activity LEDs.
  - [ ] Audio engine integration to isolate melody, basslines, arpeggios, and drum samples.

- [ ] **2.2 Live Tracker Pattern View / Piano Roll**
  - [ ] Live upward-scrolling tracker note pattern matrix (displaying notes, instruments, effects).
  - [ ] Optional retro piano roll note waterfall.

---

## 🪟 Milestone 3: Modern macOS Polish & Window Layout

- [ ] **3.1 Frosted Glass Sidebar Translucency**
  - [ ] Integrate macOS `NSVisualEffectView` into the source list and visualizer container for native vibrancy in Dark and Light mode.

- [ ] **3.2 Enhanced Timeline Scrub Bar**
  - [ ] Precise time scrub bar with elapsed and remaining time tooltips on hover.
  - [ ] Subtune section markers and looping controls.

---

## 🖥️ Milestone 4: Desktop Integration & Mini-Modes

- [ ] **4.1 macOS Menu Bar Mini-Player**
  - [ ] Lightweight status item in the macOS menu bar with current song title, Play/Pause, Next/Prev Subtune, and volume controls.

- [ ] **4.2 Detachable Floating Retro Widget**
  - [ ] Ability to pop out the retro visualizer (Boing Ball / Cassette / Floppy) into a compact, borderless floating desktop window.

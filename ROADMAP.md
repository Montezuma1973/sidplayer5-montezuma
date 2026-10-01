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

- [x] **1.3 Authentic System Color Themes**
  - [x] Commodore 64 Classic theme (Deep border purple-blue `#40318d`, screen blue `#352879`, light blue/lavender text `#a5a5ff`, VIC-II gold headers `#eeee77`).
  - [x] Amiga Workbench 1.3 theme (Iconic high-contrast deep blue `#0055aa`, topaz orange selection `#ff8800`, crisp white `#ffffff`, and black `#000000`).
  - [x] Amiga Workbench 3.1 theme (Clean AGA chisel grey `#aaaaaa`, 3D bevels, and Workbench blue selection `#0055aa`).
  - [x] Modern macOS System theme (dynamic Light and Dark mode).
  - [x] Full application styling across main window, browser outline, source list sidebar, top gradient toolbar box, voice notes panel, and retro visualizer.
  - [x] Integrated `View -> Theme` submenu with checkmarks, keyboard shortcut (`T` to cycle), retro visualizer HUD notification overlay, and persistent user preference in `NSUserDefaults`.

---

## 🎛️ Milestone 2: Multi-Channel Audio Mixer & Tracker Matrix

- [x] **2.1 Channel Mute & Solo Matrix Strip**
  - [x] Real-time mute/solo buttons for individual audio channels:
    - Voices 1, 2, and 3 for SID tunes (plus Voice 4-6 for dual SID).
    - Channels 1, 2, 3, and 4 (up to 8 channels) for Amiga MOD / XM / S3M / IT tunes.
  - [x] Real-time per-channel segmented LED VU meters with peak hold and smooth dynamic decay.
  - [x] Channel pitch/note and waveform/instrument inspector readouts (e.g. C-4, SMP 01, period).
  - [x] Interactive mouse hit testing for channel `[ M ]` (Mute), `[ S ]` (Solo), and `[ UNMUTE ALL ]` header button.
  - [x] Quick keyboard shortcuts: keys `1`–`8` toggle Mute, `Shift/Option+1`–`8` toggle Solo, `0`/`U` unmute all.
  - [x] Multi-channel scrolling tracker pattern roll underneath the matrix strip.
  - [x] Audio engine integration across `SPModPlayer` (`libxmp`) and `PlayerLibSidplayWrapper` (`libsidplayfp` ReSID).

- [x] **2.2 Live Tracker Pattern View / Piano Roll**
  - [x] Full-featured **Live Tracker Pattern Matrix** visualizer mode (`SPRetroVisualizerModeTracker`):
    - FastTracker II / ProTracker / OctaMED vertical pattern matrix with active row highlight, `▶` cursor bar, and vintage monospace formatting.
    - Full pattern event inspection per channel: Note (e.g. `C-4`), Sample/Instrument (`01`), Volume (`v64`), and Effect command (`000`, `E01`, `F06`).
    - Tracker status header displaying `POS`, `PAT`, `ROW / TOTAL`, `BPM`, and `SPD`.
    - Integrated silicon chip badges (`[ PAULA 8364 ]` / `[ MOS 6581 ]` / `[ 2x SID ]`), mute `[M]`, solo `[S]`, and mini LED meters per channel column.
  - [x] **Retro Piano Roll Waterfall** visualizer mode (`SPRetroVisualizerModePianoRoll`):
    - Synthesizer piano keyboard (4 octaves spanning C2–B5 with 28 white keys and 20 black keys).
    - Cascading waterfall note ribbons falling downward in distinct per-channel colors (Cyan, Amber, Rose, Emerald Green, Violet, Coral, Mint, and Gold).
    - Keyboard baseline collision effects with dynamic key press illumination, note labels (e.g. `C4`, `F#3`), and flare bursts.
    - Active polyphony voice counter and real-time BPM indicator.
  - [x] Integrated into the retro visualizer cycling (`V` key or click), right-click context menu, HUD overlays, and fully compatible with CRT scanlines & phosphor monitor profiles.

---

## 🪟 Milestone 3: Modern macOS Polish & Window Layout

- [x] **3.1 Frosted Glass Sidebar Translucency**
  - [x] Integrate macOS `NSVisualEffectView` into the source list and visualizer container for native vibrancy in Dark and Light mode.
  - [x] Native frosted glass sidebar behind the source list, visualizer container, and utility toolbar with `NSVisualEffectMaterialSidebar` and `behindWindow` blending.
  - [x] Dynamic theme adaptation: transparent vibrancy for Modern macOS System theme; automatic clean disable/fallback for retro solid themes (C64, Workbench 1.3, Workbench 3.1).
  - [x] Translucent visualizer container framing with 1px hairline glass separators and subtle shine highlights, seamlessly blending Spectrum, Tracker Matrix, and Piano Roll modes over the frosted glass backdrop.

- [x] **3.2 Enhanced Timeline Scrub Bar**
  - [x] Precise interactive timeline scrub bar in the playback status view with real-time seeking across both SID (`libsidplayfp`) and tracker modules (`libxmp`).
  - [x] Hover scrubbing cursor with dynamic tooltip showing elapsed and remaining time (`00:00 (-00:00)`), vertical guide line, and glowing playhead thumb.
  - [x] Subtune section markers placed along the timeline track for multi-song tunes.
  - [x] Integrated Loop Mode button badge toggling between Off (`➡️ OFF`), Single Subtune (`🔁 1`), and All Tracks (`🔁 ALL`) with retro HUD notifications.

---

## 🖥️ Milestone 4: Desktop Integration & Mini-Modes

- [x] **4.1 macOS Menu Bar Mini-Player**
  - [x] Lightweight status item in the macOS menu bar (`NSStatusItem`) with a custom crisp retro Datasette cassette template icon adapting automatically to Dark and Light macOS menu bars.
  - [x] Rich dropdown menu with live-updating Now Playing header: Song title, author/release info, subtune count, elapsed & remaining duration (`00:00 / 00:00 (-00:00)`), and hardware silicon chip badge.
  - [x] Complete playback controls: Play/Pause, Stop, Next/Prev Subtune, Next/Prev Track in Playlist, and Loop mode cycle.
  - [x] Volume control submenu with quick-access presets (100%, 75%, 50%, 25%, Mute) and active level indicators.
  - [x] Main window activation, preferences shortcut, dynamic menu bar hover tooltip, and View menu visibility toggle with `NSUserDefaults` persistence.

- [ ] **4.2 Detachable Floating Retro Widget**
  - [ ] Ability to pop out the retro visualizer (Boing Ball / Cassette / Floppy) into a compact, borderless floating desktop window.

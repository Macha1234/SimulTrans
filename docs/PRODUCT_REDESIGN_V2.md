# SimulTrans Product Redesign V2

Current interface: version 1.1.0.

## Product definition

SimulTrans is a local-first macOS live-translation tool for video, meetings and lectures. Its core promise is not merely “speech can be translated”; it is:

> Start in one click, always know whether audio and recognition are working, read stable captions without covering the content, and recover when an engine is unavailable.

The application therefore has three primary surfaces:

1. **Control Center** — configure an idle session and monitor a live one.
2. **Live Captions** — a consumption-first overlay for video and meetings.
3. **Settings & Diagnostics** — persistent preferences, processing location and technical evidence when something fails.

## Experience principles

- **State before decoration.** Ready, starting, listening, transcribing and failed must be visibly different.
- **One dominant action.** Start/stop owns the action bar; export and destructive actions remain secondary.
- **Progressive disclosure.** Recognition diagnostics never occupy the everyday session flow.
- **Translation first.** The default overlay prioritizes translation while preserving scrollable session history in every layout.
- **Honest locality.** Apple and Whisper run on this Mac. Qwen audio can travel through the user-configured SSH tunnel to a Mini PC CUDA service, and optional Context AI sends text to the user's Ollama service. The optional MLX sidecar runs Qwen on this Mac.
- **No fake controls.** Settings that have no implementation are hidden until the behavior exists.

## Information architecture

### Control Center — idle

- Audio source
- Recognition engine and processing location
- Source/target language route with swap action
- Overlay layout, opacity and type size
- Permission expectation
- Primary `Start translation` action

### Control Center — live

- Real startup/listening/transcribing state
- Compact locked route summary
- Current source text and translation
- Entry count and overlay visibility
- Recovery card with retry or engine fallback
- Primary `Stop translation` action

### Live Captions

- **Translation only** — target text with scrollable translation history
- **Bilingual** — smaller source plus dominant target text, with scrollable history
- **Transcript** — timestamped scrolling history for review
- A continuously visible toolbar for layout, export and hide; caption updates preserve the ability to browse history

### Settings

- General
- Audio & Recognition
- Translation
- Overlay
- Advanced diagnostics

## Visual system

The interface uses native macOS glass surfaces, cool neutral colors and blue primary actions. SF system typography provides consistent Latin and CJK rendering, with rounded system titles and monospaced system text for timestamps and diagnostics. Green indicates an active or healthy state; red marks stopping or errors. Caption surfaces retain strong contrast over video.

The app icon uses the native `assets/logo/AppIconGlass.icon` stack. Generated `AppIconGlass.icns` and `Assets.car` are bundled together so macOS renders the artwork without an extra gray frame. Regenerating these assets requires Xcode 26 or later with Icon Composer support; the app itself builds with Xcode 16 / Swift 6 using the checked-in assets.

## Reliability backlog

The UI redesign deliberately preserves the current recognition pipeline. The next reliability iteration should address:

1. session-generation tokens for asynchronous recognition startup and results;
2. guaranteed final-chunk flush when stopping local ASR;
3. a translation queue for phrases recognized before `TranslationSession` is ready;
4. UUID-based translation updates instead of array-index updates;
5. automatic local session persistence and crash recovery;
6. visible translation error/retry state;
7. real input level and Mini PC health/latency telemetry;
8. SRT/VTT export after entries gain end timestamps.


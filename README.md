<div align="center">
  <img src="assets/logo/app-logo-source.png" alt="SimulTrans app icon" width="132">
  <h1>SimulTrans</h1>
  <p><strong>Free, native real-time speech transcription and translation for macOS.</strong></p>
  <p>Listen to system audio or microphone input, transcribe speech, translate it, and keep a bilingual live transcript on screen.</p>
  <p>
    <a href="https://github.com/Macha1234/SimulTrans/releases/latest/download/SimulTrans.dmg"><strong>Download Latest macOS Build</strong></a>
    ·
    <a href="https://github.com/Macha1234/SimulTrans/releases/latest">Latest Release</a>
  </p>
</div>

## Why SimulTrans Exists

Real-time translation tools are often locked behind subscriptions, and many of them are expensive for a workflow that should feel like a small desktop utility.
SimulTrans is built as a practical, local-first alternative for meetings, livestreams, webinars, classes, and everyday listening across languages.

The goal is not to replace professional interpretation. The goal is to make live understanding easier when you just need fast, accessible subtitles and a saved bilingual transcript.

## What It Does

- Captures either system audio or microphone input.
- Transcribes speech using Apple's native speech stack.
- Translates recognized text with Apple's `Translation` framework.
- Shows source text and translated text in a floating live overlay.
- Preserves completed transcript lines instead of letting new speech overwrite old content.
- Supports app display language settings and target-language-specific overlay text.
- Includes onboarding for macOS permissions.
- Provides an optional recognition debug view for comparing raw, processed, and displayed text.
- Exports transcript history as a plain-text file.

## Screenshot Tour

The screenshots below use the English UI so the GitHub page stays visually consistent.

### First-Run Permission Onboarding

SimulTrans guides the user through the macOS permissions it may need: Screen Recording, Microphone, and Speech Recognition.

![SimulTrans onboarding window](assets/screenshots/onboarding.png)

### Main Control Window

The compact control window manages input source, speech language, translation target, overlay appearance, start/stop actions, export, history clearing, and optional debugging.

![SimulTrans control panel](assets/screenshots/control-panel-current.png)

### Floating Live Overlay

The overlay is designed to sit above meetings, videos, or livestreams. It keeps recent history visible and shows source and translated text side by side.

![SimulTrans live translation overlay](assets/screenshots/live-overlay.png)

### Settings Window

Secondary preferences live in a dedicated Settings window, including appearance, app language, overlay behavior, export defaults, and advanced diagnostics.

![SimulTrans settings window](assets/screenshots/settings-window.png)

### Recognition Debug View

The debug view helps compare the recognizer's raw output with the processed and displayed text. It is useful when tuning speech recognition behavior or investigating noisy audio.

![SimulTrans recognition debug panel](assets/screenshots/control-panel-detail.png)

## How Recognition Works

SimulTrans is intentionally built around Apple's native macOS frameworks instead of paid third-party speech or translation APIs.

- It prefers Apple's modern speech transcription pipeline when available.
- It falls back to the classic `SFSpeechRecognizer` path where needed.
- It keeps a short rolling audio prebuffer to reduce missed words when recognition restarts between utterances.
- It treats in-progress speech as a live row, then commits stable speech into transcript history.
- It allows translations to update while avoiding destructive overwrites of the original recognized source text.

Recognition quality still depends on macOS language assets, source audio quality, background noise, and the language pair being used.

## Download And Install

1. Download `SimulTrans.dmg` from the latest release:

```text
https://github.com/Macha1234/SimulTrans/releases/latest/download/SimulTrans.dmg
```

2. Open the DMG.
3. Drag `SimulTrans.app` into `Applications`.
4. Launch SimulTrans from `Applications`.
5. If macOS blocks the first launch because the app is distributed outside the App Store, right-click the app and choose `Open`, or open `System Settings > Privacy & Security` and choose `Open Anyway`.
6. Grant the requested permissions when prompted.

Current release builds are distributed outside the Mac App Store and are not notarized, so the first launch may include an extra Gatekeeper confirmation step.

## Typical Use Cases

- Following overseas livestreams with translated subtitles.
- Watching webinars or presentations in another language.
- Listening to meetings while keeping a bilingual running transcript.
- Saving useful spoken content with both source text and translated text.
- Debugging recognition behavior with raw recognizer output visible.

## Requirements

- macOS 15 or later.
- Screen Recording permission for system audio capture.
- Microphone permission for microphone mode.
- Speech Recognition permission for transcription.
- Apple speech and translation assets for the languages you want to use.
- Xcode 16 / Swift 6 for local development.

## Development

Build the Swift package:

```bash
swift build
```

Build, sign, install, and launch the app locally:

```bash
./build_and_run.sh
```

By default, `build_and_run.sh` installs the app to:

```text
/Applications/SimulTrans.app
```

The script creates a temporary bundle at `dist/SimulTrans.app` while building, then removes it after installation so your Mac only keeps one active app copy. If you intentionally want to keep the temporary bundle for inspection, run:

```bash
KEEP_DIST_APP=1 ./build_and_run.sh
```

Use your own signing identity if needed:

```bash
SIGNING_ID="Apple Development: Your Name" ./build_and_run.sh
```

If no signing identity is available, the script falls back to ad-hoc signing.

## Packaging A DMG

Create a release DMG:

```bash
./package.sh
```

Override the version if needed:

```bash
VERSION=1.0.1 ./package.sh
```

Release artifacts are written to `dist/`.

## Publishing A Release

For maintainers, publishing a downloadable GitHub release is:

```bash
git tag v1.0.1
git push origin v1.0.1
```

Pushing a `v*` tag triggers the GitHub Actions release workflow. The workflow builds the app on macOS, packages the DMG, generates SHA-256 checksum files, and uploads the assets to GitHub Releases.

## Project Structure

```text
.
├── AppTemplate/        # Template app bundle used for packaging
├── Sources/            # Main app source code
├── assets/             # App icon and README screenshots
├── build_and_run.sh    # Build, sign, install, and launch locally
├── package.sh          # Release build and DMG packaging
├── generate_icon.py    # Generates AppIcon.icns from the logo source
└── debug_ax.swift      # Optional accessibility/debug helper
```

## Tech Stack

- Swift Package Manager
- AppKit + SwiftUI
- `Speech`
- `ScreenCaptureKit`
- `Translation`

## Notes

- The app UI can follow the system language or use a manually selected display language.
- The translation overlay follows the selected target language for status text.
- The checked-in app icon source is used to generate `AppIcon.icns`.
- `debug_ax.swift` is a helper script and is not required for normal usage.
- Build artifacts, DMGs, and temporary outputs are excluded from git.

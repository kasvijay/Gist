# Gist — Project Summary & Capabilities

> Local meeting transcription for macOS. No cloud, no accounts, no network calls — ever.

**Version:** 0.2.1
**Platform:** macOS 14.2+ (Sonoma), Apple Silicon only (M1/M2/M3/M4)
**Language:** Swift 6 / SwiftUI
**Bundle ID:** com.vijaykas.gist
**License:** MIT

---

## What Gist Does

Gist records both sides of video calls (Zoom, Meet, Teams) and transcribes them on-device using Apple's Neural Engine. Recordings and transcripts are plain files you own — no database, no proprietary format, no cloud dependency.

---

## Core Capabilities

### 1. Audio Recording
- **Microphone capture** via AVAudioEngine input tap
- **System audio capture** via Core Audio Taps (macOS 14.2+) — captures remote participants without a meeting bot or browser extension
- **Dual-stream mixing** with RMS-based ducking — automatically reduces system audio volume when the user speaks (threshold: 0.01, duck factor: 0.3x)
- **Soft clipping** to prevent distortion in mixed output
- **Output format:** AAC .m4a (128 kbps, mono)
- **Self-exclusion:** App's own audio is excluded from system capture to prevent feedback loops
- **Device change detection:** Monitors default input/output device changes during recording and shows a warning banner

### 2. Live Transcription
- **Engine:** WhisperKit (Whisper running on Core ML / Neural Engine)
- **Streaming:** Transcribes every 200ms when ≥1.5 seconds of audio is buffered
- **Confirmation holdback:** Last 2 segments shown as "unconfirmed" until they stabilize across subsequent transcription windows
- **Language detection:** Per-window automatic language detection for mixed-language audio
- **Model options:** Multiple WhisperKit model sizes selectable in settings, plus custom model path support
- **Smart model loading:** Checks local cache before attempting download. Determinate progress bar with percentage during download, alert on first-time download completion only
- **Auto-load on switch:** Changing the model in Settings immediately starts loading/downloading — no manual step needed

### 3. Speaker Identification (Diarization)
Two methods available, selectable in Settings:
- **LS-EEND (Live):** FluidAudio LS-EEND (Core ML), up to 10 speakers, labels applied during/after recording
- **VBx (Offline):** FluidAudio VBx pipeline, unlimited speakers, better accuracy, labels applied after recording stops
- **Method:** Time-overlap matching — diarization segments are aligned to transcript segments by finding maximum temporal overlap
- **Output:** Speaker labels (SPEAKER_0, SPEAKER_1, etc.) embedded in transcript
- **Fallback:** If VBx is selected but not ready, falls back to LS-EEND automatically

### 4. On-Device Summarization
- **Default engine:** Gemma 3 4B Instruct QAT (4-bit) via MLX framework
- **Options:** Gemma 3 4B (3.0GB, recommended), Phi-4 Mini (2.2GB), Llama 3.2 3B (1.9GB)
- **Single rich summary** — overview, all key discussion points (no artificial bullet limit), decisions, and action items in one view
- **Smart model loading:** Checks local cache before downloading. Shows "Loading" for cached models, download progress for new ones
- **Streaming output** — summary text appears as it's generated
- **Auto-summarize** — summary is automatically generated when recording stops (can be disabled in Settings)
- **Stop generation** — cancel in-progress summarization via Stop button
- **Regeneration** — can re-summarize at any time via Regenerate button
- **Memory-aware loading** — on 8GB machines, WhisperKit is unloaded before loading summarization model, then reloaded after

### 5. Session Management
- **Storage:** Plain files in `~/Documents/Gist/` — one folder per session
- **Session index:** Lightweight `sessions.json` for fast UI listing without loading full session data
- **Import:** Drag in external audio files for transcription
- **Rename/delete** sessions from the sidebar context menu (rename uses focused text field with Enter to confirm, Escape to cancel)
- **Open in Finder** for direct file access
- **Re-transcribe** any session with a different model (respects VBx diarization selection)

### 6. Crash Recovery
- During recording, a `transcript.partial.json` is saved periodically
- On next launch, interrupted sessions (status = `.recording`) are automatically recovered:
  - Status marked as `.recovered`
  - Partial transcript promoted to final transcript
  - Audio file preserved (playable up to last written buffer)

### 7. Menu Bar Integration
- **MenuBarExtra** provides quick record/stop without opening the main window
- Shows red recording indicator when active
- Quick access to latest session, settings, and quit

---

## What Gist Does NOT Do

- No cloud upload, sync, or backup
- No meeting bot joins calls
- No telemetry, analytics, or crash reporting
- No network calls of any kind after initial model download
- No action item tracking or calendar integration
- No real-time collaboration or sharing

---

## Architecture

### Thread Model
| Thread | Components |
|--------|-----------|
| **Main (@MainActor)** | RecordingManager, TranscriptionEngine, DiarizationManager, SessionStore, SummarizationEngine, all SwiftUI views |
| **Audio IO threads** | RecordingPipeline callbacks, MicrophoneCapture tap, SystemAudioCapture IO proc |
| **Async workers** | TranscriptionWorker (WhisperKit), MLDiarizer (FluidAudio), VBxDiarizer (FluidAudio), model downloads |

### Thread Safety
- Audio IO closures capture dependencies as **local variables only** — never reference `self`
- Cross-thread mutable state protected by **NSLock** (AudioSharedState, AudioFileWriter, StreamingTranscriber)
- No actors on audio threads (NSLock chosen because it works outside async contexts)

### File Layout
```
Gist/
  GistApp.swift              — @main entry, service initialization, window + menu bar
  Info.plist                   — Microphone and system audio permission descriptions
  Gist.entitlements           — No sandbox, audio input enabled

  Audio/
    MicrophoneCapture.swift    — AVAudioEngine input tap
    SystemAudioCapture.swift   — Core Audio Taps for system audio
    AudioMixer.swift           — RMS ducking + vDSP mixing
    AudioFileWriter.swift      — NSLock-protected AAC writer
    AudioSharedState.swift     — NSLock-protected buffer for cross-thread coordination
    RecordingPipeline.swift    — Non-actor orchestrator for all audio IO work
    HighPassFilter.swift       — Butterworth HPF at 80Hz (available, not wired in)
    Normalizer.swift           — RMS normalization (available, not wired in)

  Models/
    Session.swift              — Recording session metadata
    SessionIndex.swift         — Lightweight session list for fast UI
    Speaker.swift              — Speaker identity (id, label, source)
    Transcript.swift           — Segments with timing, text, confidence, speaker
    Summary.swift              — LLM-generated summary with optional parsed sections

  Services/
    RecordingManager.swift     — @MainActor recording lifecycle orchestrator
    TranscriptionEngine.swift  — WhisperKit model management + transcription
    StreamingTranscriber.swift — NSLock-protected live transcription accumulator
    DiarizationManager.swift   — Speaker labeling coordinator (LS-EEND + VBx)
    MLDiarizer.swift           — FluidAudio LS-EEND wrapper (live, up to 10 speakers)
    VBxDiarizer.swift          — FluidAudio VBx offline wrapper (unlimited speakers)
    SessionStore.swift         — File-based session persistence
    CrashRecovery.swift        — Interrupted session recovery on launch
    SummarizationEngine.swift  — On-device LLM summarization (Gemma 3 4B default)

  Views/
    ContentView.swift          — NavigationSplitView root with record button + model info bar + error retry
    WelcomeView.swift          — First-launch onboarding and model selection
    SessionListView.swift      — Sidebar with session list and context menus
    SessionDetailView.swift    — Detail panel with model info, transcript/summary tabs
    LiveTranscriptView.swift   — Real-time transcript during recording
    TranscriptView.swift       — Saved transcript with speaker colors
    SummaryView.swift          — Rich summary display with decisions + action items
    MenuBarView.swift          — Menu bar extra for quick access
    SettingsView.swift         — Model selection (auto-load on switch), permissions, diarization method, storage
```

### Storage Format
```
~/Documents/Gist/
  sessions.json                    — Session index
  [YYYY-MM-dd_HHmmss]/
    metadata.json                  — Session metadata
    audio.m4a                      — AAC recording
    transcript.json                — Transcript with segments + speakers
    transcript.partial.json        — Written during recording (crash recovery)
    summary.json                   — LLM-generated summary (optional)
```

### Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| WhisperKit (argmaxinc) | 0.9.0+ | On-device transcription via Core ML |
| FluidAudio (FluidInference) | 0.13.0+ | Speaker identification via Core ML |
| mlx-swift-lm | pinned commit | On-device LLM for summarization |

---

## Build & Release

```bash
# Local development
brew install xcodegen
xcodegen generate
open Gist.xcodeproj
# Cmd+B to build, Cmd+R to run, Cmd+U to test

# Release
# 1. Bump MARKETING_VERSION in project.yml
# 2. Commit and push
# 3. Tag and push: git tag v0.X.Y && git push origin v0.X.Y
# GitHub Actions builds DMG, signs, notarizes, creates release
# 4. Update SHA256 in kasvijay/homebrew-steno
```

### Install
```bash
brew tap kasvijay/gist
brew install --cask steno
```

---

## System Requirements
- **macOS 14.2+** (Sonoma)
- **Apple Silicon** (M1/M2/M3/M4) — arm64 only, no Intel
- **RAM:** 8GB minimum
- **Disk:** ~5GB free for models (WhisperKit ~600MB, FluidAudio ~500MB, summarization LLM ~3GB)
- **Xcode 16.0+** with Swift 6 (for building from source)

## Permissions Required
- **Microphone** — prompted automatically on first recording
- **Screen & System Audio Recording** — must be granted manually in System Settings for capturing remote call audio

## UI Behavior Notes
- **Record button** is disabled until the transcription model finishes loading/downloading. Automatically re-enables after recording stops or transcription completes (state returns to `.ready`).
- **Model info bar** in toolbar shows active transcription model and diarization method
- **Transcript detail** shows which model was used to generate the transcript
- **Model switching** in Settings auto-loads the new model immediately (no manual download step)
- **Error recovery** — if model loading fails, a "Retry" button appears in the toolbar
- **Summary** is auto-generated after recording stops; saved summaries persist and load when switching sessions
- **Session switching** clears stale summary state so the correct saved summary loads for each session
- **VBx diarization** is used consistently across all transcription paths (recording, re-transcribe, Transcribe Now) when selected in Settings

### Transcription Engine State Machine
```
.notLoaded → .downloading(name, progress) → .loading(name) → .ready
.ready → .streaming (recording) → .ready (stop recording)
.ready → .transcribing(pct) (re-transcribe) → .ready (done)
[any] → .error(msg) → .ready (if model still loaded) or stays .error (retry needed)
```

---

*Last updated: 2026-04-11*

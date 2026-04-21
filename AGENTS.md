# Gist

Native macOS transcription app. Swift/SwiftUI, Apple Silicon, macOS 14.2+.

## Build

```bash
xcodegen generate
open Gist.xcodeproj
```

Build: Cmd+B. Run: Cmd+R. Test: Cmd+U.

CI uses Xcode 16.2 (macOS 15 SDK). Local dev may use a newer Xcode — don't assume a local Release build validates the CI build.

## Release

```bash
# bump MARKETING_VERSION in project.yml
git commit && git push
git tag v0.X.Y && git push origin v0.X.Y
```

GitHub Actions builds DMG, creates release. Then update SHA256 in `kasvijay/homebrew-gist`.

## Dependencies

- **WhisperKit** (argmaxinc/WhisperKit) — transcription via Core ML
- **FluidAudio** (FluidInference/FluidAudio) — speaker identification via Core ML
- **mlx-swift-lm** (ml-explore/mlx-swift-lm) — on-device LLM for meeting summarization

## Architecture

```
Gist/
  GistApp.swift         — app entry point, first-launch gating
  Audio/
    MicrophoneCapture   — AVAudioEngine input tap
    SystemAudioCapture  — Core Audio Taps (macOS 14.2+)
    AudioMixer          — RMS ducking, clipping prevention
    AudioFileWriter     — WAV (LPCM) during recording, converts to M4A after stop (NSLock-protected)
    AudioSharedState    — thread-safe buffer for audio IO threads (NSLock-protected)
    RecordingPipeline   — non-actor class owning all audio-thread work
  Models/               — Codable data types (Session, Transcript, Speaker)
  Services/
    RecordingManager    — @MainActor, holds @Published UI state only
    TranscriptionEngine — WhisperKit wrapper, model management
    StreamingTranscriber — live transcription during recording (NSLock-protected)
    DiarizationManager  — FluidAudio speaker identification
    SummarizationEngine — MLX-LLM meeting summarization (Gemma 3 4B default)
    SessionStore        — ~/Documents/Gist/ file management
    CrashRecovery       — recovers interrupted sessions on launch, repairs WAV headers
  Views/                — SwiftUI (NavigationSplitView, MenuBarExtra, Settings)
    WelcomeView         — first-launch onboarding (model picker, permissions)
```

## Conventions

- `@StateObject` services injected via `@EnvironmentObject`
- Models are Codable structs
- Services are ObservableObject classes
- File storage: ~/Documents/Gist/ with JSON + .wav (recording) → .m4a (final) per session
- Audio-thread closures: zero `self` references, explicit local captures only
- All cross-thread mutable state behind NSLock (not actors — NSLock can't be used in async contexts)

## Thread Safety Rules

Audio IO threads (mic callback, system audio IO proc) run outside any actor. Code on these threads must:
1. Never access `self` of any `@MainActor` or actor-isolated class
2. Use explicit local variable captures in closures (not capture lists with `self`)
3. Protect shared mutable state with NSLock (AudioSharedState, AudioFileWriter, StreamingTranscriber)
4. Keep lock-hold time minimal — do work outside the lock, lock only for reads/writes

## WhisperKit Notes

- Model names use underscores: `large-v3_turbo` not `large-v3-turbo` (matches HuggingFace directory `openai_whisper-large-v3_turbo`)
- 30-second windows are hardcoded in the model architecture (480,000 samples at 16kHz)
- `usePrefillPrompt: false, detectLanguage: true` enables per-window language detection for mixed-language audio
- Streaming transcriber sends full accumulated buffer (not windowed) — language detection is less reliable for live

## User-Facing Language

- Say "on your Mac" not "using MLX" or "via Core ML"
- Say "downloads on first use" not "cached at ~/.cache/huggingface/"
- Say "identifies speakers" not "runs LS-EEND diarization"
- Keep technical details in Settings tooltips; main UI should be plain language

## Action-Side-Effect Checklist

Every button, toggle, or async action must handle three states:
1. **Loading** — show progress or spinner while work happens
2. **Success** — update UI to reflect the new state
3. **Failure** — show an actionable error message with retry if applicable

## Dependency Behavior

When checking runtime behavior of dependencies (HuggingFace cache paths, WhisperKit model formats, FluidAudio output), read the dependency source code. Don't guess directory structures or file formats.

## macOS App Icon

Use asset catalog only — no `.icns` file, no `CFBundleIconFile` in Info.plist. Set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in build settings. macOS applies squircle mask automatically.

## GitHub Actions

- `macos-15` runner with `sudo xcode-select -s /Applications/Xcode_16.2.app`
- `xcodebuild -resolvePackageDependencies` step before build
- Enable Settings → Actions → General → Workflow permissions → Read and write

## Documentation

- **`docs/project-summary.md`** — Full project summary with capabilities, architecture, and file layout. **Must be updated whenever features or capabilities change.**

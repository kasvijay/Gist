# Gist — Improvement Backlog

## Stability

### Critical

- [ ] **RecordingManager double-start race condition** — `RecordingManager.swift:30`
  Set `isStarting = true` synchronously before the async Task. Two rapid `startRecording()` calls currently both pass the guard, creating two concurrent pipelines and corrupting audio.

- [ ] **SessionStore main-thread I/O blocking** — `SessionStore.swift:136-290`
  Move all file I/O (`savePartialTranscript`, `saveTranscript`, `loadTranscript`, `writeIndex`, etc.) to a serial background DispatchQueue. Currently blocks the main thread, causing UI stutter every 10s during recording.

- [ ] **Data model versioning** — `Session.swift`, `SessionIndex.swift`, `Summary.swift`
  Add `version` field and custom decoders with migration logic. Currently no way to evolve the schema without breaking existing session files. `Transcript.swift` has a version field but nothing reads it.

### High

- [ ] **AudioSharedState check-then-act race** — `AudioSharedState.swift:40-48`, `RecordingPipeline.swift:62-68`
  Replace individual property lock/unlock with a single atomic `checkAndStart()` method. Current pattern allows interleaving between the read and write of `writerStarted`.

- [ ] **CrashRecovery file validation** — `CrashRecovery.swift:44-62`
  Validate repaired WAV files are playable (via AVAsset). Validate recovered JSON transcripts parse correctly. Delete incomplete M4A files instead of keeping them.

- [ ] **System sleep handling** — `GistApp.swift`
  Add `NSWorkspace.willSleepNotification` / `didWakeNotification` listeners. Warn user if system slept during recording. Correct elapsed time drift.

- [ ] **Test coverage** — `GistTests.swift`
  Add tests for: RecordingManager state machine, SessionStore concurrent I/O, CrashRecovery scenarios, data model encode/decode round-trips, audio pipeline lifecycle.

## Speed

### Critical

- [ ] **Audio callback heap allocations** — `RecordingPipeline.swift:72-73`
  Replace `Array(UnsafeBufferPointer(...))` with pre-allocated reusable buffers. Currently allocates on every audio callback (~11 times/second).

- [ ] **Blocking file write on audio thread** — `AudioFileWriter.swift:66-80`
  Queue `file.write(from: buffer)` to a background thread. Synchronous disk I/O on the audio thread causes dropped frames on slow disks.

- [ ] **HighPassFilter allocations on audio thread** — `HighPassFilter.swift:31-36`
  Pre-allocate reusable Double/Float working buffers instead of creating new arrays on every callback (currently three heap allocations per callback).

### High

- [ ] **Unbounded streaming audio buffer** — `StreamingTranscriber.swift:19`
  Replace unbounded `_audioSamples` array with a ring buffer or sliding window. A 2-hour meeting accumulates ~460 MB in this buffer alone.

- [ ] **TranscriptView not using LazyVStack** — `TranscriptView.swift:17-45`
  Change `VStack` to `LazyVStack` so segments render only when visible. `LiveTranscriptView` already does this correctly.

- [ ] **Transcript loading not cached** — `SessionDetailView.swift:112`
  Cache loaded transcripts in memory, invalidate on save. Currently re-reads from disk on every SwiftUI view rebuild.

## User Experience

### High

- [ ] **Silent system audio failure** — `RecordingPipeline.swift:35-47`
  Notify the user when system audio capture fails and recording falls back to mic-only. Same for mic recovery failure at `MicrophoneCapture.swift:164`.

- [ ] **No progress indicator for audio import** — `SessionListView.swift:158-188`
  Show a spinner or progress bar when importing large audio files.

- [ ] **Accessibility labels missing** — Views throughout
  Add VoiceOver labels to image-only buttons (record, stop, etc.). Add `ScaledMetric` support for Dynamic Type.

### Medium

- [ ] **MenuBar latest session not clickable** — `MenuBarView.swift:35`
  Make the latest session label a button that navigates to that session in the main window.

- [ ] **Timestamp formatter missing hours** — `TranscriptView.swift:48-51`
  Include hours in the formatter so recordings past 60 minutes display correctly.

- [ ] **No quit confirmation during recording** — `MenuBarView.swift:55`
  Show a confirmation dialog when user quits while recording is active.

- [ ] **Settings changes not communicated** — `SettingsView.swift:45-50`
  Indicate to the user that model changes only apply to future recordings, not the current session.

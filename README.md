# Gist — Local Meeting Transcription for macOS

Offline meeting transcription for Mac. No cloud, no accounts, no network calls — ever. Once the model downloads, Gist runs fully air-gapped on Apple Silicon.

Record both sides of Zoom, Meet, or Teams calls. Transcribe on-device with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Whisper on Core ML). Speaker identification included. Plain files you own — no database, no proprietary format.

## What it does

1. Press record. Captures both sides of the conversation.
2. Words appear live as people speak.
3. Press stop. Audio saved as .m4a, transcript as JSON with timestamps and speaker labels.
4. Browse past sessions. Re-transcribe anytime with a different model.

Recordings go to `~/Documents/Gist/`. Plain folders, plain files. No database.

## Install

```bash
brew tap kasvijay/gist
brew install --cask gist
```

Or download the [latest DMG](https://github.com/kasvijay/gist/releases/latest) directly.

### Permissions

- **Microphone** — prompted automatically on first recording
- **Screen & System Audio Recording** — required for capturing system audio (Zoom, Meet, Teams). Grant in System Settings → Privacy & Security → Screen & System Audio Recording

## Requirements

- macOS 14.2+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4)

## Privacy

- **Audio never leaves your machine.** All transcription runs on Apple Silicon. No audio, transcript text, or file paths are ever transmitted.
- **No meeting bots.** System audio captured via Core Audio Taps — no bot joins your call, no browser extension.
- **No telemetry.** No crash reports, analytics, or network calls of any kind. Fully offline after model download.
- **Your files.** Recordings and transcripts are plain files in `~/Documents/Gist/`. No database, no proprietary format.
- **Open source.** [github.com/kasvijay/gist](https://github.com/kasvijay/gist). You can read every line.

## Extending

Gist outputs clean JSON. It doesn't summarize, generate action items, or integrate with anything. That's by design.

```json
{
  "segments": [
    {"start": 0.0, "end": 3.5, "text": "Let's start with the architecture review", "speaker": "SPEAKER_1"},
    {"start": 3.8, "end": 8.1, "text": "Sure, pulling it up now.", "speaker": "SPEAKER_0"}
  ]
}
```

Point any tool at this. Claude Code, Codex, a shell script, grep. The transcript is yours to do what you want with.

## Architecture

| Component | Technology |
|-----------|-----------|
| Language | Swift |
| UI | SwiftUI |
| System audio | Core Audio Taps (macOS 14.2+) |
| Microphone | AVAudioEngine |
| Transcription | [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML, Neural Engine) |
| Speaker ID | [FluidAudio](https://github.com/FluidInference/FluidAudio) (Core ML) |
| Storage | File system + JSON |

## Build from source

```bash
brew install xcodegen
git clone https://github.com/kasvijay/gist.git
cd steno
xcodegen generate
open Gist.xcodeproj
```

## License

MIT

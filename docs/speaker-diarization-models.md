# Speaker Diarization Models Research

## Current Implementation

Gist supports **two** speaker identification methods, selectable in Settings:

### LS-EEND (Live) — `MLDiarizer.swift`
- **Engine:** FluidAudio LS-EEND
- **Max speakers:** 10 (hardcoded in model architecture — 10 output channels)
- **Mode:** Streaming (live, during recording)
- **Variant:** `dihard3`
- **License:** CC-BY-4.0

### VBx (Offline) — `VBxDiarizer.swift` *(Implemented)*
- **Engine:** FluidAudio OfflineDiarizerManager
- **Max speakers:** Unlimited (clustering-based)
- **Mode:** Batch/offline (post-recording)
- **Architecture:** pyannote segmentation + WeSpeaker embeddings + VBx clustering
- **License:** CC-BY-4.0
- **Trade-off:** Labels applied after recording stops, not during live transcription

## Options for >10 Speakers

### FluidAudio OfflineDiarizerManager (Recommended)

The most practical option. Already part of the FluidAudio Swift Package (a dependency in this project).

| Property | Details |
|----------|---------|
| Max speakers | **Unlimited** (clustering-based, no fixed ceiling) |
| Architecture | pyannote community-1 segmentation + WeSpeaker embeddings + VBx hierarchical clustering |
| Mode | **Batch/offline** (post-recording, not live) |
| Runtime | CoreML on Apple Neural Engine |
| License | CC-BY-4.0 (requires attribution) |
| CoreML models | [FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml) |
| Swift compatible | Yes — same Swift Package already in project |

**Trade-off:** Speaker labels are applied after the recording ends, not during live transcription. For a transcription app this is typically acceptable — you can re-diarize after stop.

### NVIDIA Sortformer (CoreML available, but fewer speakers)

| Property | Details |
|----------|---------|
| Max speakers | **4** (worse than current) |
| Architecture | Fast-Conformer + Transformer |
| Mode | Streaming |
| License | CC-BY-4.0 |
| CoreML models | [FluidInference/diar-streaming-sortformer-coreml](https://huggingface.co/FluidInference/diar-streaming-sortformer-coreml) |

Not useful for >10 speaker use case. Only relevant if you need better overlap handling for small meetings.

### pyannote-audio (Python only)

| Property | Details |
|----------|---------|
| Max speakers | **Unlimited** (clustering-based) |
| License | MIT (code), CC-BY-4.0 (weights) |
| Runtime | Python + PyTorch |
| Swift compatible | **No** — would need subprocess/HTTP bridge |
| Models | [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) |

Cannot be embedded directly in a native macOS app without a Python subprocess.

### NVIDIA NeMo MSDD (Python/CUDA only)

| Property | Details |
|----------|---------|
| Max speakers | **20+** (configurable) |
| License | Apache 2.0 |
| Runtime | Python + PyTorch + CUDA |
| Swift compatible | **No** — no CoreML path exists |

Powerful but impractical for a native Swift app.

### WhisperX (Python only)

| Property | Details |
|----------|---------|
| Max speakers | **Unlimited** (delegates to pyannote) |
| License | BSD-2-Clause |
| Runtime | Python only |
| Swift compatible | **No** |

Wrapper around pyannote. Same limitations for Swift embedding.

## Comparison Summary

| Model | Max Speakers | Live/Streaming | Swift/CoreML | License |
|-------|-------------|----------------|-------------|---------|
| **LS-EEND (current)** | 10 | Yes | Yes | CC-BY-4.0 |
| **FluidAudio Offline VBx** | Unlimited | No (batch) | Yes | CC-BY-4.0 |
| Sortformer | 4 | Yes | Yes | CC-BY-4.0 |
| pyannote (Python) | Unlimited | No | No | MIT / CC-BY-4.0 |
| NeMo MSDD | 20+ | No | No | Apache 2.0 |
| WhisperX | Unlimited | No | No | BSD-2-Clause |

## Recommendation

Use **FluidAudio's OfflineDiarizerManager** for meetings exceeding 10 speakers. It is already available as a Swift Package in this project's dependencies, runs on CoreML/Neural Engine, and has no speaker count ceiling. The trade-off is batch processing (after recording stops) instead of live labeling.

For most meetings (under 10 participants), the current LS-EEND streaming model works well and provides live speaker labels during recording.

## References

- [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)
- [FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml)
- [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)
- [NVIDIA NeMo Speaker Diarization](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/speaker_diarization/intro.html)
- [LS-EEND paper](https://arxiv.org/html/2410.06670v1)

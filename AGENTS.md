# Voca Agent Context

Project-specific context for AI agents working on Voca.

## Priority (per Zhengyi 2026-03-01)

1. ~~History playback~~ — Dropped (dev-only feature)
2. **VAD fix** — On `fix/audio-cutoff-bug` branch, testing
3. **Hot words** — Post-processing correction map in `Transcriber.swift`
4. **Editable bubble** — Future
5. **Voice isolation** — Future (Silero VAD, multi-mic)

## Technical Constraints

- **KMP is black box**: `ASREngine` has no model selection API, no decoder access, no prompt injection
- **TCC resets on re-sign**: Use `AXIsProcessTrustedWithOptions(prompt: true)` not System Settings redirect
- **Sparkle breaks SPM**: `swift build` fails on Sparkle imports — use `xcodebuild`

## Research Findings (2026-03-01)

### VAD Audio Cut-Off (3 bugs)
1. Flush threshold too high (1.0s → 0.15s)
2. Race condition: callback cleared before async transcription
3. Fixed silence duration vs dynamic tracking

### Voice Processing
- **Noise cancellation hurts ASR** — removes speech-adjacent frequencies
- **Voice isolation** is the correct approach — Silero VAD (ONNX, in stack)
- **Quick win**: `setVoiceProcessingEnabled(true)` — 2 lines

### Hot Words
- KMP has no decoder API → post-processing only viable path
- TCPGen trie biasing (30% WER reduction) — requires decoder access, future
- Whisper `initial_prompt` is weak/inconsistent

### Apple macOS 26 APIs
- `SpeechAnalyzer` + `SpeechTranscriber` — future migration path
- `AVCaptureDevice.MicrophoneMode.voiceIsolation` — requires AVCaptureSession (architecture change)

### WhisperFlow 6min Cutoff
- OpenAI API 25MB limit — not applicable to Voca (local ASREngine)
- VAD-guided chunking > fixed-time chunking

## Zhengyi's Vision

- **Always-on listening** — no hotkey, learn from user's speech
- **Voice isolation via spatial direction** — multiple mics, separate speakers
- **Diarization prototype exists** — identifies speakers, clusters voices
- Voca is "冰山一角" in ZenX ecosystem

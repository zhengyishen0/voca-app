# VoicePipeline KMP - Open Source Idea

> **Status**: Idea / Future Project
> **Date**: January 2025

---

## The Idea

Extract and publish the KMP voice pipeline as an open-source Kotlin Multiplatform library for on-device speech recognition - an alternative to WhisperKit (Swift-only) and FluidAudio (Swift-only).

---

## Market Gap

| Existing Solution | Language | Platforms | Models | Limitation |
|-------------------|----------|-----------|--------|------------|
| WhisperKit | Swift | Apple only | Whisper only | No KMP, single model |
| FluidAudio | Swift | Apple only | Parakeet only | No KMP, single model |
| Vosk | C++ | Cross-platform | Vosk models | Not KMP native, complex setup |
| kotlin_speech_features | Kotlin | KMP | None | Feature extraction only, no inference |

**Gap: No Kotlin Multiplatform native ASR library with on-device inference.**

---

## Value Proposition

```
┌──────────────────────────────────────────────────────────────────┐
│                      VoicePipeline KMP                           │
│        "On-device speech recognition for Kotlin developers"      │
├──────────────────────────────────────────────────────────────────┤
│  ✓ Multiple ASR models (SenseVoice, Whisper, Parakeet)           │
│  ✓ Multiple backends (CoreML, ONNX Runtime)                      │
│  ✓ Kotlin Multiplatform (macOS, iOS, Android potential)          │
│  ✓ 100% on-device, privacy-first                                 │
│  ✓ Single unified API for all models                             │
│  ✓ VAD (Voice Activity Detection) included                       │
│  ✓ Speaker embeddings included                                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Current State

| Metric | Value |
|--------|-------|
| Location | `/Users/zhengyishen/Codes/claude-code/voice/pipelines/kmp` |
| Lines of Kotlin | ~5,000 |
| Models | SenseVoice (working), Whisper Turbo (partial), Parakeet (planned) |
| Backends | CoreML, ONNX Runtime |
| Platforms | macOS (working) |

---

## Proposed README (Draft)

````markdown
# VoicePipeline

On-device speech recognition for Kotlin Multiplatform.

[![Kotlin](https://img.shields.io/badge/Kotlin-2.0-blue.svg)](https://kotlinlang.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS%20%7C%20Android-lightgrey.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

## Features

- **Multiple ASR Models**: SenseVoice, Whisper Turbo, Parakeet
- **Multiple Backends**: CoreML (Apple), ONNX Runtime (cross-platform)
- **On-Device**: 100% local inference, no cloud required
- **Privacy-First**: Audio never leaves the device
- **Kotlin Multiplatform**: Share code across macOS, iOS, and Android

## Quick Start

```kotlin
// Initialize
val engine = ASREngine(
    modelDir = "/path/to/models",
    assetsDir = "/path/to/assets"
)
engine.initialize()

// Transcribe
val audioSamples: FloatArray = loadAudio("recording.wav")  // 16kHz mono
val text = engine.transcribe(audioSamples)
println(text)  // "Hello, world!"
```

## Supported Models

| Model | Languages | Speed | Accuracy | Size |
|-------|-----------|-------|----------|------|
| **SenseVoice** | Chinese, English, Japanese, Korean, Cantonese | Fast | High | 200MB |
| **Whisper Turbo** | 99 languages | Medium | Very High | 800MB |
| **Parakeet** | English | Very Fast | Highest (English) | 600MB |

## Installation

### Gradle (Kotlin DSL)

```kotlin
dependencies {
    implementation("com.voicepipeline:voicepipeline-core:1.0.0")
}
```

### Swift Package Manager (for iOS/macOS)

```swift
dependencies: [
    .package(url: "https://github.com/user/voicepipeline-kmp", from: "1.0.0")
]
```

## Platform Support

| Platform | Backend | Status |
|----------|---------|--------|
| macOS | CoreML | ✅ Stable |
| iOS | CoreML | 🚧 In Progress |
| Android | ONNX Runtime | 📋 Planned |

## Usage Examples

### Basic Transcription

```kotlin
val result = engine.transcribe(audioSamples)
println(result)
```

### With Custom Vocabulary (Whisper only)

```kotlin
val result = engine.transcribe(
    audio = audioSamples,
    customWords = "Claude, Anthropic, GPT-4"  // Bias toward these words
)
```

### Voice Activity Detection

```kotlin
val vad = VADEngine(modelPath = "/path/to/silero_vad.mlmodelc")
val hasSpeech = vad.detect(audioChunk)
```

### Real-time Transcription

```kotlin
val pipeline = LivePipeline(
    vadModel = vadModel,
    asrModel = asrModel,
    onResult = { segment ->
        println("[${segment.startTime}s] ${segment.text}")
    }
)

// Feed audio chunks
pipeline.processAudio(chunk1)
pipeline.processAudio(chunk2)
pipeline.flush()
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Your Application                     │
├─────────────────────────────────────────────────────────┤
│                   VoicePipeline API                     │
│              ASREngine / VADEngine / etc.               │
├──────────────────┬──────────────────┬───────────────────┤
│   SenseVoiceASR  │   WhisperASR     │   ParakeetASR     │
├──────────────────┴──────────────────┴───────────────────┤
│              Inference Backend Layer                    │
│         CoreMLModel  /  ONNXModel  /  TFLiteModel       │
├──────────────────┬──────────────────┬───────────────────┤
│     macOS/iOS    │     Android      │     Desktop       │
│    (CoreML)      │   (ONNX/TFLite)  │   (ONNX)          │
└──────────────────┴──────────────────┴───────────────────┘
```

## Comparison

| Feature | VoicePipeline | WhisperKit | FluidAudio | Vosk |
|---------|--------------|-----------|------------|------|
| Language | Kotlin | Swift | Swift | C++ |
| KMP Support | ✅ | ❌ | ❌ | ❌ |
| Multi-Model | ✅ | ❌ | ❌ | ❌ |
| Prompt/Custom Words | ✅ (Whisper) | ✅ | ❌ | ❌ |
| VAD | ✅ | Basic | ✅ | ✅ |
| Speaker Diarization | ✅ | Pro ($) | ✅ | ❌ |
| Android | 🚧 | ❌ | ❌ | ✅ |

## License

MIT License - Use freely in personal and commercial projects.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).
````

---

## Work Required to Publish

### High Priority

| Task | Effort | Description |
|------|--------|-------------|
| Clean API surface | Low | Remove internal/CLI code from public API |
| Add iOS target | Medium | Share CoreML code, add iOS-specific bindings |
| Documentation | Medium | API docs, usage examples |
| Model download helper | Low | Helper to download models from HuggingFace |
| Publish to GitHub | Low | Create repo, add CI |

### Medium Priority

| Task | Effort | Description |
|------|--------|-------------|
| Add prompt support | Medium | Whisper custom vocabulary |
| Add Android target | High | ONNX Runtime or TFLite backend |
| Maven Central publish | Low | Package for Gradle dependency |
| Example apps | Medium | Sample macOS/iOS/Android apps |

### Low Priority

| Task | Effort | Description |
|------|--------|-------------|
| Parakeet integration | Medium | Full FluidAudio-style support |
| Streaming API | Medium | Real-time transcription improvements |
| Model quantization | High | Smaller/faster models |

---

## Potential Revenue Model

| Tier | Price | Features |
|------|-------|----------|
| **Open Source** | Free | Core ASR, VAD, community models |
| **Pro** | $29/mo | Optimized models, diarization, priority support |
| **Enterprise** | Custom | Custom model training, dedicated support, SLA |

---

## Next Steps (When Ready)

1. Create new GitHub repo `voicepipeline-kmp`
2. Extract and clean up code from current location
3. Add iOS target (relatively easy - shares CoreML)
4. Write comprehensive README and docs
5. Create sample apps
6. Announce on Kotlin Slack, Reddit, Twitter

---

## Related Files

- KMP Source: `/Users/zhengyishen/Codes/claude-code/voice/pipelines/kmp/`
- Custom Words Plan: `/Users/zhengyishen/Codes/voca-app/docs/custom-words-implementation-plan.md`

# Custom Words Feature Implementation Plan

> **Goal**: Implement Handy.app-style custom words that automatically correct similar-sounding words during transcription (e.g., adding "claude" auto-corrects "cloud" → "claude").

## Background

### Current State
- Voca has a **word mapping** feature: explicit `find=replace` pairs applied post-transcription
- User must know the exact wrong transcription ("cloud=claude")
- Works with any model but is reactive, not proactive

### Desired State (Handy-style)
- User adds words to a list: "claude", "Anthropic", "GPT-4"
- Model is **biased during transcription** to recognize these words
- No need to know what the misheard word would be

### Technical Reality

| Model | Prompt Support | Reason |
|-------|---------------|--------|
| **SenseVoice** | ❌ Impossible | CTC decoding (non-autoregressive) |
| **Whisper Turbo** | ✅ Possible | Encoder-decoder (autoregressive) |
| **Parakeet** | ❌ Impossible | CTC decoding (non-autoregressive) |

**Only Whisper Turbo can support true custom words via prompt conditioning.**

---

## Implementation Options

### Option A: Modify KMP Pipeline (Recommended)
Add prompt support to existing KMP WhisperModel.

**Pros**: Single codebase, full control, works with existing architecture
**Cons**: Requires KMP development, tokenizer implementation

### Option B: Add WhisperKit as Alternative Backend
Use WhisperKit (MIT, free) for Whisper models alongside KMP for SenseVoice.

**Pros**: Prompt support already built-in, battle-tested
**Cons**: Two transcription backends, larger app, more complexity

### Option C: Phonetic Post-Processing (Fallback)
After transcription, use phonetic similarity to replace words.

**Pros**: Works with any model
**Cons**: Lower accuracy, false positives, more CPU

---

## Recommended Approach: Option A (KMP Modification)

### Phase 1: Enable Whisper Turbo in KMP

**Goal**: Get Whisper Turbo working through VoicePipeline (currently only SenseVoice works)

#### 1.1 Modify ASREngine to Support Multiple Models

**File**: `kmp/src/nativeMacosMain/kotlin/com/voice/api/ASREngine.kt`

```kotlin
class ASREngine(
    private val modelDir: String,
    private val assetsDir: String
) {
    private var currentModel: ASRModel? = null
    private var modelType: ASRModelType = ASRModelType.SENSEVOICE

    fun initialize(): Boolean {
        // Detect model type from directory contents
        modelType = detectModelType(modelDir)

        return when (modelType) {
            ASRModelType.SENSEVOICE -> initializeSenseVoice()
            ASRModelType.WHISPER_TURBO -> initializeWhisper()
        }
    }

    private fun detectModelType(dir: String): ASRModelType {
        // Check for Whisper model files
        val whisperConfig = "$dir/config.json"
        if (File(whisperConfig).exists()) {
            return ASRModelType.WHISPER_TURBO
        }
        return ASRModelType.SENSEVOICE
    }

    fun transcribe(audio: FloatArray, prompt: String? = null): String? {
        return currentModel?.transcribe(audio, prompt)?.text
    }
}
```

#### 1.2 Update ASRModel Interface

**File**: `kmp/src/nativeMacosMain/kotlin/com/voice/platform/ASRModel.kt`

```kotlin
interface ASRModel {
    val modelType: ASRModelType

    // Existing method
    fun transcribe(audio: FloatArray): ASRResult?

    // New method with prompt support (default implementation for CTC models)
    fun transcribe(audio: FloatArray, prompt: String?): ASRResult? {
        // Default: ignore prompt (for CTC models that don't support it)
        return transcribe(audio)
    }
}
```

#### 1.3 Verify Whisper Turbo Works

```bash
cd /Users/user/Codes/claude-code/voice/pipelines/kmp
./gradlew linkDebugExecutableMacos
./build/bin/macos/debugExecutable/kmp-pipeline.kexe file test.wav --whisper
```

---

### Phase 2: Add Prompt Support to WhisperModel

**Goal**: Modify WhisperModel to accept and use prompt tokens

#### 2.1 Add Tokenizer Encode Method

**File**: `kmp/src/nativeMacosMain/kotlin/com/voice/platform/WhisperModel.kt`

Add to `WhisperTokenizer` class:

```kotlin
class WhisperTokenizer private constructor(
    private val vocab: Map<Int, String>,
    private val tokenToId: Map<String, Int>  // Add reverse mapping
) {
    companion object {
        fun load(path: String): WhisperTokenizer? {
            // ... existing code ...

            // Build reverse mapping
            val tokenToId = mutableMapOf<String, Int>()
            idToToken.forEach { (id, token) ->
                tokenToId[token] = id
            }

            return WhisperTokenizer(idToToken, tokenToId)
        }
    }

    /**
     * Encode text to token IDs using simple word lookup.
     * For custom words, we use a simplified approach:
     * - Split by spaces
     * - Look up each word with "Ġ" prefix (Whisper's space marker)
     * - Fall back to character-level if word not found
     */
    fun encode(text: String): List<Int> {
        val tokens = mutableListOf<Int>()
        val words = text.split(" ").filter { it.isNotEmpty() }

        for ((index, word) in words.withIndex()) {
            val prefix = if (index > 0) "Ġ" else ""
            val tokenKey = "$prefix${word.lowercase()}"

            val tokenId = tokenToId[tokenKey]
            if (tokenId != null) {
                tokens.add(tokenId)
            } else {
                // Word not in vocab - try without prefix or skip
                tokenToId[word.lowercase()]?.let { tokens.add(it) }
            }
        }

        return tokens
    }

    // ... existing decode method ...
}
```

#### 2.2 Modify runDecoder to Accept Prompt Tokens

**File**: `kmp/src/nativeMacosMain/kotlin/com/voice/platform/WhisperModel.kt`

```kotlin
override fun transcribe(audio: FloatArray, prompt: String?): ASRResult? {
    return memScoped {
        try {
            val melOutput = computeMelSpectrogram(audio) ?: return null
            val encoderOutput = runEncoder(melOutput) ?: return null

            // Encode prompt if provided
            val promptTokens = prompt?.let { tokenizer.encode(it) } ?: emptyList()

            val tokens = runDecoder(encoderOutput, promptTokens) ?: return null
            val text = tokenizer.decode(tokens)

            ASRResult(text = text, tokens = tokens, language = detectLanguage(tokens))
        } catch (e: Exception) {
            println("Whisper transcribe error: ${e.message}")
            null
        }
    }
}

private fun runDecoder(
    encoderOutput: MLMultiArray,
    promptTokens: List<Int> = emptyList()
): List<Int>? {
    return memScoped {
        val tokens = mutableListOf<Int>()
        val maxTokens = config.maxLength

        // Start with special tokens
        tokens.add(config.decoderStartTokenId)  // <|startoftranscript|>
        tokens.add(config.langToId["<|en|>"] ?: 50259)  // Language
        tokens.add(config.taskToId["transcribe"] ?: 50360)  // Task

        // === INSERT PROMPT TOKENS HERE ===
        // Add <|startofprev|> token before prompt (token ID 50361)
        if (promptTokens.isNotEmpty()) {
            tokens.add(50361)  // <|startofprev|>
            tokens.addAll(promptTokens)
        }

        tokens.add(config.noTimestampsTokenId)  // No timestamps

        // Track where actual transcription starts
        val transcriptionStartIndex = tokens.size

        while (tokens.size < maxTokens) {
            // ... existing autoregressive decoding loop ...
            val nextToken = getNextToken(logits, tokens.size - 1)

            if (nextToken == config.eosTokenId) break
            tokens.add(nextToken)
        }

        // Return only the transcribed tokens (exclude prefix)
        tokens.drop(transcriptionStartIndex)
    }
}
```

#### 2.3 Expose Prompt in Public API

**File**: `kmp/src/nativeMacosMain/kotlin/com/voice/api/ASREngine.kt`

```kotlin
/**
 * Transcribe audio with optional vocabulary hint.
 *
 * @param audio 16kHz mono float samples
 * @param customWords Space-separated list of words to bias recognition toward
 * @return transcribed text, or null if transcription failed
 */
fun transcribe(audio: FloatArray, customWords: String? = null): String? {
    val model = currentModel ?: return null
    return model.transcribe(audio, customWords)?.text
}
```

---

### Phase 3: Rebuild Framework

```bash
cd /Users/user/Codes/claude-code/voice/pipelines/kmp

# Build release framework
./gradlew linkReleaseFrameworkMacosArm64

# The output will be at:
# build/bin/macosArm64/releaseFramework/VoicePipeline.framework

# Copy to voca-app
cp -R build/bin/macosArm64/releaseFramework/VoicePipeline.framework \
      /Users/user/Codes/voca-app/Frameworks/VoicePipeline.xcframework/macos-arm64_x86_64/
```

---

### Phase 4: Update Voca App

#### 4.1 Update AppSettings

**File**: `Voca/Settings/AppSettings.swift`

```swift
// Add new property for custom words (simple list, not mapping)
var customWords: [String] {
    get {
        defaults.stringArray(forKey: Keys.customWords) ?? []
    }
    set {
        defaults.set(newValue, forKey: Keys.customWords)
    }
}

// Keep wordReplacements for backward compatibility / fallback
```

#### 4.2 Update Settings UI

**File**: `Voca/Views/SettingsWindowController.swift`

Change the word replacement UI to a simpler word list:

```swift
// Change label
helpLabel.stringValue = """
Add words that are often misheard during transcription.
The system will automatically recognize these words.
One word per line. (Requires Whisper Turbo model)
"""

// Parse as simple list instead of key=value
func parseCustomWords(_ text: String) -> [String] {
    return text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}
```

#### 4.3 Update Transcriber

**File**: `Voca/Services/Transcriber.swift`

```swift
func transcribe(audioURL: URL, customWords: [String]? = nil,
                completion: @escaping (TranscriptionResult) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else {
            completion(TranscriptionResult(text: nil, modelTime: 0))
            return
        }

        // Convert custom words array to space-separated string
        let prompt = customWords?.joined(separator: " ")

        let result = self.runTranscription(audioURL: audioURL, prompt: prompt)
        completion(result)
    }
}

private func transcribeChunk(_ samples: [Float], prompt: String? = nil) -> String? {
    let kotlinArray = KotlinFloatArray(size: Int32(samples.count))
    for (index, sample) in samples.enumerated() {
        kotlinArray.set(index: Int32(index), value: sample)
    }

    // Use new API with prompt
    return engine.transcribe(audio: kotlinArray, customWords: prompt)
}
```

#### 4.4 Update VoiceTranslatorApp

**File**: `Voca/App/VoiceTranslatorApp.swift`

```swift
private func transcribeAudio(at audioURL: URL) {
    let settings = AppSettings.shared

    // Only pass custom words for Whisper model
    let customWords: [String]? = settings.selectedModel == .whisperTurbo
        ? settings.customWords
        : nil

    transcriber.transcribe(audioURL: audioURL, customWords: customWords) { result in
        // ... existing handling ...
    }
}
```

---

### Phase 5: Testing

#### 5.1 Test Cases

| Test | Input | Custom Words | Expected |
|------|-------|--------------|----------|
| Basic | "Hello world" | none | "Hello world" |
| Custom word | "I love cloud code" | ["claude"] | "I love claude code" |
| Multiple words | "Using chat gpt and bard" | ["ChatGPT", "Bard"] | "Using ChatGPT and Bard" |
| No effect on SenseVoice | "cloud code" | ["claude"] | "cloud code" (unchanged) |

#### 5.2 Edge Cases to Handle

- Empty custom words list
- Very long custom words list (>224 tokens limit)
- Words not in Whisper vocabulary
- Non-English custom words with Whisper

---

## Timeline Estimate

| Phase | Tasks | Complexity |
|-------|-------|------------|
| Phase 1 | Enable Whisper in KMP | Medium |
| Phase 2 | Add prompt support | Medium-High |
| Phase 3 | Rebuild framework | Low |
| Phase 4 | Update Voca app | Low-Medium |
| Phase 5 | Testing | Low |

---

## Alternative: WhisperKit Integration

If KMP modification proves too complex, consider adding WhisperKit as a second backend:

### Setup

```swift
// Package.swift or Xcode SPM
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
]
```

### Usage

```swift
import WhisperKit

class WhisperKitTranscriber {
    private var whisperKit: WhisperKit?

    func initialize() async throws {
        whisperKit = try await WhisperKit(model: "large-v3-turbo")
    }

    func transcribe(audioURL: URL, customWords: [String]) async throws -> String {
        guard let whisper = whisperKit else { throw TranscriptionError.notInitialized }

        // Encode custom words as prompt
        let promptText = customWords.joined(separator: ", ")
        let promptTokens = whisper.tokenizer.encode(text: promptText)
            .filter { $0 < whisper.tokenizer.specialTokens.specialTokenBegin }

        let options = DecodingOptions(
            promptTokens: promptTokens,
            // Workaround for empty result issue
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.3
        )

        let result = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return result.text
    }
}
```

### Considerations

- WhisperKit adds ~50MB to app size
- Need to handle two different transcription paths
- WhisperKit's promptTokens has [known issues](https://github.com/argmaxinc/WhisperKit/issues/372) with some models

---

## Fallback: Phonetic Post-Processing

If prompt-based approach doesn't work well, implement phonetic similarity matching:

```swift
import NaturalLanguage

func applyPhoneticCorrections(_ text: String, customWords: [String]) -> String {
    var result = text
    let words = text.components(separatedBy: .whitespaces)

    for word in words {
        for customWord in customWords {
            if soundsSimilar(word, customWord) && word.lowercased() != customWord.lowercased() {
                result = result.replacingOccurrences(
                    of: "\\b\(word)\\b",
                    with: customWord,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }
    }

    return result
}

func soundsSimilar(_ word1: String, _ word2: String) -> Bool {
    // Use Soundex or Metaphone algorithm
    let soundex1 = soundex(word1)
    let soundex2 = soundex(word2)
    return soundex1 == soundex2
}
```

---

## Decision Matrix

| Criteria | KMP Mod | WhisperKit | Phonetic |
|----------|---------|------------|----------|
| Accuracy | High | High | Medium |
| Effort | High | Medium | Low |
| App Size | Same | +50MB | Same |
| Works with SenseVoice | No | No | Yes |
| Maintenance | You | Argmax | You |

**Recommendation**: Start with KMP modification (Option A). If it takes too long, fall back to phonetic post-processing for v1, then revisit WhisperKit later.

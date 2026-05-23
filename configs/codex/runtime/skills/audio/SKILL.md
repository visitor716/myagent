---
name: audio
description: Imported flat Claude Code skill from audio.md. Use when the task matches the workflow described below or the user asks for audio-related workflow help.
---

<!-- Managed by sync-shared-skills. Source: /home/zhanxp/.claude/skills/audio.md -->

# Audio Skill

Specialized skill for Web Audio API and audio processing in NeoCD music player.

## Usage

```
/audio [command]
```

## Project Audio Architecture

```
Local Audio File
      ↓
File System Access API
      ↓
Web Audio Engine (AudioContext)
      ↓
Player UI (React)
```

## Web Audio API Core

### AudioContext Setup
```typescript
// src/services/audio/audioContext.ts
const audioContext = new AudioContext()

// Resume on user interaction (browser policy)
await audioContext.resume()
```

### Audio Node Chain
```typescript
// Standard chain
source → gainNode → analyserNode → destination

// With effects
source → gainNode → biquadFilter → analyserNode → destination
```

## Key Audio Components

| Component | Purpose | File |
|-----------|---------|------|
| AudioContext | Core audio engine | `audioContext.ts` |
| AudioPlayer | Main player component | `AudioPlayer.tsx` |
| AudioPlayerContext | Player state | `AudioPlayerContext.tsx` |
| CachedAudioService | Offline cache | `cached-audio-service.ts` |

## Common Audio Operations

### Play/Pause
```typescript
const audio = new Audio(url)
await audio.play()
audio.pause()
```

### Volume Control
```typescript
gainNode.gain.setValueAtTime(volume, audioContext.currentTime)
```

### Playback Rate
```typescript
audio.playbackRate = 1.5 // 1.5x speed
```

### Seek
```typescript
audio.currentTime = 30 // Seek to 30 seconds
```

### Visualizer (Analyser)
```typescript
const analyser = audioContext.createAnalyser()
analyser.fftSize = 256
const dataArray = new Uint8Array(analyser.frequencyBinCount)
analyser.getByteFrequencyData(dataArray)
```

## Audio Format Support

| Format | Support | Notes |
|--------|---------|-------|
| MP3 | ✅ Full | Most common |
| WAV | ✅ Full | Uncompressed |
| OGG | ✅ Full | Open format |
| FLAC | ⚠️ Partial | Browser dependent |
| AAC | ✅ Full | Apple ecosystem |
| M4A | ✅ Full | Apple format |

## IndexedDB Storage

Audio files stored in IndexedDB:
```typescript
// Save audio
await localAudioStore.saveAudioFile(audioFile, blob)

// Retrieve audio
const cached = await localAudioStore.getAudioFile(id)
```

## Metadata Extraction

Using jsmediatags:
```typescript
import jsmediatags from 'jsmediatags'

jsmediatags.read(file, {
  onSuccess: (tag) => {
    const { title, artist, album, picture } = tag.tags
  }
})
```

## Offline Playback

```typescript
// Check if cached
const isCached = await cacheService.isAudioCached(audioId)

// Get cached URL
const cachedUrl = await cacheService.getCachedAudioUrl(audioId)
```

## Common Issues

### CORB/CORS Errors
```typescript
// Always set crossOrigin
const audio = new Audio()
audio.crossOrigin = 'anonymous'
```

### AudioContext Suspended
```typescript
// Resume on user interaction
document.addEventListener('click', () => {
  audioContext.resume()
}, { once: true })
```

### Memory Leaks
```typescript
// Cleanup on unmount
useEffect(() => {
  return () => {
    audio.pause()
    audio.src = ''
    audioContext.close()
  }
}, [])
```

## Examples

```bash
# Help with audio player
/audio player

# Debug CORS issues
/audio cors

# Implement visualizer
/audio visualizer

# Optimize audio loading
/audio optimize
```

## Resources

- [Web Audio API MDN](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API)
- [AudioContext Reference](https://developer.mozilla.org/en-US/docs/Web/API/AudioContext)
- [IndexedDB Audio Storage](./src/services/local/)
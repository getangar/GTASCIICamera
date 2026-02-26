# GT ASCII Camera

Real-time ASCII art camera for iOS and iPadOS, powered by Metal compute shaders.

## Overview

GT ASCII Camera transforms your device's live camera feed into ASCII art in real time. Every frame passes through a Metal compute pipeline that:

1. Divides the camera texture into a grid of cells (one per ASCII character)
2. Computes average luminance and color per cell via GPU sampling
3. Maps luminance to a glyph from a pre-rendered atlas texture
4. Composites the glyph onto the output — optionally tinted with the cell's color

The result is a fluid, GPU-accelerated ASCII art viewfinder at 30 fps.

## Requirements

- **Xcode**: 16.0+ (tested with 16.2)
- **iOS Deployment Target**: 17.0 (compatible with iOS 17, 18, and 19)
- **Swift**: 6.0 with strict concurrency
- **Device**: Requires Metal GPU (all devices since iPhone 5s / iPad Air)

## Architecture

```
GTASCIICamera/
├── GTASCIICameraApp.swift          # @main entry point
├── Info.plist                       # Privacy descriptions, capabilities
│
├── Models/
│   ├── ASCIIPalette.swift          # Character palette definitions
│   ├── CaptureMode.swift           # Photo/Video mode enum
│   └── RenderingConfig.swift       # Metal uniform structs
│
├── Views/
│   ├── ContentView.swift           # Root view (permission gate)
│   ├── CameraView.swift            # Main camera UI (iOS Camera-like)
│   ├── SettingsView.swift          # Configuration sheet
│   ├── PermissionView.swift        # Camera permission request
│   └── MetalASCIIView.swift        # UIViewRepresentable ↔ MTKView bridge
│
├── ViewModels/
│   └── SettingsManager.swift       # @AppStorage-backed preferences
│
├── Services/
│   └── CameraManager.swift         # AVFoundation capture + recording
│
├── Metal/
│   ├── ASCIIMetalRenderer.swift    # Rendering pipeline orchestrator
│   └── ASCIIShaders.metal          # GPU compute kernels
│
├── Localization/
│   ├── en.lproj/                   # English
│   ├── it.lproj/                   # Italiano
│   ├── de.lproj/                   # Deutsch
│   └── fr.lproj/                   # Français
│
└── Assets.xcassets/                 # App icon, accent color
```

## Rendering Pipeline

```
Camera (AVCaptureSession, 1080p BGRA)
    │
    ▼
CVPixelBuffer → CVMetalTextureCache → MTLTexture (source)
    │
    ▼
Metal Compute Shader (asciiArtKernel / asciiArtMonochromeKernel)
    ├── Input: source texture + glyph atlas + uniforms
    ├── Per-pixel: determine cell → sample region → map luminance → atlas lookup
    └── Output: MTLTexture (rendered ASCII frame)
    │
    ├──▶ MTKView drawable (live preview via blit)
    ├──▶ UIImage (photo capture via CPU readback)
    └──▶ CVPixelBuffer → AVAssetWriter (video recording)
```

### Glyph Atlas

Characters are pre-rendered using Core Text (Menlo Bold) into a horizontal strip texture.
Each glyph occupies a fixed cell; the shader indexes into the atlas by glyph index and
local UV coordinates within the cell.

### Character Palettes

| Palette | Characters | Levels | Style |
|---------|-----------|--------|-------|
| Classic | ` .:-=+*#%@` | 10 | Traditional ASCII art ramp |
| Unicode | ` ░▒▓█` | 5 | Dense block-element look |

## Features

- **Real-time preview** at 30 fps via Metal compute
- **Photo capture** — saves ASCII art snapshot to Photos
- **Video recording** — records rendered ASCII art as H.264 MP4 with AAC audio
- **Two palettes** — classic ASCII ramp and Unicode block elements
- **Colored/Monochrome modes** — tinted characters or classic green terminal
- **Adjustable resolution** — 40 to 200 columns
- **Share sheet** — standard iOS sharing for photos and videos
- **4 languages** — English, Italian, German, French
- **Front/back camera** with flip animation
- **iOS Camera-like UI** — familiar shutter, mode selector, gallery thumbnail

## Setup in Xcode

1. Open `GTASCIICamera.xcodeproj` in Xcode 16+
2. Set your **Development Team** in Signing & Capabilities
3. Select a physical device (Metal requires hardware GPU)
4. Build and run

> **Note**: The Metal shader library is compiled automatically by Xcode from `ASCIIShaders.metal`.
> The `makeDefaultLibrary()` call in `ASCIIMetalRenderer` loads it at runtime.

## Things to Complete in Xcode

- [ ] Add your Development Team ID
- [ ] Create/import an app icon (1024×1024 PNG) into `AppIcon.appiconset`
- [ ] Test on physical device (Metal not available in Simulator)
- [ ] Adjust bundle identifier if needed
- [ ] Consider adding `@Sendable` annotations if Swift 6 strict concurrency raises warnings
- [ ] Optional: Add haptic patterns for video start/stop via `CoreHaptics`

## License

© 2025 Gennaro Tocco. All rights reserved.

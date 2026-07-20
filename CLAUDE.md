# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

GT ASCII Camera is an iOS/iPadOS app (Swift 6, strict concurrency) that renders a real-time ASCII-art camera feed via a Metal compute pipeline: `AVCaptureSession` → `CVPixelBuffer`/`CVMetalTextureCache` → Metal kernels (`ASCIIShaders.metal`) → `MTKView` preview / `UIImage` photo / `AVAssetWriter` video. See README.md for the full pipeline and glyph-atlas details.

## Build & run

```
xcodebuild -project GTASCIICamera.xcodeproj -scheme GTASCIICamera -configuration Debug build
```

- No SPM/CocoaPods/Carthage — pure Xcode project, single target, single scheme.
- **Must run on a physical device** — the Simulator does not support the Metal pipeline this app relies on.
- No test target exists in the project yet.

## Code conventions

- SwiftUI only for UI; UIKit types are used only for bridging (`UIViewRepresentable` for `MTKView`, `UIImage`, `UIImpactFeedbackGenerator`).
- Architecture: MVVM-ish `final class ... ObservableObject` "manager" services (`CameraManager`, `SettingsManager`, `PurchaseManager`) injected via `@EnvironmentObject`; `@AppStorage` for persisted settings, `@Published` for reactive state.
- Swift 6 strict concurrency: managers are mostly `@MainActor`-isolated; `nonisolated(unsafe)` is used for AVFoundation/Metal objects that must cross actors (see `CameraManager.swift`) — follow this existing pattern rather than introducing new concurrency approaches.
- Use `// MARK: - Section Name` to group properties/methods, matching existing files.
- Debug logging: `#if DEBUG print("[TAG] message") #endif`, e.g. `[IAP]` in `PurchaseManager.swift`.
- 4-space indentation, no tabs.

## Version / build number bumps

`CURRENT_PROJECT_VERSION` (build) and `MARKETING_VERSION` (marketing version) live in `GTASCIICamera.xcodeproj/project.pbxproj`, each duplicated 4x (Debug/Release × base/`[sdk=*]` variant). All 4 occurrences of a value must be updated together or the build breaks inconsistently — git history has several commits fixing missed spots. Use the `/bump-build` skill to bump the build number correctly.

## StoreKit / in-app purchases

`PurchaseManager.swift` uses StoreKit 2 with a single hardcoded product ID: `GTASCIICameraPurchase`. The local StoreKit config file `GTASCIICamera/GT ASCII Camera.storekit` currently has **no products defined**, so it cannot be used as-is for local StoreKit Testing — a product with ID `GTASCIICameraPurchase` needs to be added to that file (or tested via App Store Connect sandbox) before IAP can be exercised locally.

## Git workflow

Work happens on `develop`, merged into `main` via GitHub PRs (no per-feature branches). Commit messages are short, plain-English, sentence case (e.g. "Fixing an issue with the in-app purchases") — no Conventional Commits prefixes or ticket numbers.

---
name: bump-build
description: Bump the app's build number (CURRENT_PROJECT_VERSION) in GTASCIICamera.xcodeproj/project.pbxproj. Use when the user asks to bump/increment the build number before a TestFlight upload or release.
disable-model-invocation: true
---

Bump the build number in `GTASCIICamera.xcodeproj/project.pbxproj`.

## Steps

1. Read the file and find the **target-level** `XCBuildConfiguration` blocks (the ones that also set `PRODUCT_BUNDLE_IDENTIFIER` — currently the blocks named `Debug` / `Release` following IDs `F10020` / `F10021`, distinct from the project-level blocks `F10010` / `F10011`). Only these target-level blocks matter — Xcode's target settings override the project-level ones, and the project-level `CURRENT_PROJECT_VERSION[sdk=*]` is a stale, effectively-unused value; leave it untouched.
2. In each of the two target-level blocks, confirm both lines are present and share the same current value:
   ```
   CURRENT_PROJECT_VERSION = <N>;
   "CURRENT_PROJECT_VERSION[sdk=*]" = <N>;
   ```
3. Determine the new value:
   - If `$ARGUMENTS` gives an explicit number, use it.
   - Otherwise, auto-increment: new value = current value + 1.
4. Update all 4 occurrences (both keys, in both the Debug and Release target-level blocks) to the new value using Edit — do not touch `MARKETING_VERSION` or the project-level blocks.
5. Report the old and new build number to the user. Do not commit — leave the change staged for the user to review.

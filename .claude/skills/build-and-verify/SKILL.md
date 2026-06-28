---
name: build-and-verify
description: Regenerate the Xcode project and build Gist to confirm changes compile before committing or releasing. Use after making code changes, before any commit, or when asked to "build", "make sure it compiles", or "verify the build".
---

# Build & Verify Gist

Confirm the project compiles cleanly. Run this before every commit and before a release.

## Steps

1. **Regenerate the Xcode project** (project.yml is the source of truth; the .xcodeproj is generated):
   ```bash
   xcodegen generate
   ```

2. **Build** with the same scheme CI uses:
   ```bash
   xcodebuild -project Gist.xcodeproj \
     -scheme Gist \
     -destination 'platform=macOS' \
     build
   ```

3. **(Optional) Run tests** when the change touches logic worth covering:
   ```bash
   xcodebuild -project Gist.xcodeproj \
     -scheme Gist \
     -destination 'platform=macOS' \
     test
   ```

## Reporting
- If the build fails, surface the actual `xcodebuild` error output — do not summarize it away or claim success.
- Report plainly: built clean, or failed with <error>. Don't hedge.

## Notes
- Local Xcode may be newer than CI's Xcode 16.4 (Swift 6.1, macOS 15 SDK). A clean local build does NOT guarantee the CI/Release build passes — note this when it matters for a release.
- Build before commit is a standing project rule; never commit code changes without running this first.

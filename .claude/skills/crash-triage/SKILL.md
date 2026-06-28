---
name: crash-triage
description: Diagnose a Gist crash by reading the actual crash report before proposing any fix. Use when the user reports a crash, a hang, an unexpected quit, or asks to investigate a Gist-*.ips diagnostic report.
---

# Crash Triage for Gist

ALWAYS read the real crash report before guessing a fix. Blind fixes have cost multiple wasted release cycles.

## Steps

1. **Find the latest crash report:**
   ```bash
   ls -t ~/Library/Logs/DiagnosticReports/Gist-*.ips 2>/dev/null | head -5
   ```
   If the user pointed at a specific file or session, use that one.

2. **Read the report.** `.ips` files are JSON (a one-line header object followed by a JSON body). Read it and extract:
   - **Exception type / signal** (e.g. `EXC_BAD_ACCESS`, `EXC_CRASH (SIGABRT)`).
   - **Termination reason** and any `termination` description.
   - **The crashing thread** — find `triggered: true` under `threads`, and read its backtrace frames (resolve `imageIndex` against `usedImages` for symbol context).
   - App **version / build** from the header — confirm it matches the build you're debugging.

3. **Identify the failing code.** Map the top app-frames in the crashing thread to source under `Gist/`. Pay special attention to the project's known hazard areas:
   - Audio IO threads touching `@MainActor`/actor `self` (forbidden — see Thread Safety Rules in `AGENTS.md`).
   - Unprotected shared mutable state (must be behind NSLock: `AudioSharedState`, `AudioFileWriter`, `StreamingTranscriber`).
   - Permission-completion isolation, mic-drop handling, system-audio tap recovery.

4. **Diagnose, then propose a fix** grounded in the actual backtrace — not a plausible-sounding guess. State which frame/line implicates which code.

5. **Verify** with the `build-and-verify` skill before committing. If the crash relates to a real recorded session/artifact the user named, decode that artifact's actual properties to confirm the fix addresses it.

## Notes
- If no `.ips` exists, ask the user to reproduce and point you at the file — do not fabricate a cause.
- Report findings faithfully: what the crash actually was, which thread, which code.

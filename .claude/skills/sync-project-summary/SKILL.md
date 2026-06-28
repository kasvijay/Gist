---
name: sync-project-summary
description: Update docs/project-summary.md so it reflects current features, capabilities, architecture, and version. Use whenever a feature, capability, model, or architectural detail changes, or when asked to "update the project summary" or "sync the docs".
---

# Sync project-summary.md

`docs/project-summary.md` is the canonical, human-readable description of what Gist does. Per project convention it MUST be updated whenever features or capabilities change.

## Steps

1. **Read** `docs/project-summary.md` in full to understand its current structure (sections: What Gist Does, Core Capabilities, Architecture, file layout, etc.).

2. **Identify the delta.** Compare against what actually changed in this work — new/removed capabilities, changed models or defaults, new services or views, altered audio/thread behavior. Cross-check against `AGENTS.md` architecture and the actual source under `Gist/`.

3. **Update the relevant sections only.** Match the existing tone and depth (technical detail is welcome here, unlike the user-facing UI). Keep bullet structure consistent.

4. **Update the metadata header** when relevant:
   - `**Version:**` should match `MARKETING_VERSION` in `project.yml`.
   - Platform / language / bundle ID if they changed.

5. **Verify accuracy against source** — don't describe behavior you haven't confirmed in the code. For dependency behavior (WhisperKit model formats, FluidAudio output, HuggingFace cache paths), read the dependency source rather than guessing.

## Notes
- Keep user-facing language plain where the doc addresses users; keep deep technical notes in their dedicated sections.
- This doc is committed — include it in the same commit as the feature change it documents.

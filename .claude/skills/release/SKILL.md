---
name: release
description: Cut a Gist release — bump MARKETING_VERSION in project.yml, commit, push, tag vX.Y.Z, push the tag (triggers the GitHub Actions DMG build), then update the SHA256 in the kasvijay/homebrew-gist tap. Use when asked to "release", "ship", "cut a version", or "publish a new Gist build".
---

# Release Gist

End-to-end release procedure. Follow in order; do not skip the build verification.

## Preconditions
- Working tree clean on `main` (or confirm with the user if not).
- Run the `build-and-verify` skill first. Do not release a build that doesn't compile.
- Decide the new version with the user (semver). Current version lives in `project.yml` → `MARKETING_VERSION`.

## Steps

1. **Bump the version.** Edit `project.yml`, set `MARKETING_VERSION` to the new `X.Y.Z`.
   Also update the `**Version:**` header in `docs/project-summary.md` to match (run the `sync-project-summary` skill if features changed in this release).

2. **Regenerate the project** so the version propagates:
   ```bash
   xcodegen generate
   ```

3. **Commit and push** to `main`:
   ```bash
   git add project.yml docs/project-summary.md
   git commit -m "Release vX.Y.Z"
   git push
   ```
   Do NOT add a Co-Authored-By line (project + user rule).

4. **Tag and push the tag** — this triggers `.github/workflows/release.yml`, which builds the DMG and creates the GitHub Release:
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

5. **Wait for the GitHub Action to finish**, then get the DMG SHA256. The workflow prints it in the release notes (`**SHA256:**`), or compute it from the downloaded DMG:
   ```bash
   shasum -a 256 Gist-X.Y.Z.dmg | cut -d ' ' -f 1
   ```

6. **Update the Homebrew tap.** In the `kasvijay/homebrew-gist` repo, update the formula's `url` (new version) and `sha256` to the value from step 5, then commit and push that repo.

## Notes
- CI builds with Xcode 16.4 (Swift 6.1). A local Release build does NOT validate the CI build — rely on the Action.
- Never embed signing/Apple credentials in this skill or any committed file.
- After release, confirm `brew upgrade --cask gist` (or the tap's install path) picks up the new version.

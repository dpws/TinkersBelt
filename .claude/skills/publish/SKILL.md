---
name: publish
description: Ship a stable release of the dpws_tools addon as the Claude artifact download page - checks, version bump, changelog, git tag, zip, install instructions, always the same artifact URL. Use when the user says "publish", "release", "ship the addon" or /publish.
---

# Publish a dpws_tools release

Ships the addon as **one artifact that never changes its URL**: a download page with the zip, install
instructions and the changelog. Each release republishes that same artifact.

Not the same as `publish.ps1`: that only copies the addon into the local WoW folder for testing.

LuaJIT: `"$LOCALAPPDATA/Programs/LuaJIT/bin/luajit.exe"` (not on PATH).

## 1. Stable or stop

Stop and tell the user what failed if any of these fail; never release around a failure.

- `git status --porcelain` is empty (uncommitted work → ask whether to commit it first).
- Every `*.lua` in the repo root passes `luajit -bl <file>`.
- Every `tests/*.lua` passes (`luajit tests/x.lua`, last line `N passed`, exit 0).
- Branch: releases come from `main`. On another branch, ask the user whether to merge it into `main`
  first (don't merge on your own).
- Something to release: `git log <last tag>..HEAD` is not empty (no tags yet → whole history).

## 2. Version

Current version: `## Version:` line in `dpws_tools.toc`. Last release: `git describe --tags --abbrev=0`
(none yet → this is the first release; ship the toc version as-is if no tag uses it).

Bump (semver, pre-1.0 rules) from the commits since the last tag:
- any new feature (`feat`, or a commit that adds something the player sees) → minor: 0.1.3 → 0.2.0
- only fixes / polish → patch: 0.2.0 → 0.2.1
- the user named a version → use it.

Write the new version into the `## Version:` line.

## 3. Changelog

`CHANGELOG.md` in the repo root, newest first. Create it with a `# Changelog` heading if missing.
Add a section:

```markdown
## 0.2.0 - 2026-11-17

### New
- Panels snap to a grid while you move them (Unlock panels), with grid size and on/off switches.

### Fixed
- Slice and Dice bar now counts down in combat.
```

Write it for the player, from `git log <last tag>..HEAD`: what they'll notice in game, one line each,
no file names or internals; merge commits that touch one feature into one line; drop test/docs/refactor
commits. Sections: New, Changed, Fixed (omit empty ones). First release: a short "what's in it" list of
the tools instead of the full history.

## 4. Commit and tag

```bash
git add dpws_tools.toc CHANGELOG.md
git commit -m "release: v<version>"   # plus the session's Co-Authored-By line
git tag v<version>
```

Don't push unless the user asks.

## 5. Zip

```bash
powershell -ExecutionPolicy Bypass -File .claude/skills/publish/build-zip.ps1 -Version <version> -OutDir <scratchpad>/release
```

Prints the zip path. The zip holds a single `dpws_tools` folder (no tests, docs, scripts).

## 6. Artifact page (same URL every time)

The URL lives in `.claude/skills/publish/artifact-url.txt`.

- **File exists:** read the artifact (`Artifact` action `read` with that url) and republish to that url.
- **Missing (first release):** publish a new artifact, then write its URL into that file and commit it
  (`chore: release page url`).
- Never create a second artifact for a later release. If the saved URL is gone, ask the user before
  making a new one.

Page source: `docs/release/index.html` (kept in git so each release edits the last one). Load the
`artifact-design` skill before writing it the first time. Contents:

1. Title "dpws tools", the version, release date, one-line description (from the toc `## Notes`),
   target client: WoW Forever (`## Interface` from the toc).
2. **Download** button → the zip, published alongside the page through `files`:
   `{"dpws_tools-<version>.zip": "<zip path>"}` (contentType `application/zip`), and `null` for the
   previous release's zip path so old zips don't pile up.
3. **How to install**:
   1. Close the game (or be ready to `/reload`).
   2. Download the zip.
   3. If an older dpws_tools is installed, delete the `Interface\AddOns\dpws_tools` folder first.
   4. Extract the zip into `<WoW folder>\_forever_\Interface\AddOns\` so you get
      `Interface\AddOns\dpws_tools\dpws_tools.toc` (not a doubled `dpws_tools\dpws_tools\`).
   5. Start the game, enable "dpws tools" in the AddOns list on the character screen
      ("Load out of date AddOns" if it shows as out of date).
   6. In game: `/dpws` opens the settings. Saved settings carry over between versions.
4. **Changelog**: the whole `CHANGELOG.md`, rendered as HTML, newest first.

Publish with `icon: "download"` on the first publish only, and a one-sentence `description`.

## 7. Report

One short message: the version, the artifact link, the tag, and anything skipped (e.g. not pushed).

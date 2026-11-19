---
name: publish
description: Ship a stable release of the Tinker's Belt addon (repo dpws_tools) as the Claude artifact download page - checks, version bump, changelog, git tag, zip, install instructions, always the same artifact URL. Use when the user says "publish", "release", "ship the addon" or /publish.
---

# Publish a Tinker's Belt release

Ships the addon as a **GitHub release** (github.com/dpws/TinkersBelt, public: anyone can download, no
account) plus **one artifact that never changes its URL**: a page with the download link, install
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

Current version: `## Version:` line in `TinkersBelt.toc`. Last release: `git describe --tags --abbrev=0`
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
git add TinkersBelt.toc CHANGELOG.md docs/release/index.html
git commit -m "release: v<version>"   # plus the session's Co-Authored-By line
git tag v<version>

git push origin main --tags
```

The user agreed (2026-11-19) that releases are pushed to the public repo `origin` (dpws/TinkersBelt).
Push only `main` and tags; other branches stay local.

## 5. Zip

```bash
powershell -ExecutionPolicy Bypass -File .claude/skills/publish/build-zip.ps1 -Version <version> -OutDir <scratchpad>/release
```

Prints the zip path. The zip holds a single `TinkersBelt` folder (no tests, docs, scripts).

Then the GitHub release, with this version's changelog section as notes:

```bash
gh release create v<version> <zip> --repo dpws/TinkersBelt --title "Tinker's Belt <version>" --notes-file <notes.md>
```

Check the asset downloads without a login: `curl -sIL <download url> | grep -i "^HTTP"` ends in 200.

## 6. Artifact page (same URL every time)

The URL lives in `.claude/skills/publish/artifact-url.txt`.

- **File exists:** read the artifact (`Artifact` action `read` with that url) and republish to that url.
- **Missing (first release):** publish a new artifact, then write its URL into that file and commit it
  (`chore: release page url`).
- Never create a second artifact for a later release. If the saved URL is gone, ask the user before
  making a new one.

Page source: `docs/release/index.html` (kept in git so each release edits the last one). Load the
`artifact-design` skill before writing it the first time. Contents:

1. Title "Tinker's Belt", the version, release date, one-line description (from the toc `## Notes`),
   target client: WoW Forever (`## Interface` from the toc).
2. **Download** link to the GitHub release asset:
   `https://github.com/dpws/TinkersBelt/releases/download/v<version>/TinkersBelt-<version>.zip`
   (`<a class="dl" ... target="_blank" rel="noopener">`), plus an "All versions" link to the releases
   page. No `downloads` capability: that only works for viewers signed in to Claude. On a new release,
   change the link, the version, date and size in the page.
3. **How to install**:
   1. Close the game (a new addon folder is only picked up on a restart; updates need just `/reload`).
   2. Download the zip.
   3. If an older version is installed, delete the `Interface\AddOns\TinkersBelt` folder first.
   4. Extract the zip into `<WoW folder>\_forever_\Interface\AddOns\` so you get
      `Interface\AddOns\TinkersBelt\TinkersBelt.toc` (not a doubled `TinkersBelt\TinkersBelt\`).
   5. Start the game, enable "Tinker's Belt" in the AddOns list on the character screen
      ("Load out of date AddOns" if it shows as out of date).
   6. In game: `/tb` opens the settings. Saved settings carry over between versions.
4. **Changelog**: the whole `CHANGELOG.md`, rendered as HTML, newest first.

Publish with `icon: "download"` on the first publish only, and a one-sentence `description`.

## 7. Report

One short message: the version, the artifact link, the tag, and anything skipped (e.g. not pushed).

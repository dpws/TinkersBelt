# dpws_tools — Bar Switching (design)

Date: 2026-11-12 · Status: approved in chat, pending spec review

## Goal

In WoW: Forever, only the main action bar changes page on stealth / shapeshift.
Let the player choose, per stance state, which other bars also switch and to which page.

## Target client

- WoW: Forever, `D:\Games\World of Warcraft\_forever_`, client 1.60.1, `## Interface: 16001`.
- Retail engine (Edit Mode, MultiBar5–7, secure state drivers), Classic-era content.

## Behavior

- **State source:** the bonus bar offset, the same signal the main bar uses (`[bonusbar:N]`, N = 1..4).
  Meaning per class (labels only, logic is generic):
  - Rogue: 1 Stealth
  - Druid: 1 Cat, 2 Prowl (if the client uses it), 3 Bear, 4 Moonkin/Tree
  - Warrior: 1 Battle, 2 Defensive, 3 Berserker
  - Priest: 1 Shadowform
  - Other classes: no states, the tab says so.
- **Mapping:** for each state, each non-main bar (Bar 2 … Bar 8) maps to `none` or a page (1–15, excluding the bar's own page and 7–12).
  The page is "borrowed" from another bar (typically one hidden in Edit Mode); the player fills it by dragging spells while it is showing.
- **Switch:** a single `SecureHandlerStateTemplate` frame with state driver
  `[bonusbar:1] 1; [bonusbar:2] 2; [bonusbar:3] 3; [bonusbar:4] 4; 0`.
  `_onstate-bar` sets each mapped button's `action` attribute to `(page-1)*12 + i`, or back to the bar's own slot in state 0.
  Works in combat, no taint of Blizzard code.
- **Out of combat only:** applying a changed mapping (rebuilding the snippet data). Changes made in combat are queued until `PLAYER_REGEN_ENABLED`.

## Bars and pages (180-slot layout)

| Bar | Frame prefix | Own page |
|-----|--------------|----------|
| 1 (main) | ActionButton | 1 (+ 7–10 stance) |
| 2 | MultiBarBottomLeftButton | 6 |
| 3 | MultiBarBottomRightButton | 5 |
| 4 | MultiBarRightButton | 3 |
| 5 | MultiBarLeftButton | 4 |
| 6 | MultiBar5Button | 13 |
| 7 | MultiBar6Button | 14 |
| 8 | MultiBar7Button | 15 |

Verify page numbers in-game (`/dump MultiBarBottomLeftButton1.action`) during implementation.

## Data

`SavedVariablesPerCharacter: DpwsToolsCharDB`

```lua
DpwsToolsCharDB = {
  barSwitch = { [state] = { [barIndex] = page } },  -- empty by default = no change
  window = { point, x, y },
}
```

## Config UI

- `/dpws` toggles a standalone, draggable window (`ButtonFrameTemplate`-style), position saved.
- Left: tab list ("Bar Switching"; room for future tools).
- Right: one section per class state; per bar a dropdown `none / Bar N (page P)`.
- Warning text when the chosen page belongs to a bar currently shown.
- Also registered in Esc → Options → AddOns (a page with a button that opens the window).

## Files

- `dpws_tools.toc`
- `Core.lua` — DB init, `/dpws`, events, combat queue
- `BarSwitch.lua` — secure driver, pure `SlotFor(page, i)` helper with load-time assert self-check
- `Config.lua` — the window
- `publish.ps1` — copies the addon into the game folder (see below)

## Publish command

`./publish.ps1` (run from the repo root) mirrors the addon files (`*.toc`, `*.lua`, media) to
`D:\Games\World of Warcraft\_forever_\Interface\AddOns\dpws_tools` using `robocopy /MIR`, excluding `docs`, `.git`, `publish.ps1`.
The target folder is ours alone, so mirroring (deleting stale files there) is safe. Then `/reload` in game.

## Testing

- Assert self-check of slot math on load (prints error to chat if it fails).
- Manual in-game: Rogue, map Bar 2 → page 14 for Stealth; stealth in and out of combat, buttons swap and swap back; `/reload` keeps settings.
- Risk to verify first: Blizzard multibar buttons refresh when their `action` attribute changes on this client.

## Out of scope

Profiles, per-spec settings, custom (non-bonusbar) conditions, button art changes.

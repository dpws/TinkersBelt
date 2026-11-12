# Bar Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player choose which non-main action bars switch page (and to which page) on stealth / shapeshift / stance, configured in a `/dpws` window.

**Architecture:** One `SecureHandlerStateTemplate` frame driven by `[bonusbar:N]` rewrites the `action` attribute of mapped Blizzard bar buttons inside a secure snippet (combat-safe). Mappings live in a per-character SavedVariable and are pushed to the handler as attributes out of combat. A standalone Blizzard-styled window edits the mappings.

**Tech Stack:** WoW: Forever client (Retail engine, `## Interface: 16001`), Lua 5.1 FrameXML API, PowerShell + robocopy for publishing. No libraries.

**Spec:** `docs/superpowers/specs/2026-11-12-bar-switch-design.md`

## Global Constraints

- TOC: `## Interface: 16001`, `## SavedVariablesPerCharacter: DpwsToolsCharDB`.
- Game folder: `D:\Games\World of Warcraft\_forever_\Interface\AddOns\dpws_tools`.
- State driver: `[bonusbar:1] 1; [bonusbar:2] 2; [bonusbar:3] 3; [bonusbar:4] 4; 0`.
- Slot formula: `(page-1)*12 + i`, i = 1..12.
- Bars: 2 MultiBarBottomLeftButton, 3 MultiBarBottomRightButton, 4 MultiBarRightButton, 5 MultiBarLeftButton, 6 MultiBar5Button, 7 MultiBar6Button, 8 MultiBar7Button (own pages per spec table, verified in Task 1).
- Selectable pages: 1–15 excluding 7–12 and the bar's own page.
- Never call protected APIs / `SetAttribute` on secure frames in combat from insecure code; queue to `PLAYER_REGEN_ENABLED`.
- Default DB is empty → addon changes nothing until configured.
- No automated Lua runner on this machine: tests = load-time asserts (print `dpws_tools: self-check FAILED ...` to chat) + listed manual in-game checks.

## Review Focus

1. Mapping changed while in combat → must not error/taint; applies on leaving combat (Task 4 manual check).
2. Leaving stealth/form → every mapped button returns to its exact original slot, including after `/reload` while stealthed (Task 3 check).
3. Class without bonus bars (mage, hunter…) → window shows "No stance states for this class", no driver errors (Task 5 check).
4. Bar hidden in Edit Mode used as source page → still switches correctly; mapped bar hidden → no error (Task 3 check).
5. `publish.ps1` run when game folder missing → clear error, nothing deleted elsewhere (Task 2 check).

---

### Task 1: Spike — confirm button attribute + own pages (throwaway)

**Files:** none committed.

- [ ] **Step 1:** In game, out of combat: `/dump MultiBarBottomLeftButton1:GetAttribute("action"), MultiBarBottomLeftButton1.action` and the same for buttons of bars 3–8. Record own pages (`ceil(action/12)`); fix the spec table if they differ.
- [ ] **Step 2:** `/run MultiBarBottomLeftButton1:SetAttribute("action", 157)` → icon must change to slot 157's spell. If it does NOT, try the bar's `actionpage` attribute (`MultiBarBottomLeft:SetAttribute("actionpage", 14)`) and record which works.
- [ ] **Step 3:** Write the finding (attribute name, own pages) into the spec's "Bars and pages" section and commit: `docs: record verified bar pages`. If neither attribute works, STOP and report — design needs revisiting.

### Task 2: Skeleton addon + publish script

**Files:**
- Create: `dpws_tools.toc`, `Core.lua`, `BarSwitch.lua` (empty), `Config.lua` (empty), `publish.ps1`

**Interfaces:**
- Produces: `ns` (from `local ADDON, ns = ...`) also exposed as global `DpwsTools = ns` for `/run` debugging, `ns.db` (= `DpwsToolsCharDB`), `ns.RunOutOfCombat(fn)`, `ns.OnLogin` callbacks list `ns.loginHooks` (each `function()` called on `PLAYER_LOGIN`), slash `/dpws` → `ns.ToggleWindow()` (defined in Task 5; until then print "dpws_tools loaded").

- [ ] **Step 1:** `dpws_tools.toc`: Interface 16001, Title `dpws tools`, SavedVariablesPerCharacter, files in order `Core.lua`, `BarSwitch.lua`, `Config.lua` (create the latter two as empty files now).
- [ ] **Step 2:** `Core.lua`: on `ADDON_LOADED` init `DpwsToolsCharDB = DpwsToolsCharDB or {}` with `barSwitch = {}`, `window = {}` defaults; `ns.RunOutOfCombat(fn)` runs now if `not InCombatLockdown()` else queues and flushes on `PLAYER_REGEN_ENABLED`; register `SLASH_DPWS1 = "/dpws"`.
- [ ] **Step 3:** `publish.ps1`: target as in Global Constraints; if `D:\Games\World of Warcraft\_forever_\Interface\AddOns` doesn't exist → `Write-Error` and `exit 1`. Else `robocopy $PSScriptRoot $target /MIR /XD docs .git .claude /XF publish.ps1 .gitignore`; robocopy exit codes < 8 = success, ≥ 8 → exit 1.
- [ ] **Step 4:** Verify: `./publish.ps1` → folder exists in game dir with toc + 3 lua; in game addon list shows "dpws tools", `/dpws` prints loaded, no Lua errors (BugSack).
- [ ] **Step 5:** Verify failure path: temporarily set target base to `Z:\nope` → error, exit 1. Revert.
- [ ] **Step 6:** Commit `feat: addon skeleton, /dpws, publish script`.

### Task 3: Secure bar switch driver

**Files:** Modify `BarSwitch.lua`

**Interfaces:**
- Consumes: `ns.db`, `ns.RunOutOfCombat`, `ns.loginHooks`.
- Produces:
  - `ns.BARS` = array of `{ index = 2..8, prefix = "MultiBarBottomLeftButton", name = "Bottom Left", page = 6 }` (pages from Task 1).
  - `ns.SlotFor(page, i) -> number`.
  - `ns.ValidPages(barIndex) -> {number...}` (1–15 minus 7–12 minus own page).
  - `ns.ApplyBarSwitch()` — pushes `ns.db.barSwitch` into handler attributes and re-runs current state; safe to call any time (uses `RunOutOfCombat`).

- [ ] **Step 1: Self-check (write first, fails until helpers exist):** at file end
  ```lua
  local ok = ns.SlotFor(14, 1) == 157 and ns.SlotFor(1, 12) == 12
    and not tContains(ns.ValidPages(2), 6) and not tContains(ns.ValidPages(2), 7)
    and tContains(ns.ValidPages(2), 14)
  if not ok then print("|cffff4040dpws_tools: self-check FAILED (BarSwitch)|r") end
  ```
- [ ] **Step 2:** Publish, `/reload` → FAILED message shows (helpers nil errors also acceptable as "fail").
- [ ] **Step 3:** Implement `ns.BARS`, `ns.SlotFor`, `ns.ValidPages`.
- [ ] **Step 4:** Implement handler (created on login): `CreateFrame("Frame", "DpwsBarSwitchHandler", UIParent, "SecureHandlerStateTemplate")`; `SetFrameRef("b<bar>_<i>", button)` for all 84 buttons; store each button's original slot as handler attribute `own-<bar>-<i>` (read once at login, out of combat). `ApplyBarSwitch` sets `map-<state>-<bar>` = page or nil for states 1–4. `_onstate-bar` snippet: for bar 2..8, i 1..12: `page = self:GetAttribute("map-"..newstate.."-"..bar)`; set button attribute (name from Task 1) to `(page-1)*12+i` or `own-<bar>-<i>`. `RegisterStateDriver(handler, "bar", <driver string>)`.
- [ ] **Step 5:** Publish, `/reload` → no FAILED message.
- [ ] **Step 6: Manual check (rogue):** `/run DpwsTools.db.barSwitch[1]={[2]=14}; DpwsTools.ApplyBarSwitch()`, then Stealth: Bottom Left shows Bar 7's spells; unstealth: originals. Repeat in combat (target dummy). `/reload` while stealthed → correct page after reload. Hide Bar 7 in Edit Mode → still works.
- [ ] **Step 7:** Commit `feat: secure bar switching on bonus bar states`.

### Task 4: Combat-queued apply

**Files:** Modify `Core.lua`, `BarSwitch.lua` (only if Task 3 didn't already route through `RunOutOfCombat`)

- [ ] **Step 1:** Ensure `ApplyBarSwitch` body is wrapped in `ns.RunOutOfCombat`.
- [ ] **Step 2: Manual check:** enter combat, `/run DpwsTools.db.barSwitch[1]={[3]=13}; DpwsTools.ApplyBarSwitch()` → no error/“blocked action”; leave combat → mapping active.
- [ ] **Step 3:** Commit `fix: queue bar switch changes until combat ends` (skip if no diff).

### Task 5: Config window

**Files:** Modify `Config.lua`

**Interfaces:**
- Consumes: `ns.BARS`, `ns.ValidPages`, `ns.ApplyBarSwitch`, `ns.db`.
- Produces: `ns.ToggleWindow()`; `ns.STATE_LABELS[classFile] = { [1]="Stealth", ... }` per spec (ROGUE, DRUID, WARRIOR, PRIEST).

- [ ] **Step 1:** Window: `CreateFrame("Frame","DpwsToolsWindow",UIParent,"ButtonFrameTemplate")`, title "dpws tools", movable via title drag, position saved in `ns.db.window`, `tinsert(UISpecialFrames, ...)` so Esc closes it. Left side tab button "Bar Switching".
- [ ] **Step 2:** Bar Switching page: for each state label of the player's class, a header + 7 rows (`bar.name` + dropdown). Dropdown via `WowStyle1DropdownTemplate` + `SetupMenu` (Retail-engine menu API) with radio entries `None` and `Bar N (page P)` from `ns.ValidPages`. On select: write `ns.db.barSwitch[state][bar] = page|nil`, call `ns.ApplyBarSwitch()`. If page belongs to a bar currently shown (`_G[prefix.."1"]:IsVisible()`), show orange warning text in the row. No class states → centered text "No stance states for this class". Scroll frame if rows overflow.
- [ ] **Step 3:** Settings entry: `Settings.RegisterCanvasLayoutCategory` with a panel containing one "Open dpws tools" button; `Settings.RegisterAddOnCategory`.
- [ ] **Step 4:** Hook `/dpws` to `ns.ToggleWindow`.
- [ ] **Step 5: Manual check:** rogue + druid + mage: window opens/closes with `/dpws` and Esc, drags and remembers position after `/reload`, dropdown changes take effect immediately (and after combat if changed in combat), warning shows for visible-bar pages, mage sees the no-states text, Options → AddOns entry opens window.
- [ ] **Step 6:** Commit `feat: /dpws config window for bar switching`.

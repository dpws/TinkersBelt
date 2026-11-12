# Poison Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rogue poison bar: two weapon buttons, right-click choose poison, left-click apply, timer/charges, glow + warnings (early, expiry, entering combat unpoisoned).

**Architecture:** `Poisons.lua` builds a movable bar of two `SecureActionButtonTemplate` buttons whose left-click runs a macro; an insecure OnUpdate (0.5s) reads `GetWeaponEnchantInfo`, feeds a pure state function `ns.PoisonStep`, and drives text, glow and warnings. Settings live in `DpwsToolsCharDB.poisons`; `Config.lua` gets tab switching and a Poisons page.

**Tech Stack:** WoW: Forever Lua 5.1 FrameXML API; LuaJIT for offline tests.

**Spec:** `docs/superpowers/specs/2026-11-12-poison-bar-design.md`

## Global Constraints

- Rogue only (`select(2, UnitClass("player")) == "ROGUE"`); module inert otherwise.
- Slots: Main Hand 16, Off Hand 17.
- Macro: `"/use item:<id>\n/use <slot>"` on `type1="macro"`, `macrotext1`.
- Attribute changes only via `ns.RunOutOfCombat`.
- Defaults: `enabled=true, warnMinutes=5 (1-15), sound=true`.
- Messages exactly: `"<Main Hand> poison: N min left"`, `"<Main Hand> poison expired!"`, `"No poison on <Main Hand / Off Hand>!"` (slot names `Main Hand`, `Off Hand`; combat message joins missing ones with `" / "`).
- Warnings: `RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)` + `PlaySound(SOUNDKIT.RAID_WARNING)` when `db.poisons.sound`.
- ASCII-only strings in Lua (WoW font lacks many glyphs).

## Review Focus

1. Reapplying a poison while one is still active → early-warning re-arms (test in Task 1).
2. Applying a poison that already has < N minutes (unlikely, but e.g. N=15 with short poisons) → no instant early warning (test in Task 1).
3. Weapon swapped / unequipped → button hides, no expiry warning spam (Task 2 manual).
4. Poison chosen in combat → applies after combat, no "action blocked" (Task 2 manual).
5. Chosen poison not in bags → button desaturated, menu still opens (Task 2 manual).

---

### Task 1: `ns.PoisonStep` (pure) + offline test

**Files:** Create `Poisons.lua` (only the function for now; add to TOC after `Config.lua`), `tests/poison_step.lua`.

**Interfaces:**
- Produces: `ns.PoisonStep(prev, hasEnchant, msLeft, warnMs) -> state, event`
  - `prev`/`state`: `{ applied = bool, early = bool, msLeft = number|nil }` (prev may be nil = fresh)
  - `event`: `nil | "early" | "expired"`
  - Rules: no enchant + prev.applied → `"expired"`; enchant + (not prev.applied or msLeft > prev.msLeft + 1000) → new application, `early = msLeft < warnMs`, no event; enchant + not prev.early + msLeft < warnMs → `"early"`.

- [ ] **Step 1: Write test** `tests/poison_step.lua`: loads `Poisons.lua` with `ns = {loginHooks={}}` stub (guard WoW-only code behind `if not CreateFrame then return end` at file top after the function). Cases (warnMs = 300000):
  - nil, false, 0 → event nil, applied false
  - none → applied 1800000 → event nil, applied true, early false
  - 360000 → 240000 → event "early"; → 180000 → event nil
  - → hasEnchant false → "expired"; again false → nil
  - applied at 1800000 after early fired, then 240000 → "early" again (re-armed)
  - fresh application at 120000 → event nil, early true; then 100000 → nil
  - reapply while active: 240000(early fired) → 1800000 → nil, early false
  Prints `poison_step: N passed`, `os.exit(1)` on first failure.
- [ ] **Step 2:** `luajit tests/poison_step.lua` → FAIL (PoisonStep nil).
- [ ] **Step 3:** Implement `ns.PoisonStep` in `Poisons.lua`.
- [ ] **Step 4:** `luajit tests/poison_step.lua` → `poison_step: 8 passed` (or however many cases).
- [ ] **Step 5:** Commit `feat: poison state logic with offline test`.

### Task 2: Poison bar in game

**Files:** Create `Poisons_Data.lua` (`ns.POISON_IDS` = spec list, before `Poisons.lua` in TOC); modify `Poisons.lua`, `Core.lua` (db default `poisons = { enabled = true, warnMinutes = 5, sound = true }`).

**Interfaces:**
- Consumes: `ns.PoisonStep`, `ns.RunOutOfCombat`, `ns.loginHooks`, `ns.db`.
- Produces: `ns.Poisons.Refresh()` (re-reads db: show/hide bar, rebuild macros); `ns.Poisons.SLOTS = { {slot=16, key="mh", name="Main Hand"}, {slot=17, key="oh", name="Off Hand"} }`.

- [ ] **Step 1:** Bar frame `DpwsPoisonBar` (UIParent, Shift+drag moves, pos saved with point+relPoint); two buttons `DpwsPoisonButtonMH/OH` (`SecureActionButtonTemplate`, 40x40, `RegisterForClicks("AnyUp")`), weapon icon `GetInventoryItemTexture("player", slot)`, small poison icon (BOTTOMRIGHT 16x16, `C_Item.GetItemIconByID` or `GetItemIcon`), time text (top, `GameFontNormalSmall`), charges text (bottom-left). Glow per spec (pulsing border).
- [ ] **Step 2:** Left-click macro set from `db.poisons[key]` via `RunOutOfCombat`; right-click `PostClick` (button == "RightButton") opens `MenuUtil.CreateContextMenu` listing `ns.POISON_IDS` with `GetItemCount(id) > 0` (icon via `|T<icon>:16|t`, name via `GetItemInfo(id)` fallback `"item "..id`, count), radio for current; empty → disabled entry `"No poisons in bags"`. Selection while in combat → chat `"dpws_tools: poison change applies after combat"`.
- [ ] **Step 3:** OnUpdate throttle 0.5s: `GetWeaponEnchantInfo()` → per slot `hasEnchant, msLeft, charges`; update texts (`>=60s` → `"%dm"` ceil, else `"%ds"`), glow when `not hasEnchant or msLeft < warnMs`, `ns.PoisonStep` events → warnings with exact messages. Hide button when slot empty (`GetInventoryItemID` nil) and reset its state to nil (no expiry warning on unequip). Desaturate when chosen poison count is 0 or none chosen.
- [ ] **Step 4:** `PLAYER_REGEN_DISABLED` → combat warning per spec. `UNIT_INVENTORY_CHANGED`/`BAG_UPDATE_DELAYED` → refresh icons/desaturation.
- [ ] **Step 5:** `luajit -bl` all files OK; `luajit tests/poison_step.lua` still passes; publish.
- [ ] **Step 6: Manual (rogue):** choose poison per weapon, apply in & out of combat, timer/charges update, glow under N, warnings once each, pull without poison → combat warning, unequip OH → OH button hides silently, choose poison in combat → applies after.
- [ ] **Step 7:** Commit `feat: rogue poison bar`.

### Task 3: Config tabs + Poisons page

**Files:** Modify `Config.lua`.

**Interfaces:** Consumes `ns.Poisons.Refresh`, `ns.db.poisons`.

- [ ] **Step 1:** Left tab list becomes data-driven: `{ "Bar Switching", builder }, { "Poisons", builder }`; clicking a tab shows its page, hides others, `LockHighlight` on active.
- [ ] **Step 2:** Poisons page: `UICheckButtonTemplate` "Show poison bar" (`enabled`), slider `MinimalSliderWithSteppersTemplate` (or `OptionsSliderTemplate` if missing) 1-15 "Warn when less than N min", checkbox "Play sound". Non-rogue → text "Poison bar is for rogues". Each change → `ns.Poisons.Refresh()`.
- [ ] **Step 3:** `luajit -bl` OK; publish; manual: tabs switch, toggles work live, slider value persists across `/reload`.
- [ ] **Step 4:** Commit `feat: poisons settings tab`.

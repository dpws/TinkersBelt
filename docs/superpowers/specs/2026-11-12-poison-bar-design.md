# dpws_tools — Poison Bar (design)

Date: 2026-11-12 · Status: approved in chat, pending spec review

## Goal

Rogue keeps forgetting weapon poisons. A small bar with both weapons: right-click picks a poison, left-click applies it, each button shows time/charges left, and the addon reminds loudly when poison is missing or running out.

## Target

WoW: Forever (`## Interface: 16001`, Retail engine, Classic-era content). Rogue only; module does nothing for other classes.

## Bar

- Two buttons: Main Hand (slot 16), Off Hand (slot 17). Each shows the equipped weapon's icon, the chosen poison's icon (small, corner), time left (`24m`, `<1m` shows seconds `45s`) and charges (`87`).
- A button is hidden when its slot has no weapon. Whole bar hidden if the module is disabled or the class isn't ROGUE.
- Shift+drag moves the bar; position saved. Toggle in `/dpws` → "Poisons" tab.

## Actions

- **Left-click** (secure, works in combat): `SecureActionButtonTemplate`, `type1 = "macro"`, `macrotext1 = "/use item:<poisonID>\n/use <16|17>"`. Replacing an existing poison shows the game's own confirmation popup.
- **Right-click** (insecure menu): lists poisons found in bags (icon, name, count), radio-selected = current choice. Choosing writes `db.poisons.mh|oh = itemID` and rebuilds the button's macrotext via `ns.RunOutOfCombat` (in combat → applied after combat, chat note).
- No poison chosen, or chosen poison count = 0 → button desaturated; left-click does nothing useful (macro would fail harmlessly).

## Poisons list

Item IDs, any locale (`Poisons_Data.lua`):
Instant 6947, 6949, 6950, 8926, 8927, 8928 · Deadly 2892, 2893, 8984, 8985, 20844 · Crippling 3775, 3776 · Mind-numbing 5237, 6951, 9186 · Wound 10918, 10920, 10921, 10922.
Verify on Forever; add any extra IDs found.

## Reminders

State per weapon from `GetWeaponEnchantInfo()` (expiration ms, charges), polled every 0.5s.

- **Glow** (own pulsing texture: `Interface\Buttons\UI-ActionButton-Border`, ADD blend, alpha AnimationGroup bouncing 0.3↔1) when: no poison, or time left < N min. N = `db.poisons.warnMinutes` (default 5, slider 1–15).
- **Early warning**: once per application, when time left first drops below N → sound + center message `"<Main Hand> poison: N min left"`.
- **Expiry warning**: when an applied poison disappears (time or charges) → sound + `"<Main Hand> poison expired!"`. Once per application.
- **Combat warning**: on `PLAYER_REGEN_DISABLED`, if any shown weapon has no poison → sound + `"No poison on <Main Hand / Off Hand>!"`.
- Center message via `RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)`; sound via `PlaySound(SOUNDKIT.RAID_WARNING)`; sound can be turned off (`db.poisons.sound`).
- Logic lives in a pure function `ns.PoisonStep(prev, hasEnchant, msLeft, warnMs) -> newState, event` (event = nil | "early" | "expired"), tested offline with LuaJIT.

## Data

`DpwsToolsCharDB.poisons = { enabled = true, mh = itemID|nil, oh = itemID|nil, warnMinutes = 5, sound = true, pos = { point, relPoint, x, y } }`

## Files

- `Poisons_Data.lua` — `ns.POISON_IDS`
- `Poisons.lua` — bar, buttons, timer, reminders, `ns.PoisonStep`
- `Config.lua` — tab switching (Bar Switching / Poisons), Poisons page: enable, warn-minutes slider, sound checkbox
- `tests/poison_step.lua` — LuaJIT test of `ns.PoisonStep`

## Testing

- Offline: `luajit tests/poison_step.lua` — sequences: none→applied (no event), 6min→4min (early once), 4→3 (nothing), →0 (expired once), reapply→fresh state.
- In game (rogue): pick poison via right-click, left-click applies (in and out of combat), timer/charges show, glow at <N, warnings fire once each, combat warning on pull without poison, disabled module hides bar.

## Out of scope

Thrown weapon / ranged slot, other classes' weapon buffs (sharpening stones, shaman imbues), auto-buying poisons.

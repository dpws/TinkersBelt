-- Offline test for buff reminder logic. Run: luajit tests/buffs.lua
local ns = { loginHooks = {} }
assert(loadfile("Buffs.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

local names = { "Arcane Intellect", "Arcane Brilliance" }
check("missing", ns.BuffStatus({ Other = 500 }, names, 100, 180) == "missing")
check("ok", ns.BuffStatus({ ["Arcane Intellect"] = 1000 }, names, 100, 180) == "ok")
local st, left = ns.BuffStatus({ ["Arcane Intellect"] = 200 }, names, 100, 180)
check("low", st == "low" and left == 100)
check("group version counts", ns.BuffStatus({ ["Arcane Brilliance"] = 3000 }, names, 100, 180) == "ok")
check("longest wins", ns.BuffStatus({ ["Arcane Intellect"] = 150, ["Arcane Brilliance"] = 3000 }, names, 100, 180) == "ok")
check("no duration = ok", ns.BuffStatus({ ["Arcane Intellect"] = 0 }, names, 100, 180) == "ok")

check("pick first known", ns.BuffPickCast({ "Ice Armor", "Mage Armor" }, nil) == "Ice Armor")
check("pick remembered", ns.BuffPickCast({ "Ice Armor", "Mage Armor" }, "Mage Armor") == "Mage Armor")
check("remembered unknown -> first", ns.BuffPickCast({ "Ice Armor" }, "Mage Armor") == "Ice Armor")

-- data sanity: paladin reminder covers every blessing, each blessing also on its own button
local pal = ns.BUFF_SPELLS.PALADIN
check("paladin any-blessing entry", pal[1].key == "blessing" and #pal[1].cast == 6 and pal[1].strip == false)
check("paladin single blessings", #pal == 8 and pal[2].reminder == false)
check("paladin aura", pal[8].key == "aura" and pal[8].self and pal[8].mine and #pal[8].cast == 7)

-- blessings: only one of yours per target
local all = { "Might", "Wisdom", "Kings" }
check("blessing active", ns.ExclusiveStatus({ Might = 1000 }, { Might = 1000 }, { "Might" }, all, 100, 180) == "active")
check("other blessing of mine", ns.ExclusiveStatus({ Might = 1000 }, { Might = 1000 }, { "Wisdom" }, all, 100, 180) == "other")
check("none of mine", ns.ExclusiveStatus({}, {}, { "Wisdom" }, all, 100, 180) == "missing")
check("mine running out", ns.ExclusiveStatus({ Might = 200 }, { Might = 200 }, { "Might" }, all, 100, 180) == "low")
check("paladin counts only own casts", ns.BUFF_SPELLS.PALADIN[1].mine and ns.BUFF_SPELLS.PALADIN[2].group == "blessing")

-- another paladin's blessings: no duplicates
check("taken by another paladin", ns.ExclusiveStatus({}, { Might = 1000 }, { "Might" }, all, 100, 180) == "taken")
check("other paladin has Might, Wisdom free", ns.ExclusiveStatus({}, { Might = 1000 }, { "Wisdom" }, all, 100, 180) == "missing")
local taken = function(n) return n == "Might" end
check("skip remembered if taken", ns.BuffPickFree({ "Might", "Wisdom" }, "Might", taken) == "Wisdom")
check("remembered if free", ns.BuffPickFree({ "Might", "Wisdom" }, "Wisdom", taken) == "Wisdom")
check("all taken: nothing", ns.BuffPickFree({ "Might" }, nil, taken) == nil)

-- unit frame search: biggest visible frame with exactly that unit, not ours, not tiny
local function Fr(unit, w, h, opts)
	opts = opts or {}
	return { dpwsNotUnitFrame = opts.ours, IsForbidden = function() return opts.forbidden end,
		IsVisible = function() return not opts.hidden end, GetAttribute = function() return unit end,
		GetWidth = function() return w end, GetHeight = function() return h end }
end
local function Walk(list)
	return function(prev)
		if not prev then return list[1] end
		for i, x in ipairs(list) do if x == prev then return list[i + 1] end end
	end
end
local elv, small, ours, hidden, target = Fr("party1", 120, 40), Fr("party1", 16, 16), Fr("party1", 200, 200, { ours = true }),
	Fr("party1", 300, 300, { hidden = true }), Fr("target", 300, 60)
check("finds the frame addon's party frame", ns.PickUnitFrame(Walk({ small, ours, hidden, target, elv }), "party1") == elv)
check("no frame: nil", ns.PickUnitFrame(Walk({ small, ours, target }), "party1") == nil)
local big = Fr("player", 200, 50)
check("biggest wins", ns.PickUnitFrame(Walk({ Fr("player", 40, 20), elv, big }), "player") == big)

-- buff rank for a target's level (Classic: rank learn level - 10 <= target level)
local AI = ns.BUFF_RANKS[1] -- Arcane Intellect: 1, 14, 28, 42, 56
local all = function() return true end
check("level 3 gets rank 1", ns.BuffRankPick(AI, 3, all) == 1459)
check("level 5 gets rank 2 (learned 14: 14 - 10 = 4)", ns.BuffRankPick(AI, 5, all) == 1460)
check("level 17 still rank 2", ns.BuffRankPick(AI, 17, all) == 1460)
check("level 18 gets rank 3 (learned 28: 28 - 10 = 18)", ns.BuffRankPick(AI, 18, all) == 1461)
local id, top = ns.BuffRankPick(AI, 60, all)
check("level 60 gets your top rank", id == 10157 and top)
local upTo3 = function(x) return x == 1459 or x == 1460 or x == 1461 end
id, top = ns.BuffRankPick(AI, 60, upTo3)
check("only ranks you know", id == 1461 and top)
check("unknown level: your highest", ns.BuffRankPick(AI, nil, upTo3) == 1461)
id, top = ns.BuffRankPick(ns.BUFF_RANKS[3], 5, all) -- Divine Spirit rank 1 needs level 20
check("too low even for rank 1: rank 1 (the game explains)", id == 14752 and not top)

-- in combat: which reminder buttons stay, dim, or are unknown; needs without a button
do
	local might, kings, wis = { spell = "Might" }, { spell = "Kings" }, { spell = "Wisdom" }
	local btns = { { spell = "Might", needy = { "party1" } }, { spell = "Kings", needy = { "party2" } },
		{ spell = "Wisdom", needy = { "nameplate3" } } }
	local readable = function(u) return u ~= "nameplate3" end
	local per, extra = ns.BuffCombatView(btns, { might, { spell = "Fortitude" } }, readable)
	check("still needed: keeps its need", per[1] == might)
	check("buffed since: dimmed", per[2] == nil)
	check("buffs unreadable: left as is", per[3] == "keep")
	check("ran out in combat: icon without a button", #extra == 1 and extra[1].spell == "Fortitude")
	per, extra = ns.BuffCombatView({}, { kings, wis }, readable)
	check("no buttons: every need is an icon", #extra == 2)
end

print("buffs: " .. passed .. " passed")

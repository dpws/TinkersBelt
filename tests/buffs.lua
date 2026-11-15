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
check("paladin single blessings", #pal == 7 and pal[2].reminder == false)

print("buffs: " .. passed .. " passed")

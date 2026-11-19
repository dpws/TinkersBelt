-- Offline test for the shaman totem logic. Run: luajit tests/totems.lua
local ns = {}
assert(loadfile("Totems.lua"))("TinkersBelt", ns)
local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

local s, e = ns.TotemStep(nil, true, 100, 120, 101)
check("dropping a totem is no alert", e == nil and s.start == 100)
local _, e2 = ns.TotemStep(s, false, 0, 0, 150)
check("vanishing early = killed", e2 == "killed")
local _, e3 = ns.TotemStep(s, false, 0, 0, 219.5)
check("running out = no alert", e3 == nil)
s.dismissed = true
local _, e4 = ns.TotemStep(s, false, 0, 0, 150)
check("destroyed by you = no alert", e4 == nil)
local r = ns.TotemStep(s, true, 130, 120, 130)
check("a new totem forgets the destroy", r.dismissed == nil)
local hidden = ns.TotemStep(nil, true, nil, nil, 10)
local _, e5 = ns.TotemStep(hidden, false, 0, 0, 20)
check("hidden timer never alerts", e5 == nil)

check("empty set has no macro", ns.TotemSetMacro({}) == nil)
check("set macro casts in order", ns.TotemSetMacro({ "Strength of Earth Totem", "Searing Totem" })
	== "/castsequence reset=combat/30 Strength of Earth Totem, Searing Totem")

local known = { [8071] = true, [3599] = true }
local bags = { [5175] = 1 }
local miss = ns.MissingTotemItems(ns.TOTEM_ELEMENTS, function(id) return known[id] end, function(id) return bags[id] or 0 end)
check("missing only the item of an element you use", #miss == 1 and miss[1].key == "fire")

print("totems: " .. passed .. " passed")

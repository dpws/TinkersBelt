-- Offline test for the 5-second-rule / mana tick logic. Run: luajit tests/mana.lua
local ns = { loginHooks = {} }
assert(loadfile("Mana.lua"))("dpws_tools", ns)
local Phase = ns.ManaPhase

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

local p = Phase(101, 100, nil, false)
check("1s after spending: 5s rule, 4s left", p.phase == "fsr" and near(p.remaining, 4) and near(p.fraction, 0.8))
p = Phase(104.9, 100, nil, false)
check("still in 5s rule just before 5s", p.phase == "fsr")
p = Phase(105, 100, nil, false)
check("5s rule over at exactly 5s", p.phase == "tick")
p = Phase(106, 100, nil, false)
check("no tick seen yet: cycle counted from the end of the 5s", near(p.fraction, 0.5))
p = Phase(110.5, 100, 109, false)
check("tick seen: spark 1.5s into the 2s cycle", p.phase == "tick" and near(p.fraction, 0.75))
p = Phase(115, 100, 109, false)
check("cycle keeps repeating from the last tick", near(p.fraction, 0))
p = Phase(102, 100, 99, false)
check("tick clock runs during the 5s rule too (only spirit regen stops)", p.phase == "fsr" and near(p.tickFraction, 0.5))
check("full mana: nothing to show", Phase(102, 100, 99, true) == nil)
p = Phase(50, nil, nil, false)
check("never spent, no tick: tick phase at 0", p.phase == "tick" and near(p.fraction, 0))

print("mana: " .. passed .. " passed")

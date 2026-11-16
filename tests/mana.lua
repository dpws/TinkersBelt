-- Offline test for the 5-second-rule logic. Run: luajit tests/mana.lua
local ns = { loginHooks = {} }
assert(loadfile("Mana.lua"))("dpws_tools", ns)
local Phase = ns.ManaPhase

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

local p = Phase(101, 100, false)
check("1s after spending: 5s rule, 4s left", p.phase == "fsr" and near(p.remaining, 4) and near(p.fraction, 0.8))
check("still in 5s rule just before 5s", Phase(104.9, 100, false).phase == "fsr")
check("5s over: regenerating", Phase(105, 100, false).phase == "regen")
check("never spent, not full: regenerating", Phase(50, nil, false).phase == "regen")
check("full mana: nothing to show", Phase(102, 100, true) == nil)

print("mana: " .. passed .. " passed")

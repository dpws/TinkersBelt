-- Offline test for ns.PoisonStep. Run: luajit tests/poison_step.lua
local ns = { loginHooks = {} }
assert(loadfile("Poisons.lua"))("dpws_tools", ns)
local Step = ns.PoisonStep
assert(Step, "ns.PoisonStep missing")

local W = 300000 -- 5 min
local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

local s, e = Step(nil, false, 0, W)
check("no poison, fresh", e == nil and not s.applied)

s, e = Step(s, true, 1800000, W)
check("applied", e == nil and s.applied and not s.early)

s, e = Step(s, true, 360000, W)
check("above N", e == nil)
s, e = Step(s, true, 240000, W)
check("early fires", e == "early")
s, e = Step(s, true, 180000, W)
check("early only once", e == nil)

s, e = Step(s, false, 0, W)
check("expired fires", e == "expired")
s, e = Step(s, false, 0, W)
check("expired only once", e == nil)

s, e = Step(s, true, 1800000, W)
s, e = Step(s, true, 240000, W)
check("early re-armed after new application", e == "early")

s, e = Step(s, true, 1800000, W)
check("reapply while active: no event, re-armed", e == nil and not s.early)

s, e = Step(nil, true, 120000, W)
check("fresh application already below N: silent", e == nil and s.early)
s, e = Step(s, true, 100000, W)
check("still silent", e == nil)

print("poison_step: " .. passed .. " passed")

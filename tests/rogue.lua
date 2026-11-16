-- Offline test for rogue timers, lockbox and opener logic. Run: luajit tests/rogue.lua
local ns = { loginHooks = {} }
assert(loadfile("RogueTimers.lua"))("dpws_tools", ns)
assert(loadfile("Lockbox.lua"))("dpws_tools", ns)
assert(loadfile("Opener.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

-- cooldowns
check("never used: ready", ns.CooldownLeft(0, 0, 100) == 0)
check("global cooldown is not a cooldown", ns.CooldownLeft(99, 1.5, 100) == 0)
check("on cooldown", ns.CooldownLeft(90, 30, 100) == 20)
check("finished", ns.CooldownLeft(50, 30, 100) == 0)

-- lockboxes: open a picked one first, then pick one you can
local a = { bag = 0, slot = 1, locked = true, canPick = false }
local b = { bag = 0, slot = 2, locked = true, canPick = true }
local c = { bag = 1, slot = 3, locked = false }
local box, action = ns.LockboxNext({ a, b, c })
check("open a picked box first", box == c and action == "open")
box, action = ns.LockboxNext({ a, b })
check("then pick one your skill allows", box == b and action == "pick")
check("skill too low: nothing", ns.LockboxNext({ a }) == nil)

-- opener markers
local function tags(t) return table.concat(ns.OpenerTags(t), ",") end
local npc = { stealthed = true, attackable = true, humanoid = true }
check("humanoid npc: sap + pick pocket", tags(npc) == "Sap,Pick Pocket")
check("picked already: sap only", tags({ stealthed = true, attackable = true, humanoid = true, picked = true }) == "Sap")
check("player: sap only", tags({ stealthed = true, attackable = true, humanoid = true, player = true }) == "Sap")
check("beast: nothing", tags({ stealthed = true, attackable = true }) == "")
check("not stealthed: nothing", tags({ attackable = true, humanoid = true }) == "")
check("in combat: nothing", tags({ stealthed = true, attackable = true, humanoid = true, combat = true }) == "")
check("russian humanoid", ns.HUMANOID["Гуманоид"])

-- weapon sets
check("both hands", ns.WeaponMacro({ mh = { name = "Dagger" }, oh = { name = "Sword" } }) == "/equipslot 16 Dagger\n/equipslot 17 Sword")
check("main hand only", ns.WeaponMacro({ mh = { name = "Dagger" } }) == "/equipslot 16 Dagger")

print("rogue: " .. passed .. " passed")

-- Offline test for ns.ComboSoundFor. Run: luajit tests/combo_sound.lua
local ns = { loginHooks = {} }
assert(loadfile("Combo.lua"))("dpws_tools", ns)
local For = ns.ComboSoundFor
assert(For, "ns.ComboSoundFor missing")

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

check("0 -> 1 plays 1", For(0, 1) == 1)
check("nil -> 2 plays 2", For(nil, 2) == 2)
check("1 -> 3 jump plays 3", For(1, 3) == 3)
check("same amount: nothing", For(3, 3) == nil)
check("spent (5 -> 0): nothing", For(5, 0) == nil)
check("drop then rise 2 -> 1: nothing", For(2, 1) == nil)

print("combo_sound: " .. passed .. " passed")

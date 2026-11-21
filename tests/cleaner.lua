-- Offline test for the bag cleaner's pick. Run: luajit tests/cleaner.lua
local ns = { loginHooks = {} }
assert(loadfile("BagCleaner.lua"))("TinkersBelt", ns)
local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

local items = {
	{ name = "Linen", quality = 1, price = 1, count = 20 },     -- 20
	{ name = "Grey ring", quality = 0, price = 5, count = 1 },   -- 5
	{ name = "Hearthstone", quality = 1, price = 0, count = 1 }, -- no value: never
	{ name = "Quest thing", quality = 1, count = 1 },            -- no price known: never
	{ name = "Green axe", quality = 2, price = 2, count = 1 },   -- 2, but green
	{ name = "Cloth scrap", quality = 1, price = 3, count = 1 }, -- 3
	{ name = "Locked", quality = 0, price = 1, count = 1, locked = true },
}
local pick = ns.CleanerPick(items, 1, 5)
check("cheapest whole stack first", pick[1].name == "Cloth scrap" and pick[2].name == "Grey ring" and pick[3].name == "Linen")
check("no-value and unknown-price items never listed", #pick == 3)
check("value = price x count", pick[3].value == 20)
pick = ns.CleanerPick(items, 2, 5)
check("quality limit raised: the green axe is cheapest", pick[1].name == "Green axe")
pick = ns.CleanerPick(items, 0, 5)
check("greys only", #pick == 1 and pick[1].name == "Grey ring")
check("n limits the list", #ns.CleanerPick(items, 2, 2) == 2)
check("locked items skipped", ns.CleanerPick({ items[7] }, 4, 5)[1] == nil)
print("cleaner: " .. passed .. " passed")

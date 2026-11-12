-- Offline test for poison stock logic. Run: luajit tests/poison_stock.lua
local ns = { loginHooks = {} }
assert(loadfile("PoisonStock.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

-- poison 1: 2x dust(10) + 1x vial(20); poison 2: 3x weed(30) + 1x vial(20); poison 2 makes 2 per craft
local recipes = {
	[1] = { reagents = { [10] = 2, [20] = 1 }, makes = 1 },
	[2] = { reagents = { [30] = 3, [20] = 1 }, makes = 2 },
}
local bags = {}
local function count(id) return bags[id] or 0 end

-- materials to buy
bags = { [1] = 15, [2] = 6, [20] = 3 }
local need = ns.PoisonMaterialsNeed({ [1] = 20, [2] = 10 }, recipes, count)
-- poison 1 missing 5 -> 5 crafts: dust 10, vial 5; poison 2 missing 4 -> 2 crafts: weed 6, vial 2; vials in bags 3
check("dust", need[10] == 10)
check("weed (makes 2 per craft)", need[30] == 6)
check("vials shared and minus bags", need[20] == 4)
bags = { [1] = 20, [2] = 10 }
need = ns.PoisonMaterialsNeed({ [1] = 20, [2] = 10 }, recipes, count)
check("stock full: nothing to buy", next(need) == nil)
need = ns.PoisonMaterialsNeed({ [1] = 5, [99] = 5 }, recipes, count)
check("unknown recipe ignored", next(need) == nil)

-- how many crafts the bags allow
bags = { [10] = 7, [20] = 9 }
check("can make: limited by dust", ns.PoisonCanMake(recipes[1], count) == 3)
bags = {}
check("can make: nothing", ns.PoisonCanMake(recipes[1], count) == 0)

-- next craft job: first poison short on stock that can be made
bags = { [1] = 20, [2] = 5, [30] = 9, [20] = 5 }
local job = ns.PoisonNextCraft({ [1] = 20, [2] = 10 }, recipes, count, { 1, 2 })
check("skips full poison, crafts poison 2", job and job.id == 2)
check("crafts needed (missing 5, makes 2 -> 3) limited by mats (weed 9 -> 3)", job.crafts == 3)
bags = { [1] = 0, [2] = 10, [10] = 1, [20] = 5 }
job = ns.PoisonNextCraft({ [1] = 20, [2] = 10 }, recipes, count, { 1, 2 })
check("short but no mats: nothing", job == nil)

print("poison_stock: " .. passed .. " passed")

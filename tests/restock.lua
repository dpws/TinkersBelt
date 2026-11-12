-- Offline test for restock logic. Run: luajit tests/restock.lua
local ns = { loginHooks = {} }
assert(loadfile("Restock.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

local have = { [100] = 5, [200] = 0, [300] = 50 }
local function count(id) return have[id] or 0 end
-- goods: index, id, price per batch, batch size, available (-1 = unlimited)
local goods = {
	{ index = 1, id = 100, price = 10, batch = 1, available = -1 },
	{ index = 2, id = 200, price = 100, batch = 5, available = -1 },
	{ index = 3, id = 300, price = 1, batch = 1, available = -1 },
	{ index = 4, id = 999, price = 1, batch = 1, available = -1 },
}
local list = { [100] = 20, [200] = 12, [300] = 20 }

local buys, total, over = ns.RestockPlan(list, count, goods, 100000)
local byId = {}
for _, b in ipairs(buys) do byId[b.id] = b end
check("buys the missing amount", byId[100] and byId[100].qty == 15 and byId[100].cost == 150)
check("batches rounded up", byId[200] and byId[200].batches == 3 and byId[200].cost == 300)
check("already enough: not bought", byId[300] == nil)
check("not on list: not bought", byId[999] == nil)
check("total", total == 450 and over == false)

local _, _, over2 = ns.RestockPlan(list, count, goods, 400)
check("over budget flagged", over2 == true)

local limited = { { index = 1, id = 100, price = 10, batch = 1, available = 4 } }
buys = ns.RestockPlan(list, count, limited, 100000)
check("limited stock capped", buys[1].qty == 4)

local dup = { goods[1], { index = 9, id = 100, price = 5, batch = 1, available = -1 } }
buys = ns.RestockPlan(list, count, dup, 100000)
check("same item twice: bought once", #buys == 1)

print("restock: " .. passed .. " passed")

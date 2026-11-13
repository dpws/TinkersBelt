local _, ns = ...

-- What to buy from this vendor. list: itemID -> target count; count(id) -> in bags;
-- goods: { index, id, price (per batch), batch, available (-1 = unlimited) }.
-- Returns purchases { index, id, qty | batches, cost }, total cost, over budget.
function ns.RestockPlan(list, count, goods, budget)
	local buys, total, done = {}, 0, {}
	for _, g in ipairs(goods) do
		local target = list[g.id]
		local need = target and (target - count(g.id)) or 0
		if need > 0 and not done[g.id] then
			done[g.id] = true
			local b = { index = g.index, id = g.id }
			if g.batch > 1 then
				b.batches = math.ceil(need / g.batch)
				if g.available >= 0 then b.batches = math.min(b.batches, g.available) end
				b.cost = b.batches * g.price
			else
				b.qty = need
				if g.available >= 0 then b.qty = math.min(b.qty, g.available) end
				b.cost = b.qty * g.price
			end
			if (b.batches or b.qty) > 0 then
				buys[#buys + 1] = b
				total = total + b.cost
			end
		end
	end
	return buys, total, total > budget
end

if not CreateFrame then return end -- offline test stops here

-- Class presets (item IDs, target counts). Added to the list, never replacing what's there.
ns.RESTOCK_PRESETS = {
	ROGUE = { [5140] = 20, [5530] = 10, [8924] = 20, [8925] = 20, [8923] = 10, [5173] = 20 }, -- Flash/Blinding Powder, Dust of Deterioration, Crystal Vial, Essence of Agony, Deathweed
	MAGE = { [17020] = 20, [17031] = 10, [17032] = 5 }, -- Arcane Powder, Rune of Teleportation, Rune of Portals
	PRIEST = { [17028] = 20, [17029] = 20 }, -- Holy Candle, Sacred Candle
	PALADIN = { [17033] = 5, [21177] = 20 }, -- Symbol of Divinity, Symbol of Kings
	SHAMAN = { [17030] = 5 }, -- Ankh
	DRUID = { [17021] = 10, [17038] = 10, [17026] = 20 }, -- Wild Berries, Ironwood Seed, Wild Thornroot
	WARLOCK = { [5565] = 5, [16583] = 5 }, -- Infernal Stone, Demonic Figurine
}

local function Count(id) return (C_Item and C_Item.GetItemCount or GetItemCount)(id) end
local function ItemName(id)
	return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
end

local function Goods()
	local goods = {}
	for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
		local id = GetMerchantItemID and GetMerchantItemID(i)
		local price, batch, available
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(i)
			if info then price, batch, available = info.price, info.stackCount, info.numAvailable end
		elseif GetMerchantItemInfo then
			local _, _, p, q, n = GetMerchantItemInfo(i)
			price, batch, available = p, q, n
		end
		if id and price and price > 0 then -- price 0: bought with tokens, not gold
			goods[#goods + 1] = { index = i, id = id, price = price, batch = math.max(1, batch or 1), available = available or -1 }
		end
	end
	return goods
end

-- Purchases go through a queue, 0.5s apart: the server ignores rapid repeated buys (Krowi's vendor addon does the same)
local queue, merchantOpen = {}, false
local function RunQueue()
	if not merchantOpen then wipe(queue) return end
	local job = table.remove(queue, 1)
	if not job then return end
	BuyMerchantItem(job.index, job.n)
	if #queue > 0 then C_Timer.After(0.5, RunQueue) end
end

-- verbose: print every step (for /dpws restock)
local function Restock(verbose)
	local function Say(msg) if verbose then print("dpws_tools restock: " .. msg) end end
	local r = ns.db.restock
	-- shopping list = restock items (if on) + poison ingredients for the Poison Stock list
	local items, n = {}, 0
	if verbose and ns.PoisonStock then for _, line in ipairs(ns.PoisonStock.Describe()) do Say(line) end end
	if r.enabled then for id, c in pairs(r.items) do items[id] = c end end
	if ns.PoisonStock then
		for id, c in pairs(ns.PoisonStock.MaterialTargets()) do items[id] = math.max(items[id] or 0, c) end
	end
	for id, c in pairs(items) do
		n = n + 1
		Say(("wants %s: target %d, have %d"):format(ItemName(id), c, Count(id)))
	end
	if n == 0 then return Say(r.enabled and "shopping list is empty" or "auto restock is off and no poison ingredients needed") end
	local goods = Goods()
	Say(("vendor sells %d items (for gold)"):format(#goods))
	local buys, total, over = ns.RestockPlan(items, Count, goods, r.budget)
	if #buys == 0 then return Say("nothing to buy here (vendor doesn't sell them, or you have enough)") end
	if over then
		print(("dpws_tools: restock skipped, it would cost %s (limit %s)"):format(
			GetCoinTextureString(total), GetCoinTextureString(r.budget)))
		return
	end
	if GetMoney() < total then print("dpws_tools: restock skipped, not enough gold") return end
	local parts = {}
	for _, b in ipairs(buys) do
		if b.batches then
			for _ = 1, b.batches do queue[#queue + 1] = { index = b.index } end -- one vendor batch each
			parts[#parts + 1] = ("%dx %s"):format(b.batches, ItemName(b.id))
		else
			local stack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(b.index)) or 20
			local left = b.qty
			while left > 0 do
				local k = math.min(left, math.max(stack, 1))
				queue[#queue + 1] = { index = b.index, n = k }
				left = left - k
			end
			parts[#parts + 1] = ("%d %s"):format(b.qty, ItemName(b.id))
		end
	end
	print(("dpws_tools: restocking %s (%s)"):format(table.concat(parts, ", "), GetCoinTextureString(total)))
	RunQueue()
end

function ns.AddRestockPreset()
	local preset = ns.RESTOCK_PRESETS[select(2, UnitClass("player"))]
	if not preset then return false end
	for id, c in pairs(preset) do
		if not ns.db.restock.items[id] then ns.db.restock.items[id] = c end
	end
	return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:SetScript("OnEvent", function(_, event)
	merchantOpen = event == "MERCHANT_SHOW"
	if not merchantOpen then wipe(queue) return end
	-- the vendor's list fills in a moment after the window opens; errors go to BugSack, not swallowed
	C_Timer.After(0.5, function() if merchantOpen then xpcall(Restock, geterrorhandler()) end end)
end)

-- /dpws restock: explain what restock sees (open a vendor first to see what it would buy)
ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.restock = function()
	if not merchantOpen then print("dpws_tools restock: no vendor open, showing the list only") end
	xpcall(function() Restock(true) end, geterrorhandler())
end

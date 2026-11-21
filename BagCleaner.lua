local _, ns = ...
local Loc = ns.L or setmetatable({}, { __index = function(_, k) return k end })

-- Bag Cleaner: when your bags are (nearly) full, a panel lists the cheapest stacks; click one to delete it.
-- Never deletes items without a vendor price (quest items, keys, Hearthstone...).

-- the n cheapest stacks allowed to go. items = { { bag, slot, id, count, quality, price, name } }; price = vendor
-- price per item (0 / nil = no value: never listed); maxQuality: 0 poor .. 4 epic; keep = { [itemID] = true }
-- protected items. Cheapest whole stack first.
function ns.CleanerPick(items, maxQuality, n, keep)
	local ok = {}
	for _, it in ipairs(items) do
		if it.price and it.price > 0 and it.quality and it.quality <= maxQuality and not it.locked
			and not (keep and keep[it.id]) then
			it.value = it.price * (it.count or 1)
			ok[#ok + 1] = it
		end
	end
	table.sort(ok, function(a, b)
		if a.value ~= b.value then return a.value < b.value end
		if a.quality ~= b.quality then return a.quality < b.quality end
		return (a.name or "") < (b.name or "")
	end)
	local out = {}
	for i = 1, math.min(n, #ok) do out[i] = ok[i] end
	return out
end

if not CreateFrame then return end -- offline test stops here

local T = ns.Theme
local C = {}
ns.BagCleaner = C
local function S() return ns.db.cleaner end
-- protected items, account-wide: { [itemID] = name }
local function Keep() ns.adb.cleanerKeep = ns.adb.cleanerKeep or {} return ns.adb.cleanerKeep end
C.Keep = Keep
local QUALITY_NAMES = { [0] = "Poor (grey)", "Common (white)", "Uncommon (green)", "Rare (blue)" }
C.QUALITY_NAMES = QUALITY_NAMES

local function Coins(copper)
	local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
	return fn and fn(copper) or (copper .. "c")
end

local function FreeSlots()
	local free = 0
	for bag = 0, 4 do
		local n, family = C_Container.GetContainerNumFreeSlots(bag)
		if (family or 0) == 0 then free = free + (n or 0) end -- special bags (soul, ammo) don't count
	end
	return free
end

local function Items()
	local items = {}
	for bag = 0, 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local name, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(info.itemID) -- nil until cached
				items[#items + 1] = { bag = bag, slot = slot, id = info.itemID, count = info.stackCount or 1,
					quality = info.quality, price = (not info.hasNoValue) and price or 0, name = name or info.itemName,
					icon = info.iconFileID, link = info.hyperlink, locked = info.isLocked }
			end
		end
	end
	return items
end

local panel, header, rows = nil, nil, {}
local list = {}

-- delete one listed stack, only if that slot still holds the same item and count (bags change)
local function Delete(it)
	if not it then return end
	local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
	if not info or info.itemID ~= it.id or (info.stackCount or 1) ~= it.count or info.isLocked then
		print(Loc["Tinker's Belt: that stack moved, the list is updated"])
		return C.Update()
	end
	ClearCursor()
	C_Container.PickupContainerItem(it.bag, it.slot)
	local kind, id = GetCursorInfo()
	if kind ~= "item" or id ~= it.id then ClearCursor() return C.Update() end
	DeleteCursorItem()
	print((Loc["Tinker's Belt: deleted %s x%d (%s)"]):format(it.link or it.name or Loc["item"], it.count, Coins(it.value)))
end

local ROW_H, WIDTH = 24, 260

local function Row(i)
	if rows[i] then return rows[i] end
	local r = CreateFrame("Button", nil, panel)
	r:SetSize(WIDTH - 16, ROW_H)
	r:SetPoint("TOPLEFT", 8, -34 - (i - 1) * (ROW_H + 2))
	r.bg = T.Rounded(r, T.row, 4, "BACKGROUND", 0)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", 4, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.name = T.Text(r, "medium", 12)
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.name:SetWidth(130)
	r.name:SetWordWrap(false)
	r.value = T.Text(r, "regular", 11, T.muted)
	r.value:SetPoint("RIGHT", -6, 0)
	r.value:SetJustifyH("RIGHT")
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.3, 0.2, 0.12) -- red tint: clicking deletes
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnClick", function(self, mouse)
		local it = self.item
		if not it then return end
		if mouse == "RightButton" then
			Keep()[it.id] = it.name or true
			print((Loc["Tinker's Belt: %s is protected (undo on the Bag Cleaner page)"]):format(it.link or it.name or Loc["item"]))
			if C.OnKeepChanged then C.OnKeepChanged() end
			return C.Update()
		end
		Delete(it)
	end)
	r:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(self.item.bag, self.item.slot)
		GameTooltip:AddLine(Loc["Click: delete this stack"], 1, 0.4, 0.3)
		GameTooltip:AddLine(Loc["Right-click: protect this item (never listed)"], 0.4, 0.8, 1)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", function() ns.StartMovingPanel(panel) end)
	r:SetScript("OnDragStop", function() ns.StopMovingPanel(panel) end)
	rows[i] = r
	return r
end

function C.Update()
	if not panel then return end
	local s = S()
	local free = FreeSlots()
	local show = s.enabled and free <= (s.freeAt or 0)
	list = show and ns.CleanerPick(Items(), s.maxQuality or 1, s.n or 5, Keep()) or {}
	panel:SetShown((show and #list > 0) or ns.unlocked)
	header:SetText(free == 0 and Loc["Bags full: cheapest stacks"] or (Loc["%d free: cheapest stacks"]):format(free))
	for i = 1, math.max(#list, #rows) do
		local r = Row(i)
		local it = list[i]
		r.item = it
		if it then
			local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.quality]
			r.icon:SetTexture(it.icon)
			r.name:SetText((it.count > 1 and (it.count .. "x ") or "") .. (it.name or "?"))
			if c then r.name:SetTextColor(c.r, c.g, c.b) end
			r.value:SetText(Coins(it.value))
			r:Show()
		else
			r:Hide()
		end
	end
	panel:SetHeight(40 + math.max(#list, 1) * (ROW_H + 2))
end

table.insert(ns.loginHooks, function()
	ns.db.cleaner = ns.db.cleaner or { enabled = true, n = 5, maxQuality = 1, freeAt = 0 }
	local s = S()
	panel = CreateFrame("Frame", "DpwsBagCleaner", UIParent)
	panel:SetSize(WIDTH, 60)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("MEDIUM")
	T.Box(panel, { 0.047, 0.054, 0.066, 0.94 }, T.border, 8)
	header = T.Text(panel, "semibold", 12, T.gold)
	header:SetPoint("TOPLEFT", 10, -10)
	header:SetPoint("RIGHT", -8, 0)
	header:SetWordWrap(false)
	if s.pos then
		panel:SetPoint(s.pos.point, UIParent, s.pos.relPoint, s.pos.x, s.pos.y)
	else
		panel:SetPoint("RIGHT", UIParent, "RIGHT", -240, 0)
	end
	ns.RegisterPanel(panel, "Bag Cleaner", function(self)
		local point, _, relPoint, x, y = self:GetPoint()
		s.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("BAG_UPDATE_DELAYED")
	ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	-- item info arrives in bursts: one update per burst
	local pending = false
	ev:SetScript("OnEvent", function()
		if pending then return end
		pending = true
		C_Timer.After(0.2, function() pending = false; C.Update() end)
	end)
	C.Update()
end)

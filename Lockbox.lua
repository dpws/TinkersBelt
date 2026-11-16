local _, ns = ...

-- lockboxes and locked chests found in the world
ns.LOCKBOXES = {
	[4632] = true, [4633] = true, [4634] = true, [4636] = true, [4637] = true, [4638] = true, -- Ornate Bronze .. Reinforced Steel
	[5758] = true, [5759] = true, [5760] = true, -- Mithril, Thorium, Eternium
	[16882] = true, [16883] = true, [16884] = true, [16885] = true, -- Battered .. Heavy Junkbox
	[6354] = true, [6355] = true, [13875] = true, [13918] = true, -- Small / Sturdy / Ironbound / Reinforced Locked Chest
}

-- what the button does next: open an already picked box first, else pick one your skill allows; nil = nothing
-- boxes = { { bag, slot, locked, canPick } }
function ns.LockboxNext(boxes)
	for _, b in ipairs(boxes) do
		if not b.locked then return b, "open" end
	end
	for _, b in ipairs(boxes) do
		if b.canPick then return b, "pick" end
	end
end

if not CreateFrame then return end -- offline test stops here

-- Lockbox helper: one button that picks the next lockbox you can open (Pick Lock), then opens it.
local T = ns.Theme
local L = {}
ns.Lockbox = L
local function S() return ns.db.lockbox end
local PICK_LOCK = 1804

local button

local function Scan()
	local boxes = {}
	for bag = 0, 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local id = C_Container.GetContainerItemID(bag, slot)
			if id and ns.LOCKBOXES[id] then
				local box = { bag = bag, slot = slot, id = id }
				local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
				for _, line in ipairs(ok and data and data.lines or {}) do
					if line.leftText == LOCKED then box.locked = true end
					local c = line.leftColor
					-- the "Requires Lockpicking (N)" line turns red when your skill is too low
					if c and c.r and c.r > 0.9 and c.g < 0.2 and c.b < 0.2 then box.tooLow = true end
				end
				box.canPick = box.locked and not box.tooLow
				boxes[#boxes + 1] = box
			end
		end
	end
	return boxes
end

local function Update()
	if not button or InCombatLockdown() then return end -- clickable button: set up out of combat
	local boxes = Scan()
	local box, action = ns.LockboxNext(boxes)
	local ready = 0
	for _, b in ipairs(boxes) do
		if not b.locked or b.canPick then ready = ready + 1 end
	end
	button.box, button.action = box, action
	if box then
		local use = ("/use %d %d"):format(box.bag, box.slot)
		local pick = C_Spell.GetSpellName(PICK_LOCK)
		button:SetAttribute("macrotext", action == "pick" and ("/cast " .. pick .. "\n" .. use) or use)
		button.icon:SetTexture(C_Item.GetItemIconByID(box.id))
		button.count:SetText(ready > 1 and ready or "")
		button.label:SetText(action == "pick" and "pick" or "open")
	end
	button:SetShown((S().enabled and box ~= nil) or ns.unlocked)
end
L.Update = Update

table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "ROGUE" then return end
	local s = S()
	button = CreateFrame("Button", "DpwsLockboxButton", UIParent, "SecureActionButtonTemplate")
	button:SetSize(36, 36)
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("type", "macro")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.icon:SetTexture("Interface\\Icons\\INV_Box_04")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button.count = T.Text(button, "semibold", 14, { 1, 1, 1, 1 })
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	button.count:SetShadowColor(0, 0, 0, 1)
	button.label = T.Text(button, "semibold", 10, T.gold)
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -2)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.box then
			GameTooltip:AddLine((self.action == "pick" and "Pick the lock: " or "Open: ") .. (C_Item.GetItemNameByID(self.box.id) or ""))
		else
			GameTooltip:AddLine("Lockbox helper")
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	if s.pos then
		button:SetPoint(s.pos.point, UIParent, s.pos.relPoint, s.pos.x, s.pos.y)
	else
		button:SetPoint("CENTER", UIParent, "CENTER", 200, -150)
	end
	ns.RegisterPanel(button, "Lockbox", function(self)
		local point, _, relPoint, px, py = self:GetPoint()
		s.pos = { point = point, relPoint = relPoint, x = px, y = py }
	end)
	button:Hide()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("BAG_UPDATE_DELAYED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("SKILL_LINES_CHANGED")
	ev:SetScript("OnEvent", function() C_Timer.After(0.2, Update) end)
	C_Timer.NewTicker(2, Update) -- also catches unlock/lock of panels
	Update()
end)

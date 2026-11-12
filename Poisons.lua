local _, ns = ...

-- Pure reminder logic per weapon. Returns new state and nil | "early" | "expired".
-- itemID: the equipped weapon; a different weapon in the slot starts fresh (no false warnings on swap)
function ns.PoisonStep(prev, hasEnchant, msLeft, warnMs, itemID)
	if not prev or prev.item ~= itemID then prev = {} end
	if not hasEnchant then
		return { applied = false, item = itemID }, prev.applied and "expired" or nil
	end
	-- new application (first seen, or time jumped up = reapplied)
	if not prev.applied or msLeft > (prev.msLeft or 0) + 1000 then
		return { applied = true, early = msLeft < warnMs, msLeft = msLeft, item = itemID }, nil
	end
	local event = (not prev.early and msLeft < warnMs) and "early" or nil
	return { applied = true, early = prev.early or event ~= nil, msLeft = msLeft, item = itemID }, event
end

if not CreateFrame then return end -- offline test stops here

local P = {}
ns.Poisons = P
P.SLOTS = {
	{ slot = 16, key = "mh", name = "Main Hand" },
	{ slot = 17, key = "oh", name = "Off Hand" },
}

local bar
local buttons, states = {}, {}

local function ItemIcon(id)
	return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or GetItemIcon(id)
end
local function ItemName(id)
	local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or GetItemInfo(id)
	return name or ("item " .. id)
end
local function Count(id)
	return (C_Item and C_Item.GetItemCount or GetItemCount)(id)
end

local function Warn(msg)
	RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo.RAID_WARNING)
	if ns.db.poisons.sound then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local function FormatTime(ms)
	if ms >= 60000 then return ("%dm"):format(math.ceil(ms / 60000)) end
	return ("%ds"):format(math.ceil(ms / 1000))
end

-- weapon icon, poison icon, desaturation (insecure, fine in combat)
local function UpdateIcons()
	for _, b in ipairs(buttons) do
		local id = ns.db.poisons[b.info.key]
		b.icon:SetTexture(GetInventoryItemTexture("player", b.info.slot))
		b.poison:SetTexture(id and ItemIcon(id) or nil)
		b.icon:SetDesaturated(not id or Count(id) == 0)
	end
end

-- secure parts: macro text and visibility
local function UpdateSecure()
	ns.RunOutOfCombat(function()
		if not bar then return end
		bar:SetShown(ns.db.poisons.enabled)
		for _, b in ipairs(buttons) do
			local id = ns.db.poisons[b.info.key]
			b:SetAttribute("macrotext1", id and ("/use item:%d\n/use %d"):format(id, b.info.slot) or nil)
			b:SetShown(GetInventoryItemID("player", b.info.slot) ~= nil)
		end
	end)
end

function P.Refresh()
	if not bar then return end
	UpdateSecure()
	UpdateIcons()
end

local function SetPoison(info, id)
	ns.db.poisons[info.key] = id
	if InCombatLockdown() then print("dpws_tools: poison change applies after combat") end
	P.Refresh()
end

local function OpenMenu(owner, info)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(info.name .. " poison")
		local any = false
		for _, id in ipairs(ns.POISON_IDS) do
			local count = Count(id)
			if count > 0 then
				any = true
				local text = ("|T%s:16|t %s (%d)"):format(ItemIcon(id) or "", ItemName(id), count)
				root:CreateRadio(text, function() return ns.db.poisons[info.key] == id end, function() SetPoison(info, id) end)
			end
		end
		if not any then root:CreateButton("No poisons in bags"):SetEnabled(false) end
	end)
end

local function MakeGlow(b)
	local glow = b:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.2, 0.2)
	glow:SetSize(76, 76)
	glow:SetPoint("CENTER")
	local ag = glow:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.3)
	a:SetDuration(0.6)
	glow:Hide()
	b.SetGlow = function(_, on)
		if on == glow:IsShown() then return end
		glow:SetShown(on)
		if on then ag:Play() else ag:Stop() end
	end
end

local function MakeButton(info, i)
	local b = CreateFrame("Button", "DpwsPoisonButton" .. info.key:upper(), bar, "SecureActionButtonTemplate")
	b.info = info
	b:SetSize(40, 40)
	b:SetPoint("LEFT", (i - 1) * 48, 0)
	b:RegisterForClicks("AnyUp")
	-- with ActionButtonUseKeyDown on (default) the template acts on press, which an up-only button never gets
	b:SetAttribute("useOnKeyDown", false)
	b:RegisterForDrag("LeftButton")
	b:SetAttribute("type1", "macro")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b.poison = b:CreateTexture(nil, "OVERLAY")
	b.poison:SetSize(18, 18)
	b.poison:SetPoint("BOTTOMRIGHT", 2, -2)
	b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.time:SetPoint("BOTTOM", b, "TOP", 0, 2)
	b.charges = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.charges:SetPoint("TOPLEFT", 2, -2)
	MakeGlow(b)

	b:SetScript("PostClick", function(self, button)
		if button == "RightButton" then OpenMenu(self, info) end
	end)
	-- Shift+drag moves the whole bar
	b:SetScript("OnDragStart", function() if IsShiftKeyDown() and not InCombatLockdown() then bar:StartMoving() end end)
	b:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		local point, _, relPoint, x, y = bar:GetPoint()
		ns.db.poisons.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetInventoryItem("player", info.slot)
		GameTooltip:AddLine("Left-click: apply poison   Right-click: choose   Shift+drag: move", 0.6, 0.8, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local elapsed = 0
local function OnUpdate(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.5 then return end
	elapsed = 0
	local hasMH, mhMs, mhCharges, _, hasOH, ohMs, ohCharges = GetWeaponEnchantInfo()
	local data = { mh = { hasMH, mhMs, mhCharges }, oh = { hasOH, ohMs, ohCharges } }
	local warnMs = ns.db.poisons.warnMinutes * 60000
	for _, b in ipairs(buttons) do
		local key, d = b.info.key, data[b.info.key]
		local has, ms, charges = d[1], d[2] or 0, d[3] or 0
		local itemID = GetInventoryItemID("player", b.info.slot)
		if itemID then
			local event
			states[key], event = ns.PoisonStep(states[key], has, ms, warnMs, itemID)
			if event == "early" then
				Warn(("%s poison: %d min left"):format(b.info.name, ns.db.poisons.warnMinutes))
			elseif event == "expired" then
				Warn(b.info.name .. " poison expired!")
			end
			b.time:SetText(has and FormatTime(ms) or "")
			b.charges:SetText(has and charges > 0 and charges or "")
			b:SetGlow(not has or ms < warnMs)
		else
			states[key] = nil -- unequipped: no expiry warning
			b.time:SetText("")
			b.charges:SetText("")
			b:SetGlow(false)
		end
	end
end

local function Create()
	bar = CreateFrame("Frame", "DpwsPoisonBar", UIParent)
	bar:SetSize(88, 40)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	local pos = ns.db.poisons.pos
	if pos then
		bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end
	for i, info in ipairs(P.SLOTS) do buttons[i] = MakeButton(info, i) end
	bar:SetScript("OnUpdate", OnUpdate)

	bar:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	bar:RegisterEvent("BAG_UPDATE_DELAYED")
	bar:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	bar:RegisterEvent("PLAYER_REGEN_DISABLED")
	bar:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			if not bar:IsShown() then return end
			local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
			local missing = {}
			if GetInventoryItemID("player", 16) and not hasMH then missing[#missing + 1] = "Main Hand" end
			if GetInventoryItemID("player", 17) and not hasOH then missing[#missing + 1] = "Off Hand" end
			if #missing > 0 then Warn("No poison on " .. table.concat(missing, " / ") .. "!") end
		else
			P.Refresh()
		end
	end)
	P.Refresh()
end

table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) == "ROGUE" then ns.RunOutOfCombat(Create) end
end)

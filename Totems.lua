local _, ns = ...

-- Shaman totem bar: [set] [Earth] [Fire] [Water] [Air] [shield].
-- Elements: timer sweep while a totem is down, alert when one is killed early, left-click drops the active
-- set's totem of that element, right-click destroys it. Set button: drops the whole set, one totem per click.
-- Shield: Lightning Shield charges, click to cast. Totem items missing from bags are marked red.

-- rank 1 IDs, cast by name (= highest rank). slot = the game's totem slot.
ns.TOTEM_ELEMENTS = {
	{ slot = 2, key = "earth", name = "Earth", item = 5175, spells = { 8071, 8075, 2484, 5730, 8143 } },
	{ slot = 1, key = "fire", name = "Fire", item = 5176, spells = { 3599, 1535, 8190, 8227, 8181 } },
	{ slot = 3, key = "water", name = "Water", item = 5177, spells = { 5394, 5675, 8166, 8170, 8184, 16190 } },
	{ slot = 4, key = "air", name = "Air", item = 5178, spells = { 8512, 8835, 8177, 10595, 15107, 6495, 25908 } },
}
ns.TOTEM_SET_NAMES = { "Solo", "Group", "PvP" }

-- One element slot over time. have/start/duration from GetTotemInfo (start/duration nil when hidden).
-- Returns the new state and "killed" when a totem vanished more than a second before its time was up
-- and you didn't destroy it yourself (state.dismissed).
function ns.TotemStep(prev, have, start, duration, now)
	if have then
		local same = prev and start and prev.start == start
		return { start = start, duration = duration, dismissed = same and prev.dismissed or nil }, nil
	end
	-- shortcut: a hidden timer (start/duration nil) never alerts; learn durations if that turns out common
	local killed = prev and prev.start and prev.duration and not prev.dismissed and now < prev.start + prev.duration - 1
	return nil, killed and "killed" or nil
end

-- macro dropping the set's totems in bar order, one per click; restarts after combat or 30s idle
function ns.TotemSetMacro(names)
	if #names == 0 then return nil end
	return "/castsequence reset=combat/30 " .. table.concat(names, ", ")
end

-- elements whose totems you know but whose totem item isn't in your bags
function ns.MissingTotemItems(elements, known, count)
	local missing = {}
	for _, e in ipairs(elements) do
		local knowsOne = false
		for _, id in ipairs(e.spells) do if known(id) then knowsOne = true break end end
		if knowsOne and count(e.item) == 0 then missing[#missing + 1] = e end
	end
	return missing
end

if not CreateFrame then return end -- offline test stops here

local T = ns.Theme
local M = {}
ns.Totems = M
local SHIELD = 324 -- Lightning Shield
local SIZE, GAP = 36, 4

local function S() return ns.db.totems end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Known(id) return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) end
local function SpellName(id) return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or GetSpellInfo(id) end
local function SpellIcon(id) return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or GetSpellTexture(id) end
local function Count(id) return (C_Item and C_Item.GetItemCount or GetItemCount)(id) end
local function ActiveSet() return S().sets[S().set or 1] or {} end

local bar, setButton, shieldButton
local slots, states, missing = {}, {}, {}

local function KnowsAnyTotem()
	for _, e in ipairs(ns.TOTEM_ELEMENTS) do
		for _, id in ipairs(e.spells) do if Known(id) then return true end end
	end
	return false
end

local function Square(b)
	T.Panel(b, { 0, 0, 0, 0.9 }, { 0, 0, 0, 1 })
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b.icon)
	hl:SetColorTexture(1, 1, 1, 0.12)
	b:SetSize(SIZE, SIZE)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function() ns.StartMovingPanel(bar) end)
	b:SetScript("OnDragStop", function() ns.StopMovingPanel(bar) end)
	b:SetScript("OnLeave", GameTooltip_Hide)
end

-- secure attributes: what each click casts (out of combat only)
local function UpdateSecure()
	ns.RunOutOfCombat(function()
		if not bar then return end
		bar:SetShown(S().enabled and KnowsAnyTotem())
		local set, names = ActiveSet(), {}
		for _, b in ipairs(slots) do
			local id = set[b.e.key]
			local name = id and Known(id) and SpellName(id)
			b:SetAttribute("type1", name and "spell" or nil)
			b:SetAttribute("spell1", name or nil)
			if name then names[#names + 1] = name end
		end
		setButton:SetAttribute("type1", "macro")
		setButton:SetAttribute("macrotext1", ns.TotemSetMacro(names))
		shieldButton:SetAttribute("type1", "spell")
		shieldButton:SetAttribute("spell1", SpellName(SHIELD))
		shieldButton:SetShown(Known(SHIELD))
	end)
end

local function UpdateItems()
	wipe(missing)
	for _, e in ipairs(ns.MissingTotemItems(ns.TOTEM_ELEMENTS, Known, Count)) do missing[e.key] = true end
end

-- the Lightning Shield aura, by name (any rank): charges or nil
local function ShieldCharges()
	local name = SpellName(SHIELD)
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not name or not get then return nil end
	for i = 1, 40 do
		local ok, a = pcall(get, "player", i, "HELPFUL")
		if not ok or not a then return nil end
		if not Secret(a.name) and a.name == name then
			return Secret(a.applications) and 0 or (a.applications or 0)
		end
	end
end

local function Update()
	if not bar or not bar:IsShown() then return end
	local now, set = GetTime(), ActiveSet()
	for _, b in ipairs(slots) do
		local e = b.e
		local ok, have, _, start, duration, icon = pcall(GetTotemInfo, e.slot)
		if ok and not Secret(have) then
			if Secret(start) or Secret(duration) then start, duration = nil, nil end
			local event
			states[e.key], event = ns.TotemStep(states[e.key], have, start, duration, now)
			if event == "killed" and not UnitIsDeadOrGhost("player") then
				ns.Notify(("%s totem killed!"):format(e.name), S().sound)
			end
			if have then
				b.icon:SetTexture(icon)
				b.icon:SetDesaturated(false)
				b.icon:SetAlpha(1)
				if start and duration and b.cdStart ~= start then
					b.cd:SetCooldown(start, duration)
					b.cdStart = start
				end
			else
				local id = set[e.key]
				b.icon:SetTexture(id and SpellIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
				b.icon:SetDesaturated(true)
				b.icon:SetAlpha(0.45)
				b.cd:Clear()
				b.cdStart = nil
			end
		end
		b.missing:SetShown(missing[e.key] == true)
	end
	local charges = ShieldCharges()
	shieldButton.count:SetText(charges and charges > 0 and charges or "")
	shieldButton.icon:SetDesaturated(charges == nil)
	shieldButton.icon:SetAlpha(charges and 1 or 0.5)
end
M.Update = Update

function M.Refresh()
	if not bar then return end
	UpdateItems()
	UpdateSecure()
	ns.RunOutOfCombat(function() ns.SetPanelScale(bar, S().scale or 1) end)
	setButton.label:SetText(ns.TOTEM_SET_NAMES[S().set or 1])
	Update()
end

local function MakeSlot(e, i)
	local b = CreateFrame("Button", "DpwsTotem" .. e.name, bar, "SecureActionButtonTemplate")
	Square(b)
	b.e = e
	b:SetPoint("LEFT", i * (SIZE + GAP), 0)
	b:SetAttribute("type2", "destroytotem")
	b:SetAttribute("totem-slot", e.slot)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints(b.icon)
	b.cd:SetDrawEdge(false)
	b.cd:SetReverse(true) -- the dark part grows as the totem runs out
	if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
	b.missing = b:CreateTexture(nil, "OVERLAY")
	b.missing:SetAllPoints(b.icon)
	b.missing:SetColorTexture(0.9, 0.1, 0.1, 0.35)
	b.missing:Hide()
	-- you destroyed it: no "killed" alert
	b:SetScript("PreClick", function(_, mouse)
		if mouse == "RightButton" and states[e.key] then states[e.key].dismissed = true end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local ok, have, name = pcall(GetTotemInfo, e.slot)
		GameTooltip:AddLine(ok and have and not Secret(name) and name or (e.name .. " totem"))
		if missing[e.key] then GameTooltip:AddLine(("%s Totem item missing from your bags!"):format(e.name), 1, 0.3, 0.3) end
		GameTooltip:AddLine("Left-click: drop this set's totem   Right-click: destroy", 0.6, 0.8, 1, true)
		GameTooltip:Show()
	end)
	return b
end

local function OpenSetMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Totem set")
		for i, name in ipairs(ns.TOTEM_SET_NAMES) do
			root:CreateRadio(name, function() return (S().set or 1) == i end, function()
				S().set = i
				if InCombatLockdown() then print("Tinker's Belt: totem set change applies after combat") end
				M.Refresh()
			end)
		end
		root:CreateButton("Edit sets (/tb > Shaman > Totems)", function() ns.ToggleWindow() end)
	end)
end

local function Create()
	local s = S()
	bar = CreateFrame("Frame", "DpwsTotemBar", UIParent)
	bar:SetSize(6 * SIZE + 5 * GAP, SIZE)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:SetScale(s.scale or 1)
	if s.pos then
		bar:SetPoint(s.pos.point, UIParent, s.pos.relPoint, s.pos.x, s.pos.y)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
	end

	setButton = CreateFrame("Button", "DpwsTotemSetButton", bar, "SecureActionButtonTemplate")
	Square(setButton)
	setButton:SetPoint("LEFT")
	setButton.icon:SetTexture("Interface\\Icons\\Spell_Nature_StoneSkinTotem")
	setButton.label = T.Text(setButton, "semibold", 9, T.gold)
	setButton.label:SetPoint("BOTTOM", setButton, "TOP", 0, 2)
	setButton:SetScript("PostClick", function(self, mouse) if mouse == "RightButton" then OpenSetMenu(self) end end)
	setButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Totem set: " .. ns.TOTEM_SET_NAMES[S().set or 1])
		GameTooltip:AddLine("Left-click: drop the next totem of the set (Earth, Fire, Water, Air)", 1, 1, 1, true)
		GameTooltip:AddLine("Right-click: choose a set", 1, 1, 1, true)
		GameTooltip:Show()
	end)

	for i, e in ipairs(ns.TOTEM_ELEMENTS) do slots[i] = MakeSlot(e, i) end

	shieldButton = CreateFrame("Button", "DpwsTotemShield", bar, "SecureActionButtonTemplate")
	Square(shieldButton)
	shieldButton:SetPoint("LEFT", 5 * (SIZE + GAP), 0)
	shieldButton.icon:SetTexture(SpellIcon(SHIELD))
	shieldButton.count = T.Text(shieldButton, "semibold", 14, { 1, 1, 1, 1 })
	shieldButton.count:SetPoint("BOTTOMRIGHT", -2, 2)
	shieldButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(SpellName(SHIELD) or "Lightning Shield")
		GameTooltip:AddLine("Number = charges left. Click to cast.", 1, 1, 1, true)
		GameTooltip:Show()
	end)

	ns.RegisterPanel(bar, "Totems", function(self)
		local point, _, relPoint, x, y = self:GetPoint()
		S().pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	local warned = {}
	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_TOTEM_UPDATE", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED" }) do ev:RegisterEvent(e) end
	ev:RegisterUnitEvent("UNIT_AURA", "player")
	ev:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_DELAYED" or event == "SPELLS_CHANGED" then
			UpdateItems()
			if event == "SPELLS_CHANGED" then UpdateSecure() end
			for key in pairs(missing) do
				if not warned[key] and S().enabled then
					warned[key] = true
					ns.Notify(("%s Totem is not in your bags: its totems can't be dropped"):format(key:gsub("^%l", string.upper)), S().sound)
				end
			end
		end
		Update()
	end)
	C_Timer.NewTicker(0.25, Update)
	M.Refresh()
end

table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "SHAMAN" then return end
	ns.db.totems = ns.db.totems or { enabled = true, sound = true, set = 1, sets = {} }
	for i = 1, #ns.TOTEM_SET_NAMES do ns.db.totems.sets[i] = ns.db.totems.sets[i] or {} end
	ns.RunOutOfCombat(Create)
end)

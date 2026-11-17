local _, ns = ...

-- creature type "Humanoid" in each client language (Sap and Pick Pocket work on humanoids only)
ns.HUMANOID = {
	["Humanoid"] = true, ["Гуманоид"] = true, ["Humanoïde"] = true, ["Humanoide"] = true, ["Umanoide"] = true,
	["인간형"] = true, ["人型生物"] = true, ["人形生物"] = true,
}

-- markers for a nameplate unit while you're stealthed: Sap (humanoid, not fighting), Pick Pocket (humanoid NPC,
-- not fighting, not picked yet). t = { stealthed, attackable, dead, combat, humanoid, player, picked }
-- show = { sap, pick } (nil = both)
function ns.OpenerTags(t, show)
	if not (t.stealthed and t.attackable) or t.dead or t.combat then return {} end
	show = show or { sap = true, pick = true }
	local tags = {}
	if show.sap and t.humanoid then tags[#tags + 1] = "Sap" end
	if show.pick and t.humanoid and not t.player and not t.picked then tags[#tags + 1] = "Pick Pocket" end
	return tags
end

-- macro that equips a weapon set: set = { mh = { name }, oh = { name } }
function ns.WeaponMacro(set)
	local lines = {}
	if set.mh then lines[#lines + 1] = "/equipslot 16 " .. set.mh.name end
	if set.oh then lines[#lines + 1] = "/equipslot 17 " .. set.oh.name end
	return table.concat(lines, "\n")
end

if not CreateFrame then return end -- offline test stops here

-- Opener helper: Sap / Pick Pocket icons above enemy nameplates while stealthed, and two weapon set buttons
-- (e.g. a dagger for Ambush and your swords for the fight).
local T = ns.Theme
local O = {}
ns.Opener = O
local function S() return ns.db.opener end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local SAP, PICK_POCKET = 6770, 921
local function Show() return { sap = S().sap ~= false, pick = S().markers } end
local picked = {} -- GUIDs you picked this session
local lastPick, lastLoss = "none", "none" -- for /tb opener
local keepTarget = false -- your target was just picked: keep its plate marked while it stays your target
local pickTime = 0
-- by name too: Forever may use another rank / id
local function IsPickPocket(id)
	if Secret(id) then return false end
	return id == PICK_POCKET or (id ~= nil and C_Spell.GetSpellName(id) == C_Spell.GetSpellName(PICK_POCKET))
end
local humanCache = {} -- GUID -> humanoid (tooltip scans are slow)

local sets, setButtons = nil, {}
local tagged = {} -- plates showing icons

-- one value at a time: Forever can hide (secret) any of them; nil = couldn't read
local function Read(fn, ...)
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then return nil end
	return v
end

-- creature type hidden: read it from the tooltip ("Level 30 Humanoid"); nil = tooltip unreadable too
local function TooltipHumanoid(unit)
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or not data or not data.lines then return nil end
	local read = false
	for _, l in ipairs(data.lines) do
		local s = l.leftText
		if s and not Secret(s) then
			read = true
			for word in pairs(ns.HUMANOID) do
				if s:find(word, 1, true) then return true end
			end
		end
	end
	if read then return false end
end

local function Stealthed()
	local s = IsStealthed and Read(IsStealthed)
	if s == nil then s = Read(GetShapeshiftForm) == 1 end -- rogue Stealth is stance 1
	return s
end

local function UnitFacts(unit, stealthed)
	local ctype = Read(UnitCreatureType, unit)
	local guid = Read(UnitGUID, unit)
	local humanoid
	if ctype then
		humanoid = ns.HUMANOID[ctype] or false
	elseif guid and humanCache[guid] ~= nil then
		humanoid = humanCache[guid]
	else
		humanoid = TooltipHumanoid(unit)
		if guid and humanoid ~= nil then humanCache[guid] = humanoid end
	end
	return {
		stealthed = stealthed,
		attackable = Read(UnitCanAttack, "player", unit),
		dead = Read(UnitIsDeadOrGhost, unit),
		combat = Read(UnitAffectingCombat, unit),
		humanoid = humanoid ~= false, -- nil = unreadable everywhere: assume it may be humanoid
		tooltip = ctype == nil and humanoid,
		player = Read(UnitIsPlayer, unit),
		picked = guid ~= nil and picked[guid] or false,
		ctype = ctype,
	}
end

-- Forever hides more about "nameplateN" than about the same mob as "target": read a plate that is your
-- target / focus / mouseover through that token
local function BestToken(unit)
	for _, token in ipairs({ "target", "focus", "mouseover" }) do
		if Read(UnitIsUnit, unit, token) then return token end
	end
	return unit
end

-- the nameplate unit showing your target (for /tb opener)
local function TargetPlateUnit()
	for _, u in ipairs(ns.NamePlateUnits()) do
		if Read(UnitIsUnit, u, "target") then return u end
	end
end

local function PlateTag(plate)
	local t = plate.dpwsOpener
	if t then return t end
	t = CreateFrame("Frame", nil, plate)
	t:SetSize(40, 18)
	t:SetPoint("BOTTOM", plate, "TOP", 0, 2)
	t:SetFrameLevel(plate:GetFrameLevel() + 50) -- above the plate's own parts (the target plate is drawn bigger)
	local function Icon(spell)
		local i = t:CreateTexture(nil, "OVERLAY")
		i:SetSize(S().iconSize or 18, S().iconSize or 18)
		i:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		i:SetTexture(C_Spell.GetSpellTexture(spell))
		return i
	end
	t.Sap, t["Pick Pocket"] = Icon(SAP), Icon(PICK_POCKET)
	plate.dpwsOpener = t
	return t
end

local function UpdatePlates()
	if keepTarget then -- the picked target may have a new plate by now
		local plate = Read(C_NamePlate.GetNamePlateForUnit, "target")
		if plate and not plate.dpwsPicked then plate.dpwsPicked = Read(UnitName, "target") or true end
	end
	local seen = {}
	local show = Show()
	local stealthed = (show.sap or show.pick) and Stealthed()
	if stealthed then
		for _, unit in ipairs(ns.NamePlateUnits()) do
			local plate = C_NamePlate.GetNamePlateForUnit(unit)
			local ok, tags = pcall(function()
				local f = UnitFacts(BestToken(unit), true)
				f.picked = f.picked or (plate and plate.dpwsPicked) or false
				return ns.OpenerTags(f, show)
			end)
			if plate and ok and #tags > 0 then
				local t = PlateTag(plate)
				t.Sap:Hide()
				t["Pick Pocket"]:Hide()
				for i, tag in ipairs(tags) do
					local icon = t[tag]
					icon:ClearAllPoints()
					local size = S().iconSize or 18
					t:SetHeight(size) -- grows upward from the plate
					icon:SetSize(size, size)
					icon:SetPoint("CENTER", t, "CENTER", (i - (#tags + 1) / 2) * (size + (S().iconGap or 2)), 0)
					icon:Show()
				end
				t:Show()
				seen[plate] = true
				tagged[plate] = true
			end
		end
	end
	for plate in pairs(tagged) do
		if not seen[plate] then plate.dpwsOpener:Hide(); tagged[plate] = nil end
	end
end

-- /tb opener: what the markers see for your target
ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.opener = function()
	ns.Diagnose(function(Say)
		Say(("opener: markers=%s stealthed=%s plates=%d target=%s"):format(tostring(S().markers), tostring(Stealthed()),
			#ns.NamePlateUnits(), tostring(UnitExists("target"))))
		Say("opener: last Pick Pocket: " .. lastPick)
		Say("opener: last mark lost: " .. lastLoss)
		if UnitExists("target") then
			local t = UnitFacts("target", Stealthed())
			for _, k in ipairs({ "attackable", "dead", "combat", "ctype", "tooltip", "humanoid", "player", "picked" }) do
				Say(("opener: %s=%s"):format(k, tostring(t[k])))
			end
			Say("opener: tags=" .. table.concat(ns.OpenerTags(t, Show()), ", "))
			local plate = Read(C_NamePlate.GetNamePlateForUnit, "target")
			Say(("opener: plate marked picked=%s"):format(tostring(plate and plate.dpwsPicked or false)))
			local pu = TargetPlateUnit()
			if pu then
				local p = UnitFacts(pu, Stealthed())
				Say(("opener: as %s: ctype=%s tooltip=%s humanoid=%s combat=%s attackable=%s tags=%s"):format(pu,
					tostring(p.ctype), tostring(p.tooltip), tostring(p.humanoid), tostring(p.combat), tostring(p.attackable),
					table.concat(ns.OpenerTags(p, Show()), ", ")))
				local t = plate and plate.dpwsOpener
				Say(("opener: icons shown=%s (Sap=%s, Pick Pocket=%s)"):format(tostring(t and t:IsVisible() or false),
					tostring(t and t.Sap:IsShown() or false), tostring(t and t["Pick Pocket"]:IsShown() or false)))
			else
				Say("opener: no nameplate unit matches your target")
			end
		end
	end)
end

---------------------------------------------------------------------------
-- weapon sets

local function ItemOf(slot)
	local id = GetInventoryItemID("player", slot)
	if not id then return nil end
	local name = C_Item.GetItemNameByID(id) or GetItemInfo(id)
	return name and { id = id, name = name } or nil
end

function O.SaveSet(key)
	local s = S()
	s.sets[key] = { mh = ItemOf(16), oh = ItemOf(17) }
	ns.Notify(("Weapon set saved: %s"):format(key == "opener" and "Opener" or "Fight"))
	O.UpdateSets()
end

function O.UpdateSets()
	if not sets then return end
	local s = S()
	local any = false
	for i, key in ipairs({ "opener", "fight" }) do
		local b, set = setButtons[i], s.sets[key]
		local on = set ~= nil and set.mh ~= nil
		any = any or on
		if not InCombatLockdown() then
			b:SetAttribute("macrotext", on and ns.WeaponMacro(set) or "")
			b:SetShown(on or ns.unlocked)
		end
		b.icon:SetTexture(on and C_Item.GetItemIconByID(set.mh.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
		-- teal frame: the set you're wearing
		b.sel:SetShown(on and GetInventoryItemID("player", 16) == set.mh.id
			and (not set.oh or GetInventoryItemID("player", 17) == set.oh.id))
	end
	if not InCombatLockdown() then sets:SetShown(s.weapons and (any or ns.unlocked)) end
end

local function SetButton(i, key, label)
	local b = CreateFrame("Button", "DpwsWeaponSet" .. i, sets, "SecureActionButtonTemplate")
	b:SetSize(32, 32)
	b:SetPoint("LEFT", (i - 1) * 38, 0)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type", "macro")
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetPoint("TOPLEFT", -2, 2)
	b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
	b.sel:SetColorTexture(unpack(T.gold))
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local t = T.Text(b, "semibold", 9, T.muted)
	t:SetPoint("TOP", b, "BOTTOM", 0, -2)
	t:SetText(label)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local set = S().sets[key]
		GameTooltip:AddLine(label .. " weapons")
		if set then
			if set.mh then GameTooltip:AddLine(set.mh.name, 1, 1, 1) end
			if set.oh then GameTooltip:AddLine(set.oh.name, 1, 1, 1) end
		else
			GameTooltip:AddLine("Save it on the Openers page (/tb)", 0.6, 0.65, 0.7)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	setButtons[i] = b
end

local function Place(frame, pos, x, y, name)
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
	end
	ns.RegisterPanel(frame, name, function(self)
		local point, _, relPoint, px, py = self:GetPoint()
		S().setsPos = { point = point, relPoint = relPoint, x = px, y = py }
	end)
end

table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "ROGUE" then return end
	local s = S()
	sets = CreateFrame("Frame", "DpwsWeaponSets", UIParent)
	sets:SetSize(70, 32)
	sets:SetMovable(true)
	sets:SetClampedToScreen(true)
	SetButton(1, "opener", "Opener")
	SetButton(2, "fight", "Fight")
	Place(sets, s.setsPos, -200, -150, "Weapon Sets")

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_TARGET_CHANGED")
	ev:RegisterEvent("LOOT_CLOSED")
	ev:RegisterEvent("UPDATE_STEALTH")
	ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	local gone = {} -- picked plates that just went away: { name, t }
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:SetScript("OnEvent", function(_, event, unit, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if IsPickPocket(spellID) then
				keepTarget, pickTime = true, GetTime()
				lastPick = ("spell=%s mobID=%s name=%s plate=%s"):format(tostring(spellID), tostring(Read(UnitGUID, "target") ~= nil),
					tostring(Read(UnitName, "target") ~= nil),
					tostring(Read(C_NamePlate.GetNamePlateForUnit, "target") ~= nil))
				local guid = Read(UnitGUID, "target")
				if guid then picked[guid] = true end
				-- the mob's ID can be hidden: also mark its plate (cleared when the plate goes away)
				local plate = Read(C_NamePlate.GetNamePlateForUnit, "target")
				if plate then plate.dpwsPicked = Read(UnitName, "target") or true end
			end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			local plate = Read(C_NamePlate.GetNamePlateForUnit, unit)
			-- plates get rebuilt (e.g. during Pick Lock): a plate with the same name back within 5s keeps the mark
			if plate and type(plate.dpwsPicked) == "string" then gone[#gone + 1] = { name = plate.dpwsPicked, t = GetTime() } end
			if plate and plate.dpwsPicked then
				lastLoss = ("plate removed %.1fs after the pick, name kept=%s"):format(GetTime() - pickTime, tostring(type(plate.dpwsPicked) == "string"))
			end
			if plate then plate.dpwsPicked = nil end
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			local plate, name = Read(C_NamePlate.GetNamePlateForUnit, unit), Read(UnitName, unit)
			for i = #gone, 1, -1 do
				local g = gone[i]
				if GetTime() - g.t > 5 then
					table.remove(gone, i)
				elseif plate and name and g.name == name then
					plate.dpwsPicked = name
					table.remove(gone, i)
					break
				end
			end
		elseif event == "PLAYER_TARGET_CHANGED" then
			keepTarget = false
		elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
			O.UpdateSets()
		end
		UpdatePlates()
	end)
	C_Timer.NewTicker(0.25, UpdatePlates) -- plates come and go, mobs enter combat
	C_Timer.NewTicker(2, function() if not InCombatLockdown() then O.UpdateSets() end end)
	O.UpdateSets()
end)

local _, ns = ...

-- "ok" / "low" (under warnSec left) / "missing"; auras = { [name] = expirationTime, 0 = no duration }
function ns.BuffStatus(auras, names, now, warnSec)
	local best
	for _, n in ipairs(names) do
		local exp = auras[n]
		if exp then
			if exp == 0 then return "ok" end
			if not best or exp > best then best = exp end
		end
	end
	if not best then return "missing" end
	local left = best - now
	if left < warnSec then return "low", left end
	return "ok", left
end

-- one-of-a-kind buffs (a paladin's blessings: only one of yours per target): "active" = this one of yours is on
-- them, "low" = it's running out, "other" = a different one of yours is on them, "taken" = another paladin's
-- copy of this one is on them (casting yours would duplicate it), "missing" = none of yours
function ns.ExclusiveStatus(mine, all, names, allNames, now, warnSec)
	local st, left = ns.BuffStatus(mine, names, now, warnSec)
	if st == "ok" then return "active", left end
	if st == "low" then return "low", left end
	if ns.BuffStatus(mine, allNames, now, warnSec) ~= "missing" then return "other" end
	if ns.BuffStatus(all, names, now, 0) ~= "missing" then return "taken" end
	return "missing"
end

-- the spell to cast: the one you used last (e.g. Mage Armor over Ice Armor) if you know it, else the first known
function ns.BuffPickCast(known, remembered)
	for _, n in ipairs(known) do
		if n == remembered then return n end
	end
	return known[1]
end

-- like BuffPickCast, but skipping spells taken(name) says are already on the target; nil if all are
function ns.BuffPickFree(known, remembered, taken)
	if remembered and not taken(remembered) then
		for _, n in ipairs(known) do
			if n == remembered then return n end
		end
	end
	for _, n in ipairs(known) do
		if not taken(n) then return n end
	end
end

-- Per class: cast = spell ids to cast (rank 1; first known is the default), also = ids that count as present
-- (group versions), self = only on yourself, remember = recast the one you last had, reminder = false: not in
-- the reminder (only on the party frame buttons), strip = false: not on the party frame buttons.
local BLESSINGS = {
	{ "might", 19740, 25782 }, { "wisdom", 19742, 25894 }, { "kings", 20217, 25898 },
	{ "salvation", 1038, 25895 }, { "light", 19977, 25890 }, { "sanctuary", 20911, 25899 },
}
-- mine = only your own casts count (another paladin's Might doesn't stop you adding your Wisdom);
-- group = one-of-a-kind with that entry's spells
local paladin = { { key = "blessing", cast = {}, also = {}, remember = true, strip = false, mine = true } }
for _, b in ipairs(BLESSINGS) do
	table.insert(paladin[1].cast, b[2])
	table.insert(paladin[1].also, b[3])
	paladin[#paladin + 1] = { key = b[1], cast = { b[2] }, also = { b[3] }, reminder = false, mine = true, group = "blessing" }
end
-- your aura: Devotion, Retribution, Concentration, Shadow / Frost / Fire Resistance, Sanctity (recasts the last one;
-- only that one; if another paladin already runs it, no reminder)
paladin[#paladin + 1] = { key = "aura", cast = { 465, 7294, 19746, 19876, 19888, 19891, 20218 }, self = true, mine = true, remember = true, only = true }
ns.BUFF_SPELLS = {
	MAGE = {
		{ key = "int", cast = { 1459 }, also = { 23028 } },
		{ key = "armor", cast = { 7302, 168, 6117 }, self = true, remember = true },
	},
	PRIEST = {
		{ key = "fort", cast = { 1243 }, also = { 21562 } },
		{ key = "spirit", cast = { 14752 }, also = { 27681 } },
		{ key = "shadow", cast = { 976 }, also = { 27683 }, off = true },
		{ key = "innerfire", cast = { 588 }, self = true },
	},
	DRUID = {
		{ key = "mark", cast = { 1126 }, also = { 21849 } },
		{ key = "thorns", cast = { 467 }, off = true },
		{ key = "omen", cast = { 16864 }, self = true },
	},
	PALADIN = paladin,
	WARLOCK = { { key = "armor", cast = { 706, 687 }, self = true } },
	SHAMAN = { { key = "shield", cast = { 324 }, self = true } },
	HUNTER = {
		{ key = "aspect", cast = { 13165, 13163, 20043 }, also = { 5118, 13159, 13161 }, self = true, remember = true },
		{ key = "trueshot", cast = { 19506 }, self = true },
	},
}

-- Any unit frame addon (ElvUI, Cell, Grid2, VuhDo, Shadowed Unit Frames...) marks its frames with a "unit"
-- attribute. From all frames (nextFrame(prev) walks them, like EnumerateFrames), pick the biggest visible
-- one showing exactly this unit (exact token: no target/focus/nameplate frames that happen to show them).
function ns.PickUnitFrame(nextFrame, unit)
	local best, bestArea = nil, 0
	local f = nextFrame()
	while f do
		local ok, u, area = pcall(function()
			if f.dpwsNotUnitFrame or f:IsForbidden() or not f:IsVisible() then return end
			return f:GetAttribute("unit"), f:GetWidth() * f:GetHeight()
		end)
		-- at least ~30x20: skips small buttons other addons tag with a unit
		if ok and u == unit and area >= 600 and area > bestArea then best, bestArea = f, area end
		f = nextFrame(f)
	end
	return best
end

if not CreateFrame then return end -- offline test stops here

-- Buff Reminder: buttons for your buffs that are missing (or about to run out) on you or your group;
-- click = cast on the next one who needs it. Plus buff buttons beside each party frame.
-- Clickable buttons can't change in combat, so both update out of combat only (icons still dim in combat).

local T = ns.Theme
local B = { entries = {} }
ns.Buffs = B
local function S() return ns.db.buffs end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function SpellName(id)
	return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
end
local function SpellIcon(spell)
	return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell)) or (GetSpellTexture and GetSpellTexture(spell))
end
local function Known(id)
	return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id))
end

-- this character's buffs: { def, known = {names}, names = {names that count} }
local function LoadSpells()
	local list = {}
	for _, def in ipairs(ns.BUFF_SPELLS[select(2, UnitClass("player"))] or {}) do
		local known, names = {}, {}
		for _, id in ipairs(def.cast) do
			local n = SpellName(id)
			if n then
				names[#names + 1] = n
				if Known(id) then known[#known + 1] = n end
			end
		end
		for _, id in ipairs(def.also or {}) do
			local n = SpellName(id)
			if n then names[#names + 1] = n end
		end
		if #known > 0 then list[#list + 1] = { def = def, known = known, names = names } end
	end
	-- your own extra buffs (Buffs page): reminded on you only
	for id in pairs(S().custom) do
		local n = SpellName(id)
		if n then list[#list + 1] = { def = { key = "custom" .. id, self = true, custom = true }, known = { n }, names = { n } } end
	end
	B.entries = list
	B.byKey, B.byCast = {}, {}
	for _, e in ipairs(list) do
		B.byKey[e.def.key] = e
		if e.def.group then B.byCast[e.known[1]] = e end -- e.g. Blessing of Might -> its entry (with Greater)
	end
end

local function CastName(e) return ns.BuffPickCast(e.known, S().last[e.def.key]) end
local function Reminded(e)
	local off = S().off[e.def.key]
	if off == nil then off = e.def.off end
	return e.def.reminder ~= false and not off
end

-- { all = { [name] = expirationTime }, mine = (only those you cast) } or nil when the game hides them (combat)
local function Auras(unit)
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if not get then return nil end
	local map, mine = {}, {}
	for i = 1, 40 do
		local ok, a = pcall(get, unit, i, "HELPFUL")
		if not ok then return nil end
		if not a then break end
		if Secret(a.name) or Secret(a.expirationTime) then return nil end
		map[a.name] = a.expirationTime or 0
		local src = a.sourceUnit
		if src and not Secret(src) and UnitIsUnit(src, "player") then mine[a.name] = a.expirationTime or 0 end
	end
	return { all = map, mine = mine }
end
local function Pick(e, auras) return e.def.mine and auras.mine or auras.all end
-- a group member's name (key for the blessing you give them)
local function Who(unit)
	local n = GetUnitName(unit, true)
	if n and not Secret(n) then return n end
end
-- the blessing remembered for unit, unless another paladin's copy of it is on them now
local function Chosen(unit, auras)
	local who = Who(unit)
	local n = who and S().lastOn[who]
	local single = n and B.byCast[n]
	if not single then return nil end
	if auras and ns.BuffStatus(auras.all, single.names, GetTime(), 0) ~= "missing"
		and ns.BuffStatus(auras.mine, single.names, GetTime(), 0) == "missing" then return nil end
	return n
end

local function GroupUnits()
	local units = { "player" }
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if UnitExists(u) and not UnitIsUnit(u, "player") then units[#units + 1] = u end
		end
	else
		for i = 1, 4 do
			if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end
		end
	end
	return units
end

-- friendly players near you who aren't in your group (seen through friendly nameplates). PvP-flagged ones
-- are skipped while you aren't flagged: buffing them would flag you.
local function NearbyUnits()
	local units = {}
	if S().nearby == false then return units end
	local flagged = UnitIsPVP("player")
	for _, u in ipairs(ns.NamePlateUnits()) do
		local ok, yes = pcall(function()
			return UnitIsPlayer(u) and UnitIsFriend("player", u) and not UnitIsUnit(u, "player")
				and not UnitInParty(u) and not UnitInRaid(u) and (flagged or not UnitIsPVP(u))
		end)
		if ok and yes == true then units[#units + 1] = u end
	end
	return units
end


local function Reachable(unit, spell)
	if unit == "player" then return true end
	if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) or not UnitIsVisible(unit) then return false end
	local ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
	return ok and (r == true or r == 1)
end

---------------------------------------------------------------------------
-- reminder panel

local panel, buttons = nil, {}
local SIZE = 36
local wasMissing = {} -- self buffs missing at the last scan (for the "dropped" warning)

local function ReminderButton(i)
	local b = CreateFrame("Button", "DpwsBuffReminder" .. i, panel, "SecureActionButtonTemplate")
	b.dpwsNotUnitFrame = true -- has a unit attribute, but isn't a unit frame
	b:SetSize(SIZE, SIZE)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type", "spell")
	b:SetAttribute("shift-type1", "") -- Shift+drag moves the panel: don't cast on that click
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function()
		ns.StartMovingPanel(panel, IsShiftKeyDown())
	end)
	b:SetScript("OnDragStop", function() ns.StopMovingPanel(panel) end)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b.count = T.Text(b, "semibold", 14, { 1, 1, 1, 1 })
	b.count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.count:SetShadowColor(0, 0, 0, 1)
	b.count:SetShadowOffset(1, -1)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.spell or "")
		for _, u in ipairs(self.needy or {}) do
			local _, class = UnitClass(u)
			local c = RAID_CLASS_COLORS[class] or NORMAL_FONT_COLOR
			GameTooltip:AddLine(GetUnitName(u, true) or u, c.r, c.g, c.b)
		end
		GameTooltip:AddLine("Click: buff the first one", 0.6, 0.65, 0.7)
		GameTooltip:AddLine("Shift+drag: move", 0.6, 0.65, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

---------------------------------------------------------------------------
-- buttons beside party frames

-- the unit frame shown for unit: DandersFrames, Blizzard compact party frames, Blizzard party frames,
-- any other frame addon, then the Blizzard player frame
local found, lastScan = {}, {} -- unit -> frame from the search of all frames; unit -> time of that search
local function FindFrame(unit)
	local function Match(f, u)
		return f and u and f:IsVisible() and not Secret(u) and UnitExists(u) and UnitIsUnit(u, unit)
	end
	local headers = { "DandersPartyHeader", "DandersFlatRaidHeader" }
	for g = 1, 8 do headers[#headers + 1] = "DandersRaidGroup" .. g .. "Header" end
	for _, name in ipairs(headers) do
		local header = _G[name]
		if header and header:IsVisible() then
			for _, child in ipairs({ header:GetChildren() }) do
				if child.GetAttribute and Match(child, child:GetAttribute("unit")) then return child end
			end
		end
	end
	for i = 1, 5 do
		local f = _G["CompactPartyFrameMember" .. i]
		if f and Match(f, f.unit) then return f end
	end
	if PartyFrame then
		for i = 1, 4 do
			local f = PartyFrame["MemberFrame" .. i]
			if f and Match(f, f.unit) then return f end
		end
	end
	-- other frame addons: the last frame found, or a search of all frames (at most every 5s per unit)
	local cached = found[unit]
	if cached and cached:IsVisible() and cached:GetAttribute("unit") == unit then return cached end
	local now = GetTime()
	if (lastScan[unit] or 0) < now - 5 then
		lastScan[unit] = now
		found[unit] = ns.PickUnitFrame(EnumerateFrames, unit)
		if found[unit] then return found[unit] end
	end
	if unit == "player" and PlayerFrame and PlayerFrame:IsVisible() then return PlayerFrame end
end

local STRIP_UNITS = { "player", "party1", "party2", "party3", "party4" }
local strips = {}

-- right-click a blessing button: a row of blessing icons to pick this member's blessing (last = "show all")
local picker
function B.ShowPicker(owner, who, spells)
	local SZ = 28
	if not picker then
		picker = CreateFrame("Frame", "DpwsBlessingPicker", UIParent)
		picker:SetFrameStrata("DIALOG")
		picker:EnableMouse(true)
		T.Box(picker, T.window, T.border, 6)
		picker.title = T.Text(picker, "semibold", 11, T.gold)
		picker.title:SetPoint("TOPLEFT", 8, -6)
		picker.icons = {}
		tinsert(UISpecialFrames, "DpwsBlessingPicker") -- Esc closes
		-- closes once the mouse has been away from it for a moment
		picker:SetScript("OnUpdate", function(self, dt)
			if self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) then
				self.away = 0
			else
				self.away = (self.away or 0) + dt
				if self.away > 0.8 then self:Hide() end
			end
		end)
	end
	picker.owner, picker.away = owner, 0
	picker.title:SetText(who)
	local list = {}
	for _, n in ipairs(spells) do list[#list + 1] = n end
	list[#list + 1] = false -- show all
	for i, n in ipairs(list) do
		local b = picker.icons[i]
		if not b then
			b = CreateFrame("Button", nil, picker)
			b:SetSize(SZ, SZ)
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetAllPoints()
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			b.sel = b:CreateTexture(nil, "BACKGROUND")
			b.sel:SetPoint("TOPLEFT", -2, 2)
			b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
			b.sel:SetColorTexture(unpack(T.gold))
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(self.spell or "Show all blessings")
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", GameTooltip_Hide)
			picker.icons[i] = b
		end
		b.spell = n or nil
		b.icon:SetTexture(n and SpellIcon(n) or "Interface\\Icons\\INV_Misc_QuestionMark")
		b.sel:SetShown(S().lastOn[who] == b.spell)
		b:SetPoint("TOPLEFT", 8 + (i - 1) * (SZ + 6), -22)
		b:SetScript("OnClick", function()
			S().lastOn[who] = b.spell
			picker:Hide()
			B.Update()
		end)
		b:Show()
	end
	for i = #list + 1, #picker.icons do picker.icons[i]:Hide() end
	picker:SetSize(16 + #list * (SZ + 6) - 6, SZ + 30)
	picker:ClearAllPoints()
	picker:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -4, 4)
	picker:Show()
end

local function StripButton(strip, i)
	local b = CreateFrame("Button", nil, strip, "SecureActionButtonTemplate")
	b.dpwsNotUnitFrame = true
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type1", "spell") -- left only: right-click picks this member's blessing
	b:SetAttribute("unit", strip.unit)
	b:HookScript("OnClick", function(self, button)
		local e = self.entry
		if button ~= "RightButton" or not (e and e.def.group) or InCombatLockdown() then return end
		local who, group = Who(strip.unit), B.byKey[e.def.group]
		if not (who and group) then return end
		B.ShowPicker(self, who, group.known)
	end)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", -1, 1)
	b.border:SetPoint("BOTTOMRIGHT", 1, -1)
	b.border:SetColorTexture(1, 0.25, 0.2, 1)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b.time = T.Text(b, "semibold", 10, { 1, 0.85, 0.3, 1 })
	b.time:SetPoint("BOTTOM", 0, 1)
	b.time:SetShadowColor(0, 0, 0, 1)
	b.time:SetShadowOffset(1, -1)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.spell or "")
		GameTooltip:AddLine("Click: cast on " .. (GetUnitName(strip.unit, true) or strip.unit), 1, 1, 1)
		if self.entry and self.entry.def.group then GameTooltip:AddLine("Right-click: choose their blessing", 1, 1, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function GetStrip(unit)
	if strips[unit] then return strips[unit] end
	local s = CreateFrame("Frame", nil, UIParent)
	s:SetFrameStrata("LOW") -- re-layered onto its party frame when anchored
	s:SetSize(1, 1)
	s.unit = unit
	s.buttons = {}
	strips[unit] = s
	return s
end

-- dim = buff is on (blessings: a different one of yours is on), red border = missing, minutes = running out;
-- (a blessing you chose for a member stays visible, dim while up)
local function Paint(b, status, left)
	local dim = status == "ok" or status == "other" or status == "active"
	b.icon:SetDesaturated(dim)
	b.icon:SetAlpha(dim and 0.35 or 1)
	b.border:SetShown(status == "missing")
	b.time:SetText(status == "low" and left and ("%dm"):format(math.ceil(left / 60)) or "")
end

local function UpdateStrips(auraCache, combat)
	local s = S()
	local show = s.enabled and s.strips and not IsInRaid() -- solo too: your own frame
	local warn = (s.warn or 3) * 60
	local size = s.size or 18
	for _, unit in ipairs(STRIP_UNITS) do
		local strip = GetStrip(unit)
		local frame = show and UnitExists(unit) and FindFrame(unit)
		if not combat then
			strip:SetShown(frame and true or false)
			if frame then
				strip:ClearAllPoints()
				strip:SetPoint("LEFT", frame, "RIGHT", 4, 0)
				-- same layer as the party frame: game windows (talents, mail) cover it like they cover the frame
				strip:SetFrameStrata(frame:GetFrameStrata())
				strip:SetFrameLevel(frame:GetFrameLevel() + 5)
			end
		end
		if strip:IsShown() then
			local auras = auraCache[unit] or Auras(unit)
			local chosen = Chosen(unit, auras)
			local x = 0
			for k, e in ipairs(B.entries) do
				local b = strip.buttons[k] -- one button per buff, kept in place
				local wanted = e.def.strip ~= false and (unit == "player" or not e.def.self)
				local status, left
				if wanted and auras then
					local group = e.def.group and B.byKey[e.def.group]
					if group then
						status, left = ns.ExclusiveStatus(auras.mine, auras.all, e.names, group.names, GetTime(), warn)
					else
						status, left = ns.BuffStatus(Pick(e, auras), e.names, GetTime(), warn)
					end
				end
				-- a blessing of yours is up on them: no blessing buttons until it runs low
				local hide = status == "active" or status == "other" or status == "taken" -- taken: another paladin's copy is on them
				-- the blessing you give this member: only its button, always there (dim while up) to right-click
				if e.def.group and chosen then hide = e.known[1] ~= chosen end
				if not combat then -- (buttons can't be created, shown or hidden in combat)
					if wanted and not hide then
						b = b or StripButton(strip, k)
						strip.buttons[k] = b
						b.spell, b.entry = CastName(e), e
						b:SetAttribute("spell", b.spell)
						b:SetSize(size, size)
						b:ClearAllPoints()
						b:SetPoint("LEFT", strip, "LEFT", x * (size + 2), 0)
						b:Show()
						x = x + 1
					elseif b then
						b:Hide()
					end
				end
				if b and b:IsShown() then
					b.icon:SetTexture(SpellIcon(b.spell or CastName(e)))
					if status then Paint(b, status, left) end
				end
			end
			if not combat then
				for k, b in pairs(strip.buttons) do
					if k > #B.entries then b:Hide() end
				end
			end
		end
	end
end

---------------------------------------------------------------------------

local function Update()
	if not panel then return end
	local s = S()
	local combat = InCombatLockdown()
	local warn = (s.warn or 3) * 60
	local auraCache = {}
	local units = GroupUnits()
	for _, u in ipairs(units) do auraCache[u] = Auras(u) end
	-- needing a buff: your group first, then nearby players (the button casts on the first in the list)
	local targets = {}
	for _, u in ipairs(units) do targets[#targets + 1] = u end
	for _, u in ipairs(NearbyUnits()) do
		targets[#targets + 1] = u
		auraCache[u] = Auras(u) -- nil when the game hides them: that player is skipped
	end

	-- remember which armor/aspect/blessing you use
	local mine = auraCache.player
	if mine then
		for _, e in ipairs(B.entries) do
			if e.def.remember then
				for _, n in ipairs(e.known) do
					if Pick(e, mine)[n] then s.last[e.def.key] = n end
				end
			end
		end
	end
	-- and which blessing you give each member (the last one of yours seen on them)
	for _, u in ipairs(units) do
		local auras, who = auraCache[u], Who(u)
		if auras and who then
			for _, e in ipairs(B.entries) do
				if e.def.group and ns.BuffStatus(auras.mine, e.names, GetTime(), 0) ~= "missing" then
					s.lastOn[who] = e.known[1]
				end
			end
		end
	end

	-- who needs what
	local needs, selfMissing = {}, {}
	if s.enabled then
		for _, e in ipairs(B.entries) do
			if Reminded(e) then
				local spell, list, first = CastName(e), {}, nil
				for _, u in ipairs(targets) do
					local auras = auraCache[u]
					if auras and (u == "player" or not e.def.self) then
						local st = ns.BuffStatus(Pick(e, auras), e.names, GetTime(), warn)
						local cast = spell
						if e.def.mine and e.def.remember then
							-- blessings / auras: skip ones another paladin already has on them (yours would duplicate it)
							local remembered = (e.def.key == "blessing" and Chosen(u, auras)) or S().last[e.def.key]
							-- (only = just the last one you used, never a different one)
							local candidates = (e.def.only and remembered) and { ns.BuffPickCast(e.known, remembered) } or e.known
							cast = ns.BuffPickFree(candidates, remembered, function(n)
								local single = B.byCast[n]
								local names = single and single.names or { n }
								return ns.BuffStatus(auras.all, names, GetTime(), 0) ~= "missing"
									and ns.BuffStatus(auras.mine, names, GetTime(), 0) == "missing"
							end)
						end
						if st ~= "ok" and cast and Reachable(u, cast) then
							list[#list + 1] = u
							first = first or cast
						end
						if u == "player" and st == "missing" then selfMissing[#selfMissing + 1] = spell end
					end
				end
				if #list > 0 then needs[#needs + 1] = { spell = first, units = list } end
			end
		end
		if mine then
			-- a buff that just dropped off you
			for _, spell in ipairs(selfMissing) do
				if wasMissing[spell] == false then ns.Notify(spell .. " is gone", s.sound) end
			end
			local now = {}
			for _, e in ipairs(B.entries) do
				if Reminded(e) then now[CastName(e)] = false end
			end
			for _, spell in ipairs(selfMissing) do now[spell] = true end
			wasMissing = now
		end
	end
	B.selfMissing = selfMissing

	UpdateStrips(auraCache, combat)
	if combat then return end -- clickable buttons are frozen in combat

	for i, need in ipairs(needs) do
		local b = buttons[i] or ReminderButton(i)
		buttons[i] = b
		b.spell, b.needy = need.spell, need.units
		local unit = need.units[1]
		-- the game ignores casts on nameplate units from addon buttons (nearby players outside your group):
		-- target them by full name (two words on Forever), cast, then go back to your target
		local ok, full = pcall(GetUnitName, unit, true)
		if unit:find("^nameplate") and ok and full and not (issecretvalue and issecretvalue(full)) then
			b:SetAttribute("type", "macro")
			b:SetAttribute("macrotext", ("/targetexact %s\n/cast %s\n/targetlasttarget"):format(full, need.spell))
		else
			b:SetAttribute("type", "spell")
			b:SetAttribute("spell", need.spell)
			b:SetAttribute("unit", unit)
		end
		b.icon:SetTexture(SpellIcon(need.spell))
		b.count:SetText(#need.units > 1 and #need.units or "")
		b:ClearAllPoints()
		b:SetPoint("LEFT", panel, "LEFT", (i - 1) * (SIZE + 4), 0)
		b:Show()
	end
	for i = #needs + 1, #buttons do buttons[i]:Hide() end
	panel:SetWidth(math.max(#needs, 1) * (SIZE + 4))
	panel:SetShown(#needs > 0 or ns.unlocked)
end
-- keep the last error for /tb buffs (it still reaches BugSack)
local function SafeUpdate()
	xpcall(Update, function(err)
		B.lastError = tostring(err) .. "\n" .. (debugstack and debugstack(2, 6, 0) or "")
		geterrorhandler()(err)
	end)
end
B.Update = SafeUpdate
function B.Reload() ns.RunOutOfCombat(function() LoadSpells(); SafeUpdate() end) end

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands["buffs"] = function()
	ns.Diagnose(function(Say)
		local s = S()
		Say(("class=%s enabled=%s strips=%s inGroup=%s inRaid=%s combat=%s"):format(select(2, UnitClass("player")),
			tostring(s.enabled), tostring(s.strips), tostring(IsInGroup()), tostring(IsInRaid()), tostring(InCombatLockdown())))
		local names = {}
		for _, e in ipairs(B.entries) do names[#names + 1] = e.def.key .. "=" .. table.concat(e.known, "/") end
		Say("version: fixed font, last error: " .. (B.lastError or "none"))
		Say("buffs known: " .. (#names > 0 and table.concat(names, ", ") or "NONE"))
		for _, unit in ipairs(STRIP_UNITS) do
			if UnitExists(unit) then
				local f = FindFrame(unit)
				local strip = strips[unit]
				local shown = 0
				for _, b in pairs(strip and strip.buttons or {}) do if b:IsShown() then shown = shown + 1 end end
				Say(("%s %s: frame=%s strip=%s buttons=%d auras=%s"):format(unit, GetUnitName(unit, true) or "?",
					f and (f:GetName() or "unnamed") or "NOT FOUND", tostring(strip and strip:IsVisible()), shown,
					Auras(unit) and "ok" or "hidden"))
			end
		end
		for _, name in ipairs({ "DandersPartyHeader", "DandersFlatRaidHeader", "CompactPartyFrame", "PartyFrame" }) do
			local h = _G[name]
			if h then
				local kids = {}
				for _, c in ipairs({ h:GetChildren() }) do
					local u = c.GetAttribute and c:GetAttribute("unit")
					if u then kids[#kids + 1] = (c:GetName() or "?") .. "=" .. tostring(u) .. (c:IsVisible() and "" or "(hidden)") end
				end
				Say(("%s shown=%s units: %s"):format(name, tostring(h:IsVisible()), table.concat(kids, " ")))
			end
		end
	end)
end

table.insert(ns.loginHooks, function()
	local s = S()
	panel = CreateFrame("Frame", "DpwsBuffReminder", UIParent)
	panel:SetSize(SIZE, SIZE)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	if s.pos then
		panel:SetPoint(s.pos.point, UIParent, s.pos.relPoint, s.pos.x, s.pos.y)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
	end
	ns.RegisterPanel(panel, "Buff Reminder", function(self)
		local point, _, relPoint, px, py = self:GetPoint()
		s.pos = { point = point, relPoint = relPoint, x = px, y = py }
	end)
	panel:Hide()
	LoadSpells()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("SPELLS_CHANGED")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:SetScript("OnEvent", function(_, event)
		if event == "SPELLS_CHANGED" then
			B.Reload()
		elseif s.enabled and B.selfMissing and #B.selfMissing > 0 then
			ns.Notify("Entering combat without " .. table.concat(B.selfMissing, ", "), s.sound)
		end
	end)
	C_Timer.NewTicker(1, SafeUpdate)
	Update()
end)

local _, ns = ...

-- Distance band from the checks the game allows: exact yards (group members only), trade range (~10),
-- follow/inspect range (~28), the class buff's range (~40); otherwise just "seen by nameplate".
function ns.AllyRange(c)
	if c.yards then return c.yards end
	if c.trade then return 10 end
	if c.follow then return 28 end
	if c.spell then return 40 end
	return 100
end

function ns.AllyRangeText(range)
	if range >= 100 then return "far" end
	return ("%dy"):format(math.floor(range + 0.5))
end

-- closest first, then by name
function ns.AlliesSort(list)
	table.sort(list, function(a, b)
		if a.range ~= b.range then return a.range < b.range end
		return a.name < b.name
	end)
end

if not CreateFrame then return end -- offline test stops here

-- Nearby Allies list: friendly players seen through (invisible) friendly nameplates, closest first.
-- Left-click a row = target, right-click = cast your class buff on them; + = invite.
-- Rows are secure buttons, which can't change in combat: the list freezes during combat.

local T = ns.Theme
local L = {}
ns.AlliesList = L
local function S() return ns.db.alliesList end
local function Secret(v) return issecretvalue and issecretvalue(v) end

-- your class's main buff (rank 1 id; casting by name uses your highest rank)
local BUFFS = { MAGE = 1459, PRIEST = 1243, DRUID = 1126, PALADIN = 19740 }
local function BuffName()
	local id = BUFFS[select(2, UnitClass("player"))]
	if not id then return nil end
	if IsPlayerSpell and not IsPlayerSpell(id) and not (IsSpellKnown and IsSpellKnown(id)) then return nil end
	return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
end

local function Check(fn, ...)
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then return nil end
	return v
end

local function Collect()
	local list, myGuild = {}, GetGuildInfo("player")
	local buff = BuffName()
	for _, unit in ipairs(ns.NamePlateUnits()) do
		pcall(function() -- a plate whose values are hidden from addons is skipped
			if not (UnitIsPlayer(unit) and UnitIsFriend("player", unit)) or UnitIsUnit(unit, "player") then return end
			local name = UnitName(unit) -- first name: what /targetexact needs
			local full = GetUnitName(unit, true)
			local _, class = UnitClass(unit)
			if Secret(name) or Secret(full) or Secret(class) then return end
			local guild = GetGuildInfo(unit)
			local d2 = UnitDistanceSquared and Check(UnitDistanceSquared, unit)
			local c = {
				yards = (type(d2) == "number" and d2 > 0) and math.sqrt(d2) or nil,
				trade = CheckInteractDistance and Check(CheckInteractDistance, unit, 2),
				follow = CheckInteractDistance and Check(CheckInteractDistance, unit, 4),
				spell = buff and C_Spell and C_Spell.IsSpellInRange and Check(C_Spell.IsSpellInRange, buff, unit),
			}
			local guid = UnitGUID(unit)
			list[#list + 1] = {
				unit = unit, name = name, full = full, class = class, level = UnitLevel(unit),
				guild = guild, sameGuild = guild and myGuild and guild == myGuild,
				friend = guid and not Secret(guid) and C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid),
				grouped = UnitInParty(unit) or UnitInRaid(unit),
				range = ns.AllyRange(c),
			}
		end)
	end
	ns.AlliesSort(list)
	return list
end

local function CanInvite()
	if not IsInGroup() then return true end
	return (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and GetNumGroupMembers() < (IsInRaid() and 40 or 5)
end

local frame, title, rows = nil, nil, {}
local PARTY_BG = { 0.25, 0.38, 0.85, 0.45 } -- party-chat blue
local ROW_H, WIDTH = 22, 250

local function MakeRow(i)
	local r = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
	r:SetSize(WIDTH - 36, ROW_H)
	r:SetPoint("TOPLEFT", 30, -28 - (i - 1) * (ROW_H + 2))
	r:RegisterForClicks("AnyUp")
	r:SetAttribute("useOnKeyDown", false)
	r.bg = T.Rounded(r, T.row, 4, "BACKGROUND", 0)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	r.name = T.Text(r, "medium", 12)
	r.name:SetPoint("LEFT", 6, 0)
	r.name:SetWidth(WIDTH - 110)
	r.name:SetWordWrap(false)
	r.tags = T.Text(r, "semibold", 11)
	r.tags:SetPoint("LEFT", r.name, "RIGHT", 2, 0)
	r.range = T.Text(r, "regular", 11, T.muted)
	r.range:SetPoint("RIGHT", -6, 0)
	-- invite: a plain button left of the row (outside the secure row)
	r.invite = T.NewButton(frame, "+", 20, 20)
	r.invite:SetPoint("RIGHT", r, "LEFT", -4, 0)
	r:SetScript("OnEnter", function(self)
		if not self.entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.entry.full)
		if self.entry.guild then GameTooltip:AddLine("<" .. self.entry.guild .. ">", 0.8, 0.82, 0.86) end
		GameTooltip:AddLine("Left-click: target", 1, 1, 1)
		if BuffName() then GameTooltip:AddLine("Right-click: " .. BuffName(), 1, 1, 1) end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)
	-- /tb allies click: log every step of a click on a row
	local function Log(step, mouse)
		if not L.debug then return end
		local unit = r:GetAttribute("unit")
		print(("allies click: row %d %s %s type1=%s type2=%s unit=%s exists=%s name=%s target=%s"):format(i, step,
			tostring(mouse), tostring(r:GetAttribute("type1")), tostring(r:GetAttribute("type2")), tostring(unit),
			tostring(unit and UnitExists(unit)), tostring(unit and UnitName(unit)), tostring(UnitName("target"))))
	end
	r:HookScript("OnMouseDown", function(_, mouse) Log("mousedown", mouse) end)
	r:HookScript("OnMouseUp", function(_, mouse) Log("mouseup", mouse) end)
	r:SetScript("PreClick", function(_, mouse) Log("preclick", mouse) end)
	r:SetScript("PostClick", function(_, mouse) Log("postclick", mouse) end)
	return r
end

local function Update()
	if not frame then return end
	local s = S()
	local show = s.enabled and ns.adb.allies.enabled and not IsInInstance()
	if InCombatLockdown() then
		title:SetText("Nearby allies  |cff8c96a3(paused in combat)|r")
		return -- secure rows can't change in combat
	end
	frame:SetShown(show or ns.unlocked)
	if not (show or ns.unlocked) then return end
	local list = Collect()
	local buff = BuffName()
	local n = math.min(#list, s.rows or 10)
	title:SetText(("Nearby allies  |cff8c96a3%d|r"):format(#list))
	for i = 1, (s.rows or 10) do
		local r = rows[i] or MakeRow(i)
		rows[i] = r
		local e = list[i]
		r.entry = e
		if e then
			local color = RAID_CLASS_COLORS[e.class]
			local lvl = (e.level and not Secret(e.level) and e.level > 0) and e.level or "??"
			r.name:SetText(("|cff8c96a3%s|r %s"):format(lvl, e.full))
			if color then r.name:SetTextColor(color.r, color.g, color.b) end
			r.tags:SetText((e.friend and "|cff6dcfc4<3|r " or "") .. (e.sameGuild and "|cff4dcc66G|r" or ""))
			r.range:SetText(ns.AllyRangeText(e.range))
			r.bg:SetColor(e.grouped and PARTY_BG or T.row) -- your party / raid stands out
			-- by the player's nameplate unit, not by name (/targetexact missed some names); the list
			-- refreshes every second, so the token still points at this player when clicked
			r:SetAttribute("unit", e.unit)
			r:SetAttribute("type1", "target")
			r:SetAttribute("type2", buff and "spell" or nil)
			r:SetAttribute("spell2", buff)
			r.invite:SetShown(not e.grouped and CanInvite())
			r.invite:SetScript("OnClick", function()
				(C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit)(e.full)
			end)
			r:Show()
		else
			r:Hide()
			r.invite:Hide()
		end
	end
	for i = (s.rows or 10) + 1, #rows do rows[i]:Hide(); rows[i].invite:Hide() end
	frame:SetHeight(32 + math.max(n, 1) * (ROW_H + 2))
end
L.Update = Update

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands["allies click"] = function()
	L.debug = not L.debug
	ns.Diagnose(function(Say)
		Say("allies click: logging " .. (L.debug and "ON - now click a row (left and right), then send what chat shows" or "OFF"))
		if not frame then return Say("allies click: list not created") end
		Say(("allies click: list shown=%s strata=%s level=%s mouse=%s unlocked=%s combat=%s"):format(tostring(frame:IsShown()),
			frame:GetFrameStrata(), frame:GetFrameLevel(), tostring(frame:IsMouseEnabled()), tostring(ns.unlocked), tostring(InCombatLockdown())))
		Say(("allies click: ActionButtonUseKeyDown=%s"):format(tostring(GetCVar and GetCVar("ActionButtonUseKeyDown"))))
		for i, r in ipairs(rows) do
			if r:IsShown() then
				local unit = r:GetAttribute("unit")
				Say(("allies click: row %d level=%s mouse=%s unit=%s exists=%s name=%s"):format(i, r:GetFrameLevel(),
					tostring(r:IsMouseEnabled()), tostring(unit), tostring(unit and UnitExists(unit)), tostring(unit and UnitName(unit))))
			end
		end
	end)
	-- for 10 seconds: print what's under the mouse whenever it changes (hover a row now)
	if L.debug then
		local last
		C_Timer.NewTicker(0.5, function()
			local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
			local names = {}
			for _, fr in ipairs(foci) do
				local ok, n = pcall(function() return fr:GetDebugName() end)
				names[#names + 1] = ok and n or tostring(fr)
			end
			local text = table.concat(names, " | ")
			if text ~= last then
				last = text
				print("allies click: under mouse: " .. text)
			end
		end, 20)
	end
end

table.insert(ns.loginHooks, function()
	local s = S()
	frame = CreateFrame("Frame", "DpwsAlliesList", UIParent)
	frame:SetSize(WIDTH, 60)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	T.Box(frame, { 0.047, 0.054, 0.066, 0.92 }, T.border, 8)
	title = T.Text(frame, "semibold", 12, T.gold)
	title:SetPoint("TOPLEFT", 10, -8)
	local close = CreateFrame("Button", nil, frame)
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", -6, -5)
	local x = T.Text(close, "semibold", 12, T.muted)
	x:SetPoint("CENTER")
	x:SetText("x")
	close:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		s.enabled = false
		frame:Hide()
	end)
	if s.pos then
		frame:SetPoint(s.pos.point, UIParent, s.pos.relPoint, s.pos.x, s.pos.y)
	else
		frame:SetPoint("LEFT", UIParent, "LEFT", 20, 120)
	end
	ns.RegisterPanel(frame, "Nearby Allies", function(self)
		local point, _, relPoint, px, py = self:GetPoint()
		s.pos = { point = point, relPoint = relPoint, x = px, y = py }
	end)
	frame:Hide()
	C_Timer.NewTicker(1, Update)
	Update()
end)

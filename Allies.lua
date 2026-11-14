local _, ns = ...

-- Friendly Names: the game's friendly player nameplates are turned on (Forever's only signal that a
-- friendly player is near, the combat log is closed) but drawn invisible; our own label shows the name
-- in class colour and the guild. Turning it off restores the player's own nameplate setting.

local CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" }
local A = {}
ns.Allies = A
A.seen = {} -- name -> { class, level, guild, at }: for features built on top

local function S() return ns.adb.allies end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function GetCV(name) return (C_CVar and C_CVar.GetCVar or GetCVar)(name) end
local function SetCV(name, value) return pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, value) end

local function IsFriendlyPlayer(unit)
	local ok, yes = pcall(function() return UnitIsPlayer(unit) and UnitIsFriend("player", unit) and not UnitIsUnit(unit, "player") end)
	return ok and yes
end

local function Tag(plate)
	if plate.dpwsTag then return plate.dpwsTag end
	local tag = CreateFrame("Frame", nil, plate)
	tag:SetSize(1, 1)
	tag:SetPoint("CENTER", plate, "CENTER", 0, 4)
	tag.name = tag:CreateFontString(nil, "OVERLAY")
	tag.name:SetPoint("BOTTOM", tag, "CENTER", 0, 0)
	tag.name:SetJustifyH("CENTER")
	tag.info = tag:CreateFontString(nil, "OVERLAY")
	tag.info:SetPoint("TOP", tag.name, "BOTTOM", 0, -1)
	tag.info:SetJustifyH("CENTER")
	tag.info:SetTextColor(0.80, 0.82, 0.86)
	plate.dpwsTag = tag
	return tag
end

local function StyleTag(tag)
	local T, size = ns.Theme, S().size or 13
	if tag.size == size then return end
	tag.size = size
	tag.name:SetFont(T.font.semibold, size, "OUTLINE")
	tag.info:SetFont(T.font.medium, math.max(size - 3, 8), "OUTLINE")
end

-- friendly player + feature on: game plate invisible, our label shown. Anything else: game plate
-- visible (plates are reused, an enemy must never get a hidden plate), no label.
local function ApplyPlate(unit)
	local plate = unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	local f = plate.UnitFrame or plate
	local friendly = S().enabled and IsFriendlyPlayer(unit)
	pcall(f.SetAlpha, f, friendly and 0 or 1)
	local tag = Tag(plate)
	if not friendly then tag:Hide() return end
	StyleTag(tag)
	local filled = pcall(function()
		local name = GetUnitName(unit, true)
		local _, class = UnitClass(unit)
		local guild = GetGuildInfo(unit)
		if Secret(name) or Secret(class) or Secret(guild) then error("hidden") end
		local color = class and RAID_CLASS_COLORS[class]
		tag.name:SetText(name)
		if color then tag.name:SetTextColor(color.r, color.g, color.b) else tag.name:SetTextColor(1, 1, 1) end
		tag.info:SetText((guild and S().guild ~= false) and ("<%s>"):format(guild) or "") -- class is the name colour
		A.seen[name] = { class = class, level = UnitLevel(unit), guild = guild, at = GetTime() }
	end)
	tag:SetShown(filled)
end

local function ForEachPlate(fn)
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates() or {}) do
		if plate.namePlateUnitToken then fn(plate.namePlateUnitToken) end
	end
end

local ticker
-- turn the friendly plates on/off to match the setting (CVars can't change in combat)
function A.Apply()
	ns.RunOutOfCombat(function()
		local s = S()
		if s.enabled then
			for _, cv in ipairs(CVARS) do
				local v = GetCV(cv)
				if v ~= nil then
					if s.saved == nil then s.saved = {} end
					if s.saved[cv] == nil then s.saved[cv] = v end -- the player's own setting, remembered once
					SetCV(cv, "1")
				end
			end
			-- the game may reset plate alpha and guild info arrives late: re-apply twice a second
			ticker = ticker or C_Timer.NewTicker(0.5, function() ForEachPlate(ApplyPlate) end)
		else
			if ticker then ticker:Cancel(); ticker = nil end
			for cv, v in pairs(s.saved or {}) do SetCV(cv, v) end
			s.saved = nil
		end
		ForEachPlate(ApplyPlate)
	end)
end

-- always listening: a reused plate must be made visible again whatever the setting
local ev = CreateFrame("Frame")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:SetScript("OnEvent", function(_, _, unit) if ns.adb then ApplyPlate(unit) end end)

table.insert(ns.loginHooks, function() if S().enabled then A.Apply() end end)

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.allies = function()
	S().enabled = not S().enabled
	A.Apply()
	print(("dpws_tools: Friendly Names %s"):format(S().enabled and "ON" or "OFF (your nameplate setting is restored)"))
end

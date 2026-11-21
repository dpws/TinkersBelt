local _, ns = ...
local Loc = ns.L or setmetatable({}, { __index = function(_, k) return k end })

-- field: "k" = you killed them, "d" = they killed you; me = your character (also counted per character in e.by)
function ns.PvpRecord(scores, guid, name, field, me)
	local e = scores[guid] or { k = 0, d = 0 }
	e.name = name
	e[field] = e[field] + 1
	if me then
		e.by = e.by or {}
		local c = e.by[me] or { k = 0, d = 0 }
		c[field] = c[field] + 1
		e.by[me] = c
	end
	scores[guid] = e
end

-- the score against one enemy for one of your characters (me = nil: all of them)
function ns.PvpScoreFor(e, me)
	if not me then return e end
	return e.by and e.by[me] or nil
end

-- history entries of one of your characters (me = nil: all)
function ns.PvpFilter(log, me)
	if not me then return log end
	local out = {}
	for _, entry in ipairs(log) do if entry.me == me then out[#out + 1] = entry end end
	return out
end

-- your characters that appear in the history, sorted
function ns.PvpCharacters(log)
	local seen, list = {}, {}
	for _, entry in ipairs(log) do
		if entry.me and not seen[entry.me] then seen[entry.me] = true; list[#list + 1] = entry.me end
	end
	table.sort(list)
	return list
end

-- the game doesn't say who killed you: use the last enemy player who hit you within `window` seconds
function ns.PvpKiller(lastHit, now, window)
	if lastHit and now - lastHit.time <= window then return lastHit.guid end
end

function ns.PvpScoreText(e)
	local color = e.k > e.d and "40ff40" or (e.k < e.d and "ff4040" or "ffffff")
	return (Loc["|cff%s%d : %d|r"]):format(color, e.k, e.d)
end

-- history: oldest first, at most `cap` entries
function ns.PvpLogAdd(log, entry, cap)
	log[#log + 1] = entry
	while #log > cap do table.remove(log, 1) end
end

-- one page of the history, newest first; page is clamped to 1..pages
function ns.PvpPage(log, page, perPage)
	local pages = math.max(1, math.ceil(#log / perPage))
	page = math.min(math.max(page, 1), pages)
	local items = {}
	local first = #log - (page - 1) * perPage
	for i = first, math.max(first - perPage + 1, 1), -1 do items[#items + 1] = log[i] end
	return items, pages, page
end

-- "Killed Gank (60 Rogue)  3 : 1" / "Killed by Orc (?? Warrior)  3 : 2"
function ns.PvpAnnounceText(kind, name, className, level, score)
	local lvl = (level and level > 0) and tostring(level) or "??"
	return ("%s %s (%s %s)  %s"):format(kind == "k" and "Killed" or "Killed by", name or "?", lvl,
		className or "?", ns.PvpScoreText(score))
end

if not CreateFrame then return end -- offline test stops here

-- No combat log here: on Forever registering for it is a forbidden action. Everything comes from
-- scanning units (target, focus, mouseover, nameplates).
local KILLER_WINDOW = 10
local lastHit
local function Secret(v) return issecretvalue and issecretvalue(v) end

-- open world only: no battlegrounds, arenas or dungeons
local function OpenWorld() return not IsInInstance() end

local LOG_CAP = 500

-- the combat log has no level: remember levels of players we see (session only)
local levels = {}
local function Seen(unit)
	-- pcall: unit info can be hidden from addons (secret values) and must not raise errors
	pcall(function()
		if UnitExists(unit) and UnitIsPlayer(unit) then
			local guid = UnitGUID(unit)
			if guid and not (issecretvalue and issecretvalue(guid)) then levels[guid] = UnitLevel(unit) end
		end
	end)
end

local function Me() return GetUnitName("player", true) end -- full name: Forever names are two words
local function Record(guid, name, kind)
	local me = Me()
	ns.PvpRecord(ns.adb.pvp, guid, name, kind, me)
	Seen("target"); Seen("mouseover")
	local _, class = GetPlayerInfoByGUID(guid)
	ns.PvpLogAdd(ns.adb.pvpLog, { t = time(), kind = kind, name = name, class = class, level = levels[guid],
		me = me, meClass = select(2, UnitClass("player")) }, LOG_CAP)
	local a = ns.adb
	if a.pvpAnnounce then
		local className = class and (LOCALIZED_CLASS_NAMES_MALE[class] or class)
		local color = class and RAID_CLASS_COLORS[class]
		if color then className = ("|c%s%s|r"):format(color.colorStr, className) end
		ns.Notify(ns.PvpAnnounceText(kind, name, className, levels[guid], a.pvp[guid]))
	end
	ns.PlaySoundKey(kind == "k" and a.pvpKillSound or a.pvpDeathSound)
	if ns.OnPvpLogChanged then ns.OnPvpLogChanged() end
end

-- /tb debug: print what PvP tracking sees
local function Debug(msg) if ns.pvpDebug then print("|cff88ccffTB pvp:|r " .. msg) end end
local hiddenCount = 0 -- enemy units whose identity the game hid from us

-- the same kill can be seen through several units (target + nameplate): count it once
local recentKills = {}
local function RecordKill(guid, name, how)
	local now = GetTime()
	if recentKills[guid] and now - recentKills[guid] < 15 then return end
	recentKills[guid] = now
	Debug(("kill: %s (%s)"):format(name or "?", how))
	Record(guid, name, "k")
end

local function Attacker(guid, name, how)
	if not lastHit or lastHit.guid ~= guid then Debug(("attacker: %s (%s)"):format(name or "?", how)) end
	lastHit = { guid = guid, name = name, time = GetTime() }
end

-- Unit scan: enemy players targeting me are attackers; an enemy
-- player I fought (targeted me / I targeted them) dying while I'm in combat counts as my kill.
local myFaction
local engaged, wasDead = {}, {} -- guid -> last time we fought; guid -> dead at last scan
local function ScanUnit(unit, now)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	local faction = UnitFactionGroup(unit)
	if not faction or faction == myFaction or faction == "Neutral" then return end
	local guid, name = UnitGUID(unit), GetUnitName(unit, true)
	if not guid then return end
	if Secret(guid) or Secret(name) then hiddenCount = hiddenCount + 1 return end
	Seen(unit)
	local dead = UnitIsDeadOrGhost(unit)
	if not dead and UnitIsUnit(unit .. "target", "player") then
		engaged[guid] = now
		Attacker(guid, name, "targeting me")
	end
	if not dead and UnitIsUnit(unit, "target") and UnitAffectingCombat("player") then engaged[guid] = now end
	if dead and wasDead[guid] == false and engaged[guid] and now - engaged[guid] < 15 then
		RecordKill(guid, name, "died after fighting me")
	end
	wasDead[guid] = dead
end

local function Scan()
	if not ns.adb or not OpenWorld() or not ns.On("pvp") then return end
	local now = GetTime()
	local units = { "target", "focus", "mouseover" }
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, unit in ipairs(ns.NamePlateUnits()) do units[#units + 1] = unit end
	end
	-- the same player via two units is harmless: attacker is overwritten, kills are deduplicated
	for _, unit in ipairs(units) do
		if unit then pcall(ScanUnit, unit, now) end -- values hidden from addons must not break the scan
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_DEAD")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_TARGET_CHANGED" then return Seen("target") end
	if event == "UPDATE_MOUSEOVER_UNIT" then return Seen("mouseover") end
	if event == "NAME_PLATE_UNIT_ADDED" then return Seen(arg1) end
	if not ns.adb or not OpenWorld() or not ns.On("pvp") then return end
	if event == "PLAYER_DEAD" then
		Scan() -- last look at who is around
		local killer = ns.PvpKiller(lastHit, GetTime(), KILLER_WINDOW)
		Debug(("died; last attacker: %s"):format(lastHit and (lastHit.name .. (" %.1fs ago"):format(GetTime() - lastHit.time)) or "none"))
		if killer then Record(killer, lastHit.name, "d") end
		lastHit = nil
	end
end)

table.insert(ns.loginHooks, function()
	myFaction = UnitFactionGroup("player")
	C_Timer.NewTicker(0.25, Scan)
end)

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.debug = function()
	ns.pvpDebug = not ns.pvpDebug
	print(("Tinker's Belt: PvP debug %s. Enemy units hidden by the game so far: %d")
		:format(ns.pvpDebug and "ON" or "OFF", hiddenCount))
end

-- the engine can hand out hidden ("secret") values, e.g. tooltip units in combat: skip those
local function Secret(v) return issecretvalue and issecretvalue(v) end

local function OnTooltipUnit(tooltip)
	if tooltip ~= GameTooltip or not ns.adb or not ns.adb.pvpTooltip or not ns.On("pvp") then return end
	local _, unit = tooltip:GetUnit()
	if not unit or Secret(unit) then return end
	local ok, guid = pcall(function() return UnitIsPlayer(unit) and UnitGUID(unit) end)
	if not ok or not guid or Secret(guid) then return end
	local e = ns.adb.pvp[guid]
	if e then
		-- all your characters, and this one when it differs
		local mine = ns.PvpScoreFor(e, Me())
		local extra = (mine and (mine.k ~= e.k or mine.d ~= e.d)) and ("  (this character " .. ns.PvpScoreText(mine) .. ")") or ""
		tooltip:AddLine(Loc["PvP: "] .. ns.PvpScoreText(e) .. extra)
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipUnit)
else
	GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipUnit)
end

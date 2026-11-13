local _, ns = ...

-- field: "k" = you killed them, "d" = they killed you
function ns.PvpRecord(scores, guid, name, field)
	local e = scores[guid] or { k = 0, d = 0 }
	e.name = name
	e[field] = e[field] + 1
	scores[guid] = e
end

-- the game doesn't say who killed you: use the last enemy player who hit you within `window` seconds
function ns.PvpKiller(lastHit, now, window)
	if lastHit and now - lastHit.time <= window then return lastHit.guid end
end

function ns.PvpScoreText(e)
	local color = e.k > e.d and "40ff40" or (e.k < e.d and "ff4040" or "ffffff")
	return ("|cff%s%d : %d|r"):format(color, e.k, e.d)
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

local KILLER_WINDOW = 10
local DAMAGE = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true }
local lastHit

local function IsEnemyPlayer(guid, flags)
	return guid and guid:find("^Player%-") and bit.band(flags or 0, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
end

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

local function Record(guid, name, kind)
	ns.PvpRecord(ns.adb.pvp, guid, name, kind)
	Seen("target"); Seen("mouseover")
	local _, class = GetPlayerInfoByGUID(guid)
	ns.PvpLogAdd(ns.adb.pvpLog, { t = time(), kind = kind, name = name, class = class, level = levels[guid] }, LOG_CAP)
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

-- /dpws debug: print what PvP tracking sees
local function Debug(msg) if ns.pvpDebug then print("|cff88ccffdpws pvp:|r " .. msg) end end
local cleuCount = 0

-- the same kill can be seen by the combat log and by the unit scan: count it once
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

-- Combat log: may be closed to addons on this client (DBM doesn't use it on Forever), so it is optional
local function OnCombatLog()
	cleuCount = cleuCount + 1
	local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
	local me = UnitGUID("player")
	if sub == "PARTY_KILL" and srcGUID == me and IsEnemyPlayer(dstGUID, dstFlags) then
		RecordKill(dstGUID, dstName, "combat log")
	elseif DAMAGE[sub] and dstGUID == me and IsEnemyPlayer(srcGUID, srcFlags) then
		Attacker(srcGUID, srcName, "combat log")
	end
end

-- Unit scan, works without the combat log: enemy players targeting me are attackers; an enemy
-- player I fought (targeted me / I targeted them) dying while I'm in combat counts as my kill.
local myFaction
local engaged, wasDead = {}, {} -- guid -> last time we fought; guid -> dead at last scan
local function ScanUnit(unit, now)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	local faction = UnitFactionGroup(unit)
	if not faction or faction == myFaction or faction == "Neutral" then return end
	local guid, name = UnitGUID(unit), GetUnitName(unit, true)
	if not guid then return end
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

local scanned = {}
local function Scan()
	if not ns.adb or not OpenWorld() then return end
	local now = GetTime()
	wipe(scanned)
	local units = { "target", "focus", "mouseover" }
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do units[#units + 1] = plate.namePlateUnitToken end
	end
	for _, unit in ipairs(units) do
		local guid = unit and UnitGUID(unit)
		if guid and not scanned[guid] then
			scanned[guid] = true
			pcall(ScanUnit, unit, now) -- values hidden from addons must not break the scan
		end
	end
end

local f = CreateFrame("Frame")
local cleuOK = pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("PLAYER_DEAD")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_TARGET_CHANGED" then return Seen("target") end
	if event == "UPDATE_MOUSEOVER_UNIT" then return Seen("mouseover") end
	if event == "NAME_PLATE_UNIT_ADDED" then return Seen(arg1) end
	if not ns.adb or not OpenWorld() then return end
	if event == "PLAYER_DEAD" then
		Scan() -- last look at who is around
		local killer = ns.PvpKiller(lastHit, GetTime(), KILLER_WINDOW)
		Debug(("died; last attacker: %s"):format(lastHit and (lastHit.name .. (" %.1fs ago"):format(GetTime() - lastHit.time)) or "none"))
		if killer then Record(killer, lastHit.name, "d") end
		lastHit = nil
		return
	end
	local ok, err = pcall(OnCombatLog)
	if not ok then Debug("combat log error: " .. tostring(err)) end
end)

table.insert(ns.loginHooks, function()
	myFaction = UnitFactionGroup("player")
	C_Timer.NewTicker(0.25, Scan)
end)

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.debug = function()
	ns.pvpDebug = not ns.pvpDebug
	print(("dpws_tools: PvP debug %s. Combat log registration: %s, events received so far: %d")
		:format(ns.pvpDebug and "ON" or "OFF", cleuOK and "ok" or "REFUSED", cleuCount))
end

-- the engine can hand out hidden ("secret") values, e.g. tooltip units in combat: skip those
local function Secret(v) return issecretvalue and issecretvalue(v) end

local function OnTooltipUnit(tooltip)
	if tooltip ~= GameTooltip or not ns.adb or not ns.adb.pvpTooltip then return end
	local _, unit = tooltip:GetUnit()
	if not unit or Secret(unit) then return end
	local ok, guid = pcall(function() return UnitIsPlayer(unit) and UnitGUID(unit) end)
	if not ok or not guid or Secret(guid) then return end
	local e = ns.adb.pvp[guid]
	if e then tooltip:AddLine("PvP: " .. ns.PvpScoreText(e)) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipUnit)
else
	GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipUnit)
end

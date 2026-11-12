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
	if UnitExists(unit) and UnitIsPlayer(unit) then
		local guid = UnitGUID(unit)
		if guid then levels[guid] = UnitLevel(unit) end
	end
end

local function Record(guid, name, kind)
	ns.PvpRecord(ns.adb.pvp, guid, name, kind)
	Seen("target"); Seen("mouseover")
	local _, class = GetPlayerInfoByGUID(guid)
	ns.PvpLogAdd(ns.adb.pvpLog, { t = time(), kind = kind, name = name, class = class, level = levels[guid] }, LOG_CAP)
	if ns.OnPvpLogChanged then ns.OnPvpLogChanged() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
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
		local killer = ns.PvpKiller(lastHit, GetTime(), KILLER_WINDOW)
		if killer then Record(killer, lastHit.name, "d") end
		lastHit = nil
		return
	end
	local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
	local me = UnitGUID("player")
	if sub == "PARTY_KILL" and srcGUID == me and IsEnemyPlayer(dstGUID, dstFlags) then
		Record(dstGUID, dstName, "k")
	elseif DAMAGE[sub] and dstGUID == me and IsEnemyPlayer(srcGUID, srcFlags) then
		lastHit = { guid = srcGUID, name = srcName, time = GetTime() }
	end
end)

local function OnTooltipUnit(tooltip)
	if tooltip ~= GameTooltip or not ns.adb or not ns.adb.pvpTooltip then return end
	local _, unit = tooltip:GetUnit()
	local guid = unit and UnitIsPlayer(unit) and UnitGUID(unit)
	local e = guid and ns.adb.pvp[guid]
	if e then tooltip:AddLine("PvP: " .. ns.PvpScoreText(e)) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipUnit)
else
	GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipUnit)
end

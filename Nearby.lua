local _, ns = ...

-- Classic + TBC races (englishRace from GetPlayerInfoByGUID)
local RACE_FACTION = {
	Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance", Draenei = "Alliance",
	Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde", BloodElf = "Horde",
}
function ns.RaceFaction(race) return RACE_FACTION[race] end

-- Mark a player as seen; merges non-nil info. Returns true when new (or back after timing out).
function ns.NearbySeen(list, guid, info, now, timeout)
	local e = list[guid]
	local isNew = not e or now - e.seen > timeout
	e = e or {}
	for k, v in pairs(info) do e[k] = v end
	e.seen = now
	list[guid] = e
	return isNew
end

-- Drop expired entries; return the rest newest first.
function ns.NearbySorted(list, now, timeout)
	local items = {}
	for guid, e in pairs(list) do
		if now - e.seen > timeout then
			list[guid] = nil
		else
			e.guid = guid
			items[#items + 1] = e
		end
	end
	table.sort(items, function(a, b) return a.seen > b.seen end)
	return items
end

if not CreateFrame then return end -- offline test stops here

local MAX_ROWS = 10
local list = {}
local frame, header, rows
local myFaction

local function Settings() return ns.adb.nearby end

local function Alert(guid, e)
	local s = Settings()
	local score = ns.adb.pvp[guid]
	if s.alert == "all" or (s.alert == "killers" and score and score.d > 0) then
		local className = e.class and (LOCALIZED_CLASS_NAMES_MALE[e.class] or e.class) or "?"
		local lvl = (e.level and e.level > 0) and e.level or "??"
		ns.Notify(("Enemy nearby: %s (%s %s)"):format(e.name or "?", lvl, className))
		ns.PlaySoundKey(s.sound)
	end
end

local function Seen(guid, info)
	if not guid or not Settings().enabled or IsInInstance() then return end
	if ns.NearbySeen(list, guid, info, GetTime(), Settings().timeout) then Alert(guid, list[guid]) end
end

local function SeenUnit(unit)
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	local faction = UnitFactionGroup(unit)
	if not faction or faction == myFaction or faction == "Neutral" then return end
	Seen(UnitGUID(unit), { name = GetUnitName(unit, true), class = select(2, UnitClass(unit)), level = UnitLevel(unit) })
end

-- combat log fires a lot: cache per player (info table for enemies, false for everyone else)
local guidCache = {}
local function SeenGUID(guid, flags)
	if not guid or not guid:find("^Player%-") then return end
	local info = guidCache[guid]
	if info == nil then
		local _, class, _, race, _, name, realm = GetPlayerInfoByGUID(guid)
		if not name then return end -- not resolved yet, try again next event
		local faction = ns.RaceFaction(race)
		local enemy
		if faction then
			enemy = faction ~= myFaction
		else -- unknown race: fall back to the game's hostility flag
			enemy = bit.band(flags or 0, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
		end
		info = enemy and { name = (realm and realm ~= "") and (name .. "-" .. realm) or name, class = class } or false
		guidCache[guid] = info
	end
	if info then Seen(guid, info) end
end

local function Refresh()
	if not frame then return end
	local s = Settings()
	-- players whose nameplates are still on screen stay fresh
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do pcall(SeenUnit, plate.namePlateUnitToken) end
	end
	local now = GetTime()
	local items = ns.NearbySorted(list, now, s.timeout)
	header:SetText(("Nearby enemies (%d)"):format(#items))
	for i, row in ipairs(rows) do
		local e = items[i]
		if e then
			local color = e.class and RAID_CLASS_COLORS[e.class]
			local name = color and ("|c%s%s|r"):format(color.colorStr, e.name or "?") or (e.name or "?")
			local lvl = (e.level and e.level > 0) and e.level or "??"
			local score = ns.adb.pvp[e.guid]
			row.left:SetText(("%s  %s"):format(lvl, name))
			row.right:SetText((score and (ns.PvpScoreText(score) .. "  ") or "") .. ("%ds"):format(now - e.seen))
		else
			row.left:SetText("")
			row.right:SetText("")
		end
	end
	frame:SetShown(s.enabled and ((#items > 0 and not IsInInstance()) or ns.unlocked))
end
ns.RefreshNearby = Refresh

table.insert(ns.loginHooks, function()
	myFaction = UnitFactionGroup("player")
	local s = Settings()
	frame = CreateFrame("Frame", "DpwsNearbyFrame", UIParent)
	frame:SetSize(260, 20 + MAX_ROWS * 16)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.4)
	header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetPoint("TOPLEFT", 6, -4)
	rows = {}
	for i = 1, MAX_ROWS do
		local row = {}
		row.left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.left:SetPoint("TOPLEFT", 6, -6 - i * 16)
		row.right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.right:SetPoint("TOPRIGHT", -6, -6 - i * 16)
		rows[i] = row
	end
	if s.pos then
		frame:SetPoint(s.pos.point, UIParent, s.pos.relPoint, s.pos.x, s.pos.y)
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200)
	end
	ns.RegisterPanel(frame, "Nearby Enemies", function(self)
		local point, _, relPoint, x, y = self:GetPoint()
		s.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	ev:RegisterEvent("PLAYER_TARGET_CHANGED")
	ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	pcall(ev.RegisterEvent, ev, "COMBAT_LOG_EVENT_UNFILTERED") -- may be closed to addons on this client
	ev:SetScript("OnEvent", function(_, event, arg1)
		-- pcall: unit info can be hidden from addons (secret values) and must not raise errors
		if event == "NAME_PLATE_UNIT_ADDED" then pcall(SeenUnit, arg1)
		elseif event == "PLAYER_TARGET_CHANGED" then pcall(SeenUnit, "target")
		elseif event == "UPDATE_MOUSEOVER_UNIT" then pcall(SeenUnit, "mouseover")
		else
			pcall(function()
				local _, _, _, srcGUID, _, srcFlags, _, dstGUID, _, dstFlags = CombatLogGetCurrentEventInfo()
				SeenGUID(srcGUID, srcFlags)
				SeenGUID(dstGUID, dstFlags)
			end)
		end
	end)
	C_Timer.NewTicker(1, Refresh)
	Refresh()
end)

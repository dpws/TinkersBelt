local _, ns = ...
local Loc = ns.L or setmetatable({}, { __index = function(_, k) return k end })

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
		ns.Notify((Loc["Enemy nearby: %s (%s %s)"]):format(e.name or "?", lvl, className))
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


local function Refresh()
	if not frame then return end
	local s = Settings()
	-- players whose nameplates are still on screen stay fresh
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, unit in ipairs(ns.NamePlateUnits()) do pcall(SeenUnit, unit) end
	end
	local now = GetTime()
	local items = ns.NearbySorted(list, now, s.timeout)
	header:SetText((Loc["Nearby enemies (%d)"]):format(#items))
	for i, row in ipairs(rows) do
		local e = items[i]
		if e then
			local color = e.class and RAID_CLASS_COLORS[e.class]
			local name = color and ("|c%s%s|r"):format(color.colorStr, e.name or "?") or (e.name or "?")
			local lvl = (e.level and e.level > 0) and e.level or "??"
			local score = ns.adb.pvp[e.guid]
			row.left:SetText(("%s  %s"):format(lvl, name))
			row.right:SetText((score and (ns.PvpScoreText(score) .. "  ") or "") .. (Loc["%ds"]):format(now - e.seen))
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
	ns.Theme.Box(frame, { 0.047, 0.054, 0.066, 0.88 }, ns.Theme.border, 8)
	header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header:SetTextColor(unpack(ns.Theme.gold))
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
	-- no combat log: registering for it is a forbidden action on Forever
	ev:SetScript("OnEvent", function(_, event, arg1)
		-- pcall: unit info can be hidden from addons (secret values) and must not raise errors
		if event == "NAME_PLATE_UNIT_ADDED" then pcall(SeenUnit, arg1)
		elseif event == "PLAYER_TARGET_CHANGED" then pcall(SeenUnit, "target")
		elseif event == "UPDATE_MOUSEOVER_UNIT" then pcall(SeenUnit, "mouseover")
		end
	end)
	C_Timer.NewTicker(1, Refresh)
	Refresh()
end)

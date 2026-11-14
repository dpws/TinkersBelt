local _, ns = ...

-- TEST (/dpws allies): track friendly players via friendly nameplates while making those plates
-- invisible. Forever closes the combat log, so nameplates are the only "nearby" signal; this checks
-- whether an addon may turn friendly plates on and hide them. Session only; toggling off restores.

local CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" }
local active = false
local saved = {} -- cvar -> original value
local hidden, errors = 0, {}
local seen = {} -- name -> { class, level, at }

local function GetCV(name)
	local v = (C_CVar and C_CVar.GetCVar or GetCVar)(name)
	return v
end
local function SetCV(name, value)
	return pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, value)
end

local function IsFriendlyPlayer(unit)
	local ok, yes = pcall(function() return UnitIsPlayer(unit) and UnitIsFriend("player", unit) and not UnitIsUnit(unit, "player") end)
	return ok and yes
end

local function NoteError(msg)
	if #errors < 5 then errors[#errors + 1] = tostring(msg) end
end

-- make one plate invisible (or visible again)
local function SetPlateHidden(unit, hide)
	if not unit or not IsFriendlyPlayer(unit) then return end
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	-- with friendly plates on, the game draws the player's name on the plate instead of overhead:
	-- hide everything (bars, highlights, auras) except that name
	local ok, err = pcall(function()
		local f = plate.UnitFrame or plate
		local name = f.name or f.Name
		for _, child in ipairs({ f:GetChildren() }) do child:SetAlpha(hide and 0 or 1) end
		for _, r in ipairs({ f:GetRegions() }) do
			if r ~= name then r:SetAlpha(hide and 0 or 1) end
		end
		if name then name:SetAlpha(1) end
	end)
	if not ok then NoteError(err) return end
	if hide then
		hidden = hidden + 1
		pcall(function()
			local name = GetUnitName(unit, true)
			if name and not (issecretvalue and issecretvalue(name)) then
				seen[name] = { class = select(2, UnitClass(unit)), level = UnitLevel(unit), at = GetTime() }
			end
		end)
	end
end

local function ForEachPlate(fn)
	for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates() or {}) do
		if plate.namePlateUnitToken then fn(plate.namePlateUnitToken) end
	end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then SetPlateHidden(unit, true) end
end)
local ticker

local function Start(Say)
	if InCombatLockdown() then Say("allies: can't change nameplate settings in combat, try again after") return end
	for _, cv in ipairs(CVARS) do
		local v = GetCV(cv)
		if v ~= nil then
			saved[cv] = v
			local ok, err = SetCV(cv, "1")
			Say(("allies: %s was %s, set to 1: %s"):format(cv, tostring(v), ok and "ok" or ("FAILED " .. tostring(err))))
		end
	end
	active, hidden = true, 0
	wipe(errors)
	ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	ForEachPlate(function(u) SetPlateHidden(u, true) end)
	-- the game may reset plate alpha: re-apply twice a second
	ticker = C_Timer.NewTicker(0.5, function() ForEachPlate(function(u) SetPlateHidden(u, true) end) end)
	Say("allies: ON - friendly player plates should be invisible now. Walk near other players, then run /dpws allies again to see the result and turn it off.")
end

local function Stop(Say)
	active = false
	if ticker then ticker:Cancel(); ticker = nil end
	ev:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	ForEachPlate(function(u) SetPlateHidden(u, false) end)
	if InCombatLockdown() then
		Say("allies: in combat - nameplate setting restore skipped, run /dpws allies again after combat")
	else
		for cv, v in pairs(saved) do SetCV(cv, v) end
	end
	local names = {}
	for name, e in pairs(seen) do
		local lvl = (e.level and e.level > 0) and e.level or "??"
		names[#names + 1] = ("%s (%s %s)"):format(name, lvl, e.class or "?")
	end
	table.sort(names)
	Say(("allies: OFF. Plates hidden: %d. Errors caught: %d"):format(hidden, #errors))
	for _, e in ipairs(errors) do Say("allies: error: " .. e) end
	Say(("allies: friendly players found: %d"):format(#names))
	for _, n in ipairs(names) do Say("allies:   " .. n) end
	Say("allies: also check BugSack for ADDON_ACTION_FORBIDDEN / BLOCKED reports from dpws_tools.")
	wipe(seen)
end

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.allies = function()
	ns.Diagnose(function(Say)
		if active then Stop(Say) else Start(Say) end
	end)
end

local ADDON, ns = ...
DpwsTools = ns -- global for /run debugging

ns.loginHooks = {}

local queue = {}
function ns.RunOutOfCombat(fn)
	if InCombatLockdown() then
		queue[#queue + 1] = fn
	else
		fn()
	end
end

-- movable panels: overlay + drag only while unlocked (starts locked every session)
ns.panels = {}
ns.unlocked = false

-- onMoved(frame) saves the position after a drag
function ns.RegisterPanel(frame, name, onMoved)
	-- child at the panel's own frame level: under its buttons, but catches the mouse everywhere else
	local o = CreateFrame("Frame", nil, frame)
	o:SetFrameLevel(frame:GetFrameLevel())
	o:SetPoint("TOPLEFT", -6, 6)
	o:SetPoint("BOTTOMRIGHT", 6, -20)
	local bg = o:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.5, 1, 0.35)
	local label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("BOTTOM", 0, 4)
	label:SetText(name)
	o:EnableMouse(true)
	o:RegisterForDrag("LeftButton")
	o:SetScript("OnDragStart", function() ns.StartMovingPanel(frame) end)
	o:SetScript("OnDragStop", function() ns.StopMovingPanel(frame) end)
	frame.dpwsOnMoved = onMoved
	o:SetShown(ns.unlocked)
	ns.panels[#ns.panels + 1] = o
end

function ns.StartMovingPanel(frame)
	if ns.unlocked and not InCombatLockdown() then frame:StartMoving() end
end

function ns.StopMovingPanel(frame)
	frame:StopMovingOrSizing()
	if frame.dpwsOnMoved then frame.dpwsOnMoved(frame) end
end

-- scale around the panel's center (call out of combat for frames with secure children)
function ns.SetPanelScale(frame, scale)
	if frame:GetScale() == scale then return end
	local cx, cy = frame:GetCenter()
	if not cx then frame:SetScale(scale); return end
	local old = frame:GetEffectiveScale()
	frame:SetScale(scale)
	local new = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * old / new, cy * old / new)
	if frame.dpwsOnMoved then frame.dpwsOnMoved(frame) end
end

function ns.SetUnlocked(on)
	ns.unlocked = on
	for _, o in ipairs(ns.panels) do o:SetShown(on) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		DpwsToolsCharDB = DpwsToolsCharDB or {}
		local db = DpwsToolsCharDB
		db.barSwitch = db.barSwitch or {}
		db.window = db.window or {}
		db.poisons = db.poisons or { enabled = true, warnMinutes = 5, sound = true }
		db.combo = db.combo or { width = 200, height = 14, sounds = {} }
		db.restock = db.restock or { enabled = true, budget = 50000, items = {} } -- budget in copper (5g)
		-- older settings: combo bar switched off with a checkbox
		if db.combo.enabled == false and not db.combo.comboMode then db.combo.comboMode = "off" end
		ns.db = db
		-- account-wide (all characters)
		DpwsToolsDB = DpwsToolsDB or {}
		local adb = DpwsToolsDB
		adb.pvp = adb.pvp or {}
		adb.pvpLog = adb.pvpLog or {}
		if adb.pvpTooltip == nil then adb.pvpTooltip = true end
		if adb.pvpAnnounce == nil then adb.pvpAnnounce = true end
		adb.nearby = adb.nearby or { enabled = true, timeout = 60, alert = "off" }
		ns.adb = adb
	elseif event == "PLAYER_LOGIN" then
		-- one module failing must not stop the others; the error still reaches BugSack
		for _, hook in ipairs(ns.loginHooks) do xpcall(hook, geterrorhandler()) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		local pending = queue
		queue = {}
		for _, fn in ipairs(pending) do fn() end
	end
end)

SLASH_DPWS1 = "/dpws"
-- /dpws opens the window; /dpws <word> runs a module command (e.g. /dpws debug)
SlashCmdList.DPWS = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd ~= "" and ns.slashCommands and ns.slashCommands[cmd] then return ns.slashCommands[cmd]() end
	if ns.ToggleWindow then ns.ToggleWindow() else print("dpws_tools loaded") end
end

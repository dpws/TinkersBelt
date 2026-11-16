local ADDON, ns = ...
DpwsTools = ns -- global for /run debugging

ns.loginHooks = {}

-- unit tokens of all current nameplates. plate.namePlateUnitToken is empty on Forever, so ask the game
-- for nameplate1..40 directly.
function ns.NamePlateUnits()
	local units = {}
	for i = 1, 40 do
		local unit = "nameplate" .. i
		local ok, exists = pcall(UnitExists, unit)
		if ok and exists then units[#units + 1] = unit end
	end
	return units
end

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
	local T = ns.Theme
	T.Panel(o, T.Accent(0.16), T.Accent(0.7)) -- accent tint while unlocked
	local label = T.Text(o, "semibold", 11, T.gold)
	label:SetPoint("BOTTOM", 0, 4)
	label:SetText(name)
	T.Skin(frame) -- the panel's own texts in Inter
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
		db.alliesList = db.alliesList or { enabled = false, rows = 10 }
		db.mana = db.mana or { mode = "always", width = 200, height = 10 }
		db.buffs = db.buffs or { enabled = true, warn = 3, sound = true, strips = true, size = 18 }
		db.buffs.off = db.buffs.off or {}
		db.buffs.last = db.buffs.last or {}
		db.buffs.custom = db.buffs.custom or {} -- [spellID] = true: extra buffs to keep on yourself
		db.rogueTimers = db.rogueTimers or { mode = "combat", snd = true, size = 28, off = {} }
		db.lockbox = db.lockbox or { enabled = true }
		db.opener = db.opener or { markers = true, weapons = true, sets = {} }
		db.buffs.lastOn = db.buffs.lastOn or {} -- blessing you give each player, by name
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
		adb.allies = adb.allies or { enabled = false, size = 13, guild = true }
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
-- WoW chat can't be copied: show text in a selectable box (Ctrl+C) for diagnostics
local copyFrame
function ns.ShowCopyWindow(text)
	if not copyFrame then
		local T = ns.Theme
		copyFrame = CreateFrame("Frame", "DpwsCopyWindow", UIParent)
		copyFrame:SetSize(560, 360)
		copyFrame:SetPoint("CENTER")
		copyFrame:SetFrameStrata("DIALOG")
		copyFrame:SetMovable(true)
		copyFrame:EnableMouse(true)
		copyFrame:RegisterForDrag("LeftButton")
		copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
		copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
		T.Box(copyFrame, T.window, T.border, 10)
		local title = T.Text(copyFrame, "semibold", 13, { 1, 1, 1, 1 })
		title:SetPoint("TOPLEFT", 14, -12)
		title:SetText("dpws tools - press Ctrl+C to copy, Esc to close")
		local close = CreateFrame("Button", nil, copyFrame)
		close:SetSize(24, 24)
		close:SetPoint("TOPRIGHT", -8, -6)
		local x = T.Text(close, "semibold", 14, T.muted)
		x:SetPoint("CENTER")
		x:SetText("X")
		close:SetScript("OnClick", function() copyFrame:Hide() end)
		local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "ScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -40)
		scroll:SetPoint("BOTTOMRIGHT", -30, 12)
		local box = CreateFrame("EditBox", nil, scroll)
		box:SetMultiLine(true)
		box:SetFont(T.font.regular, 12, "")
		box:SetTextColor(unpack(T.text))
		box:SetWidth(500)
		box:SetAutoFocus(false)
		box:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
		scroll:SetScrollChild(box)
		copyFrame.box = box
		tinsert(UISpecialFrames, "DpwsCopyWindow")
	end
	copyFrame.box:SetText(text)
	copyFrame:Show()
	copyFrame.box:SetFocus()
	copyFrame.box:HighlightText()
end

-- run fn(Say) printing each line to chat and also collecting it for the copy window
function ns.Diagnose(fn)
	local lines = {}
	local function Say(msg)
		print(msg)
		lines[#lines + 1] = msg
	end
	xpcall(function() fn(Say) end, function(err)
		Say("ERROR: " .. tostring(err))
		geterrorhandler()(err)
	end)
	ns.ShowCopyWindow(table.concat(lines, "\n"))
end

-- /dpws opens the window; /dpws <word> runs a module command (e.g. /dpws debug)
SlashCmdList.DPWS = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd ~= "" and ns.slashCommands and ns.slashCommands[cmd] then return ns.slashCommands[cmd]() end
	if ns.ToggleWindow then ns.ToggleWindow() else print("dpws_tools loaded") end
end

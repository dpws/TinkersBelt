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

-- layout grid (account-wide setting adb.layout): shown while unlocked; panels snap to it while dragged.
-- Lines run out from the screen centre, so the centre lines are grid lines too. Hold Shift to place freely.
local function L() return ns.adb.layout end

-- nearest grid line to v on an axis whose centre line is at c
function ns.SnapToGrid(v, size, c)
	return math.floor((v - c) / size + 0.5) * size + c
end

-- new start of a span [lo, lo+len]: whichever of its start, middle or end is closest to a grid line snaps.
-- Also returns that grid line.
function ns.SnapEdges(lo, len, size, c)
	local best, line
	for _, off in ipairs({ 0, len / 2, len }) do
		local g = ns.SnapToGrid(lo + off, size, c)
		local d = g - (lo + off)
		if not best or math.abs(d) < math.abs(best) then best, line = d, g end
	end
	return lo + best, line
end

local grid, lines = nil, {}
local function DrawGrid()
	if not grid then
		grid = CreateFrame("Frame", nil, UIParent)
		grid:SetAllPoints()
		grid:SetFrameStrata("BACKGROUND")
	end
	for _, t in ipairs(lines) do t:Hide() end
	local n = 0
	local function Line(vertical, pos, center)
		n = n + 1
		local t = lines[n] or grid:CreateTexture(nil, "BACKGROUND")
		lines[n] = t
		t:ClearAllPoints()
		t:SetColorTexture(1, 1, 1, center and 0.35 or 0.08)
		if vertical then
			t:SetPoint("TOPLEFT", pos, 0); t:SetPoint("BOTTOMLEFT", pos, 0); t:SetWidth(1)
		else
			t:SetPoint("BOTTOMLEFT", 0, pos); t:SetPoint("BOTTOMRIGHT", 0, pos); t:SetHeight(1)
		end
		t:Show()
	end
	local w, h, size = UIParent:GetWidth(), UIParent:GetHeight(), L().size
	for x = (w / 2) % size, w, size do Line(true, x, math.abs(x - w / 2) < 0.5) end
	for y = (h / 2) % size, h, size do Line(false, y, math.abs(y - h / 2) < 0.5) end
end

local function UpdateGrid()
	local on = ns.unlocked and L().grid
	if on then DrawGrid() end
	if grid then grid:SetShown(on and true or false) end
end

-- drag: move the panel ourselves every frame so it can snap while it moves
local mover = CreateFrame("Frame")
mover:Hide()
-- the two grid lines the dragged panel is snapped to, in the accent colour
local hl
local function Highlight(x, y)
	if not hl then
		hl = CreateFrame("Frame", nil, UIParent)
		hl:SetAllPoints()
		hl:SetFrameStrata("BACKGROUND")
		hl:SetFrameLevel(10)
		local T = ns.Theme
		hl.v = hl:CreateTexture(nil, "OVERLAY")
		hl.v:SetColorTexture(unpack(T.Accent(0.9)))
		hl.v:SetWidth(2)
		hl.h = hl:CreateTexture(nil, "OVERLAY")
		hl.h:SetColorTexture(unpack(T.Accent(0.9)))
		hl.h:SetHeight(2)
	end
	hl:SetShown(x ~= nil)
	if not x then return end
	hl.v:ClearAllPoints(); hl.v:SetPoint("TOP", hl, "TOPLEFT", x, 0); hl.v:SetPoint("BOTTOM", hl, "BOTTOMLEFT", x, 0)
	hl.h:ClearAllPoints(); hl.h:SetPoint("LEFT", hl, "BOTTOMLEFT", 0, y); hl.h:SetPoint("RIGHT", hl, "BOTTOMRIGHT", 0, y)
end

local function Place(frame, left, top, snap)
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale() -- grid is in UIParent units
	local lineX, lineY
	if snap then
		local size = L().size
		local w, h = frame:GetWidth() * s, frame:GetHeight() * s
		left, lineX = ns.SnapEdges(left, w, size, UIParent:GetWidth() / 2)
		top, lineY = ns.SnapEdges(top - h, h, size, UIParent:GetHeight() / 2)
		top = top + h
	end
	Highlight(lineX, lineY)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
end
local function Cursor()
	local x, y = GetCursorPosition()
	local u = UIParent:GetEffectiveScale()
	return x / u, y / u
end
mover:SetScript("OnUpdate", function(self)
	if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then ns.StopMovingPanel(self.frame) return end
	local x, y = Cursor()
	Place(self.frame, self.left + x - self.x, self.top + y - self.y, L().snap and not IsShiftKeyDown())
end)

-- force: move even while panels are locked (Shift+drag on the buff reminder)
function ns.StartMovingPanel(frame, force)
	if not (ns.unlocked or force) or InCombatLockdown() or not frame:GetLeft() then return end
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	mover.frame, mover.left, mover.top = frame, frame:GetLeft() * s, frame:GetTop() * s
	mover.x, mover.y = Cursor()
	mover:Show()
end

function ns.StopMovingPanel(frame)
	if mover.frame ~= frame then return end
	mover:Hide()
	mover.frame = nil
	Highlight(nil)
	if frame.dpwsOnMoved then frame.dpwsOnMoved(frame) end
end

-- small settings bar at the top of the screen while unlocked
local bar
local function SettingsBar()
	local T = ns.Theme
	bar = CreateFrame("Frame", nil, UIParent)
	bar:SetSize(560, 44)
	bar:SetPoint("TOP", 0, -12)
	bar:SetFrameStrata("DIALOG")
	bar:EnableMouse(true)
	T.Panel(bar)
	local x = 14
	local function Label(text)
		local fs = T.Text(bar, "medium", 12, T.text)
		fs:SetPoint("LEFT", x, 0)
		fs:SetText(text)
		x = x + fs:GetStringWidth() + 8
	end
	local function Toggle(text, key)
		Label(text)
		local t = T.NewToggle(bar, function(on) L()[key] = on; UpdateGrid() end)
		t:SetPoint("LEFT", x, 0)
		t:SetChecked(L()[key])
		x = x + 36 + 18
	end
	Toggle("Snap", "snap")
	Toggle("Grid", "grid")
	Label("Grid size")
	local sl = T.NewSlider(bar, 8, 64, 4, "px", function(v) L().size = v; UpdateGrid() end)
	sl:SetWidth(220)
	sl:SetPoint("LEFT", x, 0)
	sl:SetValue(L().size)
	x = x + 220 + 12
	local lock = T.NewButton(bar, "Lock panels", 100, 26, "accent")
	lock:SetPoint("LEFT", x, 0)
	lock:SetScript("OnClick", function() ns.SetUnlocked(false) end)
	bar:SetWidth(x + 100 + 14)
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
	if on and not bar then SettingsBar() end
	if bar then bar:SetShown(on) end
	if not on and mover.frame then ns.StopMovingPanel(mover.frame) end
	UpdateGrid()
	if ns.OnLockChanged then ns.OnLockChanged() end
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
		adb.layout = adb.layout or { snap = true, grid = true, size = 32 }
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

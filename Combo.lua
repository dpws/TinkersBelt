local _, ns = ...

-- Which per-amount sound to play: the new amount when combo points rise, else nil.
function ns.ComboSoundFor(prev, cp)
	if cp > (prev or 0) then return cp end
end

if not CreateFrame then return end -- offline test stops here

local C = {}
ns.Combo = C

-- SOUNDKIT keys; missing ones on this client are skipped when played
ns.COMBO_SOUNDS = {
	{ key = "MAP_PING", name = "Ping" },
	{ key = "TELL_MESSAGE", name = "Whisper" },
	{ key = "READY_CHECK", name = "Ready check" },
	{ key = "RAID_WARNING", name = "Raid warning" },
	{ key = "ALARM_CLOCK_WARNING_2", name = "Alarm 1" },
	{ key = "ALARM_CLOCK_WARNING_3", name = "Alarm 2" },
}

function ns.PlayComboSound(key)
	local id = key and SOUNDKIT[key]
	if id then PlaySound(id, "Master") end
end

local bar, driver, hpBar, enBar, cpRow
local segs, last, max = {}, 0, 5
local GAP = 3

local function MaxPoints()
	local m = UnitPowerMax("player", Enum.PowerType.ComboPoints)
	return (m and m > 0) and m or 5
end

-- per-bar mode: "always" | "combat" | "off"; default only in combat
ns.COMBAT_BAR_MODES = {
	{ key = "always", name = "Always" },
	{ key = "combat", name = "Only in combat" },
	{ key = "off", name = "Disabled" },
}
local function Mode(key) return ns.db.combo[key] or "combat" end

local function MakeStatusBar(r, g, b)
	local s = CreateFrame("StatusBar", nil, bar)
	s:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	s:SetStatusBarColor(r, g, b)
	local bg = s:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	s.text:SetPoint("CENTER")
	return s
end

-- stack enabled rows top to bottom: health, energy, combo points
function C.Layout()
	if not bar then return end
	local c = ns.db.combo
	max = MaxPoints()
	local rows = {
		{ frame = hpBar, on = Mode("healthMode") ~= "off" },
		{ frame = enBar, on = Mode("energyMode") ~= "off" },
		{ frame = cpRow, on = Mode("comboMode") ~= "off" },
	}
	-- positions only depend on which rows are enabled, so hiding one out of combat leaves its slot
	local y = 0
	for _, row in ipairs(rows) do
		row.frame:ClearAllPoints()
		row.frame.enabled = row.on
		if not row.on then row.frame:Hide() end
		if row.on then
			row.frame:SetSize(c.width, c.height)
			row.frame:SetPoint("TOPLEFT", 0, -y)
			y = y + c.height + GAP
		end
	end
	bar:SetSize(c.width, math.max(y - GAP, 1))

	local w = (c.width - 2 - GAP * (max - 1)) / max
	for i = 1, math.max(max, #segs) do
		local s = segs[i]
		if not s then
			s = cpRow:CreateTexture(nil, "ARTWORK")
			segs[i] = s
		end
		s:ClearAllPoints()
		if i <= max then
			s:SetSize(w, c.height - 2)
			s:SetPoint("LEFT", 1 + (i - 1) * (w + GAP), 0)
			s:Show()
		else
			s:Hide()
		end
	end
	local any = rows[1].on or rows[2].on or rows[3].on
	driver:SetShown(any)
	bar:SetShown(any)
end

local function UpdateStatus(s, value, maxValue)
	s:SetMinMaxValues(0, math.max(maxValue, 1))
	s:SetValue(value)
	s.text:SetText(value)
end

local function Update()
	local cp = 0
	local hostile = UnitExists("target") and UnitCanAttack("player", "target")
	if hostile then cp = GetComboPoints("player", "target") or 0 end
	for i = 1, max do
		if i <= cp then
			if cp >= max then segs[i]:SetColorTexture(1, 0.15, 0.1) else segs[i]:SetColorTexture(1, 0.65, 0.1) end
		else
			segs[i]:SetColorTexture(0.15, 0.15, 0.15, 0.8)
		end
	end
	UpdateStatus(hpBar, UnitHealth("player"), UnitHealthMax("player"))
	UpdateStatus(enBar, UnitPower("player", Enum.PowerType.Energy), UnitPowerMax("player", Enum.PowerType.Energy))
	-- switching to a target that already has points is not "gaining" them: no sound
	local guid = UnitGUID("target")
	if guid ~= C.lastGuid then last, C.lastGuid = cp, guid end
	if Mode("comboMode") ~= "off" then
		local amount = ns.ComboSoundFor(last, cp)
		if amount then ns.PlayComboSound(ns.db.combo.sounds[amount]) end
	end
	last = cp

	-- per-row visibility; everything enabled shows while unlocked so it can be placed
	local inCombat = UnitAffectingCombat("player")
	local function Visible(row, mode, extra)
		row:SetShown(row.enabled and (ns.unlocked or ((inCombat or Mode(mode) == "always") and extra)))
	end
	Visible(hpBar, "healthMode", true)
	Visible(enBar, "energyMode", true)
	Visible(cpRow, "comboMode", hostile) -- combo points only mean something with a hostile target
end

local elapsed = 0
table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "ROGUE" then return end
	local c = ns.db.combo
	bar = CreateFrame("Frame", "DpwsComboBar", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	hpBar = MakeStatusBar(0.1, 0.8, 0.1)
	enBar = MakeStatusBar(1, 0.85, 0.1)
	cpRow = CreateFrame("Frame", nil, bar)
	local bg = cpRow:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	if c.pos then
		bar:SetPoint(c.pos.point, UIParent, c.pos.relPoint, c.pos.x, c.pos.y)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
	end
	ns.RegisterPanel(bar, "Combat Bars", function(self)
		local point, _, relPoint, x, y = self:GetPoint()
		c.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	-- the bar itself hides without a target, so polling runs on a separate frame
	driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.05 then return end
		elapsed = 0
		Update()
	end)
	C.Layout()
end)

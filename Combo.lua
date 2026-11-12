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

local bar, driver
local segs, last, max = {}, 0, 5

local function MaxPoints()
	local m = UnitPowerMax("player", Enum.PowerType.ComboPoints)
	return (m and m > 0) and m or 5
end

function C.Layout()
	if not bar then return end
	local c = ns.db.combo
	max = MaxPoints()
	bar:SetSize(c.width, c.height)
	local gap = 3
	local w = (c.width - 2 - gap * (max - 1)) / max
	for i = 1, math.max(max, #segs) do
		local s = segs[i]
		if not s then
			s = bar:CreateTexture(nil, "ARTWORK")
			segs[i] = s
		end
		s:ClearAllPoints()
		if i <= max then
			s:SetSize(w, c.height - 2)
			s:SetPoint("LEFT", 1 + (i - 1) * (w + gap), 0)
			s:Show()
		else
			s:Hide()
		end
	end
	driver:SetShown(c.enabled)
	if not c.enabled then bar:Hide() end
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
	-- switching to a target that already has points is not "gaining" them: no sound
	local guid = UnitGUID("target")
	if guid ~= C.lastGuid then last, C.lastGuid = cp, guid end
	local amount = ns.ComboSoundFor(last, cp)
	if amount then ns.PlayComboSound(ns.db.combo.sounds[amount]) end
	last = cp
	-- in combat with a hostile target; always while unlocked so it can be placed
	bar:SetShown((hostile and UnitAffectingCombat("player")) or ns.unlocked)
end

local elapsed = 0
table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "ROGUE" then return end
	local c = ns.db.combo
	bar = CreateFrame("Frame", "DpwsComboBar", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	if c.pos then
		bar:SetPoint(c.pos.point, UIParent, c.pos.relPoint, c.pos.x, c.pos.y)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
	end
	ns.RegisterPanel(bar, "Combo Points", function(self)
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

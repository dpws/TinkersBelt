local _, ns = ...

local FSR = 5 -- the five second rule (Forever has no mana ticks: regen is continuous, but stops for 5s after spending)

-- What to show at `now`. lastSpend: when mana was last spent.
-- Returns nil at full mana, else { phase = "fsr", remaining, fraction } or { phase = "regen" }.
function ns.ManaPhase(now, lastSpend, full)
	if full then return nil end
	if lastSpend and now - lastSpend < FSR then
		local remaining = FSR - (now - lastSpend)
		return { phase = "fsr", remaining = remaining, fraction = remaining / FSR }
	end
	return { phase = "regen" }
end

if not CreateFrame then return end -- offline test stops here

local MANA_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }
ns.MANA_CLASSES = MANA_CLASSES
local M = {}
ns.Mana = M

local MANA = Enum.PowerType.Mana
local function Secret(v) return issecretvalue and issecretvalue(v) end
local lastSpend, lastMana
local lastPowerEvent = 0 -- mana change events stop once mana is full: the fallback when mana is hidden
local bar, fill, text

local function Mode() return ns.On("mana") and (ns.db.mana.mode or "always") or "off" end

-- mana readable? (the engine can hide values from addons in combat)
local function ReadMana()
	local ok, mana, max = pcall(function() return UnitPower("player", MANA), UnitPowerMax("player", MANA) end)
	if not ok or Secret(mana) or Secret(max) then return nil end
	return mana, max
end

function M.Layout()
	if not bar then return end
	local m = ns.db.mana
	bar:SetSize(m.width, m.height)
end

local function Update()
	local now = GetTime()
	local mana, max = ReadMana()
	local full
	if mana and max then
		full = mana >= max
	else -- value hidden from addons: full = no mana changes lately and not in the 5 seconds
		full = now - lastPowerEvent > 2.5 and not (lastSpend and now - lastSpend < FSR)
	end
	local phase = ns.ManaPhase(now, lastSpend, full)
	local mode = Mode()
	local show = mode ~= "off" and (ns.unlocked or (phase and (mode == "always" or UnitAffectingCombat("player"))))
	bar:SetShown(show and true or false)
	if not show then return end
	phase = phase or { phase = "regen" } -- unlocked at full mana: show the bar to place it
	local w = bar:GetWidth()
	-- fills up over the 5 seconds; full + glowing = regenerating
	local regen = phase.phase ~= "fsr"
	fill:SetWidth(math.max(w * (regen and 1 or (1 - phase.fraction)), 0.01))
	text:SetText(regen and "" or ("%.1f"):format(math.floor(phase.remaining * 10) / 10)) -- rounded down: 0.96 reads 0.9
	if regen ~= bar.glow:IsShown() then
		bar.glow:SetShown(regen)
		if regen then bar.glowAnim:Play() else bar.glowAnim:Stop() end
	end
end

local function OnSpell(spellID)
	local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
	local costs = getCost and getCost(spellID)
	for _, c in ipairs(costs or {}) do
		if c.type == MANA and (c.cost or 0) > 0 then lastSpend = GetTime() return end
	end
end

local function OnPower()
	local mana = ReadMana()
	if not mana then return end
	if lastMana and mana < lastMana then lastSpend = GetTime() end -- spent (backup for casts the spell check missed)
	lastMana = mana
end

-- /tb mana: can the addon read mana, and what does the bar think
ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.mana = function()
	ns.Diagnose(function(Say)
		local mana, max = ReadMana()
		Say(("mana: readable=%s value=%s max=%s"):format(tostring(mana ~= nil), tostring(mana), tostring(max)))
		local now = GetTime()
		Say(("mana: last mana change %.1fs ago, last spend %s"):format(now - lastPowerEvent,
			lastSpend and ("%.1fs ago"):format(now - lastSpend) or "never"))
	end)
end

table.insert(ns.loginHooks, function()
	if not MANA_CLASSES[select(2, UnitClass("player"))] then return end
	local m = ns.db.mana
	bar = CreateFrame("Frame", "DpwsManaTickBar", UIParent)
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	fill = bar:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT")
	fill:SetPoint("BOTTOMLEFT")
	fill:SetColorTexture(0.3, 0.6, 1) -- mana blue
	-- soft pulsing glow around the bar while regenerating
	local glow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
	glow:SetPoint("TOPLEFT", -4, 4)
	glow:SetPoint("BOTTOMRIGHT", 4, -4)
	glow:SetColorTexture(0.4, 0.75, 1, 0.55)
	glow:SetBlendMode("ADD")
	glow:Hide()
	local ag = glow:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.25)
	a:SetDuration(0.8)
	bar.glow, bar.glowAnim = glow, ag
	text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", bar, "RIGHT", 4, 0)
	if m.pos then
		bar:SetPoint(m.pos.point, UIParent, m.pos.relPoint, m.pos.x, m.pos.y)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end
	ns.RegisterPanel(bar, "Mana Regen", function(self)
		local point, _, relPoint, x, y = self:GetPoint()
		m.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	M.Layout()

	local ev = CreateFrame("Frame")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	ev:SetScript("OnEvent", function(_, event, _, arg2, arg3)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			pcall(OnSpell, arg3) -- arg3 = spellID
		elseif arg2 == "MANA" then
			lastPowerEvent = GetTime()
			OnPower()
		end
	end)
	-- the bar hides at full mana, so the timer runs on its own frame
	local elapsed = 0
	ev:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.03 then return end
		elapsed = 0
		Update()
	end)
	lastMana = ReadMana()
end)

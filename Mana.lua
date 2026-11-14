local _, ns = ...

local FSR, TICK = 5, 2 -- the five second rule; Classic mana ticks every 2 seconds

-- What to show at `now`. lastSpend: when mana was last spent; lastTick: when a mana tick was last seen.
-- The 2s tick clock keeps running during the 5s rule (only spirit regen stops), so ticks are timed from
-- the last seen tick, or from the end of the 5s when none was seen yet.
-- Returns nil at full mana, else { phase = "fsr" | "tick", fraction, remaining?, tickFraction }.
function ns.ManaPhase(now, lastSpend, lastTick, full)
	if full then return nil end
	local base = lastTick or (lastSpend and lastSpend + FSR)
	local tickFraction = base and ((now - base) % TICK) / TICK or 0
	if lastSpend and now - lastSpend < FSR then
		local remaining = FSR - (now - lastSpend)
		return { phase = "fsr", remaining = remaining, fraction = remaining / FSR, tickFraction = tickFraction }
	end
	return { phase = "tick", fraction = tickFraction, tickFraction = tickFraction }
end

if not CreateFrame then return end -- offline test stops here

local MANA_CLASSES = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }
ns.MANA_CLASSES = MANA_CLASSES
local M = {}
ns.Mana = M

local MANA = Enum.PowerType.Mana
local function Secret(v) return issecretvalue and issecretvalue(v) end
local lastSpend, lastTick, lastMana
local lastPowerEvent = 0 -- mana change events stop once mana is full: the fallback when mana is hidden
local bar, fill, spark, text

local function Mode() return ns.db.mana.mode or "always" end

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
	spark:SetHeight(m.height + 6)
end

local function Update()
	local now = GetTime()
	local mana, max = ReadMana()
	local full
	if mana and max then
		full = mana >= max
	else -- value hidden from addons: full = no regen ticks lately and not in the 5 seconds
		full = now - lastPowerEvent > TICK + 0.5 and not (lastSpend and now - lastSpend < FSR)
	end
	local phase = ns.ManaPhase(now, lastSpend, lastTick, full)
	local mode = Mode()
	local show = mode ~= "off" and (ns.unlocked or (phase and (mode == "always" or UnitAffectingCombat("player"))))
	bar:SetShown(show and true or false)
	if not show then return end
	phase = phase or { phase = "tick", fraction = 0 } -- unlocked at full mana: show an empty bar to place it
	local w = bar:GetWidth()
	if phase.phase == "fsr" then
		fill:SetWidth(math.max(w * phase.fraction, 0.01))
		fill:Show()
		spark:Hide()
		text:SetFormattedText("%.1f", phase.remaining)
	else
		fill:Hide()
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", bar, "LEFT", w * phase.fraction, 0)
		spark:Show()
		text:SetText("")
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
	if lastMana then
		if mana < lastMana then lastSpend = GetTime() -- spent (backup for casts the spell check missed)
		elseif mana > lastMana then lastTick = GetTime() end -- a regen tick
	end
	lastMana = mana
end

-- /dpws mana: can the addon read mana, and what does the bar think
ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.mana = function()
	ns.Diagnose(function(Say)
		local mana, max = ReadMana()
		Say(("mana: readable=%s value=%s max=%s"):format(tostring(mana ~= nil), tostring(mana), tostring(max)))
		local now = GetTime()
		Say(("mana: last mana change %.1fs ago, last spend %s, last tick %s"):format(now - lastPowerEvent,
			lastSpend and ("%.1fs ago"):format(now - lastSpend) or "never", lastTick and ("%.1fs ago"):format(now - lastTick) or "never"))
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
	fill:SetColorTexture(1, 0.55, 0.1) -- orange: the 5 seconds
	spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetWidth(3)
	spark:SetColorTexture(0.3, 0.6, 1) -- blue: next mana tick
	text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", bar, "RIGHT", 4, 0)
	if m.pos then
		bar:SetPoint(m.pos.point, UIParent, m.pos.relPoint, m.pos.x, m.pos.y)
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	end
	ns.RegisterPanel(bar, "Mana Ticks", function(self)
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

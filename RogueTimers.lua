local _, ns = ...

-- seconds until ready; 0 = ready (the global cooldown, 1.5s or less, doesn't count)
function ns.CooldownLeft(start, duration, now)
	if not start or not duration or start == 0 or duration <= 1.5 then return 0 end
	return math.max(start + duration - now, 0)
end

-- rank 1 ids; only the ones you know are shown; off = hidden by default
ns.ROGUE_CDS = {
	{ id = 1766 }, -- Kick
	{ id = 1776 }, -- Gouge
	{ id = 408 }, -- Kidney Shot
	{ id = 2094 }, -- Blind
	{ id = 1856 }, -- Vanish
	{ id = 5277 }, -- Evasion
	{ id = 2983 }, -- Sprint
	{ id = 13750 }, -- Adrenaline Rush
	{ id = 13877 }, -- Blade Flurry
	{ id = 14177 }, -- Cold Blood
	{ id = 14185 }, -- Preparation
	{ id = 14183, off = true }, -- Premeditation
	{ id = 14278, off = true }, -- Ghostly Strike
	{ id = 14251, off = true }, -- Riposte
}
local SND = 5171 -- Slice and Dice

if not CreateFrame then return end -- offline test stops here

-- Rogue Timers: a Slice and Dice bar over a row of cooldown icons (bright = ready).
local T = ns.Theme
local R = {}
ns.RogueTimers = R
local function S() return ns.db.rogueTimers end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function SpellName(id)
	return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
end
local function SpellIcon(id)
	return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id))
end
local function Known(id) return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) end
function R.Shown(c)
	local off = S().off[c.id]
	if off == nil then off = c.off end
	return not off
end

local panel, snd, icons = nil, nil, {}
local BAR_H = 10

function R.Layout()
	if not panel then return end
	local s = S()
	local size = s.size or 28
	local top = s.snd and (BAR_H + 3) or 0
	local n = 0
	for i, c in ipairs(ns.ROGUE_CDS) do
		local b = icons[i]
		if Known(c.id) and R.Shown(c) then
			if not b then
				b = CreateFrame("Frame", nil, panel)
				b.icon = b:CreateTexture(nil, "ARTWORK")
				b.icon:SetAllPoints()
				b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				b.icon:SetTexture(SpellIcon(c.id))
				b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
				b.cd:SetAllPoints()
				b.cd:SetDrawEdge(false)
				b.spell = c.id
				icons[i] = b
			end
			b:SetSize(size, size)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", panel, "TOPLEFT", n * (size + 3), -top)
			b:Show()
			n = n + 1
		elseif b then
			b:Hide()
		end
	end
	local w = math.max(n, 3) * (size + 3) - 3
	panel:SetSize(w, size + top)
	snd:SetSize(w, BAR_H)
	snd:SetShown(s.snd)
end

local SND_IDS = { 5171, 6774 } -- ranks 1 and 2

-- the Slice and Dice aura table, or nil; by spell ID first, then by name
local function FindSnd()
	local byId = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if byId then
		for _, id in ipairs(SND_IDS) do
			local ok, a = pcall(byId, id)
			if ok and a then return a, "id" end
		end
	end
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	local name = SpellName(SND)
	if not get then return nil end
	for i = 1, 40 do
		local ok, a = pcall(get, "player", i, "HELPFUL")
		if not ok or not a then return nil end
		local sid = not Secret(a.spellId) and a.spellId
		if sid == 5171 or sid == 6774 or (name and not Secret(a.name) and a.name == name) then return a, "scan" end
	end
end

-- expirationTime, duration (numbers) or nil; secret = the aura is up but its timer is hidden
local function SndAura()
	local a = FindSnd()
	if not a then return nil end
	if Secret(a.expirationTime) or Secret(a.duration) then return nil, nil, a end
	return a.expirationTime, a.duration, a
end

ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.snd = function()
	ns.Diagnose(function(Say)
		local a, how = FindSnd()
		Say(("snd: bar=%s panel=%s shown=%s found=%s"):format(tostring(S().snd), tostring(panel ~= nil),
			tostring(panel and panel:IsShown()), tostring(how)))
		if a then
			Say(("snd: expiration=%s duration=%s id=%s"):format(Secret(a.expirationTime) and "SECRET" or tostring(a.expirationTime),
				Secret(a.duration) and "SECRET" or tostring(a.duration), tostring(a.auraInstanceID)))
		end
		Say(("snd: GetPlayerAuraBySpellID=%s GetAuraDuration=%s SetTimerDuration=%s"):format(
			tostring(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID ~= nil),
			tostring(C_UnitAuras and C_UnitAuras.GetAuraDuration ~= nil),
			tostring(snd and snd.SetTimerDuration ~= nil)))
	end)
end

local function Cooldown(id)
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, info = pcall(C_Spell.GetSpellCooldown, id)
		if ok and info then return info.startTime, info.duration end
	elseif GetSpellCooldown then
		return GetSpellCooldown(id)
	end
end

local function Update()
	if not panel then return end
	local s = S()
	local mode = s.mode or "combat"
	-- "combat" also shows while Slice and Dice is up (often cast before the pull)
	local show = ns.unlocked or mode == "always" or (mode == "combat" and (UnitAffectingCombat("player") or (s.snd and FindSnd() ~= nil)))
	panel:SetShown(show)
	if not show then return end
	local now = GetTime()
	for _, b in pairs(icons) do
		if b:IsShown() then
			local start, duration = Cooldown(b.spell)
			if Secret(start) or Secret(duration) then
				pcall(b.cd.SetCooldown, b.cd, start, duration) -- hidden values: let the game draw it
				b.icon:SetDesaturated(false)
			else
				local left = ns.CooldownLeft(start, duration, now)
				if left > 0 then
					if b.cdStart ~= start then b.cd:SetCooldown(start, duration) end
				else
					b.cd:Clear()
				end
				b.cdStart = left > 0 and start or nil
				b.icon:SetDesaturated(left > 0)
				b.icon:SetAlpha(left > 0 and 0.6 or 1)
			end
		end
	end
	if s.snd then
		local exp, dur, aura = SndAura()
		if exp and dur and dur > 0 then
			local left = math.max(exp - now, 0)
			snd:SetMinMaxValues(0, dur)
			snd:SetValue(left)
			snd.text:SetFormattedText("%d", math.ceil(left))
		elseif aura and not Secret(aura.auraInstanceID) and snd.SetTimerDuration and C_UnitAuras.GetAuraDuration then
			-- timer hidden from addons: the game can still drive the bar from the aura (once per aura)
			if snd.timerAura ~= aura.auraInstanceID then
				local ok = pcall(function()
					snd:SetTimerDuration(C_UnitAuras.GetAuraDuration("player", aura.auraInstanceID), nil, 1) -- 1 = drain
				end)
				snd.timerAura = ok and aura.auraInstanceID or nil
				snd.text:SetText("")
			end
		else
			snd.timerAura = nil
			snd:SetValue(0)
			snd.text:SetText("")
		end
	end
end
R.Update = Update

table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "ROGUE" then return end
	local s = S()
	panel = CreateFrame("Frame", "DpwsRogueTimers", UIParent)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	snd = CreateFrame("StatusBar", nil, panel)
	snd:SetPoint("TOPLEFT")
	snd:SetStatusBarTexture(T.WHITE)
	snd:SetStatusBarColor(0.95, 0.75, 0.2) -- Slice and Dice gold
	snd:SetMinMaxValues(0, 1)
	local bg = snd:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	snd.text = T.Text(snd, "semibold", 9, { 1, 1, 1, 1 })
	snd.text:SetPoint("CENTER")
	if s.pos then
		panel:SetPoint(s.pos.point, UIParent, s.pos.relPoint, s.pos.x, s.pos.y)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
	end
	ns.RegisterPanel(panel, "Rogue Timers", function(self)
		local point, _, relPoint, px, py = self:GetPoint()
		s.pos = { point = point, relPoint = relPoint, x = px, y = py }
	end)
	R.Layout()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("SPELLS_CHANGED")
	ev:SetScript("OnEvent", function() R.Layout() end)
	C_Timer.NewTicker(0.1, Update)
end)

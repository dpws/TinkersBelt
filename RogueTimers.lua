local _, ns = ...
local Loc = ns.L or setmetatable({}, { __index = function(_, k) return k end })

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
-- shamans get the same row (no Slice and Dice bar). The three shocks share one cooldown: Earth Shock stands for it.
ns.SHAMAN_CDS = {
	{ id = 8042 }, -- Earth Shock (= all shocks)
	{ id = 8177 }, -- Grounding Totem
	{ id = 17364 }, -- Stormstrike
	{ id = 16166 }, -- Elemental Mastery
	{ id = 16188 }, -- Nature's Swiftness
	{ id = 16190 }, -- Mana Tide Totem
	{ id = 1535 }, -- Fire Nova Totem
	{ id = 20608 }, -- Reincarnation
	{ id = 5730, off = true }, -- Stoneclaw Totem
	{ id = 2484, off = true }, -- Earthbind Totem
}
local SND = 5171 -- Slice and Dice

if not CreateFrame then return end -- offline test stops here

-- Rogue Timers: a Slice and Dice bar over a row of cooldown icons (bright = ready).
local T = ns.Theme
local R = {}
ns.RogueTimers = R
R.CDS = ns.ROGUE_CDS -- set per class at login
local function S() return ns.db.rogueTimers end
local function SndOn() return R.CDS == ns.ROGUE_CDS and S().snd end
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
	local top = SndOn() and (BAR_H + 3) or 0
	local n = 0
	for i, c in ipairs(R.CDS) do
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
			-- countdown numbers about a third of the icon
			local regions = { b.cd.GetCountdownFontString and b.cd:GetCountdownFontString(), b.cd:GetRegions() }
			for _, r in pairs(regions) do
				if r.GetObjectType and r:GetObjectType() == "FontString" then r:SetFont(T.font.semibold, s.textSize or math.max(math.floor(size * 0.36), 8), "OUTLINE") end
			end
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
	snd:SetShown(SndOn() and true or false)
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

-- by name: the ids are rank 1, and a rank you've replaced never goes on cooldown
local function Cooldown(id)
	local spell = SpellName(id) or id
	if C_Spell and C_Spell.GetSpellCooldown then
		local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
		if ok and info then return info.startTime, info.duration, info end
	elseif GetSpellCooldown then
		return GetSpellCooldown(spell)
	end
end

-- in combat Forever hides cooldown times: hand the hidden cooldown straight to the sweep
local function HiddenCooldown(b, start, duration)
	local spell = SpellName(b.spell) or b.spell
	if b.cd.SetCooldownFromDurationObject and C_Spell.GetSpellCooldownDuration then
		local ok = pcall(function() b.cd:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(spell)) end)
		if ok then return "duration" end
	end
	return pcall(b.cd.SetCooldown, b.cd, start, duration) and "secret" or "failed"
end

ns.slashCommands.cds = function()
	ns.Diagnose(function(Say)
		local now = GetTime()
		local _, any = next(icons)
		Say(("cds: GetSpellCooldownDuration=%s SetCooldownFromDurationObject=%s"):format(
			tostring(C_Spell.GetSpellCooldownDuration ~= nil), tostring(any and any.cd.SetCooldownFromDurationObject ~= nil)))
		for _, b in pairs(icons) do
			if b:IsShown() then
				local start, duration = Cooldown(b.spell)
				local function V(v) return Secret(v) and "SECRET" or tostring(v) end
				Say(("cds: %s start=%s duration=%s left=%s sweep=%s"):format(tostring(SpellName(b.spell)), V(start), V(duration),
					(Secret(start) or Secret(duration)) and "?" or ("%.1f"):format(ns.CooldownLeft(start, duration, now)), tostring(b.how)))
			end
		end
	end)
end

-- Slice and Dice is hidden in combat, but your cast isn't: time it from the cast. Its length per combo point
-- is learned whenever the buff is readable (out of combat, talents included); until then 6s + 3s per point.
local own -- { start, dur, cp } of your last cast
local cpSeen, cpSeenAt = nil, 0 -- last combo points read (they're spent by the time the cast event comes)
local lastCast = "none"
local function IsSnd(id)
	if not id or Secret(id) then return false end
	return id == 5171 or id == 6774 or SpellName(id) == SpellName(SND)
end
local function Learned() S().sndLearn = S().sndLearn or {} return S().sndLearn end
local function OnCast(spellID)
	if not IsSnd(spellID) then return end
	local now = GetTime()
	local cp = (now - cpSeenAt < 2) and cpSeen or nil
	local dur = (cp and (Learned()[cp] or (6 + 3 * cp))) or S().sndLast or 21
	own = { start = now, dur = dur, cp = cp }
	lastCast = (Loc["cp=%s dur=%s learned=%s"]):format(tostring(cp), tostring(dur), tostring(cp and Learned()[cp] ~= nil))
end
local function OnAura() end -- kept for the event hook

local function SndUp() return FindSnd() ~= nil or (own ~= nil and GetTime() < own.start + own.dur) end

ns.slashCommands.snd2 = function()
	ns.Diagnose(function(Say)
		Say(("snd: last cast %s, combo points seen=%s (%.1fs ago)"):format(lastCast, tostring(cpSeen), GetTime() - cpSeenAt))
		local parts = {}
		for cp, d in pairs(Learned()) do parts[#parts + 1] = cp .. "=" .. d end
		Say("snd: learned " .. (#parts > 0 and table.concat(parts, " ") or "nothing yet (cast it out of combat)"))
	end)
end

local function SetFill(on) snd:GetStatusBarTexture():SetAlpha(on and 1 or 0) end

local function Update()
	if not panel then return end
	local s = S()
	local now = GetTime()
	if SndOn() then -- combo points, sampled before they're spent
		local ok, cp = pcall(GetComboPoints, "player", "target")
		if ok and cp and not Secret(cp) and cp > 0 then cpSeen, cpSeenAt = cp, now end
	end
	local mode = ns.On("combat") and (s.mode or "combat") or "off"
	-- "combat" also shows while Slice and Dice is up (often cast before the pull)
	local show = ns.unlocked or mode == "always" or (mode == "combat" and (UnitAffectingCombat("player") or (SndOn() and SndUp())))
	panel:SetShown(show)
	if not show then return end
	for _, b in pairs(icons) do
		if b:IsShown() then
			local start, duration, info = Cooldown(b.spell)
			if Secret(start) or Secret(duration) then
				local gcd = info and not Secret(info.isOnGCD) and info.isOnGCD
				if gcd then b.cd:Clear() else b.how = HiddenCooldown(b, start, duration) end
				b.cdStart = nil
				b.icon:SetDesaturated(false)
				b.icon:SetAlpha(1)
			else
				local left = ns.CooldownLeft(start, duration, now)
				if left > 0 then
					if b.cdStart ~= start then b.cd:SetCooldown(start, duration) end
				else
					b.cd:Clear()
				end
				b.cdStart = left > 0 and start or nil
				b.how = "readable"
				b.icon:SetDesaturated(left > 0)
				b.icon:SetAlpha(left > 0 and 0.6 or 1)
			end
		end
	end
	if SndOn() then
		local exp, dur = SndAura()
		if exp and dur and dur > 0 then
			-- readable: learn its length for the combo points of the cast that made it
			if own and own.cp and math.abs((exp - dur) - own.start) < 1 then
				Learned()[own.cp] = dur
				own.dur = dur
			end
			s.sndLast = dur
		elseif own and now < own.start + own.dur then
			exp, dur = own.start + own.dur, own.dur
		end
		if exp and dur and dur > 0 and exp > now then
			local left = exp - now
			snd:SetMinMaxValues(0, dur)
			snd:SetValue(left)
			SetFill(true)
			snd.text:SetFormattedText("%d", math.floor(left)) -- last second reads 0, like the game's timers
		else
			snd:SetValue(0)
			SetFill(false)
			snd.text:SetText("")
		end
	end
end
R.Update = Update

table.insert(ns.loginHooks, function()
	local class = select(2, UnitClass("player"))
	if class ~= "ROGUE" and class ~= "SHAMAN" then return end
	R.CDS = class == "SHAMAN" and ns.SHAMAN_CDS or ns.ROGUE_CDS
	local s = S()
	panel = CreateFrame("Frame", "DpwsRogueTimers", UIParent)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	snd = CreateFrame("StatusBar", nil, panel)
	snd:SetPoint("TOPLEFT")
	snd:SetStatusBarTexture(T.BAR)
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
	ns.RegisterPanel(panel, class == "SHAMAN" and "Cooldowns" or "Rogue Timers", function(self)
		local point, _, relPoint, px, py = self:GetPoint()
		s.pos = { point = point, relPoint = relPoint, x = px, y = py }
	end)
	R.Layout()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("SPELLS_CHANGED")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:RegisterUnitEvent("UNIT_AURA", "player")
	ev:SetScript("OnEvent", function(_, event, _, a2, a3)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then pcall(OnCast, a3)
		elseif event == "UNIT_AURA" then pcall(OnAura, a2)
		else R.Layout() end
	end)
	C_Timer.NewTicker(0.1, Update)
end)

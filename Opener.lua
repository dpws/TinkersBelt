local _, ns = ...

-- creature type "Humanoid" in each client language (Sap and Pick Pocket work on humanoids only)
ns.HUMANOID = {
	["Humanoid"] = true, ["Гуманоид"] = true, ["Humanoïde"] = true, ["Humanoide"] = true, ["Umanoide"] = true,
	["인간형"] = true, ["人型生物"] = true, ["人形生物"] = true,
}

-- markers for your target while you're stealthed: Sap (humanoid, not fighting), Pick Pocket (humanoid NPC not
-- picked yet). t = { stealthed, attackable, dead, combat, humanoid, player, picked }
function ns.OpenerTags(t)
	if not (t.stealthed and t.attackable) or t.dead or t.combat then return {} end
	local tags = {}
	if t.humanoid then tags[#tags + 1] = "Sap" end
	if t.humanoid and not t.player and not t.picked then tags[#tags + 1] = "Pick Pocket" end
	return tags
end

-- macro that equips a weapon set: set = { mh = { name }, oh = { name } }
function ns.WeaponMacro(set)
	local lines = {}
	if set.mh then lines[#lines + 1] = "/equipslot 16 " .. set.mh.name end
	if set.oh then lines[#lines + 1] = "/equipslot 17 " .. set.oh.name end
	return table.concat(lines, "\n")
end

if not CreateFrame then return end -- offline test stops here

-- Opener helper: Sap / Pick Pocket markers for your target while stealthed, and two weapon set buttons
-- (e.g. a dagger for Ambush and your swords for the fight).
local T = ns.Theme
local O = {}
ns.Opener = O
local function S() return ns.db.opener end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local PICK_POCKET = 921
local picked = {} -- GUIDs you picked this session

local marker, sets, setButtons = nil, nil, {}

-- one value at a time: Forever can hide (secret) any of them; nil = couldn't read
local function Read(fn, ...)
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then return nil end
	return v
end

local function TargetFacts()
	local ctype = Read(UnitCreatureType, "target")
	local guid = Read(UnitGUID, "target")
	local stealthed = IsStealthed and Read(IsStealthed)
	if stealthed == nil then stealthed = Read(GetShapeshiftForm) == 1 end -- rogue Stealth is stance 1
	return {
		stealthed = stealthed,
		attackable = Read(UnitCanAttack, "player", "target"),
		dead = Read(UnitIsDeadOrGhost, "target"),
		combat = Read(UnitAffectingCombat, "target"),
		humanoid = ctype == nil or ns.HUMANOID[ctype] or false, -- unreadable type: assume it may be humanoid
		player = Read(UnitIsPlayer, "target"),
		picked = guid ~= nil and picked[guid] or false,
		ctype = ctype,
	}
end

local function UpdateMarker()
	if not marker then return end
	local tags = {}
	if S().markers and UnitExists("target") then
		local ok, t = pcall(ns.OpenerTags, TargetFacts())
		tags = ok and t or {}
	end
	marker.text:SetText(table.concat(tags, "  ·  "))
	marker:SetShown(#tags > 0 or ns.unlocked)
	if ns.unlocked and #tags == 0 then marker.text:SetText("Sap  ·  Pick Pocket") end
end

-- /dpws opener: what the marker sees for your target
ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.opener = function()
	ns.Diagnose(function(Say)
		Say(("opener: markers=%s panel=%s target=%s"):format(tostring(S().markers), tostring(marker ~= nil),
			tostring(UnitExists("target"))))
		if UnitExists("target") then
			local t = TargetFacts()
			for _, k in ipairs({ "stealthed", "attackable", "dead", "combat", "ctype", "humanoid", "player", "picked" }) do
				Say(("opener: %s=%s"):format(k, tostring(t[k])))
			end
			Say("opener: tags=" .. table.concat(ns.OpenerTags(t), ", "))
		end
	end)
end

---------------------------------------------------------------------------
-- weapon sets

local function ItemOf(slot)
	local id = GetInventoryItemID("player", slot)
	if not id then return nil end
	local name = C_Item.GetItemNameByID(id) or GetItemInfo(id)
	return name and { id = id, name = name } or nil
end

function O.SaveSet(key)
	local s = S()
	s.sets[key] = { mh = ItemOf(16), oh = ItemOf(17) }
	ns.Notify(("Weapon set saved: %s"):format(key == "opener" and "Opener" or "Fight"))
	O.UpdateSets()
end

function O.UpdateSets()
	if not sets then return end
	local s = S()
	local any = false
	for i, key in ipairs({ "opener", "fight" }) do
		local b, set = setButtons[i], s.sets[key]
		local on = set ~= nil and set.mh ~= nil
		any = any or on
		if not InCombatLockdown() then
			b:SetAttribute("macrotext", on and ns.WeaponMacro(set) or "")
			b:SetShown(on or ns.unlocked)
		end
		b.icon:SetTexture(on and C_Item.GetItemIconByID(set.mh.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
		-- teal frame: the set you're wearing
		b.sel:SetShown(on and GetInventoryItemID("player", 16) == set.mh.id
			and (not set.oh or GetInventoryItemID("player", 17) == set.oh.id))
	end
	if not InCombatLockdown() then sets:SetShown(s.weapons and (any or ns.unlocked)) end
end

local function SetButton(i, key, label)
	local b = CreateFrame("Button", "DpwsWeaponSet" .. i, sets, "SecureActionButtonTemplate")
	b:SetSize(32, 32)
	b:SetPoint("LEFT", (i - 1) * 38, 0)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type", "macro")
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetPoint("TOPLEFT", -2, 2)
	b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
	b.sel:SetColorTexture(unpack(T.gold))
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local t = T.Text(b, "semibold", 9, T.muted)
	t:SetPoint("TOP", b, "BOTTOM", 0, -2)
	t:SetText(label)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local set = S().sets[key]
		GameTooltip:AddLine(label .. " weapons")
		if set then
			if set.mh then GameTooltip:AddLine(set.mh.name, 1, 1, 1) end
			if set.oh then GameTooltip:AddLine(set.oh.name, 1, 1, 1) end
		else
			GameTooltip:AddLine("Save it on the Openers page (/dpws)", 0.6, 0.65, 0.7)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	setButtons[i] = b
end

local function Place(frame, pos, x, y, name)
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
	end
	ns.RegisterPanel(frame, name, function(self)
		local point, _, relPoint, px, py = self:GetPoint()
		local key = name == "Opener" and "markerPos" or "setsPos"
		S()[key] = { point = point, relPoint = relPoint, x = px, y = py }
	end)
end

table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "ROGUE" then return end
	local s = S()
	marker = CreateFrame("Frame", "DpwsOpenerMarker", UIParent)
	marker:SetSize(200, 22)
	marker:SetMovable(true)
	marker:SetClampedToScreen(true)
	marker.text = T.Text(marker, "semibold", 15, T.gold)
	marker.text:SetPoint("CENTER")
	marker.text:SetJustifyH("CENTER")
	Place(marker, s.markerPos, 0, 120, "Opener")
	marker:Hide()

	sets = CreateFrame("Frame", "DpwsWeaponSets", UIParent)
	sets:SetSize(70, 32)
	sets:SetMovable(true)
	sets:SetClampedToScreen(true)
	SetButton(1, "opener", "Opener")
	SetButton(2, "fight", "Fight")
	Place(sets, s.setsPos, -200, -150, "Weapon Sets")

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_TARGET_CHANGED")
	ev:RegisterEvent("UPDATE_STEALTH")
	ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:SetScript("OnEvent", function(_, event, _, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if spellID == PICK_POCKET then
				local guid = UnitGUID("target")
				if guid and not Secret(guid) then picked[guid] = true end
			end
		elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
			O.UpdateSets()
		end
		UpdateMarker()
	end)
	C_Timer.NewTicker(0.5, UpdateMarker) -- target entering combat, panels unlocked
	C_Timer.NewTicker(2, function() if not InCombatLockdown() then O.UpdateSets() end end)
	O.UpdateSets()
end)

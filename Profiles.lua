local _, ns = ...

local function TKey(t) return t.tab .. ":" .. t.i end

-- Next talent to put a point into: lowest tier first (tier requirements), then tab, then index.
-- rankOf(tab, i) gives the current rank; skip holds "tab:i" keys that failed.
function ns.TalentNextStep(saved, rankOf, skip)
	local best
	for _, t in ipairs(saved) do
		if t.rank > rankOf(t.tab, t.i) and not (skip and skip[TKey(t)]) then
			if not best or t.tier < best.tier or (t.tier == best.tier and (t.tab < best.tab or (t.tab == best.tab and t.i < best.i))) then
				best = t
			end
		end
	end
	return best
end

local function SameAction(a, b)
	if a == nil or b == nil then return a == b end
	return a.t == b.t and a.id == b.id and a.name == b.name
end

-- Slots whose content differs: { [slot] = { action = saved or nil (= clear) } }
function ns.BarRestorePlan(want, have, slots)
	local plan = {}
	for s = 1, slots do
		if not SameAction(want[s], have[s]) then plan[s] = { action = want[s] } end
	end
	return plan
end

if not CreateFrame then return end -- offline test stops here

local SLOTS = 180
local BACKUP = "(backup)"
local P = {}
ns.Profiles = P

local function Store()
	local class = select(2, UnitClass("player"))
	ns.adb.profiles = ns.adb.profiles or {}
	ns.adb.profiles[class] = ns.adb.profiles[class] or {}
	return ns.adb.profiles[class]
end

local function SpellName(id)
	return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
end

local function SnapshotBars()
	local bars = {}
	for s = 1, SLOTS do
		local t, id = GetActionInfo(s)
		if t == "macro" then
			local name = GetMacroInfo(id)
			if name then bars[s] = { t = "macro", name = name } end
		elseif t == "equipmentset" then
			bars[s] = { t = "equipmentset", name = id }
		elseif t then
			bars[s] = { t = t, id = id }
		end
	end
	return bars
end

local function CurrentRank(tab, i) return select(5, GetTalentInfo(tab, i)) or 0 end

local function SnapshotTalents()
	local talents = {}
	for tab = 1, GetNumTalentTabs() do
		for i = 1, GetNumTalents(tab) do
			local name, _, tier, _, rank = GetTalentInfo(tab, i)
			if rank and rank > 0 then talents[#talents + 1] = { tab = tab, i = i, tier = tier, rank = rank, name = name } end
		end
	end
	return talents
end

function P.List()
	local names = {}
	for name in pairs(Store()) do names[#names + 1] = name end
	table.sort(names)
	return names
end

function P.Get(name) return Store()[name] end

function P.Save(name)
	Store()[name] = {
		bars = SnapshotBars(),
		talents = SnapshotTalents(),
		by = UnitName("player"),
		at = time(),
	}
	if ns.OnProfilesChanged then ns.OnProfilesChanged() end
end

function P.Delete(name)
	Store()[name] = nil
	if ns.OnProfilesChanged then ns.OnProfilesChanged() end
end

-- put one saved action on the cursor and into the slot; false if it couldn't be placed
local function Place(slot, a)
	ClearCursor()
	if a.t == "spell" then
		PickupSpell(a.id)
		if not GetCursorInfo() and SpellName(a.id) then PickupSpell(SpellName(a.id)) end -- other rank: by name
	elseif a.t == "item" then
		(C_Item and C_Item.PickupItem or PickupItem)(a.id)
	elseif a.t == "macro" then
		local index = GetMacroIndexByName(a.name)
		if index and index > 0 then PickupMacro(index) end
	elseif a.t == "equipmentset" and C_EquipmentSet then
		local id = C_EquipmentSet.GetEquipmentSetID(a.name)
		if id then C_EquipmentSet.PickupEquipmentSet(id) end
	end
	if not GetCursorInfo() then return false end
	PlaceAction(slot)
	ClearCursor()
	return true
end

local function Describe(a)
	if a.t == "spell" then return SpellName(a.id) or ("spell " .. a.id) end
	if a.t == "item" then return (GetItemInfo and GetItemInfo(a.id)) or ("item " .. a.id) end
	return (a.name or a.id or "?") .. " (" .. a.t .. ")"
end

function P.LoadBars(name)
	if InCombatLockdown() then print("dpws_tools: can't change action bars in combat") return end
	local profile = Store()[name]
	if not profile then return end
	local want = profile.bars -- read before the backup may overwrite it
	if name ~= BACKUP then P.Save(BACKUP) end
	local failed = {}
	for slot, step in pairs(ns.BarRestorePlan(want, SnapshotBars(), SLOTS)) do
		if step.action then
			if not Place(slot, step.action) then failed[#failed + 1] = Describe(step.action) end
		else
			PickupAction(slot)
			ClearCursor()
		end
	end
	ClearCursor()
	if #failed > 0 then
		print(("dpws_tools: bars loaded from '%s', not placed: %s"):format(name, table.concat(failed, ", ")))
	else
		print(("dpws_tools: bars loaded from '%s' (previous bars saved as '%s')"):format(name, BACKUP))
	end
end

local function Unspent()
	if GetUnspentTalentPoints then return GetUnspentTalentPoints() or 0 end
	return UnitCharacterPoints("player") or 0
end

-- one point at a time; each LearnTalent waits for the server before the next
local applying
local function TalentStep()
	if not applying then return end
	local t = Unspent() > 0 and ns.TalentNextStep(applying.saved, CurrentRank, applying.skip)
	if not t then
		local missing = 0
		for _, s in ipairs(applying.saved) do missing = missing + math.max(0, s.rank - CurrentRank(s.tab, s.i)) end
		print(("dpws_tools: talents from '%s' done%s"):format(applying.name,
			missing > 0 and (", %d points not spent (reset talents at a trainer first?)"):format(missing) or ""))
		applying = nil
		return
	end
	local k = TKey(t)
	if applying.lastKey == k and CurrentRank(t.tab, t.i) == applying.lastRank then
		applying.tries = applying.tries + 1
		if applying.tries >= 3 then applying.skip[k] = true end -- server keeps refusing: move on
	else
		applying.lastKey, applying.lastRank, applying.tries = k, CurrentRank(t.tab, t.i), 0
	end
	if not applying.skip[k] then LearnTalent(t.tab, t.i) end
	C_Timer.After(0.4, TalentStep)
end

function P.LoadTalents(name)
	local profile = Store()[name]
	if not profile or applying then return end
	if Unspent() == 0 then print("dpws_tools: no unspent talent points (reset talents at a trainer first)") return end
	applying = { name = name, saved = profile.talents, skip = {} }
	TalentStep()
end

function P.LoadBoth(name)
	P.LoadBars(name)
	P.LoadTalents(name)
end

-- Talent window: a button with a profiles menu
local attached
local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("dpws profiles")
		for _, name in ipairs(P.List()) do
			local sub = root:CreateButton(name)
			sub:CreateButton("Load talents", function() P.LoadTalents(name) end)
			sub:CreateButton("Load bars", function() P.LoadBars(name) end)
			sub:CreateButton("Load both", function() P.LoadBoth(name) end)
		end
		root:CreateDivider()
		root:CreateButton("Save / manage...", function() ns.OpenWindow("Profiles") end)
	end)
end

local function Attach()
	if attached then return end
	-- Classic talent window; on the Retail-style UI only its talents panel (PlayerSpellsFrame is also the spellbook)
	local frame = _G.PlayerTalentFrame or (_G.PlayerSpellsFrame and _G.PlayerSpellsFrame.TalentsFrame)
	if not frame then return end
	local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	b:SetSize(120, 22)
	b:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -24, 2)
	b:SetText("dpws Profiles")
	b:SetScript("OnClick", OpenMenu)
	attached = true
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED") -- the talent UI loads on demand
f:SetScript("OnEvent", Attach)
table.insert(ns.loginHooks, Attach)

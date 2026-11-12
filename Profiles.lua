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

-- action kinds we can put back; anything else (mounts, pets, flyouts, unreadable macros) is never touched
local RESTORABLE = { spell = true, item = true, macro = true, equipmentset = true }

-- Slots whose content differs: { [slot] = { action = saved or nil (= clear) } }
function ns.BarRestorePlan(want, have, slots)
	local plan = {}
	for s = 1, slots do
		local w, h = want[s], have[s]
		if not SameAction(w, h) and (h == nil or RESTORABLE[h.t]) and (w == nil or RESTORABLE[w.t]) then
			plan[s] = { action = w }
		end
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

-- bar APIs moved into C_ namespaces on newer engines: resolve once, refuse to start if any is missing
local function ResolveAPI()
	local api = {
		pickupSpell = C_Spell and C_Spell.PickupSpell or PickupSpell,
		pickupItem = C_Item and C_Item.PickupItem or PickupItem,
		pickupMacro = PickupMacro,
		pickupAction = C_ActionBar and C_ActionBar.PickupAction or PickupAction,
		placeAction = C_ActionBar and C_ActionBar.PlaceAction or PlaceAction,
		actionText = C_ActionBar and C_ActionBar.GetActionText or GetActionText,
		macroIndex = GetMacroIndexByName,
	}
	for k, fn in pairs(api) do
		if type(fn) ~= "function" then return nil, k end
	end
	return api
end

local function SnapshotBars()
	local api = ResolveAPI()
	local bars = {}
	for s = 1, SLOTS do
		local t, id, subType = GetActionInfo(s)
		if t == "macro" then
			-- a macro showing a spell/item reports that spell/item id, not the macro index: find it by its name
			local name
			if subType == "spell" or subType == "item" then
				name = api and api.actionText(s)
			else
				name = GetMacroInfo(id)
			end
			local index = name and name ~= "" and GetMacroIndexByName(name)
			bars[s] = (index and index > 0) and { t = "macro", name = name } or { t = "unknown" }
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
local function Place(api, slot, a)
	ClearCursor()
	if a.t == "spell" then
		api.pickupSpell(a.id)
		if not GetCursorInfo() and SpellName(a.id) then api.pickupSpell(SpellName(a.id)) end -- other rank: by name
	elseif a.t == "item" then
		api.pickupItem(a.id)
	elseif a.t == "macro" then
		local index = api.macroIndex(a.name)
		if index and index > 0 then api.pickupMacro(index) end
	elseif a.t == "equipmentset" and C_EquipmentSet then
		local id = C_EquipmentSet.GetEquipmentSetID(a.name)
		if id then C_EquipmentSet.PickupEquipmentSet(id) end
	end
	if not GetCursorInfo() then return false end
	api.placeAction(slot)
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
	local api, missing = ResolveAPI()
	if not api then print("dpws_tools: can't load bars on this client (missing " .. missing .. "), nothing changed") return end
	local plan = ns.BarRestorePlan(profile.bars, SnapshotBars(), SLOTS) -- built before the backup may overwrite it
	if not next(plan) then print(("dpws_tools: bars already match '%s'"):format(name)) return end
	if name ~= BACKUP then P.Save(BACKUP) end
	local failed = {}
	for slot, step in pairs(plan) do
		-- one slot failing must not stop the rest halfway
		local ok, placed = pcall(function()
			if step.action then return Place(api, slot, step.action) end
			api.pickupAction(slot)
			ClearCursor()
			return true
		end)
		if not (ok and placed) and step.action then failed[#failed + 1] = Describe(step.action) end
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

-- One point at a time. A point is only sent when none is pending; a pending point resolves when its rank
-- goes up (landed) or after PENDING_TIMEOUT (refused). Never two requests for the same rank.
local PENDING_TIMEOUT, MAX_FAILS = 2, 2
local applying, ticker

local function Finish()
	if ticker then ticker:Cancel(); ticker = nil end
	local a = applying
	applying = nil
	local missing = 0
	for _, s in ipairs(a.saved) do missing = missing + math.max(0, s.rank - CurrentRank(s.tab, s.i)) end
	print(("dpws_tools: talents from '%s' done%s"):format(a.name,
		missing > 0 and (", %d points not spent (reset talents at a trainer first?)"):format(missing) or ""))
	if a.onDone then a.onDone() end
end

local function TalentTick()
	if not applying then return end
	local a = applying
	local p = a.pending
	if p then
		if CurrentRank(p.tab, p.i) > p.rank then
			a.pending, a.skip = nil, {} -- landed: a blocked talent may be learnable now
		elseif GetTime() - p.sentAt > PENDING_TIMEOUT then
			a.pending = nil
			a.fails[p.key] = (a.fails[p.key] or 0) + 1
			if a.fails[p.key] >= MAX_FAILS then a.skip[p.key] = true end
		else
			return -- still waiting for the server
		end
	end
	local t = Unspent() > 0 and ns.TalentNextStep(a.saved, CurrentRank, a.skip)
	if not t then return Finish() end
	a.pending = { tab = t.tab, i = t.i, key = TKey(t), rank = CurrentRank(t.tab, t.i), sentAt = GetTime() }
	LearnTalent(t.tab, t.i)
end

-- onDone runs after the last point (used by LoadBoth to place talent spells afterwards)
function P.LoadTalents(name, onDone)
	local profile = Store()[name]
	if not profile or applying then return false end
	if Unspent() == 0 then print("dpws_tools: no unspent talent points (reset talents at a trainer first)") return false end
	applying = { name = name, saved = profile.talents, skip = {}, fails = {}, onDone = onDone }
	ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(TalentTick)
		if not ok then -- never leave the stepper stuck
			if ticker then ticker:Cancel(); ticker = nil end
			applying = nil
			print("dpws_tools: talent loading stopped: " .. tostring(err))
		end
	end)
	return true
end

-- talents first: spells granted by talents must be known before they can go on the bars
function P.LoadBoth(name)
	if not P.LoadTalents(name, function() P.LoadBars(name) end) then P.LoadBars(name) end
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

local f = CreateFrame("Frame")
-- Forever shows talents in PlayerSpellsFrame (spellbook + talents window); PlayerTalentFrame on other clients
local function Attach()
	local frame = _G.PlayerSpellsFrame or _G.PlayerTalentFrame
	if attached or not frame then return end
	-- own top-level frame (the window's inner panels were drawn over a child button); follows the window
	local b = CreateFrame("Button", "DpwsProfilesTalentButton", UIParent, "UIPanelButtonTemplate")
	b:SetSize(120, 22)
	b:SetFrameStrata("DIALOG")
	b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -1)
	b:SetText("dpws Profiles")
	b:SetScript("OnClick", OpenMenu)
	b:SetShown(frame:IsShown())
	frame:HookScript("OnShow", function() b:Show() end)
	frame:HookScript("OnHide", function() b:Hide() end)
	attached = b
	f:UnregisterEvent("ADDON_LOADED")
end
f:RegisterEvent("ADDON_LOADED") -- the talent UI loads on demand
f:SetScript("OnEvent", Attach)

-- /dpws frames: which talent-like windows are open (to find the talent window on this client)
ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.frames = function()
	print(("dpws_tools: profiles button attached: %s"):format(attached and "yes" or "no"))
	if attached then
		local x, y = attached:GetCenter()
		print(("  button visible: %s, position: %s, %s (screen %d x %d)"):format(tostring(attached:IsVisible()),
			tostring(x and math.floor(x)), tostring(y and math.floor(y)), UIParent:GetWidth(), UIParent:GetHeight()))
	end
	local found = 0
	for name, obj in pairs(_G) do
		if type(name) == "string" and (name:find("Talent") or name:find("Spells")) and type(obj) == "table" then
			local ok, shown = pcall(function() return obj.IsShown and obj:IsShown() and obj.GetObjectType and obj:GetObjectType() == "Frame" end)
			if ok and shown then
				found = found + 1
				print("  shown: " .. name)
			end
		end
	end
	if found == 0 then print("  no talent/spells window is open - open it and try again") end
end
table.insert(ns.loginHooks, Attach)

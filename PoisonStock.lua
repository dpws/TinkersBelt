local _, ns = ...

-- recipes: poisonID -> { reagents = { [itemID] = qty }, makes = n }; count(id) -> in bags

-- Ingredients to buy so every stocked poison can be crafted back up to its amount.
function ns.PoisonMaterialsNeed(stock, recipes, count)
	local need = {}
	for id, target in pairs(stock) do
		local recipe = recipes[id]
		local missing = target - count(id)
		if recipe and missing > 0 then
			local crafts = math.ceil(missing / (recipe.makes or 1))
			for r, q in pairs(recipe.reagents) do need[r] = (need[r] or 0) + crafts * q end
		end
	end
	for r, n in pairs(need) do
		n = n - count(r)
		need[r] = n > 0 and n or nil
	end
	return need
end

-- how many crafts the bags allow
function ns.PoisonCanMake(recipe, count)
	local n
	for r, q in pairs(recipe.reagents) do
		local k = math.floor(count(r) / q)
		n = n and math.min(n, k) or k
	end
	return n or 0
end

-- first stocked poison (in `order`) that is short and can be made: { id, crafts }
function ns.PoisonNextCraft(stock, recipes, count, order)
	for _, id in ipairs(order) do
		local target, recipe = stock[id], recipes[id]
		if target and recipe then
			local missing = target - count(id)
			local can = ns.PoisonCanMake(recipe, count)
			if missing > 0 and can > 0 then
				return { id = id, crafts = math.min(math.ceil(missing / (recipe.makes or 1)), can) }
			end
		end
	end
end

if not CreateFrame then return end -- offline test stops here

local POISONS_SPELL = 2842 -- the Poisons skill (opens its window)
local S = {}
ns.PoisonStock = S

local function Count(id) return (C_Item and C_Item.GetItemCount or GetItemCount)(id) end
local function ItemName(id)
	return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
end
local function Recipes() return ns.db.poisonRecipes end -- per character: only what this rogue has learned
local function Stock() return ns.db.poisons.stock end

-- the materials restock should buy (itemID -> target count), used by Restock.lua at vendors
function S.MaterialTargets()
	local targets = {}
	-- non-rogues (or before login) have no stock list: their restock must still work
	if ns.db.poisons.buyMats == false or not Stock() or not Recipes() then return targets end
	for id, n in pairs(ns.PoisonMaterialsNeed(Stock(), Recipes(), Count)) do targets[id] = Count(id) + n end
	return targets
end

-- /tb tradeskill: with the Poisons window open, show what each profession API reports
ns.slashCommands = ns.slashCommands or {}
ns.slashCommands.tradeskill = function()
	local function idOf(link) return link and tonumber(link:match("item:(%d+)")) end
	ns.Diagnose(function(Say)
		local P = function(msg) Say("tradeskill: " .. msg) end
		P(("frames shown: ProfessionsFrame=%s TradeSkillFrame=%s CraftFrame=%s"):format(
			tostring(ProfessionsFrame and ProfessionsFrame:IsShown()), tostring(TradeSkillFrame and TradeSkillFrame:IsShown()),
			tostring(CraftFrame and CraftFrame:IsShown())))
		if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
			local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
			local learned = 0
			for _, rid in ipairs(ids) do
				local info = C_TradeSkillUI.GetRecipeInfo(rid)
				if info and info.learned then
					learned = learned + 1
					local s = C_TradeSkillUI.GetRecipeSchematic(rid, false)
					P(("  learned: recipe %d -> item %s (%s)"):format(rid, tostring(s and s.outputItemID), tostring(s and s.name)))
				end
			end
			P(("C_TradeSkillUI: %d recipes, %d marked learned by the game"):format(#ids, learned))
		else
			P("C_TradeSkillUI: not available")
		end
		if GetNumTradeSkills then
			local n = GetNumTradeSkills()
			P(("GetNumTradeSkills: %d lines, skill line %s"):format(n, tostring(GetTradeSkillLine and GetTradeSkillLine())))
			local shown = 0
			for i = 1, n do
				local name, kind = GetTradeSkillInfo(i)
				if kind ~= "header" and shown < 4 then
					shown = shown + 1
					P(("  %d: %s -> item %s"):format(i, tostring(name), tostring(idOf(GetTradeSkillItemLink(i)))))
				end
			end
		else
			P("GetNumTradeSkills: not available")
		end
		local learned = 0
		for _ in pairs(Recipes() or {}) do learned = learned + 1 end
		P(("poison recipes known by this character: %d (built-in poison IDs start %d, %d, %d...)"):format(
			learned, ns.POISON_IDS[1], ns.POISON_IDS[2], ns.POISON_IDS[3]))
	end)
end

-- one line per stocked poison, for /tb restock
function S.Describe()
	local lines = {}
	if not Stock() then return lines end
	for id, target in pairs(Stock()) do
		local recipe = Recipes() and Recipes()[id]
		lines[#lines + 1] = ("poison %s: have %d / %d, recipe %s"):format(ItemName(id), Count(id), target,
			recipe and "known" or "NOT known (open your Poisons window once)")
	end
	return lines
end

-- Learn recipes from the open profession window; remember how to craft each poison this session.
local handles = {} -- poisonID -> { recipeID } or { index } or { craftIndex }
local craftOpen = false -- set by CRAFT_SHOW / CRAFT_CLOSE (the frame may not be shown yet at CRAFT_SHOW)
local function itemIdOf(link) return link and tonumber(link:match("item:(%d+)")) end

local function Learn()
	local isPoison = {}
	for _, id in ipairs(ns.POISON_IDS) do isPoison[id] = true end
	wipe(handles)
	if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
		local all = C_TradeSkillUI.GetAllRecipeIDs() or {}
		-- the Poisons window = one that makes a known poison; then every recipe in it is a poison
		-- (Forever also has newer ones like Atrophic Poison)
		local poisonsWindow = false
		for _, rid in ipairs(all) do
			local s = C_TradeSkillUI.GetRecipeSchematic(rid, false)
			if s and isPoison[s.outputItemID] then poisonsWindow = true break end
		end
		if poisonsWindow then
			wipe(Recipes()) -- rebuilt fresh: only what this character has learned now
			for _, rid in ipairs(all) do
				local info = C_TradeSkillUI.GetRecipeInfo(rid)
				local s = info and info.learned and C_TradeSkillUI.GetRecipeSchematic(rid, false) -- the list also has unlearned ones
				if s and s.outputItemID then
					local reagents = {}
					for _, slot in ipairs(s.reagentSlotSchematics or {}) do
						local r = slot.reagents and slot.reagents[1]
						if r and r.itemID then reagents[r.itemID] = slot.quantityRequired end
					end
					Recipes()[s.outputItemID] = { reagents = reagents, makes = math.max(1, s.quantityMin or 1) }
					handles[s.outputItemID] = { recipeID = rid }
				end
			end
		end
	end
	-- Classic "Craft" window (Poisons and Enchanting use it, not the trade skill window)
	if GetNumCrafts and craftOpen then
		for i = 1, GetNumCrafts() do
			local _, _, kind = GetCraftInfo(i)
			local id = kind ~= "header" and GetCraftItemLink and itemIdOf(GetCraftItemLink(i))
			if id and isPoison[id] then
				local reagents = {}
				for j = 1, GetCraftNumReagents(i) do
					local rid = itemIdOf(GetCraftReagentItemLink(i, j))
					local _, _, qty = GetCraftReagentInfo(i, j)
					if rid and qty then reagents[rid] = qty end
				end
				Recipes()[id] = { reagents = reagents, makes = 1 }
				handles[id] = { craftIndex = i }
			end
		end
	end
	if GetNumTradeSkills then
		for i = 1, GetNumTradeSkills() do
			local _, kind = GetTradeSkillInfo(i)
			local id = kind ~= "header" and itemIdOf(GetTradeSkillItemLink(i))
			if id and isPoison[id] then
				local reagents = {}
				for j = 1, GetTradeSkillNumReagents(i) do
					local rid = itemIdOf(GetTradeSkillReagentItemLink(i, j))
					local _, _, qty = GetTradeSkillReagentInfo(i, j)
					if rid and qty then reagents[rid] = qty end
				end
				Recipes()[id] = { reagents = reagents, makes = math.max(1, GetTradeSkillNumMade and GetTradeSkillNumMade(i) or 1) }
				handles[id] = { index = i }
			end
		end
	end
end

local function Craft(id, crafts)
	local h = handles[id]
	if not h then print("Tinker's Belt: open your Poisons window first (left-click the craft button)") return end
	if h.craftIndex then
		DoCraft(h.craftIndex) -- the Craft window makes one per call: one poison per click
	elseif h.recipeID then
		C_TradeSkillUI.CraftRecipe(h.recipeID, crafts)
	else
		DoTradeSkill(h.index, crafts)
	end
end

-- Small craft button on the poison bar
local button
local function NextCraft() return ns.PoisonNextCraft(Stock(), Recipes(), Count, ns.AllPoisonIds()) end

local function UpdateButton()
	if not button then return end
	local ok, job = pcall(NextCraft)
	job = ok and job or nil
	local open = next(handles) ~= nil
	ns.RunOutOfCombat(function()
		-- window closed: the click opens it (casting needs the secure macro); open: PostClick crafts
		button:SetAttribute("type1", (not open) and "macro" or nil)
		button:SetShown(job ~= nil and ns.db.poisons.enabled)
	end)
end
S.Update = UpdateButton

local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Craft poison")
		local ids = {}
		for id in pairs(Stock()) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local recipe = Recipes()[id]
			local can = recipe and ns.PoisonCanMake(recipe, Count) or 0
			local missing = Stock()[id] - Count(id)
			local crafts = math.min(math.ceil(math.max(missing, 0) / (recipe and recipe.makes or 1)), can)
			local b = root:CreateButton(("%s  %d/%d  (can make %d)"):format(ItemName(id), Count(id), Stock()[id], can),
				function() Craft(id, crafts) end)
			if crafts <= 0 then b:SetEnabled(false) end
		end
		if #ids == 0 then root:CreateButton("No poisons in stock list (/tb > Rogue > Poison Stock)"):SetEnabled(false) end
	end)
end

table.insert(ns.loginHooks, function()
	if select(2, UnitClass("player")) ~= "ROGUE" then return end
	ns.db.poisons.stock = ns.db.poisons.stock or {}
	ns.db.poisonRecipes = ns.db.poisonRecipes or {}
	ns.adb.poisonRecipes = nil -- old shared list counted unlearned recipes too
	local bar = ns.Poisons and ns.Poisons.bar
	if not bar then return end
	button = CreateFrame("Button", "DpwsPoisonCraftButton", bar, "SecureActionButtonTemplate")
	button:SetSize(24, 24)
	button:SetPoint("LEFT", bar, "RIGHT", 6, 0)
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(POISONS_SPELL)) or GetSpellInfo(POISONS_SPELL)
	button:SetAttribute("macrotext1", "/cast " .. (spellName or "Poisons"))
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(POISONS_SPELL)) or GetSpellTexture(POISONS_SPELL))
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	-- craft only if the window was already open before this click: the click that opens it would
	-- otherwise start crafting while the window is still opening, which stops the batch after one
	button:SetScript("PreClick", function(self) self.wasOpen = next(handles) ~= nil end)
	button:SetScript("PostClick", function(self, mouse)
		if mouse == "RightButton" then return OpenMenu(self) end
		if self.wasOpen then
			local job = NextCraft()
			if job then Craft(job.id, job.crafts) end
		end
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Craft poisons")
		GameTooltip:AddLine("Left-click: open Poisons, click again to craft what's short", 1, 1, 1, true)
		GameTooltip:AddLine("Right-click: choose which poison to craft", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()

	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE", "NEW_RECIPE_LEARNED",
		"CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE", "BAG_UPDATE_DELAYED" }) do
		pcall(ev.RegisterEvent, ev, e)
	end
	ev:SetScript("OnEvent", function(_, event)
		if event == "CRAFT_SHOW" then craftOpen = true elseif event == "CRAFT_CLOSE" then craftOpen = false end
		if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then wipe(handles)
		elseif event ~= "BAG_UPDATE_DELAYED" then
			xpcall(Learn, geterrorhandler())
			if ns.PoisonStockPageRefresh then ns.PoisonStockPageRefresh() end
		end
		UpdateButton()
	end)
	UpdateButton()
end)

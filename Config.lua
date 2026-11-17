local ADDON, ns = ...
local T = ns.Theme

ns.STATE_LABELS = {
	ROGUE = { [1] = "Stealth" },
	DRUID = { [1] = "Cat Form", [2] = "Prowl", [3] = "Bear Form", [4] = "Moonkin / Tree of Life" },
	WARRIOR = { [1] = "Battle Stance", [2] = "Defensive Stance", [3] = "Berserker Stance" },
	PRIEST = { [1] = "Shadowform" },
}

local window

local function ItemName(id) return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id) end
local function ItemIcon(id) return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or GetItemIcon(id) end
local function ItemCount(id) return (C_Item and C_Item.GetItemCount or GetItemCount)(id) end

---------------------------------------------------------------------------
-- Stealth action bars

-- name of a currently visible bar that owns this page, if any
local function VisibleOwner(page)
	if page == 1 then return "Bar 1" end
	for _, bar in ipairs(ns.BARS) do
		local f = _G[bar.frame]
		if bar.page == page and f and f:IsVisible() then return bar.name end
	end
end

-- green = bar visible now, gray = hidden (good to borrow)
local function Colored(name, visible)
	return (visible and "|cff4dcc66%s|r" or "|cff8c96a3%s|r"):format(name)
end

local function BarLabel(bar)
	local f = _G[bar.frame]
	return Colored(bar.name, f and f:IsVisible())
end

local function PageLabel(page)
	for _, bar in ipairs(ns.BARS) do
		if bar.page == page then return BarLabel(bar) end
	end
	if page == 1 then return Colored("Bar 1", true) end
	return Colored(("Bar 1, page %d"):format(page), false)
end

local function BuildBarSwitchPage(parent)
	local P = T.Page(parent)
	local labels = ns.STATE_LABELS[select(2, UnitClass("player"))]
	if not labels then
		P:Note("No stance states for this class.")
		P:Finish()
		return
	end
	P:Note("Pick which page each bar shows while in a state. Put spells on that page by dragging them onto the bar while the state is active. Green bars are visible now, gray ones are hidden and free to borrow.")
	-- MelloUI's own bars replace Blizzard bars 2-8, which are the ones this addon switches
	if _G.MelloUIActionBar2Button1 then
		P:Note("MelloUI's own action bars are active: bar switching won't affect them.", T.red)
	end
	for state = 1, 4 do
		if labels[state] then
			P:Card(labels[state])
			for _, bar in ipairs(ns.BARS) do
				local function Get() return ns.db.barSwitch[state] and ns.db.barSwitch[state][bar.index] end
				local d, row = P:Dropdown(BarLabel(bar), function(root)
					root:CreateRadio("None", function() return Get() == nil end, function()
						ns.db.barSwitch[state] = ns.db.barSwitch[state] or {}
						ns.db.barSwitch[state][bar.index] = nil
						if not next(ns.db.barSwitch[state]) then ns.db.barSwitch[state] = nil end
						ns.ApplyBarSwitch()
					end)
					for _, page in ipairs(ns.ValidPages(bar.index)) do
						root:CreateRadio(PageLabel(page), function() return Get() == page end, function()
							ns.db.barSwitch[state] = ns.db.barSwitch[state] or {}
							ns.db.barSwitch[state][bar.index] = page
							if InCombatLockdown() then print("dpws_tools: change applies after combat") end
							ns.ApplyBarSwitch()
						end)
					end
				end, 240)
				local label = select(1, row:GetRegions())
				local warn = T.Text(row, "medium", 11, { 1, 0.6, 0.2, 1 })
				warn:SetPoint("RIGHT", d, "LEFT", -12, 0)
				P:Refresher(function()
					if label and label.SetText then label:SetText(BarLabel(bar)) end
					local owner = Get() and VisibleOwner(Get())
					warn:SetText(owner and ("in use on " .. owner) or "")
				end)
			end
		end
	end
	P:Finish()
end

-- on-screen overlays showing the number of each visible bar
local overlays, highlightsOn = {}, false
local HIGHLIGHT_BARS = { { frame = "MainActionBar", name = "Bar 1" } }
for _, bar in ipairs(ns.BARS) do HIGHLIGHT_BARS[#HIGHLIGHT_BARS + 1] = bar end

local function SetHighlights(on)
	highlightsOn = on
	for _, bar in ipairs(HIGHLIGHT_BARS) do
		local target = _G[bar.frame] or (bar.name == "Bar 1" and _G.MainMenuBar)
		local o = overlays[bar.name]
		if on and target and target:IsVisible() then
			if not o then
				-- parented to UIParent, only anchored to the bar: never touches the protected bar itself
				o = CreateFrame("Frame", nil, UIParent)
				o:SetFrameStrata("DIALOG")
				T.Panel(o, T.Accent(0.18), T.Accent(0.8))
				local text = T.Text(o, "semibold", 26, T.gold)
				text:SetPoint("CENTER")
				text:SetText(bar.name:match("%d+"))
				overlays[bar.name] = o
			end
			o:ClearAllPoints()
			o:SetAllPoints(target)
			o:Show()
		elseif o then
			o:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Rogue

local function BuildPoisonsPage(parent)
	local P = T.Page(parent)
	if select(2, UnitClass("player")) ~= "ROGUE" then
		P:Note("The poison bar is for rogues.")
		return P:Finish()
	end
	local p = ns.db.poisons
	local function Rescale() if ns.Poisons then ns.Poisons.ApplyScale() end end
	P:Card("Reminders")
	P:Toggle("Play sound with warnings", function() return p.sound end, function(v) p.sound = v end)
	P:Slider("Warn when less than", 1, 15, 1, "min", function() return p.warnMinutes end, function(v) p.warnMinutes = v end)
	P:Card("Size")
	P:Slider("Weapon icons", 50, 200, 10, "%", function() return (p.scale or 1) * 100 end,
		function(v) p.scale = v / 100; Rescale() end)
	P:Slider("Poison icon", 50, 200, 10, "%", function() return (p.poisonScale or 1) * 100 end,
		function(v) p.poisonScale = v / 100; Rescale() end)
	P:Note("On the bar: left-click applies the chosen poison, right-click chooses it. Use Unlock panels to move the bar.")
	P:Finish()
end

local function BuildPoisonStockPage(parent)
	local p = ns.db.poisons
	p.stock = p.stock or {}
	local function Changed() if ns.PoisonStock then ns.PoisonStock.Update() end end
	local P = T.Page(parent)
	local Refresh

	P:Card("Poisons to keep in bags")
	local status = P:Note(" \n ") -- two lines reserved: the text is set later
	P:Toggle("Buy ingredients", function() return p.buyMats ~= false end, function(v) p.buyMats = v end)
	local rows, MAX_ROWS = {}, 9
	local add
	P:Custom(38, function(row)
		add = T.NewDropdown(row, 260)
		add:SetPoint("LEFT")
		add:SetDefaultText("Add poison...")
		add:SetupMenu(function(_, root)
			-- once recipes are known, offer only poisons this character can craft
			local known = ns.db.poisonRecipes
			local onlyKnown = known and next(known) ~= nil
			local any = false
			for _, id in ipairs(ns.AllPoisonIds()) do
				if not p.stock[id] and (not onlyKnown or known[id]) then
					any = true
					root:CreateButton(("|T%s:16|t %s"):format(ItemIcon(id) or 134400, ItemName(id)),
						function() p.stock[id] = 20; Refresh(); Changed() end)
				end
			end
			-- an empty menu draws broken: say why instead
			if not any then root:CreateButton("All your poisons are already added"):SetEnabled(false) end
		end)
	end)
	local card, rowsTop = P.card, P.card.y -- the card shrinks to the poisons listed
	for i = 1, MAX_ROWS do
		P:Custom(30, function(row)
			local r = {}
			r.icon = row:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(20, 20)
			r.icon:SetPoint("LEFT", 2, 0)
			r.name = T.Text(row, "medium", 13)
			r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
			r.name:SetWidth(260)
			r.name:SetWordWrap(false)
			r.remove = T.NewButton(row, "Remove", 76, 24)
			r.remove:SetPoint("RIGHT")
			r.count = T.NewInput(row, 56, true)
			r.count:SetPoint("RIGHT", r.remove, "LEFT", -10, 0)
			r.have = T.Text(row, "regular", 12, T.muted)
			r.have:SetPoint("RIGHT", r.count, "LEFT", -12, 0)
			r.frame = row
			rows[i] = r
		end)
	end

	Refresh = function()
		local learned = 0
		for _ in pairs(ns.db.poisonRecipes or {}) do learned = learned + 1 end
		status:SetText(learned > 0 and ("%d poison recipes known. Amount = how many to keep in bags."):format(learned)
			or "|cffffcc00Open your Poisons window once so the addon learns the recipes (until then nothing is bought).|r")
		local ids = {}
		for id in pairs(p.stock) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, r in ipairs(rows) do
			local id = ids[i]
			r.frame:SetShown(id ~= nil)
			if id then
				r.icon:SetTexture(ItemIcon(id))
				r.name:SetText(ItemName(id))
				r.have:SetText(("have %d"):format(ItemCount(id)))
				r.count:SetText(p.stock[id])
				local function Save()
					local n = tonumber(r.count:GetText())
					if n and n > 0 and p.stock[id] then p.stock[id] = n; Changed() end
					r.count:ClearFocus()
				end
				r.count:SetScript("OnEnterPressed", Save)
				r.count:SetScript("OnEditFocusLost", Save)
				r.remove:SetScript("OnClick", function() p.stock[id] = nil; Refresh(); Changed() end)
			end
		end
		local hidden = (MAX_ROWS - math.min(#ids, MAX_ROWS)) * 30
		card:SetHeight(-rowsTop + (MAX_ROWS * 30 - hidden) + 10)
		parent:SetHeight(math.max(-P.y + 8 - hidden, 1)) -- scroll area follows
		add:GenerateMenu()
	end
	P:Refresher(Refresh)
	P:EndCard()
	local tip = P:Note("A small craft button shows next to the poison bar when something is short and you have the materials: left-click opens Poisons, click again to craft; right-click picks a poison. Ingredients use the Auto Restock spending limit.")
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 2, -18)
	P:Finish()
end

local function BuildRogueTimersPage(parent)
	local s = ns.db.rogueTimers
	local function Relayout() if ns.RogueTimers then ns.RogueTimers.Layout() end end
	local MODES = {}
	for _, m in ipairs(ns.COMBAT_BAR_MODES or {}) do MODES[#MODES + 1] = { m.key, m.name } end
	local P = T.Page(parent)
	P:Card("Slice and Dice and cooldowns")
	P:Choice("Show", MODES, function() return s.mode or "combat" end, function(v) s.mode = v end, 240)
	P:Toggle("Slice and Dice bar", function() return s.snd end, function(v) s.snd = v; Relayout() end)
	P:Slider("Icon size", 18, 48, 1, "px", function() return s.size or 28 end, function(v) s.size = v; Relayout() end)
	P:Slider("Countdown text size", 6, 24, 1, "px", function() return s.textSize or math.max(math.floor((s.size or 28) * 0.36), 8) end,
		function(v) s.textSize = v; Relayout() end)
	P:Card("Cooldowns to show")
	for _, c in ipairs(ns.ROGUE_CDS or {}) do
		local name = C_Spell.GetSpellName(c.id)
		if name and IsPlayerSpell(c.id) then
			P:Toggle(("|T%s:16|t  %s"):format(C_Spell.GetSpellTexture(c.id) or 134400, name),
				function() return ns.RogueTimers.Shown(c) end,
				function(v) s.off[c.id] = not v; Relayout() end)
		end
	end
	P:Note("Bright = ready, dark with a sweep = cooling down. Only spells you know are listed. Use Unlock panels to move it.")
	P:Finish()
end

local function BuildLockboxPage(parent)
	local P = T.Page(parent)
	P:Card("How it works")
	P:Note("When your bags hold a lockbox (or junkbox, locked chest) your Lockpicking skill can open, a button appears. Click it: it casts Pick Lock on the box; click again to open it. The number = boxes ready. Boxes your skill is too low for are skipped. Use Unlock panels to move the button.")
	P:Finish()
end

local function BuildOpenerPage(parent)
	local s = ns.db.opener
	local P = T.Page(parent)
	P:Card("Target markers")
	P:Toggle("Show a Pick Pocket icon on enemy nameplates while stealthed", function() return s.markers end, function(v) s.markers = v end)
	P:Slider("Icon size", 12, 48, 1, "px", function() return s.iconSize or 18 end, function(v) s.iconSize = v end)
	P:Note("The icon shows above NPCs that aren't fighting, no target needed (enemy nameplates must be on). Forever hides which mob is which from addons, so a picked mob is remembered only while it stays your target or keeps its nameplate, and beasts may get the icon too.")
	P:Card("Weapon sets")
	P:Toggle("Show the weapon set buttons", function() return s.weapons end,
		function(v) s.weapons = v; if ns.Opener then ns.Opener.UpdateSets() end end)
	for _, set in ipairs({ { "opener", "Opener" }, { "fight", "Fight" } }) do
		P:Custom(34, function(row)
			local label = T.Text(row, "medium", 13)
			label:SetPoint("LEFT")
			label:SetWidth(380)
			label:SetWordWrap(false)
			local save = T.NewButton(row, "Save current weapons", 170, 26)
			save:SetPoint("RIGHT")
			local function Show()
				local w = s.sets[set[1]]
				local names = w and ((w.mh and w.mh.name or "-") .. (w.oh and (" + " .. w.oh.name) or "")) or "|cff8c96a3not saved|r"
				label:SetText(set[2] .. ":  " .. names)
			end
			save:SetScript("OnClick", function()
				if InCombatLockdown() then return end
				if ns.Opener then ns.Opener.SaveSet(set[1]) end
				Show()
			end)
			P:Refresher(Show)
		end)
	end
	P:Note("Equip your opener weapons (e.g. a dagger for Ambush) and save them as Opener, then your fight weapons as Fight. Two buttons appear: click to swap (works in combat too). Teal frame = the set you're wearing. Use Unlock panels to move them.")
	P:Finish()
end

local function BuildComboPage(parent)
	local c = ns.db.combo
	local function Relayout() if ns.Combo then ns.Combo.Layout() end end
	local MODES = {}
	for _, m in ipairs(ns.COMBAT_BAR_MODES or {}) do MODES[#MODES + 1] = { m.key, m.name } end
	local P = T.Page(parent)
	P:Card("Bars")
	for _, row in ipairs({ { "Health", "healthMode" }, { "Energy", "energyMode" }, { "Combo points", "comboMode" } }) do
		P:Choice(row[1], MODES, function() return c[row[2]] or "combat" end, function(v) c[row[2]] = v; Relayout() end, 240)
	end
	P:Card("Size")
	P:Slider("Width", 60, 400, 10, "px", function() return c.width end, function(v) c.width = v; Relayout() end)
	P:Slider("Height", 6, 40, 1, "px", function() return c.height end, function(v) c.height = v; Relayout() end)
	P:Card("Combo point sounds")
	for n = 1, 5 do
		P:Sound(n == 1 and "1 point" or (n .. " points"), function() return c.sounds[n] end, function(key) c.sounds[n] = key end)
	end
	P:Note("A sound plays when your combo points rise to that amount. Use Unlock panels to move the bars.")
	P:Finish()
end

---------------------------------------------------------------------------
-- Caster

local function BuildManaPage(parent)
	local m = ns.db.mana
	local function Relayout() if ns.Mana then ns.Mana.Layout() end end
	local P = T.Page(parent)
	P:Card("Display")
	P:Choice("Show", { { "always", "Always" }, { "combat", "Only in combat" }, { "off", "Disabled" } },
		function() return m.mode or "always" end, function(v) m.mode = v end, 240)
	P:Card("Size")
	P:Slider("Width", 60, 400, 10, "px", function() return m.width end, function(v) m.width = v; Relayout() end)
	P:Slider("Height", 4, 30, 1, "px", function() return m.height end, function(v) m.height = v; Relayout() end)
	P:Note("After you spend mana the bar fills up over the 5 seconds (no regen), with a countdown; full and glowing = regenerating. Hidden at full mana. Use Unlock panels to move it.")
	P:Finish()
end

---------------------------------------------------------------------------
-- General

local function BuildPvpPage(parent)
	local a = ns.adb
	local P = T.Page(parent)
	local stats, reset
	P:Card("Score")
	P:Custom(36, function(row)
		stats = T.Text(row, "medium", 13)
		stats:SetPoint("LEFT", 2, 0)
		reset = T.NewButton(row, "Reset all scores", 170, 26)
		reset:SetPoint("RIGHT")
	end)
	local function ShowStats()
		local players, k, d = 0, 0, 0
		for _, e in pairs(a.pvp) do players, k, d = players + 1, k + e.k, e.d + d end
		stats:SetText(("%d players tracked.  Total %s"):format(players, ns.PvpScoreText({ k = k, d = d })))
	end
	-- two clicks to reset: no popup dialog
	local armed = false
	local function ResetText() reset:SetText(armed and "Click again to reset" or "Reset all scores") end
	reset:SetScript("OnClick", function()
		if armed then
			wipe(a.pvp)
			wipe(a.pvpLog)
			armed = false
			ns.OnPvpLogChanged()
		else
			armed = true
		end
		ResetText()
	end)
	P:Refresher(ShowStats)
	P:Refresher(function() armed = false; ResetText() end)

	-- history: newest first
	P:Card("Latest kills and deaths")
	local PER_PAGE = 13
	local COLS = { { "When", 0 }, { "", 100 }, { "Name", 170 }, { "Class", 380 }, { "Lvl", 500 } }
	local function Cells(row, font, color)
		local cells = {}
		for c, col in ipairs(COLS) do
			local fs = T.Text(row, font, 12, color)
			fs:SetPoint("LEFT", 2 + col[2], 0)
			fs:SetWidth((COLS[c + 1] and COLS[c + 1][2] or 560) - col[2] - 6)
			fs:SetWordWrap(false)
			cells[c] = fs
		end
		return cells
	end
	P:Custom(22, function(row)
		for c, fs in ipairs(Cells(row, "semibold", T.muted)) do fs:SetText(COLS[c][1]) end
	end)
	local rows = {}
	for i = 1, PER_PAGE do
		P:Custom(22, function(row)
			if i % 2 == 0 then
				local alt = row:CreateTexture(nil, "BACKGROUND")
				alt:SetAllPoints()
				alt:SetColorTexture(1, 1, 1, 0.025)
			end
			rows[i] = Cells(row, "regular")
		end)
	end
	local page, prev, nextB, pageText = 1
	P:Custom(36, function(row)
		prev = T.NewButton(row, "< Newer", 100, 24)
		prev:SetPoint("LEFT")
		pageText = T.Text(row, "medium", 12, T.muted)
		pageText:SetPoint("LEFT", prev, "RIGHT", 16, 0)
		nextB = T.NewButton(row, "Older >", 100, 24)
		nextB:SetPoint("LEFT", pageText, "RIGHT", 16, 0)
	end)
	local function ShowPage()
		local items, pages, p = ns.PvpPage(a.pvpLog, page, PER_PAGE)
		page = p
		for i, cells in ipairs(rows) do
			local e = items[i]
			if e then
				local color = e.class and RAID_CLASS_COLORS[e.class]
				local className = e.class and (LOCALIZED_CLASS_NAMES_MALE[e.class] or e.class) or "?"
				cells[1]:SetText(date("%m-%d %H:%M", e.t))
				cells[2]:SetText(e.kind == "k" and "|cff4dcc66Killed|r" or "|cfff25a4dDied|r")
				cells[3]:SetText(e.name or "?")
				cells[4]:SetText(color and ("|c%s%s|r"):format(color.colorStr, className) or className)
				cells[5]:SetText((e.level and e.level > 0) and e.level or "??")
			else
				for _, fs in ipairs(cells) do fs:SetText("") end
			end
		end
		if #a.pvpLog == 0 then rows[1][3]:SetText("No kills or deaths yet") end
		pageText:SetText(("Page %d / %d"):format(page, pages))
		prev:SetEnabled(page > 1)
		nextB:SetEnabled(page < pages)
	end
	prev:SetScript("OnClick", function() page = page - 1; ShowPage() end)
	nextB:SetScript("OnClick", function() page = page + 1; ShowPage() end)
	P:Refresher(function() page = 1; ShowPage() end)
	-- live update while the page is open
	ns.OnPvpLogChanged = function() if parent:IsVisible() then ShowStats(); ShowPage() end end
	P:Finish()
end

local function BuildPvpSettingsPage(parent)
	local a = ns.adb
	local P = T.Page(parent)
	P:Card("Tooltip and announcements")
	P:Toggle("Show PvP score on player tooltips", function() return a.pvpTooltip end, function(v) a.pvpTooltip = v end)
	P:Toggle("Announce kills and deaths (name, level, class, score)", function() return a.pvpAnnounce end, function(v) a.pvpAnnounce = v end)
	P:Card("Sounds")
	P:Sound("Kill sound", function() return a.pvpKillSound end, function(key) a.pvpKillSound = key end)
	P:Sound("Death sound", function() return a.pvpDeathSound end, function(key) a.pvpDeathSound = key end)
	P:Note("Open world only (not battlegrounds, arenas or dungeons). A death counts for the last enemy player who targeted you within 10 seconds. Announcements use the Notifications panel.")
	P:Finish()
end

local function BuildNearbyPage(parent)
	local s = ns.adb.nearby
	local P = T.Page(parent)
	P:Card("List")
	P:Slider("Remove after not seen for", 15, 300, 15, "sec", function() return s.timeout end, function(v) s.timeout = v end)
	P:Card("Alert")
	P:Choice("Alert", { { "off", "Off" }, { "all", "Every new enemy" }, { "killers", "Only players who killed me" } },
		function() return s.alert end, function(v) s.alert = v end, 260)
	P:Sound("Alert sound", function() return s.sound end, function(key) s.sound = key end)
	P:Note("Players are found by their nameplates (turn on enemy nameplates with Ctrl+V), your target and mouseover. Stealthed players are not seen until they show up. Open world only. Use Unlock panels to move the list.")
	P:Finish()
end

local function BuildBuffsPage(parent)
	local s = ns.db.buffs
	local function Refresh() if ns.Buffs then ns.Buffs.Update() end end
	local P = T.Page(parent)
	P:Card("Reminder")
	P:Slider("Warn when less than", 1, 10, 1, "min", function() return s.warn or 3 end, function(v) s.warn = v; Refresh() end)
	P:Toggle("Sound when a buff drops off you", function() return s.sound end, function(v) s.sound = v end)
	local any = false
	for _, e in ipairs(ns.Buffs and ns.Buffs.entries or {}) do
		if e.def.reminder ~= false and not e.def.custom then
			any = true
			local key = e.def.key
			P:Toggle("Remind: " .. table.concat(e.known, " / ") .. (e.def.self and "  (you)" or "  (you and group)"),
				function() local off = s.off[key]; if off == nil then off = e.def.off end; return not off end,
				function(v) s.off[key] = not v; Refresh() end)
		end
	end
	if not any then P:Note("You don't know any buffs this tracks yet.") end

	P:Card("My extra buffs")
	local rows, RefreshList, MAX_ROWS = {}, nil, 6
	local function SpellId(text)
		local id = tonumber(text:match("spell:(%d+)") or text:match("^%s*(%d+)%s*$"))
		if id then return id end
		local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(strtrim(text))
		return info and info.spellID
	end
	P:Custom(38, function(row)
		local input = T.NewInput(row, 260)
		input:SetPoint("LEFT")
		local add = T.NewButton(row, "Add", 64, 26)
		add:SetPoint("LEFT", input, "RIGHT", 8, 0)
		local function DoAdd()
			local id = SpellId(input:GetText() or "")
			if id then s.custom[id] = true else ns.Notify("No spell found: " .. (input:GetText() or "")) end
			input:SetText("")
			input:ClearFocus()
			if ns.Buffs then ns.Buffs.Reload() end
			RefreshList()
		end
		add:SetScript("OnClick", DoAdd)
		input:SetScript("OnEnterPressed", DoAdd)
		-- Shift-click a spell in your spellbook puts its link into our box while it has focus
		local function InsertLink(link)
			if input:HasFocus() and link then input:Insert(link) end
		end
		if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end
		if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink) end
	end)
	for i = 1, MAX_ROWS do
		P:Custom(30, function(row)
			local x = { frame = row }
			x.icon = row:CreateTexture(nil, "ARTWORK")
			x.icon:SetSize(20, 20)
			x.icon:SetPoint("LEFT", 2, 0)
			x.name = T.Text(row, "medium", 13)
			x.name:SetPoint("LEFT", x.icon, "RIGHT", 10, 0)
			x.remove = T.NewButton(row, "Remove", 76, 24)
			x.remove:SetPoint("RIGHT")
			rows[i] = x
		end)
	end
	P:Note("Any buff you cast on yourself (an aura, Righteous Fury, a shield...): type its name or Shift-click it in your spellbook. Reminded when it's missing; click the reminder to cast it.")
	RefreshList = function()
		local ids = {}
		for id in pairs(s.custom) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, x in ipairs(rows) do
			local id = ids[i]
			x.frame:SetShown(id ~= nil)
			if id then
				local info = C_Spell.GetSpellInfo(id)
				x.icon:SetTexture(info and info.iconID)
				x.name:SetText(info and info.name or ("spell " .. id))
				x.remove:SetScript("OnClick", function()
					s.custom[id] = nil
					if ns.Buffs then ns.Buffs.Reload() end
					RefreshList()
				end)
			end
		end
	end
	P:Refresher(RefreshList)

	P:Card("Party frames")
	P:Toggle("Buff buttons beside party frames", function() return s.strips end, function(v) s.strips = v; Refresh() end)
	P:Slider("Button size", 12, 32, 1, "px", function() return s.size or 18 end, function(v) s.size = v; Refresh() end)
	P:Note("One button per buff you can cast, right of each party member's frame (DandersFrames or Blizzard). Dim = they have it, red border = missing, minutes = running out. Click to cast on that member. Paladins: each member shows only the blessing you last gave them; right-click it to pick another from icons (? = show all). Solo and in a party, not in raids.")
	P:Card("About")
	P:Note("The reminder shows a button for each of your buffs missing (or running out) on you or a group member in range; click casts it on the first one, hover lists everyone. Hidden when everyone is buffed; use Unlock panels to move it. Buttons can't change in combat, so it updates after combat.")
	P:Finish()
end

local function BuildAlliesPage(parent)
	local s = ns.adb.allies
	local P = T.Page(parent)
	P:Card("Label")
	local function Redraw() if ns.Allies then ns.Allies.Refresh() end end
	P:Slider("Name size", 9, 20, 1, "px", function() return s.size or 13 end, function(v) s.size = v; Redraw() end)
	P:Toggle("Show level before the name", function() return s.level ~= false end, function(v) s.level = v; Redraw() end)
	P:Toggle("Show guild under the name", function() return s.guild ~= false end, function(v) s.guild = v; Redraw() end)
	local list = ns.db.alliesList
	local function RefreshList() if ns.AlliesList then ns.AlliesList.Update() end end
	P:Card("Nearby allies list")
	P:Toggle("Show the nearby allies list", function() return list.enabled end, function(v) list.enabled = v; RefreshList() end)
	P:Slider("Rows", 5, 20, 1, nil, function() return list.rows or 10 end, function(v) list.rows = v; RefreshList() end)
	P:Note("Closest first (exact for group members, otherwise ~10 / 28 / 40 yd or far). Left-click a row to target, right-click to cast your class buff, + to invite. Pauses in combat. Needs Friendly Names on; use Unlock panels to move it.")
	P:Card("About")
	P:Note("Above friendly players you see only their name in class colour (and guild) instead of the game's nameplate. To do this the addon turns friendly nameplates on and draws them invisible; turning this off restores your own nameplate setting. Also /dpws allies.")
	P:Finish()
end

local function BuildProfilesPage(parent)
	local P = T.Page(parent)
	P:Card("Save current bars and talents")
	P:Custom(38, function(row)
		local input = T.NewInput(row, 260)
		input:SetPoint("LEFT")
		input:SetMaxLetters(32)
		local save = T.NewButton(row, "Save", 90, 26, "accent")
		save:SetPoint("LEFT", input, "RIGHT", 10, 0)
		local function DoSave()
			local name = strtrim(input:GetText() or "")
			if name == "" then return end
			ns.Profiles.Save(name)
			input:SetText("")
			input:ClearFocus()
			print(("dpws_tools: saved profile '%s'"):format(name))
		end
		save:SetScript("OnClick", DoSave)
		input:SetScript("OnEnterPressed", DoSave)
	end)
	P:Note("Shared by all your characters of this class. Loading bars first saves your current bars as '(backup)'.")

	P:Card("Saved profiles")
	local rows, MAX_ROWS = {}, 8
	for i = 1, MAX_ROWS do
		P:Custom(40, function(row)
			local r = { frame = row }
			r.name = T.Text(row, "semibold", 13)
			r.name:SetPoint("TOPLEFT", 2, -4)
			r.name:SetWidth(220)
			r.name:SetWordWrap(false)
			r.info = T.Text(row, "regular", 11, T.muted)
			r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
			r.delete = T.NewButton(row, "Delete", 70, 24)
			r.delete:SetPoint("RIGHT")
			r.both = T.NewButton(row, "Both", 64, 24)
			r.both:SetPoint("RIGHT", r.delete, "LEFT", -8, 0)
			r.talents = T.NewButton(row, "Talents", 70, 24)
			r.talents:SetPoint("RIGHT", r.both, "LEFT", -8, 0)
			r.bars = T.NewButton(row, "Bars", 64, 24)
			r.bars:SetPoint("RIGHT", r.talents, "LEFT", -8, 0)
			rows[i] = r
		end)
	end
	local empty = P:Note("")

	local armedDelete
	local function Refresh()
		local names = ns.Profiles.List()
		for i, r in ipairs(rows) do
			local name = names[i]
			r.frame:SetShown(name ~= nil)
			if name then
				local p = ns.Profiles.Get(name)
				r.name:SetText(name)
				r.info:SetText(("by %s, %s"):format(p.by or "?", date("%Y-%m-%d %H:%M", p.at or 0)))
				r.bars:SetScript("OnClick", function() ns.Profiles.LoadBars(name) end)
				r.talents:SetScript("OnClick", function() ns.Profiles.LoadTalents(name) end)
				r.both:SetScript("OnClick", function() ns.Profiles.LoadBoth(name) end)
				-- two clicks to delete: no popup dialog
				r.delete:SetText(armedDelete == name and "Sure?" or "Delete")
				r.delete:SetScript("OnClick", function()
					if armedDelete == name then
						armedDelete = nil
						ns.Profiles.Delete(name)
					else
						armedDelete = name
						Refresh()
					end
				end)
			end
		end
		empty:SetText(#names == 0 and "No profiles yet." or (#names > MAX_ROWS and ("+%d more"):format(#names - MAX_ROWS) or ""))
	end
	ns.OnProfilesChanged = function() if parent:IsVisible() then Refresh() end end
	P:Refresher(function() armedDelete = nil; Refresh() end)
	P:Finish()
end

local function BuildRestockPage(parent)
	local r = ns.db.restock
	local P = T.Page(parent)
	P:Card("Budget")
	P:Slider("Spend at most per vendor visit", 1, 50, 1, "g", function() return math.floor(r.budget / 10000) end,
		function(v) r.budget = v * 10000 end)

	P:Card("Shopping list")
	local rows, Refresh, MAX_ROWS = {}, nil, 8
	P:Custom(38, function(row)
		local input = T.NewInput(row, 240)
		input:SetPoint("LEFT")
		local add = T.NewButton(row, "Add", 64, 26)
		add:SetPoint("LEFT", input, "RIGHT", 8, 0)
		local preset = T.NewButton(row, "Add " .. UnitClass("player") .. " preset", 170, 26, "accent")
		preset:SetPoint("RIGHT")
		preset:SetScript("OnClick", function()
			if not ns.AddRestockPreset() then print("dpws_tools: no preset for your class, add items yourself") end
			Refresh()
		end)
		local function DoAdd()
			local text = input:GetText() or ""
			local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
			if id then r.items[id] = r.items[id] or 20 end
			input:SetText("")
			input:ClearFocus()
			Refresh()
		end
		add:SetScript("OnClick", DoAdd)
		input:SetScript("OnEnterPressed", DoAdd)
		-- Shift-click on an item puts its link into our box while it has focus
		local function InsertLink(link)
			if input:HasFocus() and link then input:Insert(link) end
		end
		if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end
		if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink) end
	end)
	for i = 1, MAX_ROWS do
		P:Custom(30, function(row)
			local x = { frame = row }
			x.icon = row:CreateTexture(nil, "ARTWORK")
			x.icon:SetSize(20, 20)
			x.icon:SetPoint("LEFT", 2, 0)
			x.name = T.Text(row, "medium", 13)
			x.name:SetPoint("LEFT", x.icon, "RIGHT", 10, 0)
			x.name:SetWidth(300)
			x.name:SetWordWrap(false)
			x.remove = T.NewButton(row, "Remove", 76, 24)
			x.remove:SetPoint("RIGHT")
			x.count = T.NewInput(row, 60, true)
			x.count:SetPoint("RIGHT", x.remove, "LEFT", -10, 0)
			rows[i] = x
		end)
	end
	local more = P:Note("")
	P:EndCard()
	P:Note("Shift-click an item link into the box, or type an item ID. Poison ingredients for your Poison Stock are added automatically.")

	Refresh = function()
		local ids = {}
		for id in pairs(r.items) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, x in ipairs(rows) do
			local id = ids[i]
			x.frame:SetShown(id ~= nil)
			if id then
				x.icon:SetTexture(ItemIcon(id))
				x.name:SetText(ItemName(id))
				x.count:SetText(r.items[id])
				local function Save()
					local n = tonumber(x.count:GetText())
					if n and n > 0 then r.items[id] = n end
					x.count:ClearFocus()
				end
				x.count:SetScript("OnEnterPressed", Save)
				x.count:SetScript("OnEditFocusLost", Save)
				x.remove:SetScript("OnClick", function() r.items[id] = nil; Refresh() end)
			end
		end
		more:SetText(#ids > MAX_ROWS and ("+%d more (remove some to see them)"):format(#ids - MAX_ROWS) or
			(#ids == 0 and "No items yet: add your class preset or your own items." or ""))
	end
	P:Refresher(Refresh)
	P:Finish()
end

---------------------------------------------------------------------------
-- Window

-- Sidebar sections (General + class sections). toggle = header Enable switch; status = sidebar dot.
local ICON = "Interface\\Icons\\"
local GROUPS = {
	{ name = "General", tools = {
		{ name = "PvP Kills", build = BuildPvpPage, icon = ICON .. "Ability_DualWield",
			desc = "Your score against each enemy player and the latest kills and deaths." },
		{ name = "PvP Settings", build = BuildPvpSettingsPage, icon = ICON .. "INV_BannerPVP_01",
			desc = "Tooltip score, announcements and sounds for open-world PvP.",
			status = function() return ns.adb.pvpTooltip or ns.adb.pvpAnnounce end },
		{ name = "Nearby Enemies", build = BuildNearbyPage, icon = ICON .. "Ability_Hunter_EagleEye",
			desc = "Opposite-faction players seen around you.",
			toggle = { function() return ns.adb.nearby.enabled end,
				function(v) ns.adb.nearby.enabled = v; if ns.RefreshNearby then ns.RefreshNearby() end end } },
		{ name = "Friendly Names", build = BuildAlliesPage, icon = ICON .. "Spell_Holy_PrayerOfHealing02",
			desc = "Clean name labels above friendly players: class colour and guild, no nameplate.",
			toggle = { function() return ns.adb.allies.enabled end,
				function(v) ns.adb.allies.enabled = v; if ns.Allies then ns.Allies.Apply() end end } },
		{ name = "Profiles", build = BuildProfilesPage, icon = ICON .. "INV_Misc_Book_09",
			desc = "Save and load action bars and talents, shared by your characters of this class." },
		{ name = "Auto Restock", build = BuildRestockPage, icon = ICON .. "INV_Misc_Bag_10",
			desc = "Buy reagents and supplies automatically at vendors.",
			toggle = { function() return ns.db.restock.enabled end, function(v) ns.db.restock.enabled = v end } },
	} },
	{ name = "Caster", classes = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }, tools = {
		{ name = "Mana Ticks", build = BuildManaPage, icon = ICON .. "INV_Potion_76",
			desc = "The five second rule, then regeneration.",
			status = function() return ns.db.mana.mode ~= "off" end },
		{ name = "Buffs", build = BuildBuffsPage, icon = ICON .. "Spell_Holy_WordFortitude",
			desc = "Never forget a buff: on you, your group, and beside party frames.",
			toggle = { function() return ns.db.buffs.enabled end,
				function(v) ns.db.buffs.enabled = v; if ns.Buffs then ns.Buffs.Update() end end } },
	} },
	{ name = "Rogue", class = "ROGUE", tools = {
		{ name = "Stealth Action Bars", build = BuildBarSwitchPage, icon = ICON .. "Ability_Stealth",
			desc = "Which bars switch page while in Stealth.",
			status = function() return next(ns.db.barSwitch) ~= nil end },
		{ name = "Poisons", build = function(p) BuildPoisonsPage(p); BuildPoisonStockPage(p) end, icon = ICON .. "Ability_Poisons",
			desc = "Weapon poison bar, reminders, and poisons kept in bags.",
			toggle = { function() return ns.db.poisons.enabled end,
				function(v) ns.db.poisons.enabled = v; if ns.Poisons then ns.Poisons.Refresh() end end } },
		{ name = "Combat Bars", build = function(p) BuildComboPage(p); BuildRogueTimersPage(p) end, icon = ICON .. "Ability_Rogue_Eviscerate",
			desc = "Health, energy and combo point bars, Slice and Dice and cooldowns.",
			status = function()
				local c = ns.db.combo
				return (ns.db.rogueTimers.mode or "combat") ~= "off" or (c.healthMode or "combat") ~= "off" or (c.energyMode or "combat") ~= "off" or (c.comboMode or "combat") ~= "off"
			end },
		{ name = "Lockboxes", build = BuildLockboxPage, icon = ICON .. "INV_Box_04",
			desc = "One button to pick and open your lockboxes.",
			toggle = { function() return ns.db.lockbox.enabled end,
				function(v) ns.db.lockbox.enabled = v; if ns.Lockbox then ns.Lockbox.Update() end end } },
		{ name = "Openers", build = BuildOpenerPage, icon = ICON .. "INV_Misc_Bag_11",
			desc = "Pick Pocket icons on nameplates and opener weapon sets.",
			status = function() return ns.db.opener.markers or ns.db.opener.weapons end },
	} },
}

local toolSelectors = {} -- tool name -> function showing that tool
local SIDEBAR, HEADER, FOOTER = 210, 104, 30

local function CloseBox(parent, onClick)
	local close = CreateFrame("Button", nil, parent)
	close:SetSize(30, 30)
	T.Box(close, T.control, T.border, 6)
	local x = T.Text(close, "semibold", 14, T.muted)
	x:SetPoint("CENTER", 0, 0)
	x:SetJustifyH("CENTER")
	x:SetText("X")
	close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1) end)
	close:SetScript("OnLeave", function() x:SetTextColor(unpack(T.muted)) end)
	close:SetScript("OnClick", onClick)
	return close
end

local function CreateWindow()
	local f = CreateFrame("Frame", "DpwsToolsWindow", UIParent)
	f:SetSize(980, 740)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	T.Box(f, T.window, { 1, 1, 1, 0.07 }, 12)
	local pos = ns.db.window
	f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
	tinsert(UISpecialFrames, f:GetName()) -- Esc closes it

	-- header banner: logo, title, tagline, accent line; dragging it moves the window
	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() f:StartMoving() end)
	header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, _, x, y = f:GetPoint()
		ns.db.window = { point = point, x = x, y = y }
	end)
	local logo = header:CreateTexture(nil, "ARTWORK")
	logo:SetSize(64, 64)
	logo:SetPoint("LEFT", 26, -2)
	logo:SetTexture("Interface\\AddOns\\dpws_tools\\media\\icon")
	local kicker = T.Text(header, "semibold", 10, T.muted)
	kicker:SetPoint("TOPLEFT", logo, "TOPRIGHT", 16, -2)
	kicker:SetText(("WOW FOREVER   -   %s"):format((UnitClass("player") or ""):upper()))
	local title = T.Text(header, "semibold", 30, T.gold)
	title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", -1, -4)
	title:SetText("dpws tools")
	local tagline = T.Text(header, "medium", 13, T.text)
	tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
	tagline:SetText("Small tools for everyday play.")
	local accent = header:CreateTexture(nil, "ARTWORK")
	accent:SetTexture(T.WHITE)
	accent:SetHeight(2)
	accent:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -10)
	accent:SetWidth(520)
	if accent.SetGradient and CreateColor then
		accent:SetGradient("HORIZONTAL", CreateColor(unpack(T.Accent(0.9))), CreateColor(unpack(T.Accent(0))))
	else
		accent:SetVertexColor(unpack(T.Accent(0.6)))
	end
	local close = CloseBox(header, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -18, -18)
	local version = T.Text(header, "regular", 12, T.muted)
	version:SetPoint("RIGHT", close, "LEFT", -12, 0)
	version:SetText("v" .. ((C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("dpws_tools", "Version") or "?"))
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 1, 1, 0.07)
	rule:SetPoint("TOPLEFT", 0, -HEADER)
	rule:SetPoint("TOPRIGHT", 0, -HEADER)
	rule:SetHeight(1)

	-- footer status line (last notification)
	local footerRule = f:CreateTexture(nil, "ARTWORK")
	footerRule:SetColorTexture(1, 1, 1, 0.07)
	footerRule:SetPoint("BOTTOMLEFT", 0, FOOTER)
	footerRule:SetPoint("BOTTOMRIGHT", 0, FOOTER)
	footerRule:SetHeight(1)
	local footer = T.Text(f, "medium", 12, T.text)
	footer:SetPoint("BOTTOM", 0, 9)
	footer:SetJustifyH("CENTER")
	footer:SetText("Ready")
	ns.SetFooter = function(text) footer:SetText(text) end
	-- settings that only take full effect after a reload: footer warning + Reload button
	local reloadBtn = T.NewButton(f, "Reload UI", 100, 22, "accent")
	reloadBtn:SetPoint("BOTTOMRIGHT", -14, 4)
	reloadBtn:SetScript("OnClick", function() (C_UI and C_UI.Reload or ReloadUI)() end)
	reloadBtn:Hide()
	ns.RequestReload = function(reason)
		footer:SetText("|cffffcc00Reload needed:|r " .. reason)
		reloadBtn:Show()
		print("dpws_tools: reload needed - " .. reason .. " (Reload UI button in /dpws, or /reload)")
	end

	-- sidebar: section labels, nav items with status dots, shared actions at the bottom
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 0, -HEADER - 1)
	side:SetPoint("BOTTOMLEFT", 0, FOOTER + 1)
	side:SetWidth(SIDEBAR)
	local sideRule = side:CreateTexture(nil, "ARTWORK")
	sideRule:SetColorTexture(1, 1, 1, 0.07)
	sideRule:SetPoint("TOPRIGHT")
	sideRule:SetPoint("BOTTOMRIGHT")
	sideRule:SetWidth(1)

	-- content: page header (icon, title, description, Enable switch), then the page
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", SIDEBAR + 28, -HEADER - 22)
	content:SetPoint("BOTTOMRIGHT", -28, FOOTER + 18)
	local pageIcon = content:CreateTexture(nil, "ARTWORK")
	pageIcon:SetSize(22, 22)
	pageIcon:SetPoint("TOPLEFT", 0, 0)
	pageIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local pageTitle = T.Text(content, "semibold", 20, { 1, 1, 1, 1 })
	pageTitle:SetPoint("LEFT", pageIcon, "RIGHT", 12, 0)
	local pageDesc = T.Text(content, "regular", 12, T.muted)
	pageDesc:SetPoint("TOPLEFT", pageIcon, "BOTTOMLEFT", 34, -8)
	local headToggle = T.NewToggle(content)
	headToggle:SetPoint("TOPRIGHT", 0, -2)
	local headLabel = T.Text(content, "medium", 13, T.text)
	headLabel:SetPoint("RIGHT", headToggle, "LEFT", -10, 0)
	local headRule = content:CreateTexture(nil, "ARTWORK")
	headRule:SetColorTexture(1, 1, 1, 0.07)
	headRule:SetPoint("TOPLEFT", 0, -58)
	headRule:SetPoint("TOPRIGHT", 0, -58)
	headRule:SetHeight(1)

	local playerClass = select(2, UnitClass("player"))
	local navs, current = {}, nil
	local function UpdateDots()
		for _, n in ipairs(navs) do
			local s = n.tool.status or (n.tool.toggle and n.tool.toggle[1])
			if s then
				local on = s()
				n.dot:Show()
				n.dot:SetVertexColor(unpack(on and T.green or { 0.45, 0.48, 0.53, 0.6 }))
				n.dotHole:SetShown(not on)
			else
				n.dot:Hide()
				n.dotHole:Hide()
			end
		end
	end
	local function Select(nav)
		current = nav
		for _, n in ipairs(navs) do
			local on = n == nav
			n.page:SetShown(on)
			n.active:SetShown(on)
			n.bar:SetShown(on)
			n.label:SetTextColor(unpack(on and { 1, 1, 1, 1 } or { 0.68, 0.71, 0.76, 1 }))
			n.icon:SetDesaturated(not on)
			n.icon:SetAlpha(on and 1 or 0.7)
		end
		local tool = nav.tool
		pageIcon:SetTexture(tool.icon)
		pageTitle:SetText(tool.name)
		pageDesc:SetText(tool.desc or "")
		headToggle:SetShown(tool.toggle ~= nil)
		headLabel:SetShown(tool.toggle ~= nil)
		if tool.toggle then
			headLabel:SetText(tool.toggleText or "Enable " .. tool.name:lower())
			headToggle:SetChecked(tool.toggle[1]())
		end
		UpdateDots()
	end
	headToggle:SetScript("OnClick", function(self)
		self:SetChecked(not self:GetChecked())
		if current and current.tool.toggle then
			current.tool.toggle[2](self:GetChecked())
			if current.tool.toggle.reload and ns.RequestReload then ns.RequestReload(current.tool.toggle.reload) end
		end
		UpdateDots()
	end)

	-- nav list scrolls (mouse wheel) above the two buttons when a class has many tools
	local list = CreateFrame("ScrollFrame", nil, side)
	list:SetPoint("TOPLEFT")
	list:SetPoint("BOTTOMRIGHT", 0, 94)
	local listIn = CreateFrame("Frame", nil, list)
	listIn:SetWidth(SIDEBAR)
	list:SetScrollChild(listIn)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, d)
		local max = math.max(listIn:GetHeight() - self:GetHeight(), 0)
		self:SetVerticalScroll(math.min(math.max(self:GetVerticalScroll() - d * 40, 0), max))
	end)
	local y = -14
	for _, group in ipairs(GROUPS) do
		if (not group.class or group.class == playerClass) and (not group.classes or group.classes[playerClass])
			and #group.tools > 0 then
			local label = T.Text(listIn, "semibold", 10, T.muted)
			label:SetPoint("TOPLEFT", 26, y)
			label:SetText(group.name:upper())
			y = y - 18
			for _, tool in ipairs(group.tools) do
				local nav = CreateFrame("Button", nil, listIn)
				nav:SetPoint("TOPLEFT", 12, y)
				nav:SetSize(SIDEBAR - 24, 30)
				nav.tool = tool
				nav.active = T.Rounded(nav, T.Accent(0.10), 6, "BACKGROUND", 0)
				nav.bar = nav:CreateTexture(nil, "ARTWORK")
				nav.bar:SetPoint("TOPLEFT", 0, -6)
				nav.bar:SetPoint("BOTTOMLEFT", 0, 6)
				nav.bar:SetWidth(3)
				nav.bar:SetColorTexture(unpack(T.gold))
				local hl = nav:CreateTexture(nil, "HIGHLIGHT")
				hl:SetPoint("TOPLEFT", 2, -2)
				hl:SetPoint("BOTTOMRIGHT", -2, 2)
				hl:SetColorTexture(1, 1, 1, 0.04)
				nav.icon = nav:CreateTexture(nil, "ARTWORK")
				nav.icon:SetSize(18, 18)
				nav.icon:SetPoint("LEFT", 14, 0)
				nav.icon:SetTexture(tool.icon or 134400)
				nav.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				nav.label = T.Text(nav, "medium", 14, T.text)
				nav.label:SetPoint("LEFT", nav.icon, "RIGHT", 12, 0)
				nav.label:SetText(tool.name)
				nav.dot = nav:CreateTexture(nil, "OVERLAY")
				nav.dot:SetTexture(T.CIRCLE)
				nav.dot:SetSize(7, 7)
				nav.dot:SetPoint("RIGHT", -12, 0)
				nav.dotHole = nav:CreateTexture(nil, "OVERLAY", nil, 1) -- hollow dot when off
				nav.dotHole:SetTexture(T.CIRCLE)
				nav.dotHole:SetSize(4, 4)
				nav.dotHole:SetPoint("CENTER", nav.dot)
				nav.dotHole:SetVertexColor(unpack(T.window))
				-- every page scrolls; the scrollbar only shows when the page is taller than the area
				local W, H = 980 - SIDEBAR - 56, 740 - HEADER - FOOTER - 40 - 74
				nav.page = CreateFrame("Frame", nil, content)
				nav.page:SetPoint("TOPLEFT", 0, -74)
				nav.page:SetPoint("BOTTOMRIGHT")
				local scroll = CreateFrame("ScrollFrame", nil, nav.page, "ScrollFrameTemplate")
				scroll:SetPoint("TOPLEFT")
				scroll:SetPoint("BOTTOMRIGHT")
				local inner = CreateFrame("Frame", nil, scroll)
				inner:SetSize(W - 18, H)
				scroll:SetScrollChild(inner)
				tool.build(inner)
				local used = inner.dpwsPage and -inner.dpwsPage.y or H
				inner:SetHeight(math.max(used + 8, 1))
				if scroll.ScrollBar then scroll.ScrollBar:SetShown(used > H) end
				nav:SetScript("OnClick", function() Select(nav) end)
				navs[#navs + 1] = nav
				toolSelectors[tool.name] = function() Select(nav) end
				y = y - 31
			end
			y = y - 10
		end
	end
	listIn:SetHeight(-y)
	if navs[1] then
		Select(navs[1])
	else
		pageTitle:SetText("No tools for your class yet")
		headToggle:Hide()
	end

	local hlb = T.NewButton(side, "Highlight bars", SIDEBAR - 40, 28)
	hlb:SetPoint("BOTTOMLEFT", 20, 56)
	hlb:SetScript("OnClick", function() SetHighlights(not highlightsOn) end)
	local lock = T.NewButton(side, "Unlock panels", SIDEBAR - 40, 28, "accent")
	lock:SetPoint("BOTTOMLEFT", 20, 18)
	local function LockText() lock:SetText(ns.unlocked and "Lock panels" or "Unlock panels") end
	lock:SetScript("OnClick", function() ns.SetUnlocked(not ns.unlocked); LockText() end)
	lock:SetScript("OnShow", LockText)
	LockText()

	f:SetScript("OnShow", UpdateDots)
	f:SetScript("OnHide", function() SetHighlights(false); ns.SetUnlocked(false) end)
	f:Hide()
	return f
end

function ns.ToggleWindow()
	window = window or CreateWindow()
	window:SetShown(not window:IsShown())
end

-- open the window on a given tool, e.g. ns.OpenWindow("Profiles")
function ns.OpenWindow(toolName)
	window = window or CreateWindow()
	window:Show()
	if toolSelectors[toolName] then toolSelectors[toolName]() end
end

-- Esc > Options > AddOns entry
table.insert(ns.loginHooks, function()
	local panel = CreateFrame("Frame")
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", 16, -16)
	b:SetSize(180, 26)
	b:SetText("Open dpws tools")
	b:SetScript("OnClick", function()
		window = window or CreateWindow()
		window:Show()
	end)
	local category = Settings.RegisterCanvasLayoutCategory(panel, "dpws tools")
	Settings.RegisterAddOnCategory(category)
end)

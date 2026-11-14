local ADDON, ns = ...

ns.STATE_LABELS = {
	ROGUE = { [1] = "Stealth" },
	DRUID = { [1] = "Cat Form", [2] = "Prowl", [3] = "Bear Form", [4] = "Moonkin / Tree of Life" },
	WARRIOR = { [1] = "Battle Stance", [2] = "Defensive Stance", [3] = "Berserker Stance" },
	PRIEST = { [1] = "Shadowform" },
}

local window

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
	return (visible and "|cff40ff40%s|r" or "|cff909090%s|r"):format(name)
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

local function MakeRow(parent, y, state, bar)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 16, y - 6)
	label:SetText(BarLabel(bar) .. "  >")

	local warn = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	warn:SetPoint("TOPLEFT", 270, y - 7)
	warn:SetTextColor(1, 0.5, 0.1)

	local function Get()
		return ns.db.barSwitch[state] and ns.db.barSwitch[state][bar.index]
	end
	local function UpdateWarn()
		local owner = Get() and VisibleOwner(Get())
		warn:SetText(owner and ("in use on " .. owner) or "")
	end
	local function Set(page)
		ns.db.barSwitch[state] = ns.db.barSwitch[state] or {}
		ns.db.barSwitch[state][bar.index] = page
		if not next(ns.db.barSwitch[state]) then ns.db.barSwitch[state] = nil end
		UpdateWarn()
		if InCombatLockdown() then print("dpws_tools: change applies after combat") end
		ns.ApplyBarSwitch()
	end

	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", 90, y)
	dd:SetWidth(170)
	dd:SetupMenu(function(_, root)
		root:CreateRadio("None", function() return Get() == nil end, function() Set(nil) end)
		for _, page in ipairs(ns.ValidPages(bar.index)) do
			root:CreateRadio(PageLabel(page), function() return Get() == page end, function() Set(page) end)
		end
	end)
	return function()
		label:SetText(BarLabel(bar) .. "  >")
		dd:GenerateMenu()
		UpdateWarn()
	end
end

local function BuildBarSwitchPage(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -26, 4)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(420, 1)
	scroll:SetScrollChild(content)

	local refreshers = {}
	local labels = ns.STATE_LABELS[select(2, UnitClass("player"))]
	local y = -8
	if not labels then
		local t = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		t:SetPoint("TOP", scroll, "TOP", 0, -40)
		t:SetText("No stance states for this class")
	else
		local hint = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		hint:SetPoint("TOPLEFT", 16, y)
		hint:SetWidth(400)
		hint:SetJustifyH("LEFT")
		hint:SetText("Pick which page each bar shows while in a state. Put spells on that page by dragging them onto the bar while the state is active.")
		y = y - 36
		-- MelloUI's own bars replace Blizzard bars 2-8, which are the ones this addon switches
		if _G.MelloUIActionBar2Button1 then
			local mello = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			mello:SetPoint("TOPLEFT", 16, y)
			mello:SetWidth(400)
			mello:SetJustifyH("LEFT")
			mello:SetTextColor(1, 0.3, 0.3)
			mello:SetText("MelloUI's own action bars are active: bar switching won't affect them.")
			y = y - 30
		end
		for state = 1, 4 do
			if labels[state] then
				local h = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
				h:SetPoint("TOPLEFT", 8, y)
				h:SetText(labels[state])
				y = y - 26
				for _, bar in ipairs(ns.BARS) do
					refreshers[#refreshers + 1] = MakeRow(content, y, state, bar)
					y = y - 30
				end
				y = y - 10
			end
		end
	end
	content:SetHeight(-y)
	parent:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
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
				local bg = o:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints()
				bg:SetColorTexture(0.1, 0.6, 1, 0.35)
				local text = o:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
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

local function Checkbox(parent, y, text, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 12, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	label:SetText(text)
	cb:SetScript("OnClick", function(self) set(self:GetChecked()) end)
	return function() cb:SetChecked(get()) end
end

-- labelled dropdown of ns.SOUNDS (+ None); picking one previews it. Returns a refresher.
local function SoundDropdown(parent, y, text, get, set)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 16, y - 6)
	label:SetText(text)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", 110, y)
	dd:SetWidth(170)
	dd:SetupMenu(function(_, root)
		root:CreateRadio("None", function() return get() == nil end, function() set(nil) end)
		for _, s in ipairs(ns.SOUNDS) do
			root:CreateRadio(s.name, function() return get() == s.key end, function()
				set(s.key)
				ns.PlaySoundKey(s.key)
			end)
		end
	end)
	return function() dd:GenerateMenu() end
end

-- plain slider with own textures: no dependency on templates that changed between clients.
-- fmt shows the value (e.g. "Scale: %d%%"); returns a refresher.
local function Slider(parent, y, min, max, step, fmt, get, set)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 16, y)
	local s = CreateFrame("Slider", nil, parent)
	s:SetPoint("TOPLEFT", 16, y - 22)
	s:SetSize(220, 16)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:EnableMouse(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0, 0, 0, 0.6)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(6)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	local loading = false
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		label:SetText(fmt:format(v))
		if not loading then set(v) end
	end)
	return function()
		loading = true
		s:SetValue(get())
		label:SetText(fmt:format(math.floor(get() + 0.5)))
		loading = false
	end
end

local function BuildPoisonsPage(parent)
	if select(2, UnitClass("player")) ~= "ROGUE" then
		local t = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		t:SetPoint("TOP", 0, -40)
		t:SetText("Poison bar is for rogues")
		return
	end
	local p = ns.db.poisons
	local function Changed() if ns.Poisons then ns.Poisons.Refresh() end end
	local refreshers = {
		Checkbox(parent, -12, "Show poison bar", function() return p.enabled end, function(v) p.enabled = v; Changed() end),
		Checkbox(parent, -44, "Play sound with warnings", function() return p.sound end, function(v) p.sound = v end),
	}

	local function Rescale() if ns.Poisons then ns.Poisons.ApplyScale() end end
	refreshers[#refreshers + 1] = Slider(parent, -90, 1, 15, 1, "Warn when less than %d min left",
		function() return p.warnMinutes end, function(v) p.warnMinutes = v end)
	refreshers[#refreshers + 1] = Slider(parent, -140, 50, 200, 10, "Weapon icons: %d%%",
		function() return (p.scale or 1) * 100 end, function(v) p.scale = v / 100; Rescale() end)
	refreshers[#refreshers + 1] = Slider(parent, -190, 50, 200, 10, "Poison icon: %d%%",
		function() return (p.poisonScale or 1) * 100 end, function(v) p.poisonScale = v / 100; Rescale() end)

	local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -230)
	hint:SetWidth(400)
	hint:SetJustifyH("LEFT")
	hint:SetText("On the bar: left-click applies the chosen poison, right-click chooses it. Use Unlock panels (top) to move the bar.")

	parent:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
end

local function BuildComboPage(parent)
	local c = ns.db.combo
	local function Relayout() if ns.Combo then ns.Combo.Layout() end end
	local refreshers = {}
	-- one mode dropdown per bar: Always / Only in combat / Disabled
	for i, row in ipairs({ { "Health", "healthMode" }, { "Energy", "energyMode" }, { "Combo points", "comboMode" } }) do
		local y = -8 - (i - 1) * 30
		local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 16, y - 6)
		label:SetText(row[1])
		local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
		dd:SetPoint("TOPLEFT", 120, y)
		dd:SetWidth(170)
		dd:SetupMenu(function(_, root)
			for _, m in ipairs(ns.COMBAT_BAR_MODES or {}) do
				root:CreateRadio(m.name, function() return (c[row[2]] or "combat") == m.key end,
					function() c[row[2]] = m.key; Relayout() end)
			end
		end)
		refreshers[#refreshers + 1] = function() dd:GenerateMenu() end
	end
	refreshers[#refreshers + 1] = Slider(parent, -110, 60, 400, 10, "Width: %d", function() return c.width end, function(v) c.width = v; Relayout() end)
	refreshers[#refreshers + 1] = Slider(parent, -160, 6, 40, 1, "Height: %d", function() return c.height end, function(v) c.height = v; Relayout() end)

	local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	h:SetPoint("TOPLEFT", 12, -210)
	h:SetText("Combo point sounds")
	for n = 1, 5 do
		local y = -238 - (n - 1) * 30
		refreshers[#refreshers + 1] = SoundDropdown(parent, y, n == 1 and "1 point" or (n .. " points"),
			function() return c.sounds[n] end, function(key) c.sounds[n] = key end)
	end

	local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -395)
	hint:SetWidth(400)
	hint:SetJustifyH("LEFT")
	hint:SetText("A sound plays when your combo points rise to that amount. Use Unlock panels (top) to move the bar.")

	parent:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
end

local function BuildPvpSettingsPage(parent)
	local a = ns.adb
	local refreshers = {
		Checkbox(parent, -12, "Show PvP score on player tooltips", function() return a.pvpTooltip end, function(v) a.pvpTooltip = v end),
		Checkbox(parent, -44, "Announce kills and deaths (name, level, class, score)", function() return a.pvpAnnounce end, function(v) a.pvpAnnounce = v end),
		SoundDropdown(parent, -90, "Kill sound", function() return a.pvpKillSound end, function(key) a.pvpKillSound = key end),
		SoundDropdown(parent, -120, "Death sound", function() return a.pvpDeathSound end, function(key) a.pvpDeathSound = key end),
	}
	local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -160)
	hint:SetWidth(400)
	hint:SetJustifyH("LEFT")
	hint:SetText("Open world only (not battlegrounds, arenas or dungeons). A death counts for the last enemy player who hit you within 10 seconds. Announcements use the Notifications panel (Unlock panels to move it).")
	parent:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
end

local function BuildNearbyPage(parent)
	local s = ns.adb.nearby
	local function Changed() if ns.RefreshNearby then ns.RefreshNearby() end end
	local refreshers = {
		Checkbox(parent, -12, "Show nearby enemies (opposite faction)", function() return s.enabled end, function(v) s.enabled = v; Changed() end),
		Slider(parent, -50, 15, 300, 15, "Remove after not seen for %d sec", function() return s.timeout end, function(v) s.timeout = v end),
	}

	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 16, -106)
	label:SetText("Alert")
	local ALERTS = { { "off", "Off" }, { "all", "Every new enemy" }, { "killers", "Only players who killed me" } }
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", 110, -100)
	dd:SetWidth(200)
	dd:SetupMenu(function(_, root)
		for _, a in ipairs(ALERTS) do
			root:CreateRadio(a[2], function() return s.alert == a[1] end, function() s.alert = a[1] end)
		end
	end)
	refreshers[#refreshers + 1] = function() dd:GenerateMenu() end
	refreshers[#refreshers + 1] = SoundDropdown(parent, -130, "Alert sound", function() return s.sound end, function(key) s.sound = key end)

	local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -172)
	hint:SetWidth(400)
	hint:SetJustifyH("LEFT")
	hint:SetText("Players are found by their nameplates (turn on enemy nameplates for best results) and by what they do in the combat log. Stealthed players are not seen until they act. Open world only. Use Unlock panels (top) to move the list.")

	parent:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
end

local function BuildPvpPage(parent)
	local a = ns.adb
	local refreshers = {}
	local stats = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	stats:SetPoint("TOPLEFT", 16, -16)
	local function ShowStats()
		local players, k, d = 0, 0, 0
		for _, e in pairs(a.pvp) do players, k, d = players + 1, k + e.k, e.d + d end
		stats:SetText(("%d players tracked. Total: %s"):format(players, ns.PvpScoreText({ k = k, d = d })))
	end
	refreshers[#refreshers + 1] = ShowStats

	-- two clicks to reset: no popup dialog
	local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", 16, -40)
	reset:SetSize(180, 26)
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
	refreshers[#refreshers + 1] = function() armed = false; ResetText() end

	-- history: 15 per page, newest first
	local PER_PAGE, ROW = 15, 17
	local COLS = { { "When", 0 }, { "", 80 }, { "Name", 130 }, { "Class", 270 }, { "Lvl", 360 } }
	local top = -82
	for _, col in ipairs(COLS) do
		local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", 16 + col[2], top)
		h:SetText(col[1])
	end
	local rows = {}
	for i = 1, PER_PAGE do
		local cells = {}
		for c, col in ipairs(COLS) do
			local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			fs:SetPoint("TOPLEFT", 16 + col[2], top - 4 - i * ROW)
			fs:SetWidth((COLS[c + 1] and COLS[c + 1][2] or 400) - col[2] - 4)
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			cells[c] = fs
		end
		rows[i] = cells
	end

	local page = 1
	local pagerY = top - 12 - (PER_PAGE + 1) * ROW
	local pageText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pageText:SetPoint("TOPLEFT", 150, pagerY - 6)
	local prev = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	prev:SetPoint("TOPLEFT", 16, pagerY)
	prev:SetSize(100, 22)
	prev:SetText("< Newer")
	local nextB = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	nextB:SetPoint("TOPLEFT", 270, pagerY)
	nextB:SetSize(100, 22)
	nextB:SetText("Older >")

	local function ShowPage()
		local items, pages, p = ns.PvpPage(a.pvpLog, page, PER_PAGE)
		page = p
		for i, cells in ipairs(rows) do
			local e = items[i]
			if e then
				local color = e.class and RAID_CLASS_COLORS[e.class]
				local className = e.class and (LOCALIZED_CLASS_NAMES_MALE[e.class] or e.class) or "?"
				cells[1]:SetText(date("%m-%d %H:%M", e.t))
				cells[2]:SetText(e.kind == "k" and "|cff40ff40Killed|r" or "|cffff4040Died|r")
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
	refreshers[#refreshers + 1] = function() page = 1; ShowPage() end
	-- live update while the page is open
	ns.OnPvpLogChanged = function() if parent:IsVisible() then ShowStats(); ShowPage() end end

	parent:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
end

local function BuildPoisonStockPage(parent)
	local p = ns.db.poisons
	p.stock = p.stock or {}
	local function Changed() if ns.PoisonStock then ns.PoisonStock.Update() end end
	local Refresh
	local refreshers = {
		Checkbox(parent, -12, "Buy ingredients at vendors to keep this stock", function() return p.buyMats ~= false end,
			function(v) p.buyMats = v end),
	}
	local status = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", 16, -46)
	status:SetWidth(440)
	status:SetJustifyH("LEFT")

	local add = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	add:SetPoint("TOPLEFT", 16, -70)
	add:SetWidth(220)
	add:SetDefaultText("Add poison...")
	add:SetupMenu(function(_, root)
		-- once recipes are known, offer only poisons this character can craft
		local known = ns.db.poisonRecipes
		local onlyKnown = known and next(known) ~= nil
		for _, id in ipairs(ns.AllPoisonIds()) do
			if not p.stock[id] and (not onlyKnown or known[id]) then
				local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id)
				local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or GetItemIcon(id)
				root:CreateButton(("|T%s:16|t %s"):format(icon or 134400, name), function() p.stock[id] = 20; Refresh(); Changed() end)
			end
		end
	end)

	local rows, MAX_ROWS = {}, 10
	for i = 1, MAX_ROWS do
		local y = -106 - (i - 1) * 24
		local row = {}
		row.icon = parent:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("TOPLEFT", 16, y)
		row.name = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", 40, y - 2)
		row.name:SetWidth(200)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.have = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.have:SetPoint("TOPLEFT", 244, y - 3)
		row.count = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
		row.count:SetPoint("TOPLEFT", 296, y + 1)
		row.count:SetSize(44, 20)
		row.count:SetAutoFocus(false)
		row.count:SetNumeric(true)
		row.remove = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		row.remove:SetPoint("TOPLEFT", 348, y + 1)
		row.remove:SetSize(70, 20)
		row.remove:SetText("Remove")
		rows[i] = row
	end

	Refresh = function()
		local learned = 0
		for _ in pairs(ns.db.poisonRecipes or {}) do learned = learned + 1 end
		status:SetText(learned > 0 and ("%d poison recipes known. Amount = how many to keep in bags."):format(learned)
			or "|cffffcc00Open your Poisons window once so the addon learns the recipes (until then nothing is bought).|r")
		local ids = {}
		for id in pairs(p.stock) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, row in ipairs(rows) do
			local id = ids[i]
			for _, w in pairs(row) do w:SetShown(id ~= nil) end
			if id then
				row.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or GetItemIcon(id))
				row.name:SetText((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id))
				row.have:SetText(("have %d"):format((C_Item and C_Item.GetItemCount or GetItemCount)(id)))
				row.count:SetText(p.stock[id])
				local function Save()
					local n = tonumber(row.count:GetText())
					if n and n > 0 and p.stock[id] then p.stock[id] = n; Changed() end
					row.count:ClearFocus()
				end
				row.count:SetScript("OnEnterPressed", Save)
				row.count:SetScript("OnEditFocusLost", Save)
				row.remove:SetScript("OnClick", function() p.stock[id] = nil; Refresh(); Changed() end)
			end
		end
		add:GenerateMenu()
	end
	refreshers[#refreshers + 1] = Refresh

	local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -106 - MAX_ROWS * 24 - 8)
	hint:SetWidth(440)
	hint:SetJustifyH("LEFT")
	hint:SetText("A small craft button shows next to the poison bar when something is short and you have the materials: left-click opens Poisons, click again to craft; right-click to pick a poison. Ingredients use the Auto Restock spending limit.")

	parent:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)
end

local function BuildManaPage(parent)
	local m = ns.db.mana
	local function Relayout() if ns.Mana then ns.Mana.Layout() end end
	local refreshers = {}
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 16, -14)
	label:SetText("Show")
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetPoint("TOPLEFT", 110, -8)
	dd:SetWidth(170)
	dd:SetupMenu(function(_, root)
		for _, mode in ipairs({ { "always", "Always" }, { "combat", "Only in combat" }, { "off", "Disabled" } }) do
			root:CreateRadio(mode[2], function() return (m.mode or "always") == mode[1] end, function() m.mode = mode[1] end)
		end
	end)
	refreshers[#refreshers + 1] = function() dd:GenerateMenu() end
	refreshers[#refreshers + 1] = Slider(parent, -50, 60, 400, 10, "Width: %d", function() return m.width end,
		function(v) m.width = v; Relayout() end)
	refreshers[#refreshers + 1] = Slider(parent, -100, 4, 30, 1, "Height: %d", function() return m.height end,
		function(v) m.height = v; Relayout() end)
	local hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 16, -150)
	hint:SetWidth(440)
	hint:SetJustifyH("LEFT")
	hint:SetText("Orange: the 5 seconds after spending mana (no spirit regen), with a countdown. Blue spark: where the next 2-second mana tick is. Hidden at full mana. Use Unlock panels (top) to move it.")
	parent:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)
end

local function BuildRestockPage(parent)
	local r = ns.db.restock
	local refreshers = {
		Checkbox(parent, -12, "Buy missing items when I open a vendor", function() return r.enabled end, function(v) r.enabled = v end),
		Slider(parent, -50, 1, 50, 1, "Spend at most %d gold per vendor visit",
			function() return math.floor(r.budget / 10000) end, function(v) r.budget = v * 10000 end),
	}
	local rows, Refresh = {}, nil

	local preset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	preset:SetPoint("TOPLEFT", 16, -100)
	preset:SetSize(200, 22)
	local className = UnitClass("player")
	preset:SetText("Add " .. className .. " preset")
	preset:SetScript("OnClick", function()
		if not ns.AddRestockPreset() then print("dpws_tools: no preset for your class, add items yourself") end
		Refresh()
	end)

	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 16, -132)
	label:SetText("Add item: Shift-click an item link into the box, or type an item ID")
	local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	input:SetPoint("TOPLEFT", 22, -148)
	input:SetSize(220, 22)
	input:SetAutoFocus(false)
	local add = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	add:SetPoint("LEFT", input, "RIGHT", 8, 0)
	add:SetSize(60, 22)
	add:SetText("Add")
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
	input:SetScript("OnEscapePressed", input.ClearFocus)
	-- Shift-click on an item puts its link into our box while it has focus
	local function InsertLink(link)
		if input:HasFocus() and link then input:Insert(link) end
	end
	if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink) end

	local MAX_ROWS = 10
	for i = 1, MAX_ROWS do
		local y = -184 - (i - 1) * 24
		local row = {}
		row.icon = parent:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("TOPLEFT", 16, y)
		row.name = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", 40, y - 2)
		row.name:SetWidth(220)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.count = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
		row.count:SetPoint("TOPLEFT", 276, y + 1)
		row.count:SetSize(50, 20)
		row.count:SetAutoFocus(false)
		row.count:SetNumeric(true)
		row.remove = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		row.remove:SetPoint("TOPLEFT", 336, y + 1)
		row.remove:SetSize(70, 20)
		row.remove:SetText("Remove")
		rows[i] = row
	end
	local more = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	more:SetPoint("TOPLEFT", 16, -184 - MAX_ROWS * 24)

	Refresh = function()
		local ids = {}
		for id in pairs(r.items) do ids[#ids + 1] = id end
		table.sort(ids)
		for i, row in ipairs(rows) do
			local id = ids[i]
			for _, w in pairs(row) do w:SetShown(id ~= nil) end
			if id then
				row.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or GetItemIcon(id))
				row.name:SetText((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id))
				row.count:SetText(r.items[id])
				local function Save()
					local n = tonumber(row.count:GetText())
					if n and n > 0 then r.items[id] = n end
					row.count:ClearFocus()
				end
				row.count:SetScript("OnEnterPressed", Save)
				row.count:SetScript("OnEditFocusLost", Save)
				row.remove:SetScript("OnClick", function() r.items[id] = nil; Refresh() end)
			end
		end
		more:SetText(#ids > MAX_ROWS and ("+%d more (remove some to see them)"):format(#ids - MAX_ROWS) or
			(#ids == 0 and "No items yet: add your class preset or your own items" or ""))
	end
	refreshers[#refreshers + 1] = Refresh
	parent:SetScript("OnShow", function() for _, f in ipairs(refreshers) do f() end end)
end

local function BuildProfilesPage(parent)
	local MAX_ROWS = 12
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOPLEFT", 16, -12)
	title:SetText("Save current action bars and talents as:")
	local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	input:SetPoint("TOPLEFT", 22, -32)
	input:SetSize(200, 22)
	input:SetAutoFocus(false)
	input:SetMaxLetters(32)
	local save = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	save:SetPoint("LEFT", input, "RIGHT", 8, 0)
	save:SetSize(80, 22)
	save:SetText("Save")
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
	input:SetScript("OnEscapePressed", input.ClearFocus)

	local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 16, -62)
	note:SetWidth(440)
	note:SetJustifyH("LEFT")
	note:SetText("Shared by all your characters of this class. Loading bars first saves your current bars as '(backup)'.")

	local function SmallButton(text, x, y)
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetPoint("TOPLEFT", x, y)
		b:SetSize(58, 20)
		b:SetText(text)
		return b
	end
	local rows = {}
	for i = 1, MAX_ROWS do
		local y = -96 - (i - 1) * 26
		local row = {}
		row.name = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		row.name:SetPoint("TOPLEFT", 16, y - 2)
		row.name:SetWidth(170)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.info = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		row.info:SetPoint("TOPLEFT", 16, y - 14)
		row.bars = SmallButton("Bars", 190, y)
		row.talents = SmallButton("Talents", 250, y)
		row.both = SmallButton("Both", 310, y)
		row.delete = SmallButton("Delete", 380, y)
		rows[i] = row
	end

	local armedDelete
	local function Refresh()
		local names = ns.Profiles.List()
		for i, row in ipairs(rows) do
			local name = names[i]
			for _, w in pairs(row) do w:SetShown(name ~= nil) end
			if name then
				local p = ns.Profiles.Get(name)
				row.name:SetText(name)
				row.info:SetText(("by %s, %s"):format(p.by or "?", date("%Y-%m-%d %H:%M", p.at or 0)))
				row.bars:SetScript("OnClick", function() ns.Profiles.LoadBars(name) end)
				row.talents:SetScript("OnClick", function() ns.Profiles.LoadTalents(name) end)
				row.both:SetScript("OnClick", function() ns.Profiles.LoadBoth(name) end)
				-- two clicks to delete: no popup dialog
				row.delete:SetText(armedDelete == name and "Sure?" or "Delete")
				row.delete:SetScript("OnClick", function()
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
		if #names == 0 then
			rows[1].name:SetText("No profiles yet")
			rows[1].name:Show()
		end
	end
	ns.OnProfilesChanged = function() if parent:IsVisible() then Refresh() end end
	parent:SetScript("OnShow", function() armedDelete = nil; Refresh() end)
end

-- Sidebar sections (General + class sections), each with tools. Class sections show only on those classes.
local ICON = "Interface\\Icons\\"
local GROUPS = {
	{ name = "General", tools = {
		{ name = "PvP Kills", build = BuildPvpPage, icon = ICON .. "Ability_DualWield", desc = "Your score against each enemy player and the latest kills and deaths." },
		{ name = "PvP Settings", build = BuildPvpSettingsPage, icon = ICON .. "INV_BannerPVP_01", desc = "Tooltip score, announcements and sounds for open-world PvP." },
		{ name = "Nearby Enemies", build = BuildNearbyPage, icon = ICON .. "Ability_Hunter_EagleEye", desc = "Opposite-faction players seen around you." },
		{ name = "Profiles", build = BuildProfilesPage, icon = ICON .. "INV_Misc_Book_09", desc = "Save and load action bars and talents, shared by your characters of this class." },
		{ name = "Auto Restock", build = BuildRestockPage, icon = ICON .. "INV_Misc_Bag_10", desc = "Buy reagents and supplies automatically at vendors." },
	} },
	{ name = "Caster", classes = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }, tools = {
		{ name = "Mana Ticks", build = BuildManaPage, icon = ICON .. "INV_Potion_76", desc = "The five second rule and the next mana tick." },
	} },
	{ name = "Rogue", class = "ROGUE", tools = {
		{ name = "Stealth Action Bars", build = BuildBarSwitchPage, icon = ICON .. "Ability_Stealth", desc = "Which bars switch page while in Stealth." },
		{ name = "Poisons", build = BuildPoisonsPage, icon = ICON .. "Ability_Poisons", desc = "Weapon poison bar, timers and reminders." },
		{ name = "Poison Stock", build = BuildPoisonStockPage, icon = ICON .. "Trade_BrewPoison", desc = "Poisons to keep in bags: ingredients bought and crafting suggested." },
		{ name = "Combat Bars", build = BuildComboPage, icon = ICON .. "Ability_Rogue_Eviscerate", desc = "Health, energy and combo point bars." },
	} },
}

local toolSelectors = {} -- tool name -> function showing that tool
local T = ns.Theme
local SIDEBAR, HEADER = 200, 64

local function CreateWindow()
	local f = CreateFrame("Frame", "DpwsToolsWindow", UIParent)
	f:SetSize(900, 640)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	T.Panel(f, T.window)
	local pos = ns.db.window
	f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
	tinsert(UISpecialFrames, f:GetName()) -- Esc closes it

	-- header: logo, title, close; dragging it moves the window
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
	logo:SetSize(36, 36)
	logo:SetPoint("LEFT", 16, 0)
	logo:SetTexture("Interface\\AddOns\\dpws_tools\\media\\icon")
	local title = T.Text(header, "semibold", 18, { 1, 1, 1, 1 })
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -2)
	title:SetText("dpws tools")
	local version = T.Text(header, "regular", 11, T.muted)
	version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	version:SetText("v" .. ((C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)("dpws_tools", "Version") or "?"))
	local close = CreateFrame("Button", nil, header)
	close:SetSize(28, 28)
	close:SetPoint("TOPRIGHT", -10, -10)
	local x = T.Text(close, "semibold", 16, T.muted)
	x:SetPoint("CENTER")
	x:SetText("X")
	close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1) end)
	close:SetScript("OnLeave", function() x:SetTextColor(unpack(T.muted)) end)
	close:SetScript("OnClick", function() f:Hide() end)
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 1, 1, 0.07)
	rule:SetPoint("TOPLEFT", 0, -HEADER)
	rule:SetPoint("TOPRIGHT", 0, -HEADER)
	rule:SetHeight(1)

	-- sidebar: section labels and nav items
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 1, -HEADER - 1)
	side:SetPoint("BOTTOMLEFT", 1, 1)
	side:SetWidth(SIDEBAR)
	T.Panel(side, T.sidebar, false)

	-- content: page title, description, then the page
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", SIDEBAR + 24, -HEADER - 16)
	content:SetPoint("BOTTOMRIGHT", -24, 16)
	local pageTitle = T.Text(content, "semibold", 18, { 1, 1, 1, 1 })
	pageTitle:SetPoint("TOPLEFT")
	local pageDesc = T.Text(content, "regular", 12, T.muted)
	pageDesc:SetPoint("TOPLEFT", pageTitle, "BOTTOMLEFT", 0, -6)
	pageDesc:SetPoint("RIGHT")
	pageDesc:SetJustifyH("LEFT")

	local playerClass = select(2, UnitClass("player"))
	local navs = {}
	local function Select(nav)
		for _, n in ipairs(navs) do
			local on = n == nav
			n.page:SetShown(on)
			n.active:SetShown(on)
			n.bar:SetShown(on)
			n.label:SetTextColor(unpack(on and { 1, 1, 1, 1 } or { 0.68, 0.71, 0.76, 1 }))
		end
		pageTitle:SetText(nav.tool.name)
		pageDesc:SetText(nav.tool.desc or "")
	end
	local y = -14
	for _, group in ipairs(GROUPS) do
		if (not group.class or group.class == playerClass) and (not group.classes or group.classes[playerClass])
			and #group.tools > 0 then
			local label = T.Text(side, "semibold", 11, T.gold)
			label:SetPoint("TOPLEFT", 18, y)
			label:SetText(group.name:upper())
			y = y - 22
			for _, tool in ipairs(group.tools) do
				local nav = CreateFrame("Button", nil, side)
				nav:SetPoint("TOPLEFT", 8, y)
				nav:SetSize(SIDEBAR - 16, 30)
				nav.tool = tool
				nav.active = nav:CreateTexture(nil, "BACKGROUND")
				nav.active:SetAllPoints()
				nav.active:SetColorTexture(unpack(T.control))
				nav.bar = nav:CreateTexture(nil, "ARTWORK")
				nav.bar:SetPoint("TOPLEFT")
				nav.bar:SetPoint("BOTTOMLEFT")
				nav.bar:SetWidth(3)
				nav.bar:SetColorTexture(unpack(T.gold))
				local hl = nav:CreateTexture(nil, "HIGHLIGHT")
				hl:SetAllPoints()
				hl:SetColorTexture(unpack(T.hover))
				local icon = nav:CreateTexture(nil, "ARTWORK")
				icon:SetSize(18, 18)
				icon:SetPoint("LEFT", 12, 0)
				icon:SetTexture(tool.icon or 134400)
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				nav.label = T.Text(nav, "medium", 13, T.text)
				nav.label:SetPoint("LEFT", icon, "RIGHT", 10, 0)
				nav.label:SetText(tool.name)
				nav.page = CreateFrame("Frame", nil, content)
				nav.page:SetPoint("TOPLEFT", 0, -54)
				nav.page:SetPoint("BOTTOMRIGHT")
				tool.build(nav.page)
				T.Skin(nav.page)
				nav:SetScript("OnClick", function() Select(nav) end)
				navs[#navs + 1] = nav
				toolSelectors[tool.name] = function() Select(nav) end
				y = y - 32
			end
			y = y - 10
		end
	end
	if navs[1] then
		Select(navs[1])
	else
		pageTitle:SetText("No tools for your class yet")
	end

	-- shared actions at the bottom of the sidebar
	local hl = T.NewButton(side, "Highlight bars", SIDEBAR - 32, 26)
	hl:SetPoint("BOTTOMLEFT", 16, 50)
	hl:SetScript("OnClick", function() SetHighlights(not highlightsOn) end)
	local lock = T.NewButton(side, "Unlock panels", SIDEBAR - 32, 26)
	lock:SetPoint("BOTTOMLEFT", 16, 16)
	local function LockText() lock:SetText(ns.unlocked and "Lock panels" or "Unlock panels") end
	lock:SetScript("OnClick", function() ns.SetUnlocked(not ns.unlocked); LockText() end)
	lock:SetScript("OnShow", LockText)
	LockText()

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

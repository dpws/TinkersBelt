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

-- top tabs (General + class tabs), each with vertical tool tabs. Class tabs show only on that class.
local GROUPS = {
	{ name = "General", tools = {} },
	{ name = "Rogue", class = "ROGUE", tools = {
		{ name = "Stealth Action Bars", build = BuildBarSwitchPage },
		{ name = "Poisons", build = BuildPoisonsPage },
	} },
}

-- Questie/AceGUI-style top tab: 3-slice active/inactive textures from the options frame
local function TopTab(parent, text)
	local tab = CreateFrame("Button", nil, parent)
	tab:SetHeight(24)
	local function Slices(file, layerPoint)
		local l, m, r = tab:CreateTexture(nil, "BORDER"), tab:CreateTexture(nil, "BORDER"), tab:CreateTexture(nil, "BORDER")
		for _, t in ipairs({ l, m, r }) do t:SetTexture(file); t:SetHeight(24) end
		l:SetWidth(20); r:SetWidth(20)
		l:SetPoint(layerPoint, 0, layerPoint == "BOTTOMLEFT" and -3 or 0)
		r:SetPoint("TOP", l, "TOP"); r:SetPoint("RIGHT", tab, "RIGHT")
		m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
		l:SetTexCoord(0, 0.15625, 0, 1); m:SetTexCoord(0.15625, 0.84375, 0, 1); r:SetTexCoord(0.84375, 1, 0, 1)
		return { l, m, r }
	end
	local active = Slices("Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab", "BOTTOMLEFT")
	local inactive = Slices("Interface\\OptionsFrame\\UI-OptionsFrame-InActiveTab", "TOPLEFT")
	local fs = tab:CreateFontString(nil, "OVERLAY")
	tab:SetFontString(fs)
	tab:SetNormalFontObject(GameFontNormalSmall)
	tab:SetHighlightFontObject(GameFontHighlightSmall)
	tab:SetDisabledFontObject(GameFontHighlightSmall)
	tab:SetText(text)
	tab:SetWidth(fs:GetStringWidth() + 40)
	tab:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
	tab:GetHighlightTexture():ClearAllPoints()
	tab:GetHighlightTexture():SetPoint("LEFT", 10, -4)
	tab:GetHighlightTexture():SetPoint("RIGHT", -10, -4)
	function tab:SetSelected(on)
		for _, t in ipairs(active) do t:SetShown(on) end
		for _, t in ipairs(inactive) do t:SetShown(not on) end
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", 0, on and -2 or -3)
		self:SetEnabled(not on)
	end
	return tab
end

-- left: vertical tool tabs, right: the selected tool's page
local function BuildGroup(parent, tools)
	local tabs = {}
	local function Select(index)
		for i, t in ipairs(tabs) do
			t.page:SetShown(i == index)
			if i == index then t:LockHighlight() else t:UnlockHighlight() end
		end
	end
	for i, tool in ipairs(tools) do
		local tab = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		tab:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 30)
		tab:SetSize(150, 26)
		tab:SetText(tool.name)
		tab:SetScript("OnClick", function() Select(i) end)
		tab.page = CreateFrame("Frame", nil, parent)
		tab.page:SetPoint("TOPLEFT", 166, -4)
		tab.page:SetPoint("BOTTOMRIGHT", -4, 4)
		tool.build(tab.page)
		tabs[i] = tab
	end
	Select(1)
end

local function CreateWindow()
	local f = CreateFrame("Frame", "DpwsToolsWindow", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	f:SetTitle("dpws tools")
	f:SetSize(660, 500)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		ns.db.window = { point = point, x = x, y = y }
	end)
	local pos = ns.db.window
	f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
	tinsert(UISpecialFrames, f:GetName()) -- Esc closes it

	-- toolbar strip on top, shared by all tabs
	local TOOLBAR = 40
	local hl = CreateFrame("Button", nil, f.Inset, "UIPanelButtonTemplate")
	hl:SetPoint("TOPLEFT", 8, -8)
	hl:SetSize(130, 26)
	hl:SetText("Highlight bars")
	hl:SetScript("OnClick", function() SetHighlights(not highlightsOn) end)

	local lock = CreateFrame("Button", nil, f.Inset, "UIPanelButtonTemplate")
	lock:SetPoint("LEFT", hl, "RIGHT", 8, 0)
	lock:SetSize(130, 26)
	local function LockText() lock:SetText(ns.unlocked and "Lock panels" or "Unlock panels") end
	lock:SetScript("OnClick", function() ns.SetUnlocked(not ns.unlocked); LockText() end)
	lock:SetScript("OnShow", LockText)
	LockText()

	local line = f.Inset:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetPoint("TOPLEFT", 4, -TOOLBAR)
	line:SetPoint("TOPRIGHT", -4, -TOOLBAR)
	line:SetHeight(1)

	-- bordered content box under the top tabs (AceGUI pane look)
	local box = CreateFrame("Frame", nil, f.Inset, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 6, -TOOLBAR - 30)
	box:SetPoint("BOTTOMRIGHT", -6, 6)
	box:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 3, right = 3, top = 5, bottom = 3 },
	})
	box:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
	box:SetBackdropBorderColor(0.4, 0.4, 0.4)

	local playerClass = select(2, UnitClass("player"))
	local groups = {}
	local function SelectGroup(index)
		for i, g in ipairs(groups) do
			g.tab:SetSelected(i == index)
			g.content:SetShown(i == index)
		end
	end
	for _, group in ipairs(GROUPS) do
		if (not group.class or group.class == playerClass) and #group.tools > 0 then
			local i = #groups + 1
			local tab = TopTab(f.Inset, group.name)
			if i == 1 then
				tab:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 6, -3)
			else
				tab:SetPoint("LEFT", groups[i - 1].tab, "RIGHT", -10, 0)
			end
			tab:SetScript("OnClick", function() SelectGroup(i) end)
			local content = CreateFrame("Frame", nil, box)
			content:SetAllPoints()
			BuildGroup(content, group.tools)
			groups[i] = { tab = tab, content = content }
		end
	end
	SelectGroup(1)
	if #groups == 0 then
		local t = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		t:SetPoint("CENTER")
		t:SetText("No tools for your class yet")
	end

	f:SetScript("OnHide", function() SetHighlights(false); ns.SetUnlocked(false) end)
	f:Hide()
	return f
end

function ns.ToggleWindow()
	window = window or CreateWindow()
	window:SetShown(not window:IsShown())
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

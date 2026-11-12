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
	label:SetText(BarLabel(bar) .. "  \226\134\146") -- "Bar 2  →"

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
		label:SetText(BarLabel(bar) .. "  \226\134\146")
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

local function CreateWindow()
	local f = CreateFrame("Frame", "DpwsToolsWindow", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(f)
	f:SetTitle("dpws tools")
	f:SetSize(620, 500)
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

	-- left: tool list (one tool for now)
	local tab = CreateFrame("Button", nil, f.Inset, "UIPanelButtonTemplate")
	tab:SetPoint("TOPLEFT", 8, -8)
	tab:SetSize(130, 26)
	tab:SetText("Bar Switching")
	tab:LockHighlight()

	local page = CreateFrame("Frame", nil, f.Inset)
	page:SetPoint("TOPLEFT", 150, -4)
	page:SetPoint("BOTTOMRIGHT", -4, 4)
	BuildBarSwitchPage(page)

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

local _, ns = ...

-- page = fallback if the game doesn't expose its "actionpage" attribute; real value read at login
ns.BARS = {
	{ index = 2, frame = "MultiBarBottomLeft", name = "Bottom Left", page = 6 },
	{ index = 3, frame = "MultiBarBottomRight", name = "Bottom Right", page = 5 },
	{ index = 4, frame = "MultiBarRight", name = "Right", page = 3 },
	{ index = 5, frame = "MultiBarLeft", name = "Left", page = 4 },
	{ index = 6, frame = "MultiBar5", name = "Bar 6", page = 13 },
	{ index = 7, frame = "MultiBar6", name = "Bar 7", page = 14 },
	{ index = 8, frame = "MultiBar7", name = "Bar 8", page = 15 },
}

function ns.BarByIndex(index)
	for _, bar in ipairs(ns.BARS) do
		if bar.index == index then return bar end
	end
end

-- pages a bar may borrow: 1-15 minus stance/vehicle pages 7-12 and its own page
function ns.ValidPages(barIndex)
	local own = ns.BarByIndex(barIndex).page
	local pages = {}
	for page = 1, 15 do
		if (page < 7 or page > 12) and page ~= own then pages[#pages + 1] = page end
	end
	return pages
end

local DRIVER = "[bonusbar:1] 1; [bonusbar:2] 2; [bonusbar:3] 3; [bonusbar:4] 4; 0"
local handler

-- Runs in the restricted (secure) environment, so it works in combat.
-- Only touches bars that have at least one mapping ("used-<bar>").
local UPDATE = [[
	local state = ...
	for bar = 2, 8 do
		if self:GetAttribute("used-" .. bar) then
			local page = self:GetAttribute("map-" .. state .. "-" .. bar) or self:GetAttribute("own-" .. bar)
			for i = 1, 12 do
				local b = self:GetFrameRef("b" .. bar .. "_" .. i)
				if b then b:SetAttribute("actionpage", page) end
			end
		end
	end
]]

local function Setup()
	handler = CreateFrame("Frame", "DpwsBarSwitchHandler", UIParent, "SecureHandlerStateTemplate")
	for _, bar in ipairs(ns.BARS) do
		local first = _G[bar.frame .. "Button1"]
		if first then
			-- button's own value (nil when it reads the bar's via useparent) is what we restore
			handler:SetAttribute("own-" .. bar.index, first:GetAttribute("actionpage"))
			local page = tonumber(first:GetAttribute("actionpage"))
				or (_G[bar.frame] and tonumber(_G[bar.frame]:GetAttribute("actionpage")))
			bar.page = page or bar.page
			for i = 1, 12 do
				local b = _G[bar.frame .. "Button" .. i]
				if b then handler:SetFrameRef("b" .. bar.index .. "_" .. i, b) end
			end
		end
	end
	handler:SetAttribute("update", UPDATE)
	handler:SetAttribute("_onstate-bar", [[ self:RunAttribute("update", newstate) ]])
	ns.ApplyBarSwitch()
	RegisterStateDriver(handler, "bar", DRIVER)
end

function ns.ApplyBarSwitch()
	ns.RunOutOfCombat(function()
		if not handler then return end
		for _, bar in ipairs(ns.BARS) do
			local used = false
			for state = 1, 4 do
				local page = ns.db.barSwitch[state] and ns.db.barSwitch[state][bar.index]
				handler:SetAttribute("map-" .. state .. "-" .. bar.index, page)
				used = used or page ~= nil
			end
			-- a bar that just lost its last mapping is restored once, then left alone
			if not used and handler:GetAttribute("used-" .. bar.index) then
				handler:Execute(([[ self:SetAttribute("used-%d", true); self:RunAttribute("update", "0") ]]):format(bar.index))
			end
			handler:SetAttribute("used-" .. bar.index, used or nil)
		end
		handler:Execute([[ self:RunAttribute("update", self:GetAttribute("state-bar") or "0") ]])
	end)
end

table.insert(ns.loginHooks, function() ns.RunOutOfCombat(Setup) end)

-- self-check
local p2 = ns.ValidPages(2)
if not (tContains(p2, 14) and not tContains(p2, 6) and not tContains(p2, 7) and not tContains(p2, 12) and #p2 == 8) then
	print("|cffff4040dpws_tools: self-check FAILED (BarSwitch)|r")
end

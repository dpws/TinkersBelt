local _, ns = ...

local ICON = "Interface\\AddOns\\dpws_tools\\media\\icon"
local RADIUS = 105 -- distance from minimap center; default minimap is ~140px wide

local function Place(button, angle)
	local r = math.rad(angle)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(r) * RADIUS, math.sin(r) * RADIUS)
end

table.insert(ns.loginHooks, function()
	ns.db.minimap = ns.db.minimap or { angle = 225 }

	local b = CreateFrame("Button", "DpwsToolsMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture(ICON)
	local mask = b:CreateMaskTexture()
	mask:SetAllPoints(icon)
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	icon:AddMaskTexture(mask)

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	b:SetScript("OnClick", function() ns.ToggleWindow() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("dpws tools")
		GameTooltip:AddLine("Click: open settings  ||  Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)

	-- drag around the minimap edge
	local function OnUpdate(self)
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		ns.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
		Place(self, ns.db.minimap.angle)
	end
	b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnUpdate) end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	Place(b, ns.db.minimap.angle)
end)

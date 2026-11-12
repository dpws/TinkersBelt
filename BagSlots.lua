local _, ns = ...

-- Free slot count on the backpack and reagent bag buttons (bag bar, bottom right).
local BAGS = {
	{ button = "MainMenuBarBackpackButton", bag = 0 },
	{ button = "CharacterReagentBag0Slot", bag = Enum.BagIndex and Enum.BagIndex.ReagentBag or 5 },
}

local labels = {}

local function Update()
	for i, b in ipairs(BAGS) do
		local fs = labels[i]
		if fs then
			local size = C_Container.GetContainerNumSlots(b.bag)
			fs:SetText(size > 0 and C_Container.GetContainerNumFreeSlots(b.bag) or "")
		end
	end
end

table.insert(ns.loginHooks, function()
	for i, b in ipairs(BAGS) do
		local button = _G[b.button]
		if button then
			-- big, outlined, on its own top layer so the bag icon doesn't swallow it
			local holder = CreateFrame("Frame", nil, button)
			holder:SetAllPoints()
			holder:SetFrameLevel(button:GetFrameLevel() + 5)
			local fs = holder:CreateFontString(nil, "OVERLAY")
			fs:SetFont(STANDARD_TEXT_FONT, 18, "THICKOUTLINE")
			fs:SetTextColor(1, 0.85, 0.1)
			fs:SetShadowOffset(1, -1)
			fs:SetPoint("CENTER", 0, 2)
			labels[i] = fs
		end
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("BAG_UPDATE_DELAYED")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", Update)
	Update()
end)

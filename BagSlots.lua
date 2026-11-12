local _, ns = ...

-- Free slot count on the backpack and reagent bag buttons (bag bar, bottom right).
-- backpack button: all general bags (backpack + 4 bag slots); reagent button: the reagent bag
local BAGS = {
	{ button = "MainMenuBarBackpackButton", bags = { 0, 1, 2, 3, 4 }, generalOnly = true },
	{ button = "CharacterReagentBag0Slot", bags = { Enum.BagIndex and Enum.BagIndex.ReagentBag or 5 } },
}

local labels = {}

-- free slots and total size; generalOnly skips special bags (quiver, ammo, soul, herb...: bagType ~= 0)
local function Free(bags, generalOnly)
	local free, size = 0, 0
	for _, bag in ipairs(bags) do
		local n = C_Container.GetContainerNumSlots(bag)
		local f, bagType = C_Container.GetContainerNumFreeSlots(bag)
		if n > 0 and (not generalOnly or bagType == 0) then
			free, size = free + f, size + n
		end
	end
	return free, size
end

local function Update()
	for i, b in ipairs(BAGS) do
		local fs = labels[i]
		if fs then
			local free, size = Free(b.bags, b.generalOnly)
			fs:SetText(size > 0 and free or "")
			fs.shade:SetShown(size > 0)
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
			fs:SetShadowOffset(2, -2)
			fs:SetShadowColor(0, 0, 0, 1)
			fs:SetPoint("CENTER", 0, 2)
			-- dark round backing so the number reads on any bag icon
			local shade = holder:CreateTexture(nil, "ARTWORK")
			shade:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
			shade:SetVertexColor(0, 0, 0, 0.75)
			shade:SetSize(28, 28)
			shade:SetPoint("CENTER", fs, "CENTER", 0, 0)
			fs.shade = shade
			labels[i] = fs
		end
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("BAG_UPDATE_DELAYED")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", Update)
	Update()
end)

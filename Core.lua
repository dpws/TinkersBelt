local ADDON, ns = ...
DpwsTools = ns -- global for /run debugging

ns.loginHooks = {}

local queue = {}
function ns.RunOutOfCombat(fn)
	if InCombatLockdown() then
		queue[#queue + 1] = fn
	else
		fn()
	end
end

-- movable panels: overlay + drag only while unlocked (starts locked every session)
ns.panels = {}
ns.unlocked = false

local function ShowOverlay(p) p.bg:SetShown(ns.unlocked); p.label:SetShown(ns.unlocked) end

function ns.RegisterPanel(frame, name)
	-- on the panel frame itself, BACKGROUND layer: draws under its child buttons
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -6, 6)
	bg:SetPoint("BOTTOMRIGHT", 6, -20)
	bg:SetColorTexture(0.1, 0.5, 1, 0.35)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("BOTTOM", bg, "BOTTOM", 0, 4)
	label:SetText(name)
	local p = { bg = bg, label = label }
	ns.panels[#ns.panels + 1] = p
	ShowOverlay(p)
end

function ns.SetUnlocked(on)
	ns.unlocked = on
	for _, p in ipairs(ns.panels) do ShowOverlay(p) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		DpwsToolsCharDB = DpwsToolsCharDB or {}
		local db = DpwsToolsCharDB
		db.barSwitch = db.barSwitch or {}
		db.window = db.window or {}
		db.poisons = db.poisons or { enabled = true, warnMinutes = 5, sound = true }
		ns.db = db
	elseif event == "PLAYER_LOGIN" then
		for _, hook in ipairs(ns.loginHooks) do hook() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		local pending = queue
		queue = {}
		for _, fn in ipairs(pending) do fn() end
	end
end)

SLASH_DPWS1 = "/dpws"
SlashCmdList.DPWS = function()
	if ns.ToggleWindow then ns.ToggleWindow() else print("dpws_tools loaded") end
end

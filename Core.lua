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

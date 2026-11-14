local _, ns = ...

-- Addon-wide center-screen notifications in a movable panel (unlock in /dpws to move).
local frame

-- addon-wide sound choices (SOUNDKIT keys); missing ones on this client are skipped when played
ns.SOUNDS = {
	{ key = "MAP_PING", name = "Ping" },
	{ key = "TELL_MESSAGE", name = "Whisper" },
	{ key = "READY_CHECK", name = "Ready check" },
	{ key = "RAID_WARNING", name = "Raid warning" },
	{ key = "ALARM_CLOCK_WARNING_2", name = "Alarm 1" },
	{ key = "ALARM_CLOCK_WARNING_3", name = "Alarm 2" },
	{ key = "UI_BATTLEGROUND_COUNTDOWN_FINISHED", name = "Battle start" },
	{ key = "PVP_THROUGH_QUEUE", name = "PvP queue" },
}

function ns.PlaySoundKey(key)
	local id = key and SOUNDKIT[key]
	if id then PlaySound(id, "Master") end
end

function ns.Notify(msg, playSound)
	if frame then
		frame:AddMessage(msg, 1, 0.3, 0.1)
	else
		print("dpws_tools: " .. msg) -- before login
	end
	if playSound then PlaySound(SOUNDKIT.RAID_WARNING) end
	if ns.SetFooter then ns.SetFooter(msg) end -- config window status line
end

table.insert(ns.loginHooks, function()
	ns.db.notify = ns.db.notify or {}
	frame = CreateFrame("MessageFrame", "DpwsNotifyFrame", UIParent)
	frame:SetSize(500, 60)
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetInsertMode("TOP")
	frame:SetFading(true)
	frame:SetTimeVisible(4)
	frame:SetFadeDuration(1)
	frame:SetFont(ns.Theme.font.semibold, 24, "OUTLINE")
	local pos = ns.db.notify.pos
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
	end
	ns.RegisterPanel(frame, "Notifications", function(self)
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.notify.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)
end)

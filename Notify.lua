local _, ns = ...

-- Addon-wide center-screen notifications in a movable panel (unlock in /dpws to move).
local frame

function ns.Notify(msg, playSound)
	if frame then
		frame:AddMessage(msg, 1, 0.3, 0.1)
	else
		print("dpws_tools: " .. msg) -- before login
	end
	if playSound then PlaySound(SOUNDKIT.RAID_WARNING) end
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
	frame:SetFontObject(GameFontNormalHuge)
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

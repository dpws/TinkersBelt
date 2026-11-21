-- Offline test for panel grid snapping. Run: luajit tests/grid.lua
local ns = {}
local stub = setmetatable({}, { __index = function() return function() end end })
CreateFrame = function() return stub end
SlashCmdList = {}
assert(loadfile("Core.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

check("grid lines run out from the centre", ns.SnapToGrid(530, 32, 500) == 532)
check("start edge snaps", ns.SnapEdges(3, 10, 16, 0) == 0)
check("middle snaps", ns.SnapEdges(9, 10, 16, 0) == 11)
check("end edge snaps", ns.SnapEdges(23, 10, 16, 0) == 22)
check("returns the line it snapped to", select(2, ns.SnapEdges(9, 10, 16, 0)) == 16)
check("centred panel stays centred", ns.SnapEdges(450, 100, 32, 500) == 450)
check("says which part snapped: middle", select(3, ns.SnapEdges(9, 10, 16, 0)) == 2)
check("says which part snapped: end edge", select(3, ns.SnapEdges(23, 10, 16, 0)) == 3)
check("pin point: right edge + top edge", ns.SnapPoint(3, 3) == "TOPRIGHT")
check("pin point: middle + middle", ns.SnapPoint(2, 2) == "CENTER")
check("pin point: left edge + middle", ns.SnapPoint(1, 2) == "LEFT")
check("pin point: middle + bottom edge", ns.SnapPoint(2, 1) == "BOTTOM")
local fx, fy = ns.PointFraction("TOPRIGHT")
check("TOPRIGHT sits at the top right", fx == 1 and fy == 1)
fx, fy = ns.PointFraction("CENTER")
check("CENTER sits in the middle", fx == 0.5 and fy == 0.5)
fx, fy = ns.PointFraction("BOTTOMLEFT")
check("BOTTOMLEFT sits at the bottom left", fx == 0 and fy == 0)
print("grid: " .. passed .. " passed")

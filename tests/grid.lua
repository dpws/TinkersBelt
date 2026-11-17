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
check("centred panel stays centred", ns.SnapEdges(450, 100, 32, 500) == 450)
print("grid: " .. passed .. " passed")

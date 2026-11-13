-- Offline test for nearby-enemies list logic. Run: luajit tests/nearby.lua
local ns = { loginHooks = {} }
assert(loadfile("Nearby.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

-- seen: returns true only when the player is new (or came back after timing out)
local list = {}
check("first sighting is new", ns.NearbySeen(list, "A", { name = "Aaa" }, 100, 60) == true)
check("seen again: not new", ns.NearbySeen(list, "A", { level = 60 }, 110, 60) == false)
check("info merged, name kept", list.A.name == "Aaa" and list.A.level == 60 and list.A.seen == 110)
check("level not overwritten by nil", (function() ns.NearbySeen(list, "A", {}, 111, 60); return list.A.level == 60 end)())
check("back after timeout is new again", ns.NearbySeen(list, "A", {}, 200, 60) == true)

-- sorted + pruned: newest first, expired removed
list = {}
ns.NearbySeen(list, "A", { name = "A" }, 100, 60)
ns.NearbySeen(list, "B", { name = "B" }, 150, 60)
ns.NearbySeen(list, "C", { name = "C" }, 120, 60)
local items = ns.NearbySorted(list, 170, 60)
check("expired dropped", #items == 2 and list.A == nil)
check("newest first", items[1].name == "B" and items[2].name == "C")

print("nearby: " .. passed .. " passed")

-- Offline test for nearby allies list logic. Run: luajit tests/allies_list.lua
local ns = { loginHooks = {} }
assert(loadfile("AlliesList.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

-- range band from the checks the game gives: exact yards (group) > trade > follow > spell > visible
check("exact distance wins", ns.AllyRange({ yards = 7.4, trade = false }) == 7.4)
check("trade range ~10", ns.AllyRange({ trade = true, follow = true, spell = true }) == 10)
check("follow range ~28", ns.AllyRange({ trade = false, follow = true, spell = true }) == 28)
check("buff spell range ~40", ns.AllyRange({ trade = false, follow = false, spell = true }) == 40)
check("only visible: far", ns.AllyRange({ trade = false, follow = false, spell = false }) == 100)

-- sorted by range, then name
local list = {
	{ name = "Zed", range = 28 }, { name = "Amy", range = 28 }, { name = "Bob", range = 10 }, { name = "Cid", range = 100 },
}
ns.AlliesSort(list)
check("closest first", list[1].name == "Bob")
check("same band by name", list[2].name == "Amy" and list[3].name == "Zed")
check("far last", list[4].name == "Cid")

-- range label
check("label 10", ns.AllyRangeText(10) == "10y")
check("label exact rounds", ns.AllyRangeText(7.4) == "7y")
check("label far", ns.AllyRangeText(100) == "far")

print("allies_list: " .. passed .. " passed")

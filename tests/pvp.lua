-- Offline test for PvP score logic. Run: luajit tests/pvp.lua
local ns = { loginHooks = {} }
assert(loadfile("Pvp.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

-- record
local scores = {}
ns.PvpRecord(scores, "Player-1-AAA", "Gank", "k")
ns.PvpRecord(scores, "Player-1-AAA", "Gank", "k")
ns.PvpRecord(scores, "Player-1-AAA", "Gank-Realm", "d")
check("kills counted", scores["Player-1-AAA"].k == 2)
check("deaths counted", scores["Player-1-AAA"].d == 1)
check("latest name kept", scores["Player-1-AAA"].name == "Gank-Realm")
ns.PvpRecord(scores, "Player-1-BBB", "Other", "d")
check("separate players", scores["Player-1-BBB"].k == 0 and scores["Player-1-BBB"].d == 1)

-- killer = last enemy player hit within the window
check("recent hit is killer", ns.PvpKiller({ guid = "G", name = "N", time = 100 }, 105, 10) == "G")
check("old hit is not killer", ns.PvpKiller({ guid = "G", name = "N", time = 100 }, 111, 10) == nil)
check("no hit, no killer", ns.PvpKiller(nil, 100, 10) == nil)

-- score text: your kills first, colored by who's ahead
check("ahead green", ns.PvpScoreText({ k = 3, d = 1 }) == "|cff40ff403 : 1|r")
check("behind red", ns.PvpScoreText({ k = 0, d = 2 }) == "|cffff40400 : 2|r")
check("even white", ns.PvpScoreText({ k = 1, d = 1 }) == "|cffffffff1 : 1|r")

print("pvp: " .. passed .. " passed")

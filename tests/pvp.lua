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

-- history log: capped, oldest dropped
local log = {}
for i = 1, 7 do ns.PvpLogAdd(log, { n = i }, 5) end
check("log capped", #log == 5)
check("oldest dropped", log[1].n == 3 and log[5].n == 7)

-- pages: newest first, 2 per page
local items, pages = ns.PvpPage(log, 1, 2)
check("page 1 newest first", #items == 2 and items[1].n == 7 and items[2].n == 6)
check("page count", pages == 3)
items = ns.PvpPage(log, 3, 2)
check("last page partial", #items == 1 and items[1].n == 3)
items, pages = ns.PvpPage(log, 9, 2)
check("page clamped to last", #items == 1 and items[1].n == 3)
items, pages = ns.PvpPage({}, 1, 15)
check("empty log: 1 page, no items", #items == 0 and pages == 1)

-- announcement text
local score = { k = 3, d = 1 }
check("kill text", ns.PvpAnnounceText("k", "Gank", "Rogue", 60, score) == "Killed Gank (60 Rogue)  |cff40ff403 : 1|r")
check("death text, unknown level", ns.PvpAnnounceText("d", "Orc", "Warrior", nil, score) == "Killed by Orc (?? Warrior)  |cff40ff403 : 1|r")
check("skull level -1 shows ??", ns.PvpAnnounceText("d", "Orc", "Warrior", -1, score) == "Killed by Orc (?? Warrior)  |cff40ff403 : 1|r")
check("unknown class", ns.PvpAnnounceText("k", "X", nil, 10, score) == "Killed X (10 ?)  |cff40ff403 : 1|r")

print("pvp: " .. passed .. " passed")

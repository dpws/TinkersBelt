-- luajit tests/theme.lua : classic theme swaps colours in place and leaves modern alone
local passed = 0
local function check(cond, msg) assert(cond, msg); passed = passed + 1 end

local function load()
	local ns = {}
	assert(loadfile("Theme.lua"))("TinkersBelt", ns)
	return ns.Theme
end

local T = load()
local gold, font = T.gold, T.font.medium
T.UseTheme(nil)
check(T.theme == "modern" and T.gold[1] < 0.5 and T.font.medium == font, "no setting keeps modern")

T = load()
gold = T.gold
T.UseTheme("classic")
check(T.theme == "classic", "classic chosen")
check(gold == T.gold and gold[1] == 1 and gold[2] == 0.82, "gold changed in place (references stay valid)")
check(T.font.medium:find("FRIZQT"), "Friz Quadrata font")
check(T.BAR:find("UI%-StatusBar"), "Blizzard status bar")

print(("theme: %d passed"):format(passed))

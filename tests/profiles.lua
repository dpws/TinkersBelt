-- Offline test for profile logic. Run: luajit tests/profiles.lua
local ns = { loginHooks = {} }
assert(loadfile("Profiles.lua"))("dpws_tools", ns)

local passed = 0
local function check(name, cond)
	if not cond then print("FAIL: " .. name); os.exit(1) end
	passed = passed + 1
end

-- talents: next point to buy = lowest tier first, then tab, then index
local saved = {
	{ tab = 1, i = 5, tier = 3, rank = 2 },
	{ tab = 1, i = 1, tier = 1, rank = 5 },
	{ tab = 2, i = 2, tier = 1, rank = 1 },
}
local current = {} -- "tab:i" -> rank
local function rankOf(tab, i) return current[tab .. ":" .. i] or 0 end

local t = ns.TalentNextStep(saved, rankOf)
check("tier 1 first, tab 1 before tab 2", t.tab == 1 and t.i == 1)
current["1:1"] = 5
t = ns.TalentNextStep(saved, rankOf)
check("then tab 2 tier 1", t.tab == 2 and t.i == 2)
current["2:2"] = 1
t = ns.TalentNextStep(saved, rankOf)
check("then tier 3", t.tab == 1 and t.i == 5)
current["1:5"] = 2
check("done: nil", ns.TalentNextStep(saved, rankOf) == nil)
check("skip set excludes failed talent", ns.TalentNextStep(saved, function() return 0 end, { ["1:1"] = true }).tab == 2)

-- bars: only slots that differ; nil saved = slot should be empty
local want = { [1] = { t = "spell", id = 100 }, [2] = { t = "macro", name = "Go" } }
local have = { [1] = { t = "spell", id = 100 }, [2] = { t = "spell", id = 5 }, [3] = { t = "item", id = 7 } }
local plan = ns.BarRestorePlan(want, have, 4)
check("unchanged slot skipped", plan[1] == nil)
check("changed slot planned", plan[2] and plan[2].action.name == "Go")
check("extra slot cleared", plan[3] and plan[3].action == nil)
check("both empty: skipped", plan[4] == nil)
local n = 0
for _ in pairs(plan) do n = n + 1 end
check("exactly two changes", n == 2)

print("profiles: " .. passed .. " passed")

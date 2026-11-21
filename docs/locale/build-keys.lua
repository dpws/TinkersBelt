-- Rebuilds docs/locale/keys.txt: every English text the addon translates (Loc["..."] literals, plus names kept
-- in tables that are translated where shown). Run from the repo root: luajit docs/locale/build-keys.lua
local files = { "Allies.lua", "AlliesList.lua", "BagCleaner.lua", "BagSlots.lua", "BarSwitch.lua", "Buffs.lua",
	"Combo.lua", "Config.lua", "Core.lua", "Lockbox.lua", "Macros.lua", "Mana.lua", "Minimap.lua", "Nearby.lua",
	"Notify.lua", "Opener.lua", "PoisonStock.lua", "Poisons.lua", "Profiles.lua", "Pvp.lua", "Restock.lua",
	"RogueTimers.lua", "Theme.lua", "Totems.lua" }
local keys = {}
local function add(lit)
	local ok, v = pcall(load("return " .. lit))
	if ok and type(v) == "string" and v:find("%a") then keys[v] = true end
end
local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
local LIT = '"[^"\\]*"'
for _, p in ipairs(files) do
	local s = read(p)
	for lit in s:gmatch('Loc%[(' .. LIT .. ')%]') do add(lit) end
end
-- names in tables, translated where shown
local cfg = read("Config.lua")
local groups = cfg:sub(cfg:find("local MANA_TOOL"), cfg:find("local toolSelectors"))
for lit in groups:gmatch('name = (' .. LIT .. ')') do add(lit) end
for lit in cfg:gmatch('KINDS = (%b{})') do for v in lit:gmatch(LIT) do add(v) end end
for lit in cfg:gmatch('{ "modern", (' .. LIT .. ') }') do add(lit) end
for lit in cfg:gmatch('{ "classic", (' .. LIT .. ') }') do add(lit) end
local mac = read("Macros.lua")
for _, block in ipairs({ "ns.MACRO_COMMANDS = (%b{})", "ns.MACRO_UNITS = (%b{})", "local FORMS = (%b{})", "local CHIP_ROWS = (%b{})" }) do
	local t = mac:match(block)
	for v in t:gmatch(LIT) do add(v) end
end
local tips = mac:match("local CHIP_TIPS = (%b{})")
for v in tips:gmatch("= (" .. LIT .. ")") do add(v) end
for k in tips:gmatch('%["([^"]+)"%] =') do keys[k] = true end
for k in tips:gmatch('(%a+) = "') do keys[k] = true end
for v in mac:match("ns.MACRO_TEMPLATES = (%b{})"):gmatch('name = (' .. LIT .. ')') do add(v) end
local tot = read("Totems.lua")
for v in tot:match("ns.TOTEM_ELEMENTS = (%b{})"):gmatch('name = (' .. LIT .. ')') do add(v) end
for v in tot:match("ns.TOTEM_SET_NAMES = (%b{})"):gmatch(LIT) do add(v) end
local combo = read("Combo.lua")
for v in combo:match("ns.COMBAT_BAR_MODES = (%b{})"):gmatch('name = (' .. LIT .. ')') do add(v) end
for _, p in ipairs({ "Notify.lua", "Core.lua" }) do
	local s = read(p)
	local t = s:match("ns.SOUNDS = (%b{})")
	if t then for v in t:gmatch('name = (' .. LIT .. ')') do add(v) end end
end
local bc = read("BagCleaner.lua")
for v in bc:match("local QUALITY_NAMES = (%b{})"):gmatch(LIT) do add(v) end
for _, word in ipairs({ "General", "Rogue", "Shaman", "poison", "imbue" }) do keys[word] = true end
-- engine words that are not text
for _, junk in ipairs({ "cast", "use", "target", "focus", "cancelaura", "startattack", "stopattack", "stopcasting",
	"/cast", "/use", "/target", "/focus", "/cancelaura", "/startattack", "/stopattack", "/stopcasting", "mouseover",
	"player", "targettarget", "pet", "help", "combat", "stealth", "dead", "shift", "ctrl", "alt", "Tinker's Belt" }) do
	keys[junk] = nil
end
local list = {}
for k in pairs(keys) do list[#list + 1] = k end
table.sort(list)
os.execute("mkdir docs\\locale 2>nul")
local out = assert(io.open("docs/locale/keys.txt", "wb"))
for _, k in ipairs(list) do out:write(("%q"):format(k):gsub("\\\n", "\\n"), "\n") end
out:close()
print(#list .. " texts")

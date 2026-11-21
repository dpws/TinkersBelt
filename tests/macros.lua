-- Offline test for the macro builder's text. Run: luajit tests/macros.lua
local ns = {}
assert(loadfile("Macros.lua"))("TinkersBelt", ns)
local passed = 0
local function check(name, got, want)
	if got ~= want then print("FAIL: " .. name .. "\n  got:  " .. tostring(got) .. "\n  want: " .. tostring(want)); os.exit(1) end
	passed = passed + 1
end

check("no conditions", ns.MacroConditions({}), "")
check("all conditions, fixed order", ns.MacroConditions({ unit = "mouseover", help = true, combat = false, stealth = true,
	dead = false, shift = true, alt = true, form = 0 }), "[@mouseover,help,nocombat,stealth,nodead,mod:shift,mod:alt,form:0]")
check("harm", ns.MacroConditions({ help = false }), "[harm]")

check("mouseover heal with fallback", ns.MacroText({ tooltip = true, lines = { { cmd = "cast", options = {
	{ unit = "mouseover", help = true, dead = false, spell = "Flash Heal" }, { spell = "Flash Heal" } } } } }),
	"#showtooltip\n/cast [@mouseover,help,nodead] Flash Heal; Flash Heal")
check("stop casting first, then attack", ns.MacroText({ stopcasting = true, lines = { { cmd = "cast", options = {
	{ stealth = true, spell = "Cheap Shot" }, { spell = "Sinister Strike" } } }, { cmd = "startattack" } } }),
	"/stopcasting\n/cast [stealth] Cheap Shot; Sinister Strike\n/startattack")
check("options without a spell are skipped", ns.MacroText({ lines = { { cmd = "cast", options = { { shift = true, spell = "" },
	{ spell = "Sap" } } } } }), "/cast Sap")
check("a line with no spell is dropped", ns.MacroText({ lines = { { cmd = "cast", options = { {} } }, { cmd = "stopattack" } } }),
	"/stopattack")
check("focus chains its conditions", ns.MacroText({ lines = { { cmd = "focus", options = { { unit = "mouseover", help = false },
	{ unit = "target" } } } } }), "/focus [@mouseover,harm][@target]")
check("use item", ns.MacroText({ lines = { { cmd = "use", options = { { spell = "Hearthstone" } } } } }), "/use Hearthstone")
check("raw text wins", ns.MacroText({ raw = "/say hi", lines = { { cmd = "startattack" } } }), "/say hi")

for _, t in ipairs(ns.MACRO_TEMPLATES) do
	local m = t.make("Sap")
	check("template " .. t.name .. " builds text", type(ns.MacroText(m)), "string")
end
check("template keeps your spell", ns.MacroText(ns.MACRO_TEMPLATES[3].make("Power Word: Shield")),
	"#showtooltip\n/cast [@player,mod:alt] Power Word: Shield; Power Word: Shield")

-- text -> blocks -> text
local function round(text) local m = ns.ParseMacro(text); return m and ns.MacroText(m) end
check("parse: builder text comes back the same", round("#showtooltip\n/cast [@mouseover,help,nodead] Flash Heal; Flash Heal"),
	"#showtooltip\n/cast [@mouseover,help,nodead] Flash Heal; Flash Heal")
check("parse: stopcasting, opener, attack", round("/stopcasting\n/cast [stealth] Cheap Shot; Sinister Strike\n/startattack"),
	"/stopcasting\n/cast [stealth] Cheap Shot; Sinister Strike\n/startattack")
check("parse: [a][b] X becomes two options", round("/cast [@mouseover,harm][] Sap"), "/cast [@mouseover,harm] Sap; Sap")
check("parse: target= and modifier: spellings", round("/cast [target=player,modifier:alt] Renew"), "/cast [@player,mod:alt] Renew")
check("parse: @target shown as the default target", round("/cast [@target,harm] Sap"), "/cast [harm] Sap")
check("parse: focus conditions", round("/focus [@mouseover,harm][@target]"), "/focus [@mouseover,harm][@target]")
check("parse: noform", round("/cast [noform] Bear Form"), "/cast [form:0] Bear Form")
check("parse: /say stays text", select(2, ns.ParseMacro("/say hi")), "/say lines")
check("parse: unknown condition stays text", select(2, ns.ParseMacro("/cast [exists] Sap")), "[exists]")
check("parse: /target by name stays text", select(2, ns.ParseMacro("/target Lava Craft")), "/target by name")
check("parse: #show stays text", select(2, ns.ParseMacro("#show Sap\n/cast Sap")), "a #show line")
check("parse: /startattack with conditions stays text", select(2, ns.ParseMacro("/startattack [harm]")), "/startattack with conditions")

local pick = "#showtooltip Удар в спину\n/cast Обшаривание карманов\n/cast Удар в спину"
check("parse: #showtooltip with a spell, Russian names", round(pick), pick)
check("parse: #showtooltip keeps its spell", ns.ParseMacro(pick).tooltip, "Удар в спину")

print("macros: " .. passed .. " passed")

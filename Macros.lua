local _, ns = ...
local Loc = ns.L or setmetatable({}, { __index = function(_, k) return k end }) -- translations (Locale.lua)

-- Macro builder: a macro is a model of lines (command blocks); each Cast/Use/Target line holds options
-- (first match wins), each option a spell/item, a unit and condition switches. MacroText turns it into
-- the macro text the game runs.

ns.MACRO_COMMANDS = {
	{ key = "cast", label = "Cast", slash = "/cast" },
	{ key = "use", label = "Use item", slash = "/use" },
	{ key = "target", label = "Target", slash = "/target", unitOnly = true },
	{ key = "focus", label = "Focus", slash = "/focus", unitOnly = true },
	{ key = "cancelaura", label = "Cancel buff", slash = "/cancelaura" },
	{ key = "startattack", label = "Start attack", slash = "/startattack", bare = true },
	{ key = "stopattack", label = "Stop attack", slash = "/stopattack", bare = true },
	{ key = "stopcasting", label = "Stop casting", slash = "/stopcasting", bare = true },
}
local CMD = {}
for _, c in ipairs(ns.MACRO_COMMANDS) do CMD[c.key] = c end

ns.MACRO_UNITS = { { nil, "Target" }, { "mouseover", "Mouseover" }, { "focus", "Focus" }, { "player", "Yourself" },
	{ "targettarget", "Target's target" }, { "pet", "Your pet" } }

-- tri-state switches: true = first word, false = second, nil = don't care
local PAIRS = { help = { "help", "harm" }, combat = { "combat", "nocombat" }, stealth = { "stealth", "nostealth" },
	dead = { "dead", "nodead" } }

-- "[@mouseover,help,nodead,mod:shift]" for an option, "" when it has no conditions
function ns.MacroConditions(o)
	local parts = {}
	if o.unit then parts[#parts + 1] = "@" .. o.unit end
	for _, key in ipairs({ "help", "combat", "stealth", "dead" }) do
		if o[key] ~= nil then parts[#parts + 1] = PAIRS[key][o[key] and 1 or 2] end
	end
	for _, mod in ipairs({ "shift", "ctrl", "alt" }) do
		if o[mod] then parts[#parts + 1] = "mod:" .. mod end
	end
	if o.form then parts[#parts + 1] = "form:" .. o.form end
	return #parts > 0 and ("[" .. table.concat(parts, ",") .. "]") or ""
end

-- one macro line, or nil when it would do nothing (no spell chosen yet)
function ns.MacroLine(line)
	local c = CMD[line.cmd]
	if not c then return nil end
	if c.bare then return c.slash end
	local parts = {}
	if c.unitOnly then
		for _, o in ipairs(line.options or {}) do
			local cond = ns.MacroConditions(o)
			if cond ~= "" then parts[#parts + 1] = cond end
		end
	else
		local opts = {}
		for _, o in ipairs(line.options or {}) do
			if o.spell and o.spell ~= "" then opts[#opts + 1] = o end
		end
		-- options in a row with the same spell share it: "[a][] Sap" instead of "[a] Sap; Sap" (shorter,
		-- and long spell names in some languages must still fit 255 bytes)
		local i = 1
		while i <= #opts do
			local conds, j = {}, i
			while j <= #opts and opts[j].spell == opts[i].spell do
				conds[#conds + 1] = ns.MacroConditions(opts[j])
				j = j + 1
			end
			if #conds == 1 then
				parts[#parts + 1] = (conds[1] ~= "" and (conds[1] .. " ") or "") .. opts[i].spell
			else
				for k, cond in ipairs(conds) do if cond == "" then conds[k] = "[]" end end
				parts[#parts + 1] = table.concat(conds) .. " " .. opts[i].spell
			end
			i = j
		end
	end
	if #parts == 0 then return nil end
	-- unit-only commands chain their conditions ([@mouseover,harm][@focus]); spells are "; "-separated
	return c.slash .. " " .. table.concat(parts, c.unitOnly and "" or "; ")
end

function ns.MacroText(m)
	if m.raw then return m.raw end
	local out = {}
	-- tooltip = true, or the spell to show ("#showtooltip Backstab")
	if m.tooltip then out[#out + 1] = type(m.tooltip) == "string" and ("#showtooltip " .. m.tooltip) or "#showtooltip" end
	if m.stopcasting then out[#out + 1] = "/stopcasting" end
	for _, line in ipairs(m.lines or {}) do
		local text = ns.MacroLine(line)
		if text then out[#out + 1] = text end
	end
	return table.concat(out, "\n")
end

-- Text -> blocks. Returns a model, or nil and the reason when the macro uses something the blocks can't show
-- (other commands, unknown conditions...): then it stays text. Equivalent, not identical: "[a][b] X" becomes
-- two options "[a] X; [b] X", so saving rewrites the text in the builder's own form.
local SLASH = { ["/cast"] = "cast", ["/use"] = "use", ["/target"] = "target", ["/tar"] = "target", ["/focus"] = "focus",
	["/cancelaura"] = "cancelaura", ["/startattack"] = "startattack", ["/stopattack"] = "stopattack",
	["/stopcasting"] = "stopcasting" }
local WORDS = {}
for key, pair in pairs(PAIRS) do WORDS[pair[1]] = { key, true }; WORDS[pair[2]] = { key, false } end

local function ParseConditions(text)
	local o = {}
	for token in text:gmatch("[^,]+") do
		token = strtrim and strtrim(token) or token:match("^%s*(.-)%s*$")
		local unit = token:match("^@(%w+)$") or token:match("^target=(%w+)$")
		local mod = token:match("^mod:(%a+)$") or token:match("^modifier:(%a+)$")
		local form = token:match("^form:(%d)$") or token:match("^stance:(%d)$")
		if unit then o.unit = unit ~= "target" and unit or nil; o.explicitTarget = unit == "target" or nil
		elseif mod and (mod == "shift" or mod == "ctrl" or mod == "alt") then o[mod] = true
		elseif form then o.form = tonumber(form)
		elseif token == "noform" or token == "nostance" then o.form = 0
		elseif WORDS[token] then o[WORDS[token][1]] = WORDS[token][2]
		else return nil, token end
	end
	return o
end

function ns.ParseMacro(text)
	local m = { lines = {} }
	for line in (text or ""):gmatch("[^\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line == "" then -- skip
		elseif line:sub(1, 12):lower() == "#showtooltip" and (#line == 12 or line:sub(13, 13):match("%s")) then
			local spell = line:sub(13):match("^%s*(.-)$")
			m.tooltip = spell ~= "" and spell or true
		elseif line:sub(1, 1) == "#" then return nil, "a " .. line:match("^(#%S+)") .. " line"
		else
			local slash, rest = line:match("^(/%S+)%s*(.-)$")
			local cmd = slash and SLASH[slash:lower()]
			if not cmd then return nil, (slash or line) .. " lines" end
			if CMD[cmd].bare then
				if rest ~= "" then return nil, slash .. " with conditions" end
				if cmd == "stopcasting" and #m.lines == 0 and not m.stopcasting then m.stopcasting = true
				else m.lines[#m.lines + 1] = { cmd = cmd } end
			else
				local options = {}
				if CMD[cmd].unitOnly then
					-- only conditions: /target [@mouseover,harm][@focus]
					if rest == "" or rest:gsub("%b[]", ""):match("%S") then return nil, slash .. " by name" end
					for group in rest:gmatch("%[(.-)%]") do
						local o, bad = ParseConditions(group)
						if not o then return nil, "[" .. bad .. "]" end
						if o.explicitTarget then o.unit = "target" end
						o.explicitTarget = nil
						options[#options + 1] = o
					end
				else
					for clause in rest:gmatch("[^;]+") do
						local conds, spell = clause:match("^%s*(.-)%s*([^%]]-)%s*$")
						if not spell or spell == "" then return nil, "an empty clause" end
						local groups = {}
						for group in conds:gmatch("%[(.-)%]") do groups[#groups + 1] = group end
						if conds:gsub("%b[]", ""):match("%S") then return nil, "text before a spell" end
						if #groups == 0 then groups = { "" } end
						for _, group in ipairs(groups) do
							local o, bad = ParseConditions(group)
							if not o then return nil, "[" .. bad .. "]" end
							-- @target is the default target: the blocks show it as "Target"
							o.explicitTarget = nil
							o.spell = spell
							options[#options + 1] = o
						end
					end
				end
				m.lines[#m.lines + 1] = { cmd = cmd, options = options }
			end
		end
	end
	return m
end

-- starting points; s = the spell already in the editor (kept), may be ""
ns.MACRO_TEMPLATES = {
	{ name = "Mouseover friend, else target", make = function(s)
		return { tooltip = true, lines = { { cmd = "cast", options = {
			{ unit = "mouseover", help = true, dead = false, spell = s }, { spell = s } } } } }
	end },
	{ name = "Mouseover enemy, else target", make = function(s)
		return { tooltip = true, lines = { { cmd = "cast", options = {
			{ unit = "mouseover", help = false, dead = false, spell = s }, { spell = s } } } } }
	end },
	{ name = "Alt: cast on yourself", make = function(s)
		return { tooltip = true, lines = { { cmd = "cast", options = { { alt = true, unit = "player", spell = s }, { spell = s } } } } }
	end },
	{ name = "Shift: a second spell", make = function(s)
		return { tooltip = true, lines = { { cmd = "cast", options = { { shift = true, spell = "" }, { spell = s } } } } }
	end },
	{ name = "Stealth opener, then attack", make = function(s)
		return { tooltip = true, lines = { { cmd = "cast", options = { { stealth = true, spell = s }, { spell = "" } } },
			{ cmd = "startattack" } } }
	end },
	{ name = "Focus: mouseover enemy", make = function()
		return { lines = { { cmd = "focus", options = { { unit = "mouseover", help = false, dead = false } } } } }
	end },
}

-- Curated macros per class. Spells by rank-1 ID: N(id) gives the name in the player's language, so the
-- macros work on any client. name = macro name (16 letters max), desc = what it does.
local function cast(...)
	local options = {}
	for _, o in ipairs({ ... }) do options[#options + 1] = o end
	return { cmd = "cast", options = options }
end
-- Rogue set judged against Forever and Classic guides (RankedBoost Forever, Skill Capped Forever, Classic wikis).
local MO = function(spell) return { unit = "mouseover", help = false, dead = false, spell = spell } end
ns.MACRO_LIBRARY = {
	ROGUE = {
		{ name = "Opener", desc = "Stealth: Cheap Shot. Otherwise Sinister Strike. Starts auto attack.", make = function(N)
			return { tooltip = true, lines = { cast({ stealth = true, spell = N(1833) }, { spell = N(1752) }), { cmd = "startattack" } } }
		end },
		{ name = "Dagger Opener", desc = "Stealth: Ambush, Ctrl: Garrote. Otherwise Backstab. Starts auto attack.", make = function(N)
			return { tooltip = true, lines = { cast({ stealth = true, ctrl = true, spell = N(703) }, { stealth = true, spell = N(8676) },
				{ spell = N(53) }), { cmd = "startattack" } } }
		end },
		{ name = "Pick + Cheap", desc = "Pick Pocket, then Cheap Shot. Stand still when you press it.", make = function(N)
			return { tooltip = N(1833), lines = { cast({ spell = N(921) }), cast({ spell = N(1833) }) } }
		end },
		{ name = "Pick + Ambush", desc = "Pick Pocket, then Ambush (dagger). Stand still when you press it.", make = function(N)
			return { tooltip = N(8676), lines = { cast({ spell = N(921) }), cast({ spell = N(8676) }) } }
		end },
		{ name = "Pick + Sap", desc = "Pick Pocket, then Sap: loot a mob and leave it asleep.", make = function(N)
			return { tooltip = N(6770), lines = { cast({ spell = N(921) }), cast({ spell = N(6770) }) } }
		end },
		{ name = "Sap / Blind", desc = "Stealth: Sap. Otherwise Blind. Mouseover enemy first, else your target.", make = function(N)
			local sap, blind = MO(N(6770)), MO(N(2094))
			sap.stealth = true
			return { tooltip = true, lines = { cast(sap, { stealth = true, spell = N(6770) }, blind, { spell = N(2094) }) } }
		end },
		{ name = "Stealth", desc = "In combat: Vanish. Otherwise Stealth, which a second press can't cancel.", make = function(N)
			return { tooltip = true, lines = { cast({ combat = true, spell = N(1856) }, { stealth = false, spell = N(1784) }) } }
		end },
		{ name = "Escape", desc = "Stop attacking, Vanish, then Sprint away.", make = function(N)
			return { tooltip = N(1856), lines = { { cmd = "stopattack" }, cast({ spell = N(1856) }), cast({ spell = N(2983) }) } }
		end },
		{ name = "Kick", desc = "Kicks your focus if it's an enemy, else your target. Ctrl: always your target.", make = function(N)
			return { tooltip = true, lines = { cast({ ctrl = true, spell = N(1766) }, { unit = "focus", help = false, dead = false,
				spell = N(1766) }, { spell = N(1766) }) } }
		end },
		{ name = "Feint / Evasion", desc = "Feint to drop threat. Ctrl: Evasion.", make = function(N)
			return { tooltip = true, lines = { cast({ ctrl = true, spell = N(5277) }, { spell = N(1966) }) } }
		end },
		{ name = "Finisher", desc = "Eviscerate. Ctrl: Slice and Dice.", make = function(N)
			return { tooltip = true, lines = { cast({ ctrl = true, spell = N(5171) }, { spell = N(2098) }) } }
		end },
		{ name = "Kidney / Gouge", desc = "Kidney Shot. Ctrl: Gouge.", make = function(N)
			return { tooltip = true, lines = { cast({ ctrl = true, spell = N(1776) }, { spell = N(408) }) } }
		end },
		{ name = "Premed Opener", desc = "Premeditation, then Cheap Shot (needs the talent).", make = function(N)
			return { tooltip = N(14183), lines = { cast({ spell = N(14183) }), cast({ spell = N(1833) }) } }
		end },
	},
}

-- shared shapes for the other classes (spell ids, resolved through N when picked)
local function Help(id) -- Alt: yourself; else mouseover friend; else target
	return function(N)
		local sp = N(id)
		return { tooltip = true, lines = { cast({ alt = true, unit = "player", spell = sp },
			{ unit = "mouseover", help = true, dead = false, spell = sp }, { spell = sp }) } }
	end
end
local function Harm(id, unit) -- mouseover (or focus) enemy, else target
	return function(N)
		local sp = N(id)
		return { tooltip = true, lines = { cast({ unit = unit or "mouseover", help = false, dead = false, spell = sp }, { spell = sp }) } }
	end
end
local function Pair(first, second) -- one press: first, then second (talent + spell)
	return function(N)
		return { tooltip = N(second), lines = { cast({ spell = N(first) }), cast({ spell = N(second) }) } }
	end
end
local function E(name, desc, make) return { name = name, desc = desc, make = make } end

local L = ns.MACRO_LIBRARY
L.WARRIOR = {
	E("Charge", "Battle Stance: Charge. Berserker Stance: Intercept. Otherwise Battle Stance.", function(N)
		return { tooltip = true, lines = { cast({ form = 1, spell = N(100) }, { form = 3, spell = N(20252) }, { spell = N(2457) }) } }
	end),
	E("Overpower", "Overpower, switching to Battle Stance first if needed.", function(N)
		return { tooltip = true, lines = { cast({ form = 1, spell = N(7384) }, { spell = N(2457) }) } }
	end),
	E("Interrupt", "Berserker Stance: Pummel. Otherwise Shield Bash.", function(N)
		return { tooltip = true, lines = { cast({ form = 3, spell = N(6552) }, { spell = N(72) }) } }
	end),
	E("Taunt", "Taunt, switching to Defensive Stance first if needed.", function(N)
		return { tooltip = true, lines = { cast({ form = 2, spell = N(355) }, { spell = N(71) }) } }
	end),
	E("Execute", "Execute, leaving Defensive Stance for Battle Stance if needed.", function(N)
		return { tooltip = true, lines = { cast({ form = 2, spell = N(2457) }, { spell = N(5308) }) } }
	end),
	E("Strike", "Heroic Strike. Shift: Cleave.", function(N)
		return { tooltip = true, lines = { cast({ shift = true, spell = N(845) }, { spell = N(78) }) } }
	end),
}
L.MAGE = {
	E("Polymorph", "Mouseover enemy, else target.", Harm(118)),
	E("Counterspell", "Stops your cast. Counterspells your focus if it's an enemy, else your target.", function(N)
		local m = Harm(2139, "focus")(N); m.stopcasting = true; return m
	end),
	E("Intellect", "Arcane Intellect. Alt: yourself, else mouseover friend, else target.", Help(1459)),
	E("Remove Curse", "Remove Lesser Curse. Alt: yourself, else mouseover friend, else target.", Help(475)),
	E("Blink", "Stops your cast, then Blinks.", function(N) return { tooltip = true, stopcasting = true, lines = { cast({ spell = N(1953) }) } } end),
	E("PoM Pyro", "Presence of Mind, then Pyroblast (needs both talents).", Pair(12043, 11366)),
}
L.PRIEST = {
	E("Shield", "Power Word: Shield. Alt: yourself, else mouseover friend, else target.", Help(17)),
	E("Flash Heal", "Alt: yourself, else mouseover friend, else target.", Help(2061)),
	E("Renew", "Alt: yourself, else mouseover friend, else target.", Help(139)),
	E("Dispel", "Dispel Magic. Alt: yourself, else mouseover (friend or enemy), else target.", function(N)
		local sp = N(527)
		return { tooltip = true, lines = { cast({ alt = true, unit = "player", spell = sp }, { unit = "mouseover", dead = false, spell = sp }, { spell = sp }) } }
	end),
	E("Fortitude", "Power Word: Fortitude. Alt: yourself, else mouseover friend, else target.", Help(1243)),
	E("Inner Focus", "Inner Focus, then Greater Heal (needs the talent).", Pair(14751, 2060)),
	E("Shackle", "Shackle Undead: mouseover enemy, else target.", Harm(9484)),
}
L.DRUID = {
	E("Rejuvenation", "Alt: yourself, else mouseover friend, else target.", Help(774)),
	E("Healing Touch", "Alt: yourself, else mouseover friend, else target.", Help(5185)),
	E("Innervate", "Alt: yourself, else mouseover friend, else target.", Help(29166)),
	E("Remove Curse", "Alt: yourself, else mouseover friend, else target.", Help(2782)),
	E("Abolish Poison", "Alt: yourself, else mouseover friend, else target.", Help(2893)),
	E("Roots", "Entangling Roots: mouseover enemy, else target.", Harm(339)),
	E("Hibernate", "Mouseover enemy, else target.", Harm(2637)),
	E("NS Heal", "Nature's Swiftness, then Healing Touch (needs the talent).", Pair(17116, 5185)),
	E("Cat Opener", "Prowling: Ravage (Ctrl: Pounce). Otherwise Shred.", function(N)
		return { tooltip = true, lines = { cast({ stealth = true, ctrl = true, spell = N(9005) }, { stealth = true, spell = N(6785) }, { spell = N(5221) }) } }
	end),
}
L.HUNTER = {
	E("Feign Trap", "In combat: Feign Death. Out of combat (after feigning): Freezing Trap.", function(N)
		return { tooltip = true, lines = { cast({ combat = true, spell = N(5384) }, { spell = N(1499) }) } }
	end),
	E("Pet Heal", "Dead pet: Revive Pet. Otherwise Mend Pet.", function(N)
		return { tooltip = true, lines = { cast({ unit = "pet", dead = true, spell = N(982) }, { spell = N(136) }) } }
	end),
	E("Melee", "Mongoose Bite when it's up, then Raptor Strike.", function(N)
		return { tooltip = N(2973), lines = { cast({ spell = N(1495) }), cast({ spell = N(2973) }) } }
	end),
	E("Aspects", "Aspect of the Hawk. Shift: Cheetah. Ctrl: Monkey.", function(N)
		return { tooltip = true, lines = { cast({ shift = true, spell = N(5118) }, { ctrl = true, spell = N(13163) }, { spell = N(13165) }) } }
	end),
	E("Hunters Mark", "Mouseover enemy, else target.", Harm(1130)),
	E("Tranq Shot", "Tranquilizing Shot: mouseover enemy, else target.", Harm(19801)),
}
L.WARLOCK = {
	E("Fear", "Mouseover enemy, else target.", Harm(5782)),
	E("Banish", "Mouseover enemy, else target.", Harm(710)),
	E("Corruption", "Mouseover enemy, else target (dot several mobs).", Harm(172)),
	E("Agony", "Curse of Agony: mouseover enemy, else target.", Harm(980)),
	E("Spell Lock", "Felhunter Spell Lock on your focus if it's an enemy, else your target.", Harm(19244, "focus")),
	E("Seduction", "Succubus Seduction: mouseover enemy, else target.", Harm(6358)),
	E("Fel Felhunter", "Fel Domination, then Summon Felhunter (needs the talent).", Pair(18708, 691)),
}
L.PALADIN = {
	E("Flash of Light", "Alt: yourself, else mouseover friend, else target.", Help(19750)),
	E("Holy Light", "Alt: yourself, else mouseover friend, else target.", Help(635)),
	E("Cleanse", "Alt: yourself, else mouseover friend, else target.", Help(4987)),
	E("Protection", "Blessing of Protection. Alt: yourself, else mouseover friend, else target.", Help(1022)),
	E("Freedom", "Blessing of Freedom. Alt: yourself, else mouseover friend, else target.", Help(1044)),
	E("Hammer", "Hammer of Justice: mouseover enemy, else target.", Harm(853)),
	E("DF Holy Light", "Divine Favor, then Holy Light (needs the talent).", Pair(20216, 635)),
	E("Judge + Seal", "Judgement, then Seal of Righteousness again.", Pair(20271, 20154)),
}
L.SHAMAN = {
	E("Healing Wave", "Alt: yourself, else mouseover friend, else target.", Help(331)),
	E("Lesser Wave", "Lesser Healing Wave. Alt: yourself, else mouseover friend, else target.", Help(8004)),
	E("Chain Heal", "Alt: yourself, else mouseover friend, else target.", Help(1064)),
	E("Cure Poison", "Alt: yourself, else mouseover friend, else target.", Help(526)),
	E("Interrupt", "Earth Shock on your focus if it's an enemy, else your target.", Harm(8042, "focus")),
	E("Purge", "Mouseover enemy, else target.", Harm(370)),
	E("NS Heal", "Nature's Swiftness, then Healing Wave (needs the talent).", Pair(16188, 331)),
	E("EM Chain", "Elemental Mastery, then Chain Lightning (needs the talent).", Pair(16166, 421)),
}

if not CreateFrame then return end -- offline test stops here

ns.slashCommands = ns.slashCommands or {}
-- /tb macros check: library spell ids this client doesn't know
ns.slashCommands["macros check"] = function()
	ns.Diagnose(function(Say)
		local missing, total = {}, 0
		for class, list in pairs(ns.MACRO_LIBRARY) do
			for _, e in ipairs(list) do
				e.make(function(id)
					total = total + 1
					local name = C_Spell.GetSpellName(id)
					if not name then missing[#missing + 1] = (Loc["%s / %s: spell %d unknown"]):format(class, e.name, id) end
					return name or ("spell " .. id)
				end)
			end
		end
		Say(("macros: %d spell uses checked, %d unknown"):format(total, #missing))
		for _, line in ipairs(missing) do Say("macros: " .. line) end
	end)
end

local T = ns.Theme
local MAX_ACCOUNT = MAX_ACCOUNT_MACROS or 120
local MAX_CHAR = MAX_CHARACTER_MACROS or 18
local QUESTION = 134400 -- with #showtooltip the game shows the spell's own icon

local function Copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = Copy(v) end
	return c
end
local function Models() ns.adb.macroModels = ns.adb.macroModels or {} return ns.adb.macroModels end
local function Key(scope, name)
	return scope == "char" and ("c:" .. (GetUnitName("player", true) or "?") .. ":" .. name) or ("a:" .. name)
end
-- fill colour of a T.Box frame (rounded in Modern, backdrop in Classic)
local function Fill(frame, c)
	if frame.SetBackdropColor then frame:SetBackdropColor(unpack(c)) elseif frame.dpwsFill then frame.dpwsFill:SetColor(c) end
end
local function SpellIcon(cmd, text)
	if not text or text == "" then return QUESTION end
	if cmd == "use" then
		return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(text)) or QUESTION
	end
	return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(text)) or QUESTION
end

-- your spellbook by tab: { { name, spells = { { name, icon } } } }; castable spells only, one entry per name (ranks)
local function SpellBook()
	local tabs = {}
	local function Add(tab, name, icon, seen)
		if name and not seen[name] then seen[name] = true; tab.spells[#tab.spells + 1] = { name = name, icon = icon } end
	end
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
		local bank = Enum.SpellBookSpellBank.Player
		for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
			local tab, seen = { name = line and line.name or ("Tab " .. i), spells = {} }, {}
			for k = (line.itemIndexOffset or 0) + 1, (line.itemIndexOffset or 0) + (line.numSpellBookItems or 0) do
				local info = C_SpellBook.GetSpellBookItemInfo(k, bank)
				if info and not info.isPassive and info.itemType == Enum.SpellBookItemType.Spell then Add(tab, info.name, info.iconID, seen) end
			end
			if #tab.spells > 0 then tabs[#tabs + 1] = tab end
		end
	elseif GetNumSpellTabs then
		for i = 1, GetNumSpellTabs() do
			local tabName, _, offset, num = GetSpellTabInfo(i)
			local tab, seen = { name = tabName, spells = {} }, {}
			for k = offset + 1, offset + num do
				if not IsPassiveSpell(k, "spell") then Add(tab, GetSpellBookItemName(k, "spell"), GetSpellBookItemTexture(k, "spell"), seen) end
			end
			if #tab.spells > 0 then tabs[#tabs + 1] = tab end
		end
	end
	return tabs
end

-- usable items in your bags (ones with a "Use:" effect), one entry each
local function BagItems()
	local items, seen = {}, {}
	if not (C_Container and C_Container.GetContainerNumSlots) then return items end
	for bag = 0, 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not seen[id] and C_Item.GetItemSpell(id) then
				seen[id] = true
				items[#items + 1] = { name = C_Item.GetItemNameByID(id) or info.itemName, icon = info.iconFileID }
			end
		end
	end
	table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
	return items
end

local function Chip(parent, text, w)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, 20)
	T.Box(b, T.control, T.border, 9)
	b.text = T.Text(b, "medium", 11, T.muted)
	b.text:SetPoint("CENTER")
	b.text:SetJustifyH("CENTER")
	b.text:SetText(text)
	b:SetWidth(math.max(w, math.ceil(b.text:GetStringWidth()) + 14)) -- fits longer translations
	function b:SetOn(on)
		Fill(self, on and T.Accent(0.35) or T.control)
		self.text:SetTextColor(unpack(on and T.gold or T.muted))
	end
	b:SetOn(false)
	return b
end

-- condition switches: key + val (val nil = plain on/off flag)
local CHIP_ROWS = {
	{ { "Friend", "help", true, 54 }, { "Enemy", "help", false, 54 }, { "Shift", "shift", nil, 46 }, { "Ctrl", "ctrl", nil, 40 },
		{ "Alt", "alt", nil, 36 }, { "In combat", "combat", true, 70 }, { "No combat", "combat", false, 76 } },
	{ { "Stealth", "stealth", true, 58 }, { "No stealth", "stealth", false, 74 }, { "Dead", "dead", true, 44 },
		{ "Alive", "dead", false, 46 } },
}
local CHIP_TIPS = {
	Friend = "[help]: only if that unit is friendly", Enemy = "[harm]: only if that unit is an enemy",
	Shift = "[mod:shift]: only while Shift is held", Ctrl = "[mod:ctrl]: only while Ctrl is held",
	Alt = "[mod:alt]: only while Alt is held", ["In combat"] = "[combat]: only in combat",
	["No combat"] = "[nocombat]: only out of combat", Stealth = "[stealth]: only while stealthed or prowling",
	["No stealth"] = "[nostealth]: only while not stealthed", Dead = "[dead]: only if that unit is dead",
	Alive = "[nodead]: only if that unit is alive",
}
local function ChipOn(o, spec)
	if spec[3] == nil then return o[spec[2]] == true end
	return o[spec[2]] == spec[3]
end
local FORMS = { { nil, "Any form" }, { 0, "No form" }, { 1, "Form 1" }, { 2, "Form 2" }, { 3, "Form 3" }, { 4, "Form 4" } }

local OPT_H, HEAD_H, ADD_H, EDIT_W = 86, 34, 28, 490

function ns.BuildMacrosPage(page)
	local W = page:GetWidth() > 0 and page:GetWidth() or 696
	local cur = { tab = "account", scope = "account", model = { tooltip = true, lines = {} } }
	local Relayout, UpdatePreview, RefreshList, Open, NewMacro, Say
	local focusedInput -- the spell box Shift-click should fill

	-----------------------------------------------------------------------
	-- left: your macros
	local list = CreateFrame("Frame", nil, page)
	list:SetPoint("TOPLEFT")
	list:SetWidth(180)
	local tabA, tabC = Chip(list, Loc["General"], 86), Chip(list, Loc["Character"], 86)
	tabA:SetPoint("TOPLEFT", 0, 0)
	tabC:SetPoint("LEFT", tabA, "RIGHT", 8, 0)
	tabA:SetScript("OnClick", function() cur.tab = "account"; RefreshList() end)
	tabC:SetScript("OnClick", function() cur.tab = "char"; RefreshList() end)
	local newBtn = T.NewButton(list, Loc["+ New macro"], 180, 24, "accent")
	newBtn:SetPoint("TOPLEFT", 0, -28)
	newBtn:SetScript("OnClick", function() NewMacro() end)
	local count = T.Text(list, "regular", 11, T.muted)
	count:SetPoint("TOPLEFT", 2, -58)
	local rows = {}
	local function Row(i)
		if rows[i] then return rows[i] end
		local r = CreateFrame("Button", nil, list)
		r:SetSize(180, 24)
		r:SetPoint("TOPLEFT", 0, -74 - (i - 1) * 26)
		r.bg = T.Rounded(r, T.row, 4, "BACKGROUND", 0)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18)
		r.icon:SetPoint("LEFT", 4, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.name = T.Text(r, "medium", 12)
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.name:SetPoint("RIGHT", -4, 0)
		r.name:SetWordWrap(false)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.06)
		rows[i] = r
		return r
	end
	RefreshList = function()
		tabA:SetOn(cur.tab == "account")
		tabC:SetOn(cur.tab == "char")
		local numA, numC = GetNumMacros()
		local first, n, max = cur.tab == "account" and 1 or MAX_ACCOUNT + 1, cur.tab == "account" and numA or numC,
			cur.tab == "account" and MAX_ACCOUNT or MAX_CHAR
		count:SetText((Loc["%d / %d macros"]):format(n, max))
		for i = 1, math.max(n, #rows) do
			local r = Row(i)
			if i <= n then
				local index = first + i - 1
				local name, icon = GetMacroInfo(index)
				r.icon:SetTexture(icon or QUESTION)
				r.name:SetText(name or "?")
				r.bg:SetColor(cur.index == index and T.Accent(0.25) or T.row)
				r:SetScript("OnClick", function() Open(index) end)
				r:Show()
			else
				r:Hide()
			end
		end
		list:SetHeight(74 + n * 26)
		Relayout()
	end

	-----------------------------------------------------------------------
	-- right: the editor
	local ed = CreateFrame("Frame", nil, page)
	ed:SetPoint("TOPLEFT", W - EDIT_W, 0)
	ed:SetWidth(EDIT_W)

	local nameBox = T.NewInput(ed, 140)
	nameBox:SetPoint("TOPLEFT", 0, 0)
	nameBox:SetMaxLetters(16)
	local nameHint = T.Text(ed, "regular", 11, T.muted)
	nameHint:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", 2, 3)
	nameHint:SetText(Loc["Name"])
	local scopeA, scopeC = Chip(ed, Loc["Account"], 70), Chip(ed, Loc["Character"], 80)
	scopeA:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
	T.Tip(scopeA, Loc["Account macro"], Loc["Shared by all your characters"])
	T.Tip(scopeC, Loc["Character macro"], Loc["Only this character"])
	scopeC:SetPoint("LEFT", scopeA, "RIGHT", 6, 0)
	local scopeLabel = T.Text(ed, "regular", 12, T.muted)
	scopeLabel:SetPoint("LEFT", nameBox, "RIGHT", 12, 0)
	scopeA:SetScript("OnClick", function() cur.scope = "account"; Relayout() end)
	scopeC:SetScript("OnClick", function() cur.scope = "char"; Relayout() end)

	local tmpl = T.NewDropdown(ed, 210)
	tmpl:SetPoint("TOPLEFT", 0, -34)
	tmpl:SetDefaultText(Loc["Start from a template..."])
	tmpl:SetupMenu(function(_, root)
		for _, t in ipairs(ns.MACRO_TEMPLATES) do
			root:CreateButton(Loc[t.name], function()
				local first = cur.model.lines and cur.model.lines[1]
				local s = first and first.options and first.options[#first.options] and first.options[#first.options].spell or ""
				cur.model = t.make(s or "")
				Relayout()
			end)
		end
	end)
	local library = ns.MACRO_LIBRARY[select(2, UnitClass("player"))]
	local lib = T.NewDropdown(ed, 140)
	lib:SetPoint("TOPRIGHT", 0, 0)
	lib:SetDefaultText(Loc["Class macros..."])
	lib:SetShown(library ~= nil)
	lib:SetupMenu(function(_, root)
		local function N(id) return C_Spell.GetSpellName(id) or ("spell " .. id) end
		for _, entry in ipairs(library or {}) do
			local b = root:CreateButton(entry.name, function()
				-- a new macro: nothing you have is changed until you Save
				cur.index = nil
				cur.scope = cur.tab
				cur.model = entry.make(N)
				nameBox:SetText(entry.name)
				Say(Loc[entry.desc])
				RefreshList()
			end)
			if b.SetTooltip then b:SetTooltip(function(tip) GameTooltip_SetTitle(tip, entry.name); GameTooltip_AddNormalLine(tip, Loc[entry.desc]) end) end
		end
	end)
	local tipChip, stopChip = Chip(ed, Loc["Spell tooltip"], 88), Chip(ed, Loc["Stop casting first"], 116)
	tipChip:SetPoint("LEFT", tmpl, "RIGHT", 10, 0)
	T.Tip(tipChip, Loc["Spell tooltip"], Loc["#showtooltip: the button shows the spell's icon and tooltip"])
	T.Tip(stopChip, Loc["Stop casting first"], Loc["/stopcasting first: interrupts what you're casting"])
	stopChip:SetPoint("LEFT", tipChip, "RIGHT", 6, 0)
	tipChip:SetScript("OnClick", function() cur.model.tooltip = not cur.model.tooltip or nil; Relayout() end)
	-- which spell the tooltip and icon show: automatic (the one that would cast), a spell of this macro, or any
	local tipLabel = T.Text(ed, "regular", 12, T.muted)
	tipLabel:SetText(Loc["Tooltip shows"])
	local tipPick = T.NewDropdown(ed, 240)
	tipPick:SetPoint("LEFT", tipLabel, "RIGHT", 10, 0)
	tipPick:SetupMenu(function(_, root)
		local m = cur.model
		local function Set(v) return function() m.tooltip = v; UpdatePreview() end end
		root:CreateRadio(Loc["Automatic (the spell it casts)"], function() return m.tooltip == true end, Set(true))
		local seen = {}
		for _, line in ipairs(m.lines or {}) do
			for _, o in ipairs(line.options or {}) do
				local name = o.spell
				if name and name ~= "" and not seen[name] then
					seen[name] = true
					root:CreateRadio(("|T%s:16|t %s"):format(SpellIcon(line.cmd, name), name),
						function() return m.tooltip == name end, Set(name))
				end
			end
		end
		-- a spell chosen from the spellbook that the macro doesn't cast: listed here too, so it shows as selected
		if type(m.tooltip) == "string" and not seen[m.tooltip] then
			root:CreateRadio(("|T%s:16|t %s"):format(SpellIcon("cast", m.tooltip), m.tooltip), function() return true end, Set(m.tooltip))
		end
		-- plain buttons, not radios: only one entry above may count as selected (else the name shows twice)
		local book = root:CreateButton(Loc["From your spellbook"])
		for _, tab in ipairs(SpellBook()) do
			local sub = book:CreateButton(tab.name)
			for _, sp in ipairs(tab.spells) do
				sub:CreateButton(("|T%s:16|t %s"):format(sp.icon or QUESTION, sp.name), function()
					m.tooltip = sp.name
					UpdatePreview()
					tipPick:GenerateMenu()
				end)
			end
		end
	end)
	stopChip:SetScript("OnClick", function() cur.model.stopcasting = not cur.model.stopcasting or nil; Relayout() end)

	-- line cards (pooled)
	local cards = {}
	local function OptBlock(card, j)
		card.opts = card.opts or {}
		if card.opts[j] then return card.opts[j] end
		local b = CreateFrame("Frame", nil, card)
		b:SetSize(EDIT_W - 20, OPT_H)
		b.num = T.Text(b, "semibold", 12, T.gold)
		b.num:SetPoint("TOPLEFT", 0, -6)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(22, 22)
		b.icon:SetPoint("TOPLEFT", 18, -2)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.input = T.NewInput(b, 150)
		b.input:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
		b.pick = T.NewDropdown(b, 28) -- "v": pick from your spellbook / bags
		b.pick:SetPoint("LEFT", b.input, "RIGHT", 2, 0)
		if b.pick.Text then b.pick.Text:SetText("") end
		b.on = T.Text(b, "regular", 11, T.muted)
		b.on:SetText(Loc["on"])
		b.unit = T.NewDropdown(b, 130)
		b.rm = T.NewButton(b, "x", 24, 22)
		b.rm:SetPoint("TOPRIGHT", 0, -2)
		b.chips = {}
		-- switches flow left to right and wrap, so longer translations take more rows instead of overlapping
		local x, row = 18, 0
		local function Place(frame, w)
			if x > 18 and x + w > EDIT_W - 20 then x, row = 18, row + 1 end
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", x, -32 - row * 26)
			x = x + w + 4
		end
		for _, specs in ipairs(CHIP_ROWS) do
			for _, spec in ipairs(specs) do
				local c = Chip(b, Loc[spec[1]], spec[4])
				c.spec = spec
				T.Tip(c, Loc[spec[1]], Loc[CHIP_TIPS[spec[1]]] .. Loc[". Click again to turn it off."])
				Place(c, c:GetWidth())
				b.chips[#b.chips + 1] = c
			end
		end
		b.form = T.NewDropdown(b, 110)
		Place(b.form, 110)
		b.height = 32 + (row + 1) * 26 + 2
		b:SetHeight(b.height)
		T.Tip(b.form, Loc["Form / stance"], Loc["[form:N]: only in that form or stance (1 = first on your stance bar)"])
		T.Tip(b.pick, Loc["Pick a spell"], Loc["From your spellbook (Use item lines: from your bags)"])
		T.Tip(b.unit, Loc["Cast on"], Loc["Who this option casts on"])
		T.Tip(b.rm, Loc["Remove this option"])
		-- drag a spell or item from the spellbook / bags into the box
		b.input:SetScript("OnReceiveDrag", function(self)
			local kind, a, _, d = GetCursorInfo()
			local name
			if kind == "spell" then name = C_Spell.GetSpellName(d or a)
			elseif kind == "item" then name = C_Item.GetItemNameByID(a) end
			if name then self:SetText(name); ClearCursor() end
		end)
		b.input:HookScript("OnEditFocusGained", function(self) focusedInput = self end)
		card.opts[j] = b
		return b
	end
	-- Shift-click a spell or item while a spell box has focus: its name goes in
	local function InsertLink(link)
		if focusedInput and focusedInput:HasFocus() and link then
			local name = link:match("%[(.-)%]")
			if name then focusedInput:SetText(name) end
		end
	end
	if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink) end

	local function Card(i)
		if cards[i] then return cards[i] end
		local c = CreateFrame("Frame", nil, ed)
		c:SetWidth(EDIT_W)
		T.Box(c, T.card, T.border, 8)
		c.cmd = T.NewDropdown(c, 140)
		c.cmd:SetPoint("TOPLEFT", 10, -6)
		c.label = T.Text(c, "semibold", 11, T.gold)
		c.label:SetPoint("LEFT", c.cmd, "RIGHT", 10, 0)
		c.del = T.NewButton(c, "x", 24, 22)
		c.del:SetPoint("TOPRIGHT", -8, -7)
		c.down = T.NewButton(c, "v", 24, 22)
		c.down:SetPoint("RIGHT", c.del, "LEFT", -4, 0)
		c.up = T.NewButton(c, "^", 24, 22)
		c.up:SetPoint("RIGHT", c.down, "LEFT", -4, 0)
		c.add = T.NewButton(c, Loc["+ or"], 60, 22)
		T.Tip(c.cmd, Loc["Command"], Loc["What this line does"])
		T.Tip(c.up, Loc["Move line up"])
		T.Tip(c.down, Loc["Move line down"])
		T.Tip(c.del, Loc["Delete this line"])
		T.Tip(c.add, Loc["Add a fallback"], Loc["Another option, used when the ones above don't match"])
		cards[i] = c
		return c
	end

	local addLine = T.NewButton(ed, Loc["+ Add line"], 110, 24)
	addLine:SetScript("OnClick", function()
		table.insert(cur.model.lines, { cmd = "cast", options = { {} } })
		Relayout()
	end)

	-- preview / raw text
	local box = CreateFrame("Frame", nil, ed)
	box:SetWidth(EDIT_W)
	T.Box(box, T.field, T.border, 6)
	local preview = T.Text(box, "regular", 12, T.text)
	preview:SetPoint("TOPLEFT", 10, -10)
	preview:SetWidth(EDIT_W - 20)
	preview:SetWordWrap(true)
	local raw = CreateFrame("EditBox", nil, box)
	raw:SetMultiLine(true)
	raw:SetAutoFocus(false)
	raw:SetFont(T.font.regular, 12, "")
	raw:SetTextColor(unpack(T.text))
	raw:SetPoint("TOPLEFT", 10, -10)
	raw:SetWidth(EDIT_W - 20)
	raw:SetMaxLetters(255)
	raw:SetScript("OnEscapePressed", raw.ClearFocus)
	raw:SetScript("OnTextChanged", function(self, user)
		if user then cur.model.raw = self:GetText(); UpdatePreview() end
	end)
	local chars = T.Text(ed, "regular", 11, T.muted)
	chars:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -2, 3)
	local mode = T.NewButton(ed, Loc["Edit as text"], 110, 24)
	mode:SetScript("OnClick", function()
		if cur.model.raw then
			local parsed, why = ns.ParseMacro(cur.model.raw)
			if not parsed then return Say("|cffff6060Can't turn this into blocks: " .. why .. ".|r") end
			cur.model = parsed
			if #cur.model.lines == 0 then cur.model.lines = { { cmd = "cast", options = { {} } } } end
			Say("")
		else
			cur.model.raw = ns.MacroText(cur.model)
		end
		Relayout()
	end)

	local save = T.NewButton(ed, Loc["Save"], 100, 26, "accent")
	local pick = T.NewButton(ed, Loc["Pick up"], 90, 26)
	local del = T.NewButton(ed, Loc["Delete"], 90, 26)
	local status = T.Text(ed, "regular", 11, T.muted)

	UpdatePreview = function()
		local text = ns.MacroText(cur.model)
		if not cur.model.raw then preview:SetText(text ~= "" and text or Loc["|cff8c96a3(empty)|r"]) end
		local n = #text
		chars:SetText(("%d / 255"):format(n))
		chars:SetTextColor(unpack(n > 255 and T.red or T.muted))
	end

	local function Unit(b, o, cmdKey)
		b.unit:SetupMenu(function(_, root)
			for _, u in ipairs(ns.MACRO_UNITS) do
				root:CreateRadio(Loc[u[2]], function() return o.unit == u[1] end, function() o.unit = u[1]; UpdatePreview() end)
			end
		end)
		b.unit:GenerateMenu()
		b.form:SetupMenu(function(_, root)
			for _, fm in ipairs(FORMS) do
				root:CreateRadio(Loc[fm[2]], function() return o.form == fm[1] end, function() o.form = fm[1]; UpdatePreview() end)
			end
		end)
		b.form:GenerateMenu()
		local unitOnly = CMD[cmdKey].unitOnly
		b.icon:SetShown(not unitOnly)
		b.input:SetShown(not unitOnly)
		b.pick:SetShown(not unitOnly)
		b.pick:SetupMenu(function(_, root)
			local function Pick(name)
				o.spell = name
				b.input:SetText(name)
				b.icon:SetTexture(SpellIcon(cmdKey, name))
				UpdatePreview()
			end
			if cmdKey == "use" then
				local items = BagItems()
				if #items == 0 then root:CreateButton(Loc["No usable items in your bags"]):SetEnabled(false) end
				for _, it in ipairs(items) do root:CreateButton(("|T%s:16|t %s"):format(it.icon or QUESTION, it.name), function() Pick(it.name) end) end
			else
				local tabs = SpellBook()
				if #tabs == 0 then root:CreateButton(Loc["No spells found"]):SetEnabled(false) end
				for _, tab in ipairs(tabs) do
					local sub = root:CreateButton(tab.name)
					for _, sp in ipairs(tab.spells) do
						sub:CreateButton(("|T%s:16|t %s"):format(sp.icon or QUESTION, sp.name), function() Pick(sp.name) end)
					end
				end
			end
		end)
		b.on:ClearAllPoints()
		b.unit:ClearAllPoints()
		if unitOnly then
			b.on:SetText("")
			b.unit:SetPoint("TOPLEFT", 18, -2)
		else
			b.on:SetText(Loc["on"])
			b.on:SetPoint("LEFT", b.pick, "RIGHT", 8, 0)
			b.unit:SetPoint("LEFT", b.on, "RIGHT", 8, 0)
		end
	end

	Relayout = function()
		local m = cur.model
		m.lines = m.lines or {}
		local existing = cur.index ~= nil
		scopeA:SetShown(not existing)
		scopeC:SetShown(not existing)
		scopeLabel:SetShown(existing)
		scopeLabel:SetText(cur.scope == "char" and Loc["Character macro"] or Loc["Account macro"])
		scopeA:SetOn(cur.scope == "account")
		scopeC:SetOn(cur.scope == "char")
		tipChip:SetOn(m.tooltip ~= nil) -- true or a spell name
		stopChip:SetOn(m.stopcasting == true)
		tipChip:SetShown(not m.raw)
		stopChip:SetShown(not m.raw)
		tmpl:SetShown(not m.raw)

		local y = -66
		-- the two switches beside the template menu: on their own row when they don't fit
		tipChip:ClearAllPoints()
		if tmpl:GetWidth() + 10 + tipChip:GetWidth() + 6 + stopChip:GetWidth() > EDIT_W then
			tipChip:SetPoint("TOPLEFT", 0, -64)
			y = y - 28
		else
			tipChip:SetPoint("LEFT", tmpl, "RIGHT", 10, 0)
		end
		local showTip = (not m.raw) and m.tooltip ~= nil
		tipLabel:SetShown(showTip)
		tipPick:SetShown(showTip)
		if showTip then
			tipLabel:ClearAllPoints()
			tipLabel:SetPoint("TOPLEFT", 2, y - 6)
			tipPick:GenerateMenu()
			y = y - 34
		end
		for i, line in ipairs(m.raw and {} or m.lines) do
			local c = Card(i)
			local spec = CMD[line.cmd] or CMD.cast
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", 0, y)
			c.cmd:SetupMenu(function(_, root)
				for _, cm in ipairs(ns.MACRO_COMMANDS) do
					root:CreateRadio(Loc[cm.label], function() return line.cmd == cm.key end, function()
						line.cmd = cm.key
						if not cm.bare and (not line.options or #line.options == 0) then line.options = { {} } end
						Relayout()
					end)
				end
			end)
			c.cmd:GenerateMenu()
			c.label:SetText((Loc["LINE %d"]):format(i))
			c.up:SetEnabled(i > 1)
			c.down:SetEnabled(i < #m.lines)
			c.up:SetScript("OnClick", function() m.lines[i], m.lines[i - 1] = m.lines[i - 1], m.lines[i]; Relayout() end)
			c.down:SetScript("OnClick", function() m.lines[i], m.lines[i + 1] = m.lines[i + 1], m.lines[i]; Relayout() end)
			c.del:SetScript("OnClick", function() table.remove(m.lines, i); Relayout() end)
			local h = HEAD_H
			local opts = (not spec.bare) and (line.options or {}) or {}
			for j, o in ipairs(opts) do
				local b = OptBlock(c, j)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", 10, -h)
				b.num:SetText(#opts > 1 and (j == 1 and "1" or tostring(j)) or "")
				b.input:SetText(o.spell or "")
				b.icon:SetTexture(SpellIcon(line.cmd, o.spell))
				b.input:SetScript("OnTextChanged", function(self, user)
					if user or self:HasFocus() then o.spell = self:GetText() end
					b.icon:SetTexture(SpellIcon(line.cmd, o.spell))
					UpdatePreview()
				end)
				Unit(b, o, line.cmd)
				for _, chip in ipairs(b.chips) do
					local s = chip.spec
					chip:SetOn(ChipOn(o, s))
					chip:SetScript("OnClick", function()
						if s[3] == nil then o[s[2]] = (not o[s[2]]) or nil
						else o[s[2]] = (o[s[2]] == s[3]) and nil or s[3] end
						for _, other in ipairs(b.chips) do other:SetOn(ChipOn(o, other.spec)) end
						UpdatePreview()
					end)
				end
				b.rm:SetShown(#opts > 1)
				b.rm:SetScript("OnClick", function() table.remove(line.options, j); Relayout() end)
				b:Show()
				h = h + b.height
			end
			for j = #opts + 1, #(c.opts or {}) do c.opts[j]:Hide() end
			c.add:SetShown(not spec.bare)
			if not spec.bare then
				c.add:ClearAllPoints()
				c.add:SetPoint("TOPLEFT", 28, -h)
				c.add:SetScript("OnClick", function() table.insert(line.options, {}); Relayout() end)
				h = h + ADD_H
			end
			c:SetHeight(h + 6)
			c:Show()
			y = y - h - 16
		end
		for i = (m.raw and 0 or #m.lines) + 1, #cards do cards[i]:Hide() end

		addLine:SetShown(not m.raw)
		if not m.raw then
			addLine:ClearAllPoints()
			addLine:SetPoint("TOPLEFT", 0, y)
			y = y - 40
		end
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", 0, y - 16)
		preview:SetShown(not m.raw)
		raw:SetShown(m.raw ~= nil)
		if m.raw then
			if not raw:HasFocus() then raw:SetText(m.raw) end
			box:SetHeight(140)
		else
			UpdatePreview()
			box:SetHeight(math.max(preview:GetStringHeight() + 20, 44))
		end
		UpdatePreview()
		y = y - 16 - box:GetHeight() - 10
		mode:SetText(m.raw and Loc["Use blocks"] or Loc["Edit as text"])
		mode:ClearAllPoints()
		mode:SetPoint("TOPLEFT", 0, y)
		save:ClearAllPoints()
		save:SetPoint("TOPRIGHT", ed, "TOPRIGHT", 0, y)
		pick:ClearAllPoints()
		pick:SetPoint("RIGHT", save, "LEFT", -8, 0)
		del:ClearAllPoints()
		del:SetPoint("RIGHT", pick, "LEFT", -8, 0)
		pick:SetEnabled(existing)
		del:SetShown(existing)
		y = y - 34
		status:ClearAllPoints()
		status:SetPoint("TOPLEFT", 0, y)
		y = y - 20
		ed:SetHeight(-y)

		-- the page scrolls: its height is the taller column
		local hgt = math.max(-y, list:GetHeight()) + 8
		page:SetHeight(hgt)
		page.dpwsPage = { y = -hgt } -- the settings window sizes the page from this right after building it
		local scroll = page:GetParent()
		if scroll and scroll.ScrollBar then scroll.ScrollBar:SetShown(hgt > scroll:GetHeight()) end
	end

	Say = function(msg) status:SetText(msg) end

	NewMacro = function()
		cur.index = nil
		cur.scope = cur.tab
		cur.model = { tooltip = true, lines = { { cmd = "cast", options = { {} } } } }
		nameBox:SetText("")
		Say("")
		RefreshList()
	end

	Open = function(index)
		local name, _, body = GetMacroInfo(index)
		if not name then return end
		cur.index = index
		cur.scope = index > MAX_ACCOUNT and "char" or "account"
		nameBox:SetText(name)
		-- built here and unchanged since: blocks; otherwise its text
		local saved = Models()[Key(cur.scope, name)]
		local parsed, why = ns.ParseMacro(body)
		if saved and ns.MacroText(saved) == body then
			cur.model = Copy(saved)
			Say("")
		elseif parsed then
			cur.model = parsed
			Say(ns.MacroText(parsed) == body and "" or "Read into blocks; saving rewrites it in the builder's form.")
		else
			cur.model = { raw = body or "", lines = {} }
			Say("Shown as text: blocks can't show " .. why .. ".")
		end
		RefreshList()
	end

	save:SetScript("OnClick", function()
		local name = strtrim(nameBox:GetText() or "")
		local body = ns.MacroText(cur.model)
		if name == "" then return Say("|cffff6060Give the macro a name.|r") end
		if #body > 255 then return Say("|cffff6060Too long: macros hold 255 characters.|r") end
		if body == "" then return Say("|cffff6060The macro is empty.|r") end
		if InCombatLockdown() then Say("Saves when combat ends.") end
		ns.RunOutOfCombat(function()
			local oldName = cur.index and GetMacroInfo(cur.index)
			if cur.index then
				cur.index = EditMacro(cur.index, name, QUESTION, body) or GetMacroIndexByName(name)
			else
				local numA, numC = GetNumMacros()
				if (cur.scope == "char" and numC >= MAX_CHAR) or (cur.scope ~= "char" and numA >= MAX_ACCOUNT) then
					return Say("|cffff6060No free macro slots in that tab.|r")
				end
				cur.index = CreateMacro(name, QUESTION, body, cur.scope == "char")
			end
			if oldName and oldName ~= name then Models()[Key(cur.scope, oldName)] = nil end
			Models()[Key(cur.scope, name)] = (not cur.model.raw) and Copy(cur.model) or nil
			cur.tab = cur.scope
			Say("Saved " .. name .. ".")
			RefreshList()
		end)
	end)
	pick:SetScript("OnClick", function() if cur.index then PickupMacro(cur.index) end end)
	-- delete asks for a second click
	local armed
	del:SetScript("OnClick", function()
		if not cur.index then return end
		if not armed then
			armed = true
			del:SetText(Loc["Sure?"])
			C_Timer.After(3, function() armed = false; del:SetText(Loc["Delete"]) end)
			return
		end
		armed = false
		del:SetText(Loc["Delete"])
		ns.RunOutOfCombat(function()
			local name = GetMacroInfo(cur.index)
			DeleteMacro(cur.index)
			if name then Models()[Key(cur.scope, name)] = nil end
			Say("Deleted " .. (name or "macro") .. ".")
			NewMacro()
		end)
	end)

	page:SetScript("OnShow", function() RefreshList() end)
	NewMacro()
end

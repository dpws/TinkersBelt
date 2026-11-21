local _, ns = ...

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
	{ "targettarget", "Target's target" } }

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
	for _, o in ipairs(line.options or {}) do
		local cond = ns.MacroConditions(o)
		if c.unitOnly then
			if cond ~= "" then parts[#parts + 1] = cond end
		elseif o.spell and o.spell ~= "" then
			parts[#parts + 1] = (cond ~= "" and (cond .. " ") or "") .. o.spell
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

if not CreateFrame then return end -- offline test stops here

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
	local tabA, tabC = Chip(list, "General", 86), Chip(list, "Character", 86)
	tabA:SetPoint("TOPLEFT", 0, 0)
	tabC:SetPoint("LEFT", tabA, "RIGHT", 8, 0)
	tabA:SetScript("OnClick", function() cur.tab = "account"; RefreshList() end)
	tabC:SetScript("OnClick", function() cur.tab = "char"; RefreshList() end)
	local newBtn = T.NewButton(list, "+ New macro", 180, 24, "accent")
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
		count:SetText(("%d / %d macros"):format(n, max))
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

	local nameBox = T.NewInput(ed, 170)
	nameBox:SetPoint("TOPLEFT", 0, 0)
	nameBox:SetMaxLetters(16)
	local nameHint = T.Text(ed, "regular", 11, T.muted)
	nameHint:SetPoint("BOTTOMLEFT", nameBox, "TOPLEFT", 2, 3)
	nameHint:SetText("Name")
	local scopeA, scopeC = Chip(ed, "Account", 70), Chip(ed, "Character", 80)
	scopeA:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
	scopeC:SetPoint("LEFT", scopeA, "RIGHT", 6, 0)
	local scopeLabel = T.Text(ed, "regular", 12, T.muted)
	scopeLabel:SetPoint("LEFT", nameBox, "RIGHT", 12, 0)
	scopeA:SetScript("OnClick", function() cur.scope = "account"; Relayout() end)
	scopeC:SetScript("OnClick", function() cur.scope = "char"; Relayout() end)

	local tmpl = T.NewDropdown(ed, 210)
	tmpl:SetPoint("TOPLEFT", 0, -34)
	tmpl:SetDefaultText("Start from a template...")
	tmpl:SetupMenu(function(_, root)
		for _, t in ipairs(ns.MACRO_TEMPLATES) do
			root:CreateButton(t.name, function()
				local first = cur.model.lines and cur.model.lines[1]
				local s = first and first.options and first.options[#first.options] and first.options[#first.options].spell or ""
				cur.model = t.make(s or "")
				Relayout()
			end)
		end
	end)
	local tipChip, stopChip = Chip(ed, "Spell tooltip", 88), Chip(ed, "Stop casting first", 116)
	tipChip:SetPoint("LEFT", tmpl, "RIGHT", 10, 0)
	stopChip:SetPoint("LEFT", tipChip, "RIGHT", 6, 0)
	tipChip:SetScript("OnClick", function() cur.model.tooltip = not cur.model.tooltip or nil; Relayout() end)
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
		b.on:SetText("on")
		b.unit = T.NewDropdown(b, 130)
		b.rm = T.NewButton(b, "x", 24, 22)
		b.rm:SetPoint("TOPRIGHT", 0, -2)
		b.chips = {}
		for r, specs in ipairs(CHIP_ROWS) do
			local x = 18
			for _, spec in ipairs(specs) do
				local c = Chip(b, spec[1], spec[4])
				c:SetPoint("TOPLEFT", x, -32 - (r - 1) * 26)
				c.spec = spec
				x = x + spec[4] + 4
				b.chips[#b.chips + 1] = c
			end
		end
		b.form = T.NewDropdown(b, 110)
		b.form:SetPoint("TOPLEFT", 18 + 58 + 74 + 44 + 46 + 16, -54)
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
		c.add = T.NewButton(c, "+ or", 60, 22)
		cards[i] = c
		return c
	end

	local addLine = T.NewButton(ed, "+ Add line", 110, 24)
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
	local mode = T.NewButton(ed, "Edit as text", 110, 24)
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

	local save = T.NewButton(ed, "Save", 100, 26, "accent")
	local pick = T.NewButton(ed, "Pick up", 90, 26)
	local del = T.NewButton(ed, "Delete", 90, 26)
	local status = T.Text(ed, "regular", 11, T.muted)

	UpdatePreview = function()
		local text = ns.MacroText(cur.model)
		if not cur.model.raw then preview:SetText(text ~= "" and text or "|cff8c96a3(empty)|r") end
		local n = #text
		chars:SetText(("%d / 255"):format(n))
		chars:SetTextColor(unpack(n > 255 and T.red or T.muted))
	end

	local function Unit(b, o, cmdKey)
		b.unit:SetupMenu(function(_, root)
			for _, u in ipairs(ns.MACRO_UNITS) do
				root:CreateRadio(u[2], function() return o.unit == u[1] end, function() o.unit = u[1]; UpdatePreview() end)
			end
		end)
		b.unit:GenerateMenu()
		b.form:SetupMenu(function(_, root)
			for _, fm in ipairs(FORMS) do
				root:CreateRadio(fm[2], function() return o.form == fm[1] end, function() o.form = fm[1]; UpdatePreview() end)
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
				if #items == 0 then root:CreateButton("No usable items in your bags"):SetEnabled(false) end
				for _, it in ipairs(items) do root:CreateButton(("|T%s:16|t %s"):format(it.icon or QUESTION, it.name), function() Pick(it.name) end) end
			else
				local tabs = SpellBook()
				if #tabs == 0 then root:CreateButton("No spells found"):SetEnabled(false) end
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
			b.on:SetText("on")
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
		scopeLabel:SetText(cur.scope == "char" and "Character macro" or "Account macro")
		scopeA:SetOn(cur.scope == "account")
		scopeC:SetOn(cur.scope == "char")
		tipChip:SetOn(m.tooltip == true)
		stopChip:SetOn(m.stopcasting == true)
		tipChip:SetShown(not m.raw)
		stopChip:SetShown(not m.raw)
		tmpl:SetShown(not m.raw)

		local y = -66
		for i, line in ipairs(m.raw and {} or m.lines) do
			local c = Card(i)
			local spec = CMD[line.cmd] or CMD.cast
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", 0, y)
			c.cmd:SetupMenu(function(_, root)
				for _, cm in ipairs(ns.MACRO_COMMANDS) do
					root:CreateRadio(cm.label, function() return line.cmd == cm.key end, function()
						line.cmd = cm.key
						if not cm.bare and (not line.options or #line.options == 0) then line.options = { {} } end
						Relayout()
					end)
				end
			end)
			c.cmd:GenerateMenu()
			c.label:SetText("LINE " .. i)
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
				h = h + OPT_H
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
		mode:SetText(m.raw and "Use blocks" or "Edit as text")
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
			del:SetText("Sure?")
			C_Timer.After(3, function() armed = false; del:SetText("Delete") end)
			return
		end
		armed = false
		del:SetText("Delete")
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

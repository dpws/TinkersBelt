local _, ns = ...

-- Flat dark UI kit in the style of BuffTap's settings window: rounded cards, gold accent, Inter font.
-- Own textures only (media/circle.tga is generated, Inter is OFL-licensed).
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\TinkersBelt\\media\\"
local CIRCLE = MEDIA .. "circle"

local T = {
	window = { 0.047, 0.054, 0.066, 0.98 },
	sidebar = { 0.036, 0.042, 0.052, 1 },
	card = { 0.071, 0.081, 0.099, 1 },
	row = { 0.088, 0.100, 0.121, 1 },
	control = { 0.105, 0.118, 0.140, 1 },
	field = { 0.040, 0.047, 0.058, 1 },
	border = { 1, 1, 1, 0.10 },
	hover = { 1, 1, 1, 0.06 },
	gold = { 0.427, 0.812, 0.769, 1 }, -- the accent colour (#6dcfc4); the key name stayed from the first theme
	text = { 0.86, 0.88, 0.91, 1 },
	muted = { 0.55, 0.59, 0.64, 1 },
	off = { 0.20, 0.22, 0.26, 1 },
	switchOn = { 0.090, 0.247, 0.235, 1 }, -- #173f3c
	green = { 0.30, 0.80, 0.40, 1 },
	red = { 0.95, 0.35, 0.30, 1 },
	WHITE = WHITE,
	CIRCLE = CIRCLE,
	BAR = WHITE, -- status bar fill
	theme = "modern",
}
ns.Theme = T

-- Classic theme: Blizzard tooltip/dialog frames, Friz Quadrata, gold and white text. Picked once at
-- ADDON_LOADED (before any UI exists), so switching needs a reload. Colours change in place: other
-- files keep references to these tables.
local CLASSIC = {
	window = { 0, 0, 0, 0.92 }, sidebar = { 0, 0, 0, 0 }, card = { 0.08, 0.08, 0.08, 0.9 }, row = { 0.14, 0.12, 0.09, 0.9 },
	control = { 0.22, 0.05, 0.03, 1 }, field = { 0.02, 0.02, 0.02, 0.95 }, border = { 0.7, 0.7, 0.7, 1 },
	hover = { 1, 1, 1, 0.08 }, gold = { 1, 0.82, 0, 1 }, text = { 1, 1, 1, 1 }, muted = { 0.62, 0.62, 0.62, 1 },
	off = { 0.25, 0.23, 0.2, 1 }, switchOn = { 0.45, 0.33, 0.04, 1 },
}
function T.UseTheme(name)
	if name ~= "classic" then return end
	T.theme = "classic"
	for key, c in pairs(CLASSIC) do for i = 1, 4 do T[key][i] = c[i] end end
	local friz = "Fonts\\FRIZQT__.TTF"
	T.font.regular, T.font.medium, T.font.semibold = friz, friz, friz
	T.BAR = "Interface\\TargetingFrame\\UI-StatusBar"
end

-- classic frames: tooltip border, or the big dialog border for windows (radius >= 10)
local function Backdrop(frame, fill, border, dialog)
	if not frame.SetBackdrop then
		Mixin(frame, BackdropTemplateMixin)
		frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
	end
	if dialog then
		frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		frame:SetBackdropColor(1, 1, 1, 1)
		frame:SetBackdropBorderColor(1, 1, 1, 1)
	else
		frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		frame:SetBackdropColor(unpack(fill))
		frame:SetBackdropBorderColor(unpack(border))
	end
end

-- the accent at a given alpha (tints, borders, gradients)
function T.Accent(a) return { T.gold[1], T.gold[2], T.gold[3], a or 1 } end

T.font = {
	regular = MEDIA .. "fonts\\Inter-Regular.ttf",
	medium = MEDIA .. "fonts\\Inter-Medium.ttf",
	semibold = MEDIA .. "fonts\\Inter-SemiBold.ttf",
}

-- set a font string to Inter, keeping its size, outline and colour
function T.Font(fs, weight, size)
	local _, oldSize, oldFlags = fs:GetFont()
	fs:SetFont(T.font[weight or "medium"], size or oldSize or 12, oldFlags or "")
	fs:SetShadowColor(0, 0, 0, 0.6)
	fs:SetShadowOffset(1, -1)
end

function T.Text(parent, weight, size, color, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(T.font[weight or "medium"], size or 12, "")
	fs:SetShadowColor(0, 0, 0, 0.6)
	fs:SetShadowOffset(1, -1)
	fs:SetTextColor(unpack(color or T.text))
	fs:SetJustifyH("LEFT")
	return fs
end

---------------------------------------------------------------------------
-- Rounded rectangles: four circle quadrants + three bands. inset shrinks it (for borders).

local Round = {}
Round.__index = Round
function Round:SetColor(c) for _, t in ipairs(self.t) do t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end end
function Round:SetShown(on) for _, t in ipairs(self.t) do t:SetShown(on) end end

function T.Rounded(frame, color, radius, layer, sub, inset)
	radius, inset = radius or 6, inset or 0
	local r = setmetatable({ t = {} }, Round)
	local function tex(file)
		local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
		t:SetTexture(file)
		t.dpws = true
		r.t[#r.t + 1] = t
		return t
	end
	local corners = { TOPLEFT = { 0, 0.5, 0, 0.5, inset, -inset }, TOPRIGHT = { 0.5, 1, 0, 0.5, -inset, -inset },
		BOTTOMLEFT = { 0, 0.5, 0.5, 1, inset, inset }, BOTTOMRIGHT = { 0.5, 1, 0.5, 1, -inset, inset } }
	for point, c in pairs(corners) do
		local t = tex(CIRCLE)
		t:SetTexCoord(c[1], c[2], c[3], c[4])
		t:SetSize(radius, radius)
		t:SetPoint(point, c[5], c[6])
	end
	local mid = tex(WHITE) -- full height, between left and right corners
	mid:SetPoint("TOPLEFT", inset + radius, -inset)
	mid:SetPoint("BOTTOMRIGHT", -inset - radius, inset)
	local left = tex(WHITE)
	left:SetPoint("TOPLEFT", inset, -inset - radius)
	left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", inset + radius, inset + radius)
	local right = tex(WHITE)
	right:SetPoint("TOPRIGHT", -inset, -inset - radius)
	right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", -inset - radius, inset + radius)
	r:SetColor(color or T.card)
	return r
end

-- filled rounded box with a 1px border (border box underneath, fill box inset by 1)
function T.Box(frame, fill, border, radius, layer)
	if T.theme == "classic" then
		Backdrop(frame, fill or T.card, border or T.border, (radius or 6) >= 10)
		return frame
	end
	frame.dpwsBorder = T.Rounded(frame, border or T.border, radius or 6, layer, -8, 0)
	frame.dpwsFill = T.Rounded(frame, fill or T.card, (radius or 6) - 1, layer, -7, 1)
	return frame
end

-- square fill + 1px border (for in-game panels)
function T.Panel(frame, color, border)
	if T.theme == "classic" then
		Backdrop(frame, color or { 0, 0, 0, 0.8 }, border == false and { 0, 0, 0, 0 } or border or T.border)
		return frame
	end
	if frame.dpwsBg then
		frame.dpwsBg:SetColorTexture(unpack(color or T.window))
		return frame
	end
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(color or T.window))
	frame.dpwsBg = bg
	if border ~= false then
		local c = border or T.border
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
			{ "TOPLEFT", "BOTTOMLEFT", 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 1 } }) do
			local t = frame:CreateTexture(nil, "BORDER", nil, 7)
			t:SetColorTexture(unpack(c))
			t:SetPoint(e[1])
			t:SetPoint(e[2])
			if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
		end
	end
	return frame
end

-- texts of a whole frame tree to Inter (in-game panels)
function T.Skin(frame)
	if not frame then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:GetObjectType() == "FontString" and not r.dpwsFont then
			r.dpwsFont = true
			pcall(T.Font, r)
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do T.Skin(child) end
end

-- restyle an existing UIPanelButtonTemplate button (secure/template buttons we can't replace)
function T.Button(b)
	if b.dpwsSkinned then return end
	b.dpwsSkinned = true
	for _, r in ipairs({ b:GetRegions() }) do
		if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
	end
	T.Box(b, T.control, T.border, 5)
	local fs = b:GetFontString()
	if fs then
		fs:SetFont(T.font.medium, 12, "")
		fs:SetTextColor(unpack(T.text))
	end
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 2, -2)
	hl:SetPoint("BOTTOMRIGHT", -2, 2)
	hl:SetColorTexture(1, 1, 1, 0.05)
end

---------------------------------------------------------------------------
-- Controls

-- flat button; kind "accent" = gold fill with dark text
function T.NewButton(parent, text, w, h, kind)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w or 120, h or 26)
	local accent = kind == "accent"
	T.Box(b, accent and T.gold or T.control, accent and T.gold or T.border, 5)
	local fs = T.Text(b, "medium", 12, accent and { 0.06, 0.065, 0.08, 1 } or T.text)
	fs:SetPoint("CENTER")
	fs:SetJustifyH("CENTER")
	fs:SetShadowOffset(0, 0)
	b:SetFontString(fs)
	b:SetText(text or "")
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 2, -2)
	hl:SetPoint("BOTTOMRIGHT", -2, 2)
	hl:SetColorTexture(1, 1, 1, 0.05)
	b:HookScript("OnEnable", function() fs:SetTextColor(unpack(accent and { 0.06, 0.065, 0.08, 1 } or T.text)) end)
	b:HookScript("OnDisable", function() fs:SetTextColor(unpack(T.muted)) end)
	return b
end

-- pill toggle; onChange(checked)
function T.NewToggle(parent, onChange)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(36, 20)
	local track = T.Rounded(c, T.off, 10, "BACKGROUND", 0)
	local knob = c:CreateTexture(nil, "ARTWORK")
	knob:SetTexture(CIRCLE)
	knob:SetSize(16, 16)
	local checked = false
	-- on: dark teal track (#173f3c) with the bright accent knob; off: gray track, dim knob
	function c:SetChecked(on)
		checked = on and true or false
		track:SetColor(checked and T.switchOn or T.off)
		knob:ClearAllPoints()
		knob:SetPoint(checked and "RIGHT" or "LEFT", checked and -2 or 2, 0)
		knob:SetVertexColor(unpack(checked and T.gold or { 0.55, 0.59, 0.64, 1 }))
	end
	function c:GetChecked() return checked end
	c:SetScript("OnClick", function(self)
		self:SetChecked(not checked)
		if onChange then onChange(checked) end
	end)
	c:SetChecked(false)
	return c
end

function T.NewInput(parent, w, numeric)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(w or 120, 26)
	e:SetAutoFocus(false)
	e:SetFont(T.font.medium, 12, "")
	e:SetTextColor(unpack(T.text))
	e:SetTextInsets(8, 8, 0, 0)
	if numeric then e:SetNumeric(true) end
	T.Box(e, T.field, T.border, 5)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

-- slider: value box + track with gold fill + round knob. onChange(value)
function T.NewSlider(parent, min, max, step, suffix, onChange)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(300, 26)
	local box = T.NewInput(f, 74, true)
	box:SetPoint("LEFT")
	box:SetJustifyH("RIGHT")
	box:SetTextInsets(6, suffix and 30 or 8, 0, 0)
	if suffix then
		local unit = T.Text(box, "regular", 11, T.muted)
		unit:SetPoint("RIGHT", -7, 0)
		unit:SetText(suffix)
	end
	local s = CreateFrame("Slider", nil, f)
	s:SetPoint("LEFT", box, "RIGHT", 14, 0)
	s:SetPoint("RIGHT", -8, 0)
	s:SetHeight(18)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:SetHitRectInsets(0, 0, -6, -6)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(unpack(T.off))
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	s:SetThumbTexture(CIRCLE)
	local thumb = s:GetThumbTexture()
	thumb:SetSize(16, 16)
	thumb:SetVertexColor(unpack(T.gold))
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetColorTexture(unpack(T.gold))
	fill:SetHeight(4)
	fill:SetPoint("LEFT")
	fill:SetPoint("RIGHT", thumb, "CENTER")
	local loading = false
	local function Show(v) box:SetText(tostring(v)) end
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		Show(v)
		if not loading and onChange then onChange(v) end
	end)
	local function Commit()
		local v = tonumber(box:GetText())
		if v then
			v = math.min(max, math.max(min, v))
			s:SetValue(v)
		end
		box:ClearFocus()
	end
	box:SetScript("OnEnterPressed", Commit)
	box:SetScript("OnEditFocusLost", Commit)
	function f:SetValue(v)
		loading = true
		s:SetValue(v)
		Show(math.floor(v / step + 0.5) * step)
		loading = false
	end
	return f
end

-- WoW's menu dropdown (keeps its menu), restyled: rounded field and a chevron
function T.NewDropdown(parent, w)
	local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	d:SetWidth(w or 220)
	for _, r in ipairs({ d:GetRegions() }) do
		if r:GetObjectType() == "Texture" then r:SetAlpha(0) end
	end
	T.Box(d, T.field, T.border, 5)
	if d.Text then
		d.Text:SetFont(T.font.medium, 12, "")
		d.Text:SetTextColor(unpack(T.text))
		d.Text:ClearAllPoints()
		d.Text:SetPoint("LEFT", 10, 0)
		d.Text:SetPoint("RIGHT", -24, 0)
		d.Text:SetJustifyH("LEFT")
	end
	local chevron = T.Text(d, "semibold", 11, T.muted)
	chevron:SetPoint("RIGHT", -10, 0)
	chevron:SetText("v")
	local hl = d:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 2, -2)
	hl:SetPoint("BOTTOMRIGHT", -2, 2)
	hl:SetColorTexture(1, 1, 1, 0.04)
	return d
end

---------------------------------------------------------------------------
-- Page builder: cards with a gold section label and label/control rows, stacked top to bottom.
-- Every control registers a refresher; Finish() runs them whenever the page is shown.

local Page = {}
Page.__index = Page
local ROW, PAD = 38, 16

function T.Page(parent)
	if parent.dpwsPage then return parent.dpwsPage end -- a second builder on the same page continues below
	local p = setmetatable({ parent = parent, y = 0, refreshers = {} }, Page)
	p.width = parent:GetWidth() > 0 and parent:GetWidth() or 640
	parent.dpwsPage = p -- the window reads p.y to size its scroll area
	return p
end

function Page:Refresher(fn) self.refreshers[#self.refreshers + 1] = fn end

function Page:EndCard()
	local c = self.card
	if not c then return end
	c:SetHeight(-c.y + 10)
	self.y = self.y - c:GetHeight() - 14
	self.card = nil
end

function Page:Card(title)
	self:EndCard()
	local c = CreateFrame("Frame", nil, self.parent)
	c:SetPoint("TOPLEFT", 0, self.y)
	c:SetPoint("RIGHT")
	T.Box(c, T.card, T.border, 8)
	c.y = -10
	if title then
		local label = T.Text(c, "semibold", 11, T.gold)
		label:SetPoint("TOPLEFT", PAD + 2, -14)
		label:SetText(title:upper())
		c.y = -34
	end
	self.card = c
	return c
end

-- the frame rows go into (current card, or the page itself)
function Page:Host()
	return self.card or self.parent
end

function Page:Row(height)
	local host = self:Host()
	local row = CreateFrame("Frame", nil, host)
	local x = self.card and PAD or 0
	if self.card then
		row:SetPoint("TOPLEFT", x, self.card.y)
		row:SetPoint("RIGHT", -PAD, 0)
		self.card.y = self.card.y - (height or ROW)
	else
		row:SetPoint("TOPLEFT", 0, self.y)
		row:SetPoint("RIGHT")
		self.y = self.y - (height or ROW)
	end
	row:SetHeight(height or ROW)
	return row
end

local function Label(row, text)
	local fs = T.Text(row, "medium", 13, T.text)
	fs:SetPoint("LEFT", 2, 0)
	fs:SetText(text)
	return fs
end

-- [toggle] Label
function Page:Toggle(text, get, set)
	local row = self:Row()
	local t = T.NewToggle(row, set)
	t:SetPoint("LEFT", 2, 0)
	local fs = T.Text(row, "medium", 13, T.text)
	fs:SetPoint("LEFT", t, "RIGHT", 10, 0)
	fs:SetText(text)
	self:Refresher(function() t:SetChecked(get()) end)
	return t, row
end

-- Label ........ [value][----o----]
function Page:Slider(text, min, max, step, suffix, get, set)
	local row = self:Row()
	Label(row, text)
	local s = T.NewSlider(row, min, max, step, suffix, set)
	s:SetPoint("RIGHT")
	s:SetWidth(320)
	self:Refresher(function() s:SetValue(get()) end)
	return s, row
end

-- Label ........ [dropdown v]; setup(root) fills the menu
function Page:Dropdown(text, setup, width)
	local row = self:Row()
	if text then Label(row, text) end
	local d = T.NewDropdown(row, width or 320)
	d:SetPoint("RIGHT")
	d:SetupMenu(function(_, root) setup(root) end)
	self:Refresher(function() d:GenerateMenu() end)
	return d, row
end

-- radio choices in a dropdown: options = { {key, label}, ... }
function Page:Choice(text, options, get, set, width)
	return self:Dropdown(text, function(root)
		for _, o in ipairs(options) do
			root:CreateRadio(o[2], function() return get() == o[1] end, function() set(o[1]) end)
		end
	end, width)
end

-- sound picker (ns.SOUNDS + None); choosing one plays it
function Page:Sound(text, get, set)
	return self:Dropdown(text, function(root)
		root:CreateRadio("None", function() return get() == nil end, function() set(nil) end)
		for _, s in ipairs(ns.SOUNDS) do
			root:CreateRadio(s.name, function() return get() == s.key end, function() set(s.key); ns.PlaySoundKey(s.key) end)
		end
	end)
end

-- muted wrapped text
function Page:Note(text, color)
	local host = self:Host()
	local fs = T.Text(host, "regular", 12, color or T.muted)
	local x = self.card and PAD + 2 or 2
	local w = (self.card and self.width - 2 * PAD or self.width) - 4
	fs:SetWidth(w)
	fs:SetWordWrap(true)
	fs:SetText(text)
	if self.card then
		fs:SetPoint("TOPLEFT", x, self.card.y - 4)
	else
		fs:SetPoint("TOPLEFT", x, self.y - 4)
	end
	local h = math.max(fs:GetStringHeight(), 14) + 10
	if self.card then self.card.y = self.card.y - h else self.y = self.y - h end
	return fs
end

function Page:Space(n)
	if self.card then self.card.y = self.card.y - n else self.y = self.y - n end
end

-- free-form block: build(frame) fills it
function Page:Custom(height, build)
	local row = self:Row(height)
	build(row)
	return row
end

function Page:Finish()
	self:EndCard()
	local refreshers = self.refreshers
	self.parent:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
	for _, r in ipairs(refreshers) do pcall(r) end
end

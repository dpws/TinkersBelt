local _, ns = ...

-- Flat dark theme (inspired by BuffTap's settings window). Presentation only: skins restyle existing
-- controls in place, their scripts and values are untouched.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONTS = "Interface\\AddOns\\dpws_tools\\media\\fonts\\Inter-"

local T = {
	window = { 0.047, 0.054, 0.066, 0.97 },
	sidebar = { 0.036, 0.042, 0.052, 1 },
	card = { 0.071, 0.081, 0.099, 1 },
	control = { 0.105, 0.118, 0.140, 1 },
	field = { 0.040, 0.047, 0.058, 1 },
	border = { 1, 1, 1, 0.10 },
	hover = { 1, 1, 1, 0.06 },
	gold = { 0.91, 0.71, 0.36, 1 },
	text = { 0.86, 0.88, 0.91, 1 },
	muted = { 0.55, 0.59, 0.64, 1 },
	off = { 0.22, 0.24, 0.28, 1 },
	WHITE = WHITE,
}
ns.Theme = T

T.font = {
	regular = FONTS .. "Regular.ttf",
	medium = FONTS .. "Medium.ttf",
	semibold = FONTS .. "SemiBold.ttf",
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
	T.Font(fs, weight, size)
	fs:SetTextColor(unpack(color or T.text))
	return fs
end

-- solid fill + 1px border on any frame (textures, no template)
function T.Panel(frame, color, border)
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
		local function edge(p1, p2, w, h)
			local t = frame:CreateTexture(nil, "BORDER", nil, 7)
			t:SetColorTexture(unpack(c))
			t:SetPoint(p1)
			t:SetPoint(p2)
			if w then t:SetWidth(w) else t:SetHeight(h) end
		end
		edge("TOPLEFT", "TOPRIGHT", nil, 1)
		edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
		edge("TOPLEFT", "BOTTOMLEFT", 1)
		edge("TOPRIGHT", "BOTTOMRIGHT", 1)
	end
	return frame
end

-- hide a template's own textures (keeps the ones we add, which are tagged)
local function StripTextures(frame, keep)
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:GetObjectType() == "Texture" and not r.dpws and r ~= keep then r:SetAlpha(0) end
	end
end

local function Tex(frame, layer, color)
	local t = frame:CreateTexture(nil, layer)
	t:SetColorTexture(unpack(color))
	t.dpws = true
	return t
end

-- flat button: control fill, border, hover light, Inter text
function T.Button(b)
	if b.dpwsSkinned then return end
	b.dpwsSkinned = true
	StripTextures(b)
	for _, key in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		local t = b[key] and b[key](b)
		if t then t:SetAlpha(0) end
	end
	local hl = Tex(b, "HIGHLIGHT", T.hover)
	hl:SetAllPoints()
	T.Panel(b, T.control)
	local fs = b:GetFontString()
	if fs then T.Font(fs, "medium", 12) end
	b:HookScript("OnEnable", function() if b:GetFontString() then b:GetFontString():SetTextColor(unpack(T.text)) end end)
	b:HookScript("OnDisable", function() if b:GetFontString() then b:GetFontString():SetTextColor(unpack(T.muted)) end end)
	if fs then fs:SetTextColor(unpack(b:IsEnabled() and T.text or T.muted)) end
end

function T.EditBox(e)
	if e.dpwsSkinned then return end
	e.dpwsSkinned = true
	StripTextures(e)
	T.Panel(e, T.field)
	e.dpwsBg:ClearAllPoints()
	e.dpwsBg:SetPoint("TOPLEFT", -5, 0)
	e.dpwsBg:SetPoint("BOTTOMRIGHT", 0, 0)
	local font, size = e:GetFont()
	if font then e:SetFont(T.font.medium, size or 12, "") end
	e:SetTextColor(unpack(T.text))
end

-- checkbox -> pill toggle (36x18), same CheckButton underneath
function T.Toggle(c)
	if c.dpwsSkinned then return end
	c.dpwsSkinned = true
	StripTextures(c)
	for _, key in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
		local t = c[key] and c[key](c)
		if t then t:SetAlpha(0) end
	end
	c:SetSize(36, 18)
	local track = Tex(c, "BACKGROUND", T.off)
	track:SetAllPoints()
	local knob = Tex(c, "ARTWORK", { 1, 1, 1, 1 })
	knob:SetSize(14, 14)
	local function Update()
		local on = c:GetChecked()
		track:SetColorTexture(unpack(on and T.gold or T.off))
		knob:ClearAllPoints()
		knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
	end
	c:HookScript("OnClick", Update)
	hooksecurefunc(c, "SetChecked", Update)
	Update()
end

-- our plain sliders: thin track, gold knob
function T.Slider(s)
	if s.dpwsSkinned then return end
	s.dpwsSkinned = true
	StripTextures(s, s:GetThumbTexture())
	local track = Tex(s, "BACKGROUND", T.control)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	s:SetThumbTexture(WHITE)
	local thumb = s:GetThumbTexture()
	thumb:SetVertexColor(unpack(T.gold))
	thumb:SetSize(10, 16)
end

function T.Dropdown(d)
	if d.dpwsSkinned then return end
	d.dpwsSkinned = true
	StripTextures(d, d.Arrow)
	T.Panel(d, T.control)
	if d.Text then
		T.Font(d.Text, "medium", 12)
		d.Text:SetTextColor(unpack(T.text))
	end
	local hl = Tex(d, "HIGHLIGHT", T.hover)
	hl:SetAllPoints()
end

-- Restyle a whole tree: fonts to Inter, known widgets skinned.
function T.Skin(frame)
	if not frame or frame.dpwsNoSkin then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:GetObjectType() == "FontString" and not r.dpwsFont then
			r.dpwsFont = true
			pcall(T.Font, r)
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local kind = child:GetObjectType()
		if kind == "CheckButton" then
			T.Toggle(child)
		elseif kind == "EditBox" then
			T.EditBox(child)
		elseif kind == "Slider" and not child.ScrollBar then
			T.Slider(child)
		elseif kind == "DropdownButton" then
			T.Dropdown(child)
		elseif kind == "Button" and (child.dpwsButton or (child.Left and child.Middle and child.Right)) then -- UIPanelButtonTemplate
			T.Button(child)
		end
		T.Skin(child)
	end
end

-- a template button marked for skinning (UIPanelButtonTemplate gives us text + click handling)
function T.NewButton(parent, text, w, h)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w or 120, h or 24)
	b:SetText(text or "")
	b.dpwsButton = true
	T.Button(b)
	return b
end

-- Checks every Locales/<locale>.lua against docs/locale/keys.txt. Run: luajit tests/locales.lua [locale]
-- A translation must keep the English text's %-placeholders (same ones, same order), colour codes (|c...|r),
-- textures (|T...|t), line breaks and leading/trailing spaces. Missing keys are allowed (English shows) but listed.
local LOCALES = { "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local only = arg and arg[1]

local keys = {}
for line in io.lines("docs/locale/keys.txt") do
	if line ~= "" then keys[#keys + 1] = assert(load("return " .. line))() end
end

local function placeholders(s)
	local out = {}
	for p in s:gmatch("%%[%-%d%.]*[%a%%]") do out[#out + 1] = p end
	return table.concat(out, " ")
end
local function codes(s)
	local out = {}
	for c in s:gmatch("|c%x%x%x%x%x%x%x%x") do out[#out + 1] = c end
	for _ in s:gmatch("|r") do out[#out + 1] = "|r" end
	for t in s:gmatch("|T.-|t") do out[#out + 1] = t end
	local _, nl = s:gsub("\n", "")
	out[#out + 1] = "nl" .. nl
	return table.concat(out, " ")
end
local function edges(s) return (s:match("^%s*") or "") .. "|" .. (s:match("%s*$") or "") end

local failed, checked = 0, 0
for _, loc in ipairs(LOCALES) do
	if not only or only == loc then
		local path = "Locales/" .. loc .. ".lua"
		local chunk = loadfile(path)
		if not chunk then
			print(("%s: missing or does not parse"):format(path))
			failed = failed + 1
		else
			local ns = {}
			chunk("TinkersBelt", ns)
			local L = ns.LOCALES and ns.LOCALES[loc] or {}
			local missing, bad = 0, {}
			for _, en in ipairs(keys) do
				local tr = rawget(L, en)
				if tr == nil then missing = missing + 1
				elseif type(tr) ~= "string" or tr == "" then bad[#bad + 1] = ("empty: %q"):format(en)
				elseif placeholders(tr) ~= placeholders(en) then bad[#bad + 1] = ("placeholders %q -> %q"):format(en, tr)
				elseif codes(tr) ~= codes(en) then bad[#bad + 1] = ("colour/texture/line codes %q -> %q"):format(en, tr)
				elseif edges(tr) ~= edges(en) then bad[#bad + 1] = ("leading/trailing spaces %q -> %q"):format(en, tr)
				end
			end
			local extra = 0
			local known = {}
			for _, en in ipairs(keys) do known[en] = true end
			for k in pairs(L) do if not known[k] then extra = extra + 1; bad[#bad + 1] = ("unknown key %q"):format(k) end end
			checked = checked + 1
			print(("%s: %d translated, %d missing, %d problems"):format(loc, #keys - missing, missing, #bad))
			for i = 1, math.min(#bad, 15) do print("  " .. bad[i]) end
			if #bad > 0 then failed = failed + 1 end
		end
	end
end
if failed > 0 then print("locales: FAILED"); os.exit(1) end
print("locales: " .. checked .. " passed")

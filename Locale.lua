local _, ns = ...

-- Translations. Code writes L["English text"] (as Loc[...]); each Locales/<code>.lua fills ns.LOCALES[code].
-- The active language is the client's, or the one picked in the settings (ns.SetLanguage at ADDON_LOADED,
-- before any UI exists; a change needs a reload). Anything not translated shows in English.
ns.LOCALES = ns.LOCALES or {}
ns.lang = GetLocale and GetLocale() or "enUS"
ns.L = setmetatable({}, { __index = function(_, key)
	local t = ns.LOCALES[ns.lang]
	return t and t[key] or key
end })

-- the language menu: code and the language's own name
ns.LANGUAGES = {
	{ "enUS", "English" }, { "deDE", "Deutsch" }, { "frFR", "Français" }, { "esES", "Español (España)" },
	{ "esMX", "Español (Latinoamérica)" }, { "itIT", "Italiano" }, { "ptBR", "Português (Brasil)" },
	{ "ruRU", "Русский" }, { "koKR", "한국어" }, { "zhCN", "简体中文" }, { "zhTW", "繁體中文" },
}
-- languages whose letters the addon's fonts lack: the game's own font is used for them
ns.CJK = { koKR = true, zhCN = true, zhTW = true }

function ns.SetLanguage(code)
	if code == "enUS" or (code and ns.LOCALES[code]) then ns.lang = code end
end

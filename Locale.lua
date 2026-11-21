local _, ns = ...

-- Translations. Text is written in English in the code as L["English text"]; each Locales/<locale>.lua fills
-- in its language for that client (GetLocale()). Anything not translated shows in English.
ns.L = setmetatable({}, { __index = function(_, key) return key end })

local _, ns = ...

-- Classic rogue poisons by item ID (locale independent). Add Forever-specific IDs here.
ns.POISON_IDS = {
	6947, 6949, 6950, 8926, 8927, 8928, -- Instant I-VI
	2892, 2893, 8984, 8985, 20844, -- Deadly I-V
	3775, 3776, -- Crippling I-II
	5237, 6951, 9186, -- Mind-numbing I-III
	10918, 10920, 10921, 10922, -- Wound I-IV
}

-- Known list + every poison learned from the Poisons window (Forever also has Season of Discovery
-- poisons, e.g. Atrophic Poison 217347). Sorted by item ID.
function ns.AllPoisonIds()
	local seen, ids = {}, {}
	for _, id in ipairs(ns.POISON_IDS) do seen[id] = true end
	for id in pairs(ns.db and ns.db.poisonRecipes or {}) do seen[id] = true end
	for id in pairs(seen) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

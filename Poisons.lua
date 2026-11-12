local _, ns = ...

-- Pure reminder logic per weapon. Returns new state and nil | "early" | "expired".
function ns.PoisonStep(prev, hasEnchant, msLeft, warnMs)
	prev = prev or {}
	if not hasEnchant then
		return { applied = false }, prev.applied and "expired" or nil
	end
	-- new application (first seen, or time jumped up = reapplied)
	if not prev.applied or msLeft > (prev.msLeft or 0) + 1000 then
		return { applied = true, early = msLeft < warnMs, msLeft = msLeft }, nil
	end
	local event = (not prev.early and msLeft < warnMs) and "early" or nil
	return { applied = true, early = prev.early or event ~= nil, msLeft = msLeft }, event
end

if not CreateFrame then return end -- offline test stops here

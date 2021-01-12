--[[
	API overrides from external addons that augment the data missing in the Classic API
]]
ShadowUF = select(2, ...)
ShadowUF.API = {}

local LibCLHealth = LibStub("LibCombatLogHealth-1.0")

ShadowUF.API.UnitHealth = function(unit)
	if LibCLHealth then
		return LibCLHealth.UnitHealth(unit)
	end
	if RealMobHealth then
		local cur, max = RealMobHealth.GetUnitHealth(unit)
		if cur then return cur end
	end
	return UnitHealth(unit)
end

ShadowUF.API.UnitHealthMax = function(unit)
	if RealMobHealth then
		local cur, max = RealMobHealth.GetUnitHealth(unit)
		if max then return max end
	end
	return UnitHealthMax(unit)
end
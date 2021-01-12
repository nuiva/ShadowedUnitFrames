--[================[
LibCombatLogHealth-1.0
Author: d87
--]================]


local MAJOR, MINOR = "LibCombatLogHealth-1.0", 11
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib or lib.UnitHealth then
	return
end

local callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)

local frame = CreateFrame("Frame")

local errorThreshold = 100 -- If health error is larger, the cache is flushed
local healthDiffLifetime = 2 -- Time in seconds how long health diffs are considered valid
local unitLifetime = 60 -- Time in seconds until units are removed from memory

local function createClass(a)
	a.__index = a
	a.new = function(self, ...)
		local b = {}
		setmetatable(b, a)
		b:constructor(...)
		return b
	end
	return a
end

local HealthDifference = createClass({
	constructor = function(self, difference, timestamp)
		self.d = difference
		self.t = timestamp
	end,
})

local function getAllUnits()
	local a = {}
	a[UnitGUID("player")] = "player"
	if UnitExists("target") then
		a[UnitGUID("target")] = "target"
	end
	if IsInGroup() then
		local prefix = IsInRaid() and "raid" or "party"
		for i = 1,GetNumGroupMembers() do
			local u = prefix .. i
			a[UnitGUID(u)] = u
		end
	end
	return a
end

local Unit = createClass({
	constructor = function(self, unitId)
		self.guid = UnitGUID(unitId)
		self.lastHealth = UnitHealth(unitId)
		self.healthDiffs = {}
		self.lastSeen = GetTime()
	end,
	UNIT_HEALTH = function(self, unitId)
		local t = GetTime()
		self.lastSeen = t
		local newHealth = UnitHealth(unitId)
		local d = newHealth - self.lastHealth
		if d == 0 then
			return
		end
		self.lastHealth = newHealth
		local n = #self.healthDiffs
		local closest = {math.huge}
		for i = 1,n do
			if t - self.healthDiffs[i].t < healthDiffLifetime then -- Skip old entries, they should get eventually deleted below
				local sum = 0
				for j = i,n do
					sum = sum + self.healthDiffs[j].d
					local abs_error = math.abs(sum - d)
					if abs_error < closest[1] then
						closest = {abs_error, i, j}
					end
				end
			end
		end
		if closest[1] < errorThreshold then
			self.healthDiffs = {unpack(self.healthDiffs, closest[3]+1)}
		elseif math.abs(d) > errorThreshold then
			self.healthDiffs = {}
		end
		callbacks:Fire("COMBAT_LOG_HEALTH", unitId, "UNIT_HEALTH")
	end,
	COMBAT_LOG_EVENT_UNFILTERED = function(self, cleu)
		local handler = self.cleuHandlers[cleu[2]]
		if handler then
			handler(self, cleu)
		end
	end,
	addHealthDifference = function(self, difference, timestamp)
		self.lastSeen = GetTime()
		table.insert(self.healthDiffs, HealthDifference:new(difference, timestamp))
		self:fireClhCallbacks()
	end,
	purgeExpired = function(self)
		local t = GetTime()
		for i = 1,#self.healthDiffs do
			if t - self.healthDiffs[i].t < healthDiffLifetime then
				if i > 1 then
					self.healthDiffs = {unpack(self.healthDiffs, i)}
					self:fireClhCallbacks()
				end
				return
			end
		end
	end,
	fireClhCallbacks = function(self)
		for guid,unitId in pairs(getAllUnits()) do
			if guid == self.guid then
				callbacks:Fire("COMBAT_LOG_HEALTH", unitId)
			end
			return
		end
	end,
	getHealth = function(self, unitId)
		local h = UnitHealth(unitId)
		for _,healthDiff in pairs(self.healthDiffs) do
			h = h + healthDiff.d
		end
		return h
	end,
	cleuHandlers = {
		SWING_DAMAGE = function(self, cleu)
			self:addHealthDifference(-cleu[12], cleu[1])
		end,
		RANGE_DAMAGE = function(self, cleu)
			self:addHealthDifference(-cleu[15], cleu[1])
		end,
		SPELL_DAMAGE = function(self, cleu)
			self:addHealthDifference(-cleu[15], cleu[1])
		end,
		SPELL_HEAL = function(self, cleu)
			local d = cleu[15] - cleu[16] -- Remove overheal
			if d > 0 then
				self:addHealthDifference(d, cleu[1])
			end
		end,
		SPELL_PERIODIC_DAMAGE = function(self, cleu)
			self:addHealthDifference(-cleu[15], cleu[1])
		end,
		SPELL_PERIODIC_HEAL = function(self, cleu)
			local d = cleu[15] - cleu[16] -- Remove overheal
			if d > 0 then
				self:addHealthDifference(d, cleu[1])
			end
		end,
		ENVIRONMENTAL_DAMAGE = function(self, cleu)
			self:addHealthDifference(-cleu[13], cleu[1])
		end,
		DAMAGE_SPLIT = function(self, cleu)
			self:addHealthDifference(-cleu[15], cleu[1])
		end,
		DAMAGE_SHIELD = function(self, cleu)
			self:addHealthDifference(-cleu[15], cleu[1])
		end,
	},
})

local units = {
	add = function(self, unitId)
		local guid = UnitGUID(unitId)
		if self.units[guid] == nil then
			self.units[guid] = Unit:new(unitId)
		end
	end,
	purgeExpired = function(self)
		local t = GetTime()
		for _,unitId in pairs(getAllUnits()) do
			local guid = UnitGUID(unitId)
			local u = self.units[guid]
			if u then
				u.lastSeen = t
			end
		end
		local toRemove = {}
		for guid,u in pairs(self.units) do
			if t - u.lastSeen > unitLifetime then
				table.insert(toRemove, guid)
			else
				u:purgeExpired()
			end
		end
		for _,guid in pairs(toRemove) do
			self.units[guid] = nil
		end
	end,
	units = {},
}

frame.eventHandlers = {
	COMBAT_LOG_EVENT_UNFILTERED = function()
		local cleu = {CombatLogGetCurrentEventInfo()}
		local guid = cleu[8]
		local u = units.units[guid]
		if u then
			u:COMBAT_LOG_EVENT_UNFILTERED(cleu)
		end
	end,
	PLAYER_TARGET_CHANGED = function()
		if UnitExists("target") then
			units:add("target")
		end
	end,
	GROUP_ROSTER_UPDATE = function()
		if not IsInGroup() then
			return
		end
		local prefix = IsInRaid() and "raid" or "group"
		for i = 1,GetNumGroupMembers() do
			units:add(prefix .. i)
		end
	end,
	PLAYER_LOGIN = function()
		units:add("player")
	end,
	UNIT_HEALTH_FREQUENT = function(_, _, unitId)
		local guid = UnitGUID(unitId)
		local u = units.units[guid]
		if u then
			u:UNIT_HEALTH(unitId)
		end
	end,
}
frame:SetScript("OnEvent", function(self, event, ...)
	self.eventHandlers[event](self, event, ...)
end)
frame:SetScript("OnUpdate", function()
	units:purgeExpired()
end)

function lib.UnitHealth(unitId)
	local guid = UnitGUID(unitId)
	local u = units.units[guid]
	if u then
		return u:getHealth(unitId)
	end
	return UnitHealth(unitId)
end

-- function lib.RegisterUnit(unit)
    -- allowedUnits[unit] = true
-- end

function callbacks.OnUsed()
    frame:RegisterEvent"GROUP_ROSTER_UPDATE"
    frame:RegisterEvent"PLAYER_LOGIN"
	frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent"COMBAT_LOG_EVENT_UNFILTERED"
    frame:RegisterEvent"UNIT_HEALTH_FREQUENT"
	if UnitGUID("player") then
		frame.eventHandlers.PLAYER_LOGIN()
		frame.eventHandlers:GROUP_ROSTER_UPDATE()
	end
end

function callbacks.OnUnused()
    f:UnregisterAllEvents()
end
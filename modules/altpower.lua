local AltPower = {}
ShadowUF:RegisterModule(AltPower, "altPowerBar", ShadowUF.L["Alt. Power bar"], true)

function AltPower:OnEnable(frame)
	frame.altPowerBar = frame.altPowerBar or ShadowUF.Units:CreateBar(frame)

	frame:RegisterUnitEvent("UNIT_POWER", self, "Update")
	frame:RegisterUnitEvent("UNIT_MAXPOWER", self, "Update")
	frame:RegisterUnitEvent("UNIT_POWER_BAR_SHOW", self, "UpdateVisibility")
	frame:RegisterUnitEvent("UNIT_POWER_BAR_HIDE", self, "UpdateVisibility")
	frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", self, "UpdateVisibility")

	frame:RegisterUpdateFunc(self, "UpdateVisibility")
end

function AltPower:OnDisable(frame)
	frame:UnregisterAll(self)
end

local altColor = {}
function AltPower:UpdateVisibility(frame)
	local barType, minPower, _, _, _, hideFromOthers, showOnRaid = UnitAlternatePowerInfo(frame.unit)
	local visible = false
	if( barType ) then
		if( ( frame.unitType == "player" or frame.unitType == "pet" ) or not hideFromOthers ) then
			visible = true
		elseif( showOnRaid and ( UnitInRaid(frame.unit) or UnitInParty(frame.unit) ) ) then
			visible = true
		end
	end

	ShadowUF.Layout:SetBarVisibility(frame, "altPowerBar", visible)

	local color = ShadowUF.db.profile.powerColors.ALTERNATE
	if( not showOnRaid ) then
		local powerType, powerToken, altR, altG, altB = UnitPowerType(frame.unit)
		if( ShadowUF.db.profile.powerColors[powerToken] ) then
			color = ShadowUF.db.profile.powerColors[powerToken]
		elseif( altR ) then
			altColor.r, altColor.g, altColor.b = altR, altG, altB
			color = altColor
		else
			color = ShadowUF.db.profile.colors.MANA
		end
	end
	
	frame.altPowerBar:SetStatusBarColor(color.r, color.g, color.b, ShadowUF.db.profile.bars.alpha)


	AltPower:Update(frame, nil, nil, "ALTERNATE")
end

function AltPower:Update(frame, event, unit, type)
	if( type ~= "ALTERNATE" ) then return end

	frame.altPowerBar:SetMinMaxValues(select(2, UnitAlternatePowerInfo(frame.unit)) or 0, UnitPowerMax(frame.unit, ALTERNATE_POWER_INDEX) or 0)
	frame.altPowerBar:SetValue(UnitPower(frame.unit, ALTERNATE_POWER_INDEX) or 0)
end

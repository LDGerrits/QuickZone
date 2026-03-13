local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Lighting = game:GetService('Lighting')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedZones = require(ReplicatedStorage.Common.Zones)

local DEFAULTS = {
	Brightness = Lighting.Brightness,
	Ambient = Lighting.Ambient,
	FogEnd = Lighting.FogEnd,
	FogColor = Lighting.FogColor,
}

local PRESETS = {
	Lava = {
		Brightness = 1.5,
		Ambient = Color3.fromRGB(255, 100, 0),
		FogEnd = 80,
		FogColor = Color3.fromRGB(100, 20, 0),
	},
	ToxicGas = {
		Brightness = 0.7,
		Ambient = Color3.fromRGB(50, 200, 50),
		FogEnd = 150,
		FogColor = Color3.fromRGB(20, 60, 20),
	},
}

local function applyProps(props)
	for prop, value in props do
		Lighting[prop] = value
	end
end

local camera = workspace.CurrentCamera
local cameraGroup = QuickZone.Group.new({ entities = { camera } })

local cameraEffectsObserver = QuickZone.Observer.new({
	groups = { cameraGroup },
	updateRate = 60,
})

SharedZones.Lava:attach(cameraEffectsObserver)
SharedZones.ToxicGas:attach(cameraEffectsObserver)

cameraEffectsObserver:observe(function(entity, initialZone)
	local name = initialZone:getMetadata().Name
	applyProps(PRESETS[name] or DEFAULTS)

	local disconnectTransition = cameraEffectsObserver:onTransition(function(transitioningEntity, newZone)
		if transitioningEntity ~= entity then
			return
		end

		local newName = newZone:getMetadata().Name
		applyProps(PRESETS[newName] or DEFAULTS)
	end)

	return function()
		disconnectTransition()
		applyProps(DEFAULTS)
	end
end)

return nil

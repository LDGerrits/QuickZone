local ReplicatedStorage = game:GetService('ReplicatedStorage')
local TweenService = game:GetService('TweenService')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)
local SharedZones = require(ReplicatedStorage.Common.Zones)

local camera = workspace.CurrentCamera
local localPlayer = game:GetService('Players').LocalPlayer

local speedBoostObserver = QuickZone.Observer.new({
	groups = { SharedGroups.LocalPlayer },
	updateRate = 20,
})

SharedZones.SpeedBoost:attach(speedBoostObserver)

local DEFAULT_SPEED = 16
local DEFAULT_FOV = 70

local function getBoostData(zone)
	local part = zone:getReference()
	if part then
		return {
			WalkSpeed = part:GetAttribute('WalkSpeed') or 32,
			FOV = part:GetAttribute('FOV') or 90,
		}
	end
	return { WalkSpeed = 32, FOV = 90 }
end

speedBoostObserver:observeLocalPlayer(function(initialZone)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChild('Humanoid')
	if not humanoid then
		return
	end

	local function applyBoost(data)
		humanoid.WalkSpeed = data.WalkSpeed
		TweenService:Create(camera, TweenInfo.new(0.5), { FieldOfView = data.FOV }):Play()
	end

	applyBoost(getBoostData(initialZone))

	local disconnectTransition = speedBoostObserver:onLocalPlayerTransition(function(newZone)
		applyBoost(getBoostData(newZone))
	end)

	return function()
		disconnectTransition()

		if humanoid then
			humanoid.WalkSpeed = DEFAULT_SPEED
		end
		TweenService:Create(camera, TweenInfo.new(0.5), { FieldOfView = DEFAULT_FOV }):Play()
	end
end)

return nil

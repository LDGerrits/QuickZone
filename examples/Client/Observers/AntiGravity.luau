local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)
local SharedZones = require(ReplicatedStorage.Common.Zones)

local localPlayer = game:GetService('Players').LocalPlayer

local antiGravityObserver = QuickZone.Observer.new({
	updateRate = 20,
	groups = { SharedGroups.LocalPlayer },
})

SharedZones.AntiGravity:attach(antiGravityObserver)

RunService.PreSimulation:Connect(function(dt)
	local zone = antiGravityObserver:getZoneOfPlayer(localPlayer)
	if zone then
		local character = localPlayer.Character
		local hrp = character and character:FindFirstChild('HumanoidRootPart')
		if not hrp then
			return
		end

		local reference = zone:getReference()
		local gravityFactor = reference and reference:GetAttribute('Gravity')
		if not gravityFactor then
			return
		end

		local totalMass = hrp.AssemblyMass
		local upwardForce = totalMass * workspace.Gravity * (1 - gravityFactor)
		local upwardImpulse = Vector3.new(0, upwardForce * dt, 0)

		hrp:ApplyImpulse(upwardImpulse)
	end
end)

return nil

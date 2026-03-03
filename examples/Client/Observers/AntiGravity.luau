local ReplicatedStorage = game:GetService('ReplicatedStorage')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)
local SharedZones = require(ReplicatedStorage.Common.Zones)

local localPlayer = game:GetService('Players').LocalPlayer

local antiGravityObserver = QuickZone.Observer.new({
	updateRate = 20,
	groups = { SharedGroups.LocalPlayer },
})

SharedZones.AntiGravity:attach(antiGravityObserver)

antiGravityObserver:observeLocalPlayer(function()
	local character = localPlayer.Character
	local hrp = character and character:FindFirstChild('HumanoidRootPart')
	if not hrp then
		return
	end

	local force = Instance.new('BodyForce')
	force.Name = 'AntiGravityForce'

	local totalMass = 0
	for _, part in character:GetDescendants() do
		if part:IsA('BasePart') then
			totalMass += part:GetMass()
		end
	end

	force.Force = Vector3.new(0, totalMass * workspace.Gravity * 0.6, 0)
	force.Parent = hrp

	return function()
		force:Destroy()
	end
end)

return nil

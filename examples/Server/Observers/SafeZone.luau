local ReplicatedStorage = game:GetService('ReplicatedStorage')
local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)

local safeZonePart = workspace:WaitForChild('SafeZone')

local safeZone = QuickZone.Zone.fromPart(safeZonePart)

local safeObserver = QuickZone.Observer.new({
	groups = { SharedGroups.Players },
	zones = { safeZone },
	updateRate = 10,
	priority = 100, -- Higher priority than the HazardsObserver, so a player is always safe here from hazards!
})

safeObserver:observe(function(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChild('Humanoid')

	local forceField = Instance.new('ForceField')
	forceField.Parent = character

	if humanoid and humanoid.Health < 100 then
		humanoid.Health = 100
		print('Health restored to 100')
	end

	return function()
		if forceField and forceField.Parent then
			forceField:Destroy()
		end
	end
end)

return nil

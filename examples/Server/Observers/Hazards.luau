local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)
local SharedZones = require(ReplicatedStorage.Common.Zones)

local hazardObserver = QuickZone.Observer.new({
	groups = { SharedGroups.Players },
	zones = { SharedZones.Lava, SharedZones.ToxicGas },
	updateRate = 20,
	priority = 0,
})

RunService.Heartbeat:Connect(function(dt)
	for player, zone in hazardObserver:iterPlayersInside() do
		local character = player.Character
		local humanoid = character and character:FindFirstChild('Humanoid')

		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local metadata = zone:getMetadata() or {}
		local dps = metadata.Damage
		if not dps then
			continue
		end

		humanoid:TakeDamage(dps * dt)

		if humanoid.Health <= 0 then
			local hazardName = metadata.Name or 'Unknown Hazard'
			print(player.Name .. ' died in the ' .. hazardName .. '!')
		end
	end
end)

return nil

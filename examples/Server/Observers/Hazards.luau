local ReplicatedStorage = game:GetService('ReplicatedStorage')

local QuickZone = require(ReplicatedStorage.QuickZone)
local SharedGroups = require(ReplicatedStorage.Common.Groups)
local SharedZones = require(ReplicatedStorage.Common.Zones)

local hazardObserver = QuickZone.Observer.new({
	groups = { SharedGroups.Players },
	updateRate = 20,
	priority = 0,
})

SharedZones.Lava:attach(hazardObserver)
SharedZones.ToxicGas:attach(hazardObserver)

hazardObserver:observePlayer(function(player, zone)
	local metadata = zone:getMetadata() or {}
	local dmg = metadata.Damage or 10
	local tickRate = metadata and metadata.TickRate or 1
	local hazardName = metadata and metadata.HazardName or 'Unknown Hazard'
	local active = true

	local character = player.Character
	local humanoid = character and character:FindFirstChild('Humanoid')
	if not humanoid then
		return
	end

	local deathConn = humanoid.Died:Connect(function()
		active = false
		print(player.Name .. ' died to ' .. hazardName .. '!')
	end)

	local currentThread = nil
	local function applyCurrentHazard()
		if currentThread then
			task.cancel(currentThread)
			currentThread = nil
		end

		if tickRate <= 0 then
			humanoid:TakeDamage(dmg)
		else
			currentThread = task.spawn(function()
				while active and humanoid.Health > 0 do
					humanoid:TakeDamage(dmg)
					task.wait(tickRate)
				end
			end)
		end
	end

	applyCurrentHazard()
	print(player.Name .. ' stepped into ' .. hazardName .. '!')

	local transitionCleanup = hazardObserver:onPlayerTransition(function(newPlayer, newZone)
		if player ~= newPlayer then
			return
		end
		if not active then
			return
		end

		metadata = newZone:getMetadata() or {}
		dmg = metadata.Damage or 10
		tickRate = metadata.TickRate or 1
		hazardName = metadata.HazardName or 'Unknown Hazard'

		print(player.Name .. ' transitioned into ' .. hazardName .. '!')
		applyCurrentHazard()
	end)

	return function()
		active = false

		deathConn:Disconnect()
		transitionCleanup()
		if currentThread then
			task.cancel(currentThread)
		end

		if humanoid.Health > 0 then
			print(player.Name .. ' escaped the ' .. hazardName .. '!')
		end
	end
end)

return nil

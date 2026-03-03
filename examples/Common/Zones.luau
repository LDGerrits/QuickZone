local RunService = game:GetService('RunService')

local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Zone = QuickZone.Zone

--[=[
	Define zones here if they trigger effects across multiple scripts
	(e.g., "Lava" deals damage on the server, but changes lighting on the client).
	By sharing zones across scripts, you keep the LBVH small!

	For single-purpose zones, just create the Zone locally inside its respective script.
]=]
local Zones = {
	Lava = Zone.fromTag('Lava', {
		metadata = { PresetName = 'Lava', Damage = 50, TickRate = 0, HazardName = 'Scorching Lava' },
	}),
	ToxicGas = Zone.fromTag('ToxicGas', {
		metadata = { PresetName = 'ToxicGas', Damage = 2, TickRate = 0.1, HazardName = 'Toxic Gas' },
	}),
}

if RunService:IsClient() then
	Zones.SpeedBoost = Zone.fromChildren(workspace:WaitForChild('SpeedBoosts'))
	Zones.AntiGravity = Zone.fromChildren(workspace:WaitForChild('AntiGravZones'))
end

return Zones

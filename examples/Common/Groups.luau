local RunService = game:GetService('RunService')

local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Group = QuickZone.Group

--[=[
	Put groups here only if they need to be accessed by multiple scripts.
	(e.g., The "Players" group is used by Hazards, SafeZones, and Disco).
]=]
local Groups = {
	Players = Group.players(),
}

if RunService:IsClient() then
	Groups.LocalPlayer = Group.localPlayer()
end

return Groups

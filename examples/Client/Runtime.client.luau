while not game:IsLoaded() do
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService('ReplicatedStorage')

local QuickZone = require(ReplicatedStorage.QuickZone)
QuickZone:configure({
	enabled = true,
	autoSyncRate = 0,
	frameBudget = 1,
})

for _, moduleScript: ModuleScript in script.Parent.Observers:GetChildren() do
	require(moduleScript)
end

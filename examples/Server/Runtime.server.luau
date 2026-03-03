local ReplicatedStorage = game:GetService('ReplicatedStorage')

local QuickZone = require(ReplicatedStorage.QuickZone)
QuickZone:configure({
	enabled = true,
	autoSyncRate = 30,
	frameBudget = 1,
})

for _, moduleScript: ModuleScript in script.Parent.Observers:GetChildren() do
	require(moduleScript)
end

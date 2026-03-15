local ReplicatedStorage = game:GetService('ReplicatedStorage')

local QuickZone = require(ReplicatedStorage.QuickZone)
QuickZone:configure({
	enabled = true,
	autoSyncRate = 30,
	frameBudget = 1,
})

for _, instance in script.Parent.Observers:GetChildren() do
	if instance:IsA('ModuleScript') then
		require(instance)
	end
end

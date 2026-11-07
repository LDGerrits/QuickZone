--!strict

-- Follows the instances that have a tag, for the fromTag constructors

local CollectionService = game:GetService('CollectionService')

local TagWatcher = {}

-- Calls onChange when an instance gets the tag and each time its ancestry changes, and onRemoved when it loses the
-- tag or the watch stops. Only instances accept passes are followed, but onRemoved hears of every instance losing
-- the tag. Returns the function that stops the watch
function TagWatcher.watch(
	tag: string,
	accept: ((instance: Instance) -> boolean)?,
	onChange: (instance: Instance) -> (),
	onRemoved: (instance: Instance) -> ()
): () -> ()
	local watching = {} :: { [Instance]: RBXScriptConnection }

	local function startWatching(instance: Instance)
		if watching[instance] or (accept and not accept(instance)) then
			return
		end
		watching[instance] = instance.AncestryChanged:Connect(function()
			onChange(instance)
		end)
		onChange(instance)
	end

	local function stopWatching(instance: Instance)
		local conn = watching[instance]
		if conn then
			conn:Disconnect()
			watching[instance] = nil
		end
		onRemoved(instance)
	end

	local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(startWatching)
	local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(stopWatching)
	for _, instance in CollectionService:GetTagged(tag) do
		startWatching(instance)
	end

	return function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for instance in watching do
			stopWatching(instance)
		end
	end
end

return TagWatcher

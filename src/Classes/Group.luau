--!strict

local CollectionService = game:GetService('CollectionService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)
local State = require(script.Parent.Parent.Core.State)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

local DEFAULT_PRECISION_SQ = Config.Observer.precision ^ 2

local IS_CLIENT = RunService:IsClient()

local function trackPlayer(group: Types.InternalGroup<any>, player: Player, trackerStore: { [Player]: () -> () })
	if trackerStore[player] then
		return
	end

	local charConns: { RBXScriptConnection } = {}
	local currentHrp: BasePart? = nil

	local function cleanCharacter()
		if currentHrp then
			group:_remove(currentHrp)
			State.entityToReference[currentHrp] = nil
			State.referenceToEntity[player] = nil
			currentHrp = nil
		end
		for _, c in charConns do
			c:Disconnect()
		end
		table.clear(charConns)
	end

	local function onCharAdded(character: Model)
		cleanCharacter()

		task.spawn(function()
			local hrp = character:WaitForChild('HumanoidRootPart', 5)

			if not hrp or not player:IsDescendantOf(Players) then
				return
			end

			if player.Character ~= character then
				return
			end

			if hrp:IsA('BasePart') then
				currentHrp = hrp

				State.entityToReference[hrp] = player
				State.referenceToEntity[player] = hrp

				group:_add(player)

				table.insert(
					charConns,
					hrp.Destroying:Connect(function()
						cleanCharacter()
					end)
				)
			end
		end)
	end

	local addedConn = player.CharacterAdded:Connect(onCharAdded)

	local removingConn = player.CharacterRemoving:Connect(function(character)
		if currentHrp and currentHrp.Parent == character then
			cleanCharacter()
		end
	end)

	trackerStore[player] = function()
		addedConn:Disconnect()
		removingConn:Disconnect()
		cleanCharacter()
	end

	if player.Character then
		onCharAdded(player.Character)
	end
end

local function untrackPlayer(player: Player, trackerStore: { [Player]: () -> () })
	local cleanup = trackerStore[player]
	if cleanup then
		cleanup()
		trackerStore[player] = nil
	end
end

--[=[ 
	Groups represent a collection of entities that should be tracked by the system.

	:::info Observer
	Every entity must be in a group to be observed.
	:::

	@class Group
]=]
local Group = {}
Group.__index = Group

--[=[ 
	Creates a generic Group. 
	Groups manage collections of Entities (any instance with a position in the world like BaseParts, Models, Attachments, etc.) that Observers should track.

	```lua
	local myGroup = Group.new({
		entities = { NPC1, NPC2, NPC3 }, -- Add entities
		autoClean = true, -- Entities in group are cleaned up when entities are destroyed
	})
	```

	@tag Constructor
	@param config { entities: { T }?, autoClean: boolean? }?
	@return Group
]=]
function Group.new<T>(config: {
	entities: { T }?,
	autoClean: boolean?,
}?): Types.Group<T>
	local id = State.nextGroupId
	State.nextGroupId += 1

	local autoClean = Config.Group.autoClean
	if config and config.autoClean ~= nil then
		autoClean = config.autoClean
	end

	local self: Types.InternalGroup<T> = setmetatable({
		id = id,
		entities = {},
		entityIndices = {},
		autoClean = autoClean,
	}, Group) :: any

	State.groups[id] = self
	State.groupToObservers[id] = {}
	State.groupEntityCleanups[id] = {}

	if config and config.entities then
		self:_addBulk(config.entities)
	end

	return self
end

--[=[ 
	Creates a dynamic Group that automatically tracks all instances with a specific tag.
	Instances are only tracked while they are descendants of the Workspace.

	@tag Constructor
	@param tag string
	@return Group
]=]
function Group.fromTag(tag: string): Types.Group<Types.Entity>
	local group = Group.new({ autoClean = false }) :: Types.InternalGroup<Types.Entity>
	group.isManaged = true

	local watchingInstances = {} :: { [Instance]: RBXScriptConnection }

	local function checkAncestry(instance: BasePart | Model | Attachment | Bone | Camera)
		if instance:IsDescendantOf(workspace) then
			group:_add(instance)
		else
			group:_remove(instance)
		end
	end

	local function startWatching(instance: Instance)
		if watchingInstances[instance] then
			return
		end

		if
			not (
				instance:IsA('BasePart')
				or instance:IsA('Model')
				or instance:IsA('Attachment')
				or instance:IsA('Bone')
				or instance:IsA('Camera')
			)
		then
			return
		end

		watchingInstances[instance] = instance.AncestryChanged:Connect(function()
			checkAncestry(instance)
		end)

		checkAncestry(instance)
	end

	local function stopWatching(instance: Instance)
		local conn = watchingInstances[instance]
		if conn then
			conn:Disconnect()
			watchingInstances[instance] = nil
		end
		group:_remove(instance :: any)
	end

	local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(startWatching)
	local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(stopWatching)

	for _, instance in CollectionService:GetTagged(tag) do
		startWatching(instance)
	end

	group:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for instance, _ in watchingInstances do
			stopWatching(instance)
		end
	end)

	return group
end

--[=[ 
	Returns a Group that automatically tracks all Players in the server.

	:::info Behavior
	* Automatically tracks the `HumanoidRootPart` of every player.
	* Handles `PlayerAdded` and `CharacterAdded` internally.
	:::

	@tag Constructor
	@return Group
]=]
function Group.players(): Types.Group<Player>
	local group = Group.new({ autoClean = false }) :: Types.InternalGroup<Player>
	group.isManaged = true

	local trackerStore = {} :: { [Player]: () -> () }
	local mainConnections = {} :: { RBXScriptConnection }

	table.insert(
		mainConnections,
		Players.PlayerAdded:Connect(function(player)
			trackPlayer(group, player, trackerStore)
		end)
	)

	table.insert(
		mainConnections,
		Players.PlayerRemoving:Connect(function(player)
			untrackPlayer(player, trackerStore)
		end)
	)

	for _, player in Players:GetPlayers() do
		trackPlayer(group, player, trackerStore)
	end

	group:onDestroy(function()
		for _, conn in mainConnections do
			conn:Disconnect()
		end
		for _, cleanup in trackerStore do
			cleanup()
		end

		table.clear(mainConnections)
		table.clear(trackerStore)
	end)

	return group
end

--[=[ 
	Returns a Group that tracks only the LocalPlayer.

	:::info Behavior
	* Automatically tracks the `HumanoidRootPart` of the local player.
	* Handles `CharacterAdded` internally.
	:::

	@client
	@tag Constructor
	@return Group
]=]
function Group.localPlayer(): Types.Group<Player>
	assert(IS_CLIENT, '[QuickZone] QuickZone.LocalPlayerGroup can only be called on the Client.')

	local group = Group.new({ autoClean = false }) :: Types.InternalGroup<Player>
	group.isManaged = true

	local lp = Players.LocalPlayer
	local trackers = {}

	trackPlayer(group, lp, trackers)

	group:onDestroy(function()
		untrackPlayer(lp, trackers)
	end)

	return group
end

--[=[ 
	Enables or disables automatic cleanup for Instances in this group.
	When enabled, if an Instance is Destroyed() or parented to nil, it will be 
	automatically removed from this group.

	@method setAutoClean
	@within Group
	@param enabled boolean
	@return Group
]=]
function Group.setAutoClean(self: Types.InternalGroup<any>, enabled: boolean): Types.Group<any>
	if self.isManaged then
		warn(`[QuickZone] Cannot set autoClean on a Managed Group.`)
		return self
	end

	if self.autoClean == enabled then
		return self
	end

	self.autoClean = enabled
	local cleanups = State.groupEntityCleanups[self.id]

	if enabled then
		for _, entity in self.entities do
			if typeof(entity) == 'Instance' and not cleanups[entity] then
				cleanups[entity] = (entity :: Instance).AncestryChanged:Connect(function(_, parent)
					if not parent then
						self:_remove(entity)
					end
				end)
			end
		end
	else
		for entity, conn in cleanups do
			conn:Disconnect()
			cleanups[entity] = nil
		end
	end

	return self
end

--[=[ 
	Adds an entity to the group. If the entity is already in another group, 
	it is automatically removed from the old one first.

	#### Example: Adding Different Entity Types
	```lua
	-- Adding a BasePart and a Model
	myGroup:add(workspace.Part):add(workspace.NPCModel)

	-- Adding a custom table
	local spell = {
		CFrame = CFrame.new(0, 10, 0),
		Name = 'Fireball'
	}
	myGroup:add(spell)
	```

	:::info Strategy Detection
	QuickZone automatically determines how to track the entity's position:
	* **BasePart:** Uses `Position`
	* **Model:** Uses `PrimaryPart.Position` or `GetPivot()`
	* **Attachment/Bone:** Uses `WorldPosition`
	* **Camera:** Uses `CFrame`
	* **Table:** Looks for `.Position`, `.CFrame`, `.WorldPosition`, or `:GetPivot()`.
	:::

	@method add
	@within Group
	@param entity any -- The object to track.
	@return Group
]=]
function Group.add(self: Types.InternalGroup<any>, entity: any): Types.Group<any>
	if self.isManaged then
		warn(`[QuickZone] Cannot manually add to a Managed Group.`)
		return self
	end
	return self:_add(entity)
end

--[=[ 
	Adds multiple entities to the group.

	```lua
	-- Add an entire folder of NPCs at once
	myGroup:addBulk(workspace.Enemies:GetChildren())
	```

	@method addBulk
	@within Group
	@param entities { any } -- Array of entities to add.
	@return Group
]=]
function Group.addBulk(self: Types.InternalGroup<any>, entities: { any }): Types.Group<any>
	if self.isManaged then
		warn(`[QuickZone] Cannot manually addBulk from a Managed Group.`)
		return self
	end
	return self:_addBulk(entities)
end

--[=[ 
	Removes the entity from the group.

	@method remove
	@within Group
	@param entity any
	@return Group
]=]
function Group.remove(self: Types.InternalGroup<any>, entity: any): Types.Group<any>
	if self.isManaged then
		warn(`[QuickZone] Cannot manually remove from a Managed Group.`)
		return self
	end
	return self:_remove(entity)
end

--[=[ 
	Removes multiple entities from the group.
	
	@method removeBulk
	@within Group
	@param entities { any }
	@return Group
]=]
function Group.removeBulk(self: Types.InternalGroup<any>, entities: { any }): Types.Group<any>
	if self.isManaged then
		warn(`[QuickZone] Cannot manually removeBulk from a Managed Group.`)
		return self
	end
	return self:_removeBulk(entities)
end

--[=[ 
	Removes all entities from the group.
	This fires 'onExit' events for every entity currently inside a zone.

	@method clear
	@within Group
	@return Group
]=]
function Group.clear(self: Types.InternalGroup<any>): Types.Group<any>
	if self.isManaged then
		warn(`[QuickZone] Cannot clear from a Managed Group.`)
		return self
	end
	return self:_clear()
end

--[=[ 
	Checks if a specific entity is currently a member of this group.

	@method contains
	@within Group
	@param entity any
	@return boolean
]=]
function Group.contains(self: Types.InternalGroup<any>, entity: any): boolean
	entity = State.referenceToEntity[entity] or entity
	local groups = State.entityToGroups[entity]
	return groups and groups[self.id] == true or false
end

--[=[ 
	Returns the unique internal ID of the group.

	@method getId
	@within Group
	@return number
]=]
function Group.getId(self: Types.InternalGroup<any>): number
	return self.id
end

--[=[ 
	Returns a list of all entities currently belonging to the group.

	@method getEntities
	@within Group
	@return { any }
]=]
function Group.getEntities(self: Types.InternalGroup<any>): { any }
	local result = table.create(#self.entities)
	for i, entity in ipairs(self.entities) do
		result[i] = State.entityToReference[entity] or entity
	end
	return result
end

--[=[ 
	Returns a list of all Players currently represented in the group.

	@method getPlayers
	@within Group
	@return { Player }
]=]
function Group.getPlayers(self: Types.InternalGroup<any>): { Player }
	local result = {}
	for entity in self.entityIndices do
		local ref = State.entityToReference[entity] or entity
		if typeof(ref) == 'Instance' and ref:IsA('Player') then
			table.insert(result, ref)
		end
	end
	return result
end

--[=[ 
	Iterates over all entities currently belonging to the group.
	Provides a zero-allocation way to loop through entities, ideal for high-frequency 
	checks.

	```lua
	for entity in myGroup:iterEntities() do
		print(entity.Name .. " is in the group!")
	end
	```

	@method iterEntities
	@within Group
	@return () -> any?
]=]
function Group.iterEntities(self: Types.InternalGroup<any>): () -> any?
	local entity = nil

	return function()
		entity = next(self.entityIndices, entity)
		if entity then
			return State.entityToReference[entity] or entity
		end
		return entity
	end
end

--[=[ 
	Iterates over all players currently represented in the group.

	@method iterPlayers
	@within Group
	@return () -> Player?
]=]
function Group.iterPlayers(self: Types.InternalGroup<any>): () -> Player?
	local entity = nil

	return function()
		while true do
			entity = next(self.entityIndices, entity)

			if not entity then
				return nil
			end

			local ref = State.entityToReference[entity] or entity
			if typeof(ref) == 'Instance' and ref:IsA('Player') then
				return ref
			end
		end
	end
end

--[=[ 
	Fires when `destroy()` is called on the group.

	```lua
	local disconnect = myGroup:onDestroy(function()
		print('Group was destroyed!')
	end)
	```

	@tag Event
	@method onDestroy
	@within Group
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Group.onDestroy(self: Types.InternalGroup<any>, callback: () -> ()): () -> ()
	if not self.onDestroyCallbacks then
		self.onDestroyCallbacks = {}
	end

	table.insert(self.onDestroyCallbacks :: any, callback)

	return function()
		local idx = table.find(self.onDestroyCallbacks :: any, callback)
		if idx then
			table.remove(self.onDestroyCallbacks :: any, idx)
		end
	end
end

--[=[ 
	Cleans up the group, removes all tracked entities, and detaches any 
	associated observers.
	
	@tag Destructor
	@method destroy
	@within Group
]=]
function Group.destroy(self: Types.InternalGroup<any>): ()
	if self.onDestroyCallbacks then
		for _, callback in self.onDestroyCallbacks do
			task.spawn(callback)
		end
		table.clear(self.onDestroyCallbacks)
	end

	for idx = #self.entities, 1, -1 do
		self:_remove(self.entities[idx])
	end

	State.groupToObservers[self.id] = nil
	State.groups[self.id] = nil

	setmetatable(self :: any, nil)
end

function Group._add(self: Types.InternalGroup<any>, entity: any): Types.Group<any>
	entity = State.referenceToEntity[entity] or entity

	if not State.entityToGroups[entity] then
		State.entityToGroups[entity] = {}
	end

	if State.entityToGroups[entity][self.id] then
		return self
	end

	State.entityToGroups[entity][self.id] = true

	if not State.entityData[entity] then
		local strat
		if typeof(entity) == 'Instance' then
			if entity:IsA('BasePart') then
				strat = STRAT_POS
			elseif entity:IsA('Attachment') or entity:IsA('Bone') then
				strat = STRAT_WORLD
			elseif entity:IsA('Camera') then
				strat = STRAT_CFRAME
			elseif entity:IsA('Model') then
				strat = entity.PrimaryPart and STRAT_PRIM or STRAT_PIVOT
			end
		elseif typeof(entity) == 'table' then
			if entity.Position then
				strat = STRAT_POS
			elseif entity.CFrame then
				strat = STRAT_CFRAME
			elseif entity.WorldPosition then
				strat = STRAT_WORLD
			elseif entity.GetPivot then
				strat = STRAT_PIVOT
			end
		end

		if not strat then
			warn(
				string.format(
					'[QuickZone] Invalid entity (%s). Expected BasePart, Model, Bone, Attachment, Camera, an EntityTable, or a reference to such an object.',
					tostring(entity)
				)
			)
			State.entityToGroups[entity][self.id] = nil
			return self
		end

		State.entityData[entity] = {
			strategy = strat,
			lastPosition = Vector3.zero,
			activeObserverMemberships = {},
			precisionSq = DEFAULT_PRECISION_SQ,
			updateRate = -1,
			bucketIndex = 0,
			dynamicVersion = 0,
			staticVersion = 0,
			logicVersion = 0,
			needsStatic = false,
			needsDynamic = false,
		}
	end

	local idx = #self.entities + 1
	self.entities[idx] = entity
	self.entityIndices[entity] = idx

	State.dirtyProfiles[entity] = true
	State.dirtyTopology[entity] = true

	if self.autoClean and typeof(entity) == 'Instance' and not State.groupEntityCleanups[self.id][entity] then
		State.groupEntityCleanups[self.id][entity] = (entity :: Instance).AncestryChanged:Connect(function(_, parent)
			if not parent then
				self:_remove(entity)
			end
		end)
	end

	return self
end

function Group._addBulk(self: Types.InternalGroup<any>, entities: { any }): Types.Group<any>
	for _, entity in entities do
		self:_add(entity)
	end
	return self
end

function Group._remove(self: Types.InternalGroup<any>, entity: any): Types.Group<any>
	entity = State.referenceToEntity[entity] or entity

	if not State.entityToGroups[entity] or not State.entityToGroups[entity][self.id] then
		return self
	end

	local cleanupConn = State.groupEntityCleanups[self.id][entity]
	if cleanupConn then
		cleanupConn:Disconnect()
		State.groupEntityCleanups[self.id][entity] = nil
	end

	State.entityToGroups[entity][self.id] = nil
	local data = State.entityData[entity]

	local idx = self.entityIndices[entity]
	local lastIdx = #self.entities
	if idx == lastIdx then
		self.entities[lastIdx] = nil
		self.entityIndices[entity] = nil
	else
		local lastEntity = self.entities[lastIdx]
		self.entities[idx] = lastEntity
		self.entityIndices[lastEntity] = idx
		self.entities[lastIdx] = nil
		self.entityIndices[entity] = nil
	end

	State.dirtyProfiles[entity] = true
	State.dirtyTopology[entity] = true

	for observerId, oldZoneId in data.activeObserverMemberships do
		local stillTracked = false
		for remainingGroupId in State.entityToGroups[entity] do
			if State.groupToObservers[remainingGroupId] and State.groupToObservers[remainingGroupId][observerId] then
				stillTracked = true
				break
			end
		end

		if stillTracked then
			continue
		end

		data.activeObserverMemberships[observerId] = nil

		if State.observerTrackingEntities[observerId] then
			State.observerTrackingEntities[observerId][entity] = nil
		end

		local cbs = State.observerExitedCallbacks[observerId]
		if not cbs then
			continue
		end

		local safety = State.observerSafety[observerId]
		local z = State.zoneIdToZoneObj[oldZoneId]
		local ref = State.entityToReference[entity] or entity

		for _, fn in cbs do
			if safety then
				task.spawn(fn, ref, z)
			else
				fn(ref, z)
			end
		end
	end

	if next(State.entityToGroups[entity]) == nil then
		-- Remove from bucket
		local currentRate = data.updateRate
		if currentRate and currentRate > 0 and State.buckets[currentRate] then
			local bucket = State.buckets[currentRate]
			local bucketIdx = data.bucketIndex
			local maxEntities = #bucket
			local lastEntity = bucket[maxEntities]

			-- We swap and then pop to avoid shifting all entities down
			if bucketIdx ~= maxEntities then
				bucket[bucketIdx] = lastEntity
				if State.entityData[lastEntity] then
					State.entityData[lastEntity].bucketIndex = bucketIdx
				end
			end

			bucket[maxEntities] = nil
		end

		State.entityData[entity] = nil
		State.entityToGroups[entity] = nil
		State.entityToObservers[entity] = nil
		State.dirtyProfiles[entity] = nil
		State.dirtyTopology[entity] = nil
	end

	return self
end

function Group._removeBulk(self: Types.InternalGroup<any>, entities: { any }): Types.Group<any>
	for _, entity in entities do
		self:_remove(entity)
	end
	return self
end

function Group._clear(self: Types.InternalGroup<any>): Types.Group<any>
	-- Iterate backwards for safe removal
	local entities = self.entities
	for idx = #entities, 1, -1 do
		self:_remove(entities[idx])
	end
	return self
end

return Group

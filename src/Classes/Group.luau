--!strict

local CollectionService = game:GetService('CollectionService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)
local updateProfile = require(script.Parent.Parent.Core.updateProfile)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

local DEFAULT_PRECISION_SQ = Config.Observer.precision ^ 2
local DEFAULT_UPDATE_RATE = Config.Observer.updateRate

local IS_CLIENT = RunService:IsClient()

local function trackPlayer(group: Types.Group, player: Player, trackerStore: { [Player]: () -> () })
	if trackerStore[player] then
		return
	end

	local charConns: { RBXScriptConnection } = {}
	local currentHrp: BasePart? = nil

	local function cleanCharacter()
		if currentHrp then
			group:remove(currentHrp)
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
			local hrp = character:WaitForChild('HumanoidRootPart')

			if not hrp or not player:IsDescendantOf(Players) then
				return
			end

			if player.Character ~= character then
				return
			end

			if hrp:IsA('BasePart') then
				currentHrp = hrp
				State.entityToPlayer[hrp] = player
				group:add(hrp)

				table.insert(
					charConns,
					hrp.AncestryChanged:Connect(function(_, parent)
						if not parent then
							cleanCharacter()
						end
					end)
				)
			end
		end)
	end

	local addedConn = player.CharacterAdded:Connect(onCharAdded)

	trackerStore[player] = function()
		addedConn:Disconnect()
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
		entities = { NPC1, NPC2, NPC3 } -- Add entities
	})
	```

	@tag Constructor
	@param config { updateRate: number?, precision: number?, entities: { Types.Entity }? }?
	@return Group
]=]
function Group.new(config: {
	entities: { Types.Entity }?,
}?): Types.Group
	local id = State.nextGroupId
	State.nextGroupId += 1

	local self: Types.InternalGroup = setmetatable({
		id = id,
		entities = {},
		entityIndices = {},
	}, Group) :: any

	State.groups[id] = self
	State.groupToObservers[id] = {}

	if config and config.entities then
		self:addBulk(config.entities)
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
function Group.fromTag(
	tag: string,
	config: {
		entities: { Types.Entity }?,
	}?
): Types.Group
	local group = Group.new(config)

	local watchingInstances = {} :: { [Instance]: RBXScriptConnection }

	local function checkAncestry(instance: BasePart | Model | Attachment | Bone | Camera)
		if instance:IsDescendantOf(workspace) then
			group:add(instance)
		else
			group:remove(instance)
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
		group:remove(instance :: any)
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
	@param config { updateRate: number?, precision: number?, entities: { Types.Entity }? }?
	@return Group
]=]
function Group.players(config: {
	entities: { Types.Entity }?,
}?): Types.Group
	local group = Group.new(config)

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
	@param config { updateRate: number?, precision: number?, entities: { Types.Entity }? }?
	@return Group
]=]
function Group.localPlayer(config: {
	entities: { Types.Entity }?,
}?): Types.Group
	assert(IS_CLIENT, '[QuickZone] QuickZone.LocalPlayerGroup can only be called on the Client.')

	local group = Group.new(config)

	local lp = Players.LocalPlayer
	local trackers = {}

	trackPlayer(group, lp, trackers)

	group:onDestroy(function()
		untrackPlayer(lp, trackers)
	end)

	return group
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
	@param entity Entity -- The object to track.
	@return Group
]=]
function Group.add(self: Types.InternalGroup, entity: Types.Entity): Types.Group
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
					'[QuickZone] Invalid entity (%s). Expected BasePart, Model, Bone, Attachment, Camera, or an EntityTable.',
					tostring(entity)
				)
			)
			State.entityToGroups[entity][self.id] = nil
			return self
		end

		State.entityData[entity] = {
			strategy = strat,
			lastPosition = Vector3.zero,
			lastSpatialVersion = 0,
			activeObserverMemberships = {},
			precisionSq = DEFAULT_PRECISION_SQ,
			updateRate = DEFAULT_UPDATE_RATE,
			bucketIndex = 0,
		}
	end

	local idx = #self.entities + 1
	self.entities[idx] = entity
	self.entityIndices[entity] = idx

	updateProfile(entity)

	return self
end

--[=[ 
	Adds multiple entities to the group.

	```lua
	-- Add an entire folder of NPCs at once
	myGroup:addBulk(workspace.Enemies:GetChildren())
	```

	@method addBulk
	@within Group
	@param entities { Entity } -- Array of entities to add.
	@return Group
]=]
function Group.addBulk(self: Types.InternalGroup, entities: { Types.Entity }): Types.Group
	for _, entity in entities do
		self:add(entity)
	end
	return self
end

--[=[ 
	Removes the entity from the group.

	@method remove
	@within Group
	@param entity Entity
	@return Group
]=]
function Group.remove(self: Types.InternalGroup, entity: Types.Entity): Types.Group
	if not State.entityToGroups[entity] or not State.entityToGroups[entity][self.id] then
		return self
	end

	State.entityToGroups[entity][self.id] = nil
	local data = State.entityData[entity]

	local idx = self.entityIndices[entity]
	local lastIdx = #self.entities
	local lastEntity = self.entities[lastIdx]

	if idx == lastIdx then
		self.entities[lastIdx] = nil
		self.entityIndices[entity] = nil
	else
		self.entities[idx] = lastEntity
		self.entityIndices[lastEntity] = idx
		self.entities[lastIdx] = nil
		self.entityIndices[entity] = nil
	end

	updateProfile(entity)

	local activeObservers = State.entityToObservers[entity] or {}

	for observerId, oldZoneId in data.activeObserverMemberships do
		if not activeObservers[observerId] then
			data.activeObserverMemberships[observerId] = nil
			if State.observerTrackingEntities[observerId] then
				State.observerTrackingEntities[observerId][entity] = nil
			end

			local cbs = State.observerExitedCallbacks[observerId]
			if cbs then
				local safety = State.observerSafety[observerId]
				local z = State.zoneIdToZoneObj[oldZoneId]
				for _, fn in cbs do
					if safety then
						task.spawn(fn, entity, z)
					else
						fn(entity, z)
					end
				end
			end
		end
	end

	if next(State.entityToGroups[entity]) == nil then
		State.entityData[entity] = nil
		State.entityToGroups[entity] = nil
		State.entityToObservers[entity] = nil
		State.entityToPlayer[entity] = nil
	end

	return self
end

--[=[ 
	Removes multiple entities from the group.
	
	@method removeBulk
	@within Group
	@param entities { Entity }
	@return Group
]=]
function Group.removeBulk(self: Types.InternalGroup, entities: { Types.Entity }): Types.Group
	for _, entity in entities do
		self:remove(entity)
	end
	return self
end

--[=[ 
	Removes all entities from the group.
	This fires 'onExited' events for every entity currently inside a zone.

	@method clear
	@within Group
	@return Group
]=]
function Group.clear(self: Types.InternalGroup): Types.Group
	-- Iterate backwards for safe removal
	local entities = self.entities
	for idx = #entities, 1, -1 do
		self:remove(entities[idx])
	end
	return self
end

--[=[ 
	Checks if a specific entity is currently a member of this group.

	@method contains
	@within Group
	@param entity Entity
	@return boolean
]=]
function Group.contains(self: Types.InternalGroup, entity: Types.Entity): boolean
	local groups = State.entityToGroups[entity]
	return groups and groups[self.id] == true or false
end

--[=[ 
	Returns the unique internal ID of the group.

	@method getId
	@within Group
	@return number
]=]
function Group.getId(self: Types.InternalGroup): number
	return self.id
end

--[=[ 
	Returns a list of all entities currently belonging to the group.

	@method getEntities
	@within Group
	@return { Entity }
]=]
function Group.getEntities(self: Types.InternalGroup): { Types.Entity }
	local result = table.create(#self.entities)
	table.move(self.entities, 1, #self.entities, 1, result)
	return result
end

--[=[
	Returns a list of all Observers currently watching the group.

	```lua
	local observers = myGroup:getObservers()
	print('This group is being watched by ' .. #observers .. ' observers.')
	```

	@method getObservers
	@within Group
	@return { Observer }
]=]
function Group.getObservers(self: Types.InternalGroup): { Types.Observer }
	local result = {}
	local observersMap = State.groupToObservers[self.id]

	if not observersMap then
		return result
	end

	for observerId, _ in observersMap do
		local observer = State.observerIdToObserverObj[observerId]
		if observer then
			table.insert(result, observer)
		end
	end

	return result
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
	@return () -> ()
]=]
function Group.onDestroy(self: Types.InternalGroup, callback: () -> ()): () -> ()
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
function Group.destroy(self: Types.InternalGroup): ()
	if self.onDestroyCallbacks then
		for _, callback in self.onDestroyCallbacks do
			task.spawn(callback)
		end
		table.clear(self.onDestroyCallbacks)
	end

	for idx = #self.entities, 1, -1 do
		self:remove(self.entities[idx])
	end

	State.groupToObservers[self.id] = nil
	State.groups[self.id] = nil

	setmetatable(self :: any, nil)
end

return Group

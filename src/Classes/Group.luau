--!strict
--[=[ 
	@class Group

	Groups represent a collection of entities that should be tracked by the system.

	:::info Observer
	Every entity must be in a group to be observed.
	:::
]=]

local CollectionService = game:GetService('CollectionService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)
local Entities = require(script.Parent.Parent.Core.Entities)
local Memberships = require(script.Parent.Parent.Core.Memberships)
local PlayerTracker = require(script.Parent.Parent.Core.PlayerTracker)
local References = require(script.Parent.Parent.Core.References)
local Routing = require(script.Parent.Parent.Core.Routing)
local State = require(script.Parent.Parent.Core.State)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Log = require(script.Parent.Parent.Utils.Log)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)

local IS_CLIENT = RunService:IsClient()

local Group = {}
Group.__index = Group

local isPlayer = References.isPlayer

-- Removes an instance from the group once it leaves the game, while the group has autoClean on
local function watchRemoval(group: Types.InternalGroup, entity: any)
	local cleanups = State.groupEntityCleanups[group.id]
	if typeof(entity) == 'Instance' and not cleanups[entity] then
		cleanups[entity] = entity.AncestryChanged:Connect(function(_, parent)
			if not parent then
				group:_removeEntity(entity)
			end
		end)
	end
end

-- Removes a member. A character part of a player goes through the player as well, so the player's next
-- character is not added back
local function removeMember(group: Types.InternalGroup, entity: any)
	local reference = References.entityToReference[entity]
	if isPlayer(reference) then
		group:_remove(reference)
	end
	-- Unless an exit callback destroyed the group meanwhile
	if not Destroyed.isDead(group) then
		group:_removeEntity(entity)
	end
end

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
	@tag Chainable
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
		phase = 'alive',
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
	@tag Chainable
	@param tag string
	@return Group
]=]
function Group.fromTag(tag: string): Types.Group<Types.Entity>
	local group = Group.new({ autoClean = false, entities = nil }) :: Types.InternalGroup<Types.Entity>
	group.isManaged = true

	local watchingInstances = {} :: { [Instance]: RBXScriptConnection }

	local function checkAncestry(instance: BasePart | Model | Attachment | Bone | Camera)
		if instance:IsDescendantOf(workspace) then
			group:_addEntity(instance)
		else
			group:_removeEntity(instance)
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
		group:_removeEntity(instance :: any)
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
	@tag Chainable
	@return Group
]=]
function Group.players(): Types.Group<Player>
	local group = Group.new({ autoClean = false, entities = nil }) :: Types.InternalGroup<Player>
	group.isManaged = true

	local conn = Players.PlayerAdded:Connect(function(player)
		group:_add(player)
	end)

	for _, player in Players:GetPlayers() do
		group:_add(player)
	end

	group:onDestroy(function()
		conn:Disconnect()
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
	@tag Chainable
	@return Group
]=]
function Group.localPlayer(): Types.Group<Player>
	if not IS_CLIENT then
		Log.fatal('Group.localPlayer() can only be called on the Client.', nil)
	end

	local group = Group.new({ autoClean = false, entities = nil }) :: Types.InternalGroup<Player>
	group.isManaged = true

	group:_add(Players.LocalPlayer)

	return group
end

--[=[ 
	Enables or disables automatic cleanup for Instances in this group.
	When enabled, if an Instance is Destroyed() or parented to nil, it will be 
	automatically removed from this group.

	@tag Chainable
	@method setAutoClean
	@within Group
	@param enabled boolean
	@return Group
]=]
function Group.setAutoClean(self: Types.InternalGroup, enabled: boolean): Types.Group
	if self.isManaged then
		Log.warn('Cannot set autoClean on a Managed Group. Ignoring request.', nil)
		return self
	end

	if self.autoClean == enabled then
		return self
	end

	self.autoClean = enabled
	local cleanups = State.groupEntityCleanups[self.id]

	if enabled then
		for _, entity in self.entities do
			watchRemoval(self, entity)
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
	Adds an entity to the group.

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
	* **Table:** Looks for `.Position`, `.CFrame`, `.Transform`, `.WorldPosition`, or `:GetPivot()`.
	:::

	@tag Chainable
	@method add
	@within Group
	@param entity any -- The object to track.
	@return Group
]=]
function Group.add(self: Types.InternalGroup, entity: any): Types.Group
	if self.isManaged then
		Log.warn('Cannot manually add to a Managed Group. Ignoring request.', nil)
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

	@tag Chainable
	@method addBulk
	@within Group
	@param entities { any } -- Array of entities to add.
	@return Group
]=]
function Group.addBulk(self: Types.InternalGroup, entities: { any }): Types.Group
	if self.isManaged then
		Log.warn('Cannot manually addBulk to a Managed Group. Ignoring request.', nil)
		return self
	end
	return self:_addBulk(entities)
end

--[=[ 
	Removes the entity from the group. Removing a player's `HumanoidRootPart` removes the player.

	@tag Chainable
	@method remove
	@within Group
	@param entity any
	@return Group
]=]
function Group.remove(self: Types.InternalGroup, entity: any): Types.Group
	if self.isManaged then
		Log.warn('Cannot manually remove from a Managed Group. Ignoring request.', nil)
		return self
	end
	return self:_remove(entity)
end

--[=[ 
	Removes multiple entities from the group.
	
	@tag Chainable
	@method removeBulk
	@within Group
	@param entities { any }
	@return Group
]=]
function Group.removeBulk(self: Types.InternalGroup, entities: { any }): Types.Group
	if self.isManaged then
		Log.warn('Cannot manually removeBulk from a Managed Group. Ignoring request.', nil)
		return self
	end
	return self:_removeBulk(entities)
end

--[=[ 
	Removes all entities from the group.
	This fires 'onExit' events for every entity currently inside a zone.

	@tag Chainable
	@method clear
	@within Group
	@return Group
]=]
function Group.clear(self: Types.InternalGroup): Types.Group
	if self.isManaged then
		Log.warn('Cannot clear a Managed Group. Ignoring request.', nil)
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
function Group.contains(self: Types.InternalGroup, entity: any): boolean
	-- A player is a member while it has no character too
	return Entities.isIn(References.entityOf(entity), self.id)
		or (isPlayer(entity) and PlayerTracker.isSubscribed(entity, self))
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
	@return { any }
]=]
function Group.getEntities(self: Types.InternalGroup): { any }
	local result = table.create(#self.entities)
	for i, entity in ipairs(self.entities) do
		result[i] = References.entityToReference[entity] or entity
	end
	return result
end

--[=[ 
	Iterates over all entities currently belonging to the group, ideal for high-frequency checks.
	Safe to use while entities are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	```lua
	for entity in myGroup:iterEntities() do
		print(entity.Name .. " is in the group!")
	end
	```

	@method iterEntities
	@within Group
	@return () -> any?
]=]
function Group.iterEntities(self: Types.InternalGroup): () -> any?
	local nextEntity = Snapshot.keys(self.entityIndices)

	return function()
		local entity = nextEntity()
		if entity ~= nil then
			return References.entityToReference[entity] or entity
		end
		return nil
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
function Group.onDestroy(self: Types.InternalGroup, callback: () -> ()): () -> ()
	return Destroyed.connect(self, callback)
end

--[=[ 
	Cleans up the group, removes all tracked entities, and detaches any 
	associated observers.
	
	@tag Destructor
	@method destroy
	@within Group
]=]
function Group.destroy(self: Types.InternalGroup): ()
	-- A callback below may destroy the group again
	if not Destroyed.begin(self) then
		return
	end

	Destroyed.fireCallbacks(self.onDestroyCallbacks)

	self:_clear()
	Memberships.groupDestroyed(self.id)

	State.groupToObservers[self.id] = nil
	State.groups[self.id] = nil
	State.groupEntityCleanups[self.id] = nil

	Destroyed.finish(self)
end

function Group._add(self: Types.InternalGroup, reference: any): Types.Group
	-- A callback during destroy must not add entities that are never removed
	if Destroyed.isDestroyed(self) then
		return self
	end

	if isPlayer(reference) then
		PlayerTracker.subscribe(reference, self)
		return self
	end

	return self:_addEntity(References.entityOf(reference))
end

-- Adds the entity as given, never through the reference map. For internal callers that hold the instance
function Group._addEntity(self: Types.InternalGroup, entity: Types.Entity): Types.Group
	if Destroyed.isDestroyed(self) then
		return self
	end
	if entity == nil then
		Log.nonFatal('Cannot add nil to Group %d.', nil, self.id)
		return self
	end

	if not Entities.join(entity, self.id) then
		return self
	end

	local idx = #self.entities + 1
	self.entities[idx] = entity
	self.entityIndices[entity] = idx

	Routing.recheck(entity)

	if self.autoClean then
		watchRemoval(self, entity)
	end

	-- Its group may arrive in observers it is already in
	Memberships.groupsChanged(entity)

	return self
end

function Group._addBulk(self: Types.InternalGroup, references: { any }): Types.Group
	for _, reference in references do
		-- A callback may have destroyed the group
		if Destroyed.isDestroyed(self) then
			break
		end
		self:_add(reference)
	end
	return self
end

function Group._remove(self: Types.InternalGroup, reference: any): Types.Group
	if isPlayer(reference) then
		PlayerTracker.unsubscribe(reference, self)
		return self
	end

	-- An entity is removed itself, also when it is another entity's reference, as contains finds it. A player's
	-- part is removed as the player
	removeMember(self, References.entityOf(reference))
	return self
end

-- Removes the entity as given, never through the reference map. For internal callers that hold the member
function Group._removeEntity(self: Types.InternalGroup, entity: Types.Entity): Types.Group
	if not Entities.isIn(entity, self.id) then
		return self
	end

	local cleanupConn = State.groupEntityCleanups[self.id][entity]
	if cleanupConn then
		cleanupConn:Disconnect()
		State.groupEntityCleanups[self.id][entity] = nil
	end

	Entities.leave(entity, self.id)
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

	Routing.recheck(entity)

	Memberships.exitUnsubscribed(entity, data)
	-- Its group may leave observers it stays in through other groups
	Memberships.groupsChanged(entity)

	-- Exit callbacks may have removed the entity everywhere, or added it back
	Entities.dropIfGroupless(entity, data)

	return self
end

function Group._removeBulk(self: Types.InternalGroup, entities: { any }): Types.Group
	for _, entity in entities do
		-- An exit callback may have destroyed the group
		if Destroyed.isDead(self) then
			break
		end
		self:_remove(entity)
	end
	return self
end

function Group._clear(self: Types.InternalGroup): Types.Group
	-- Iterate backwards for safe removal
	local entities = self.entities
	for idx = #entities, 1, -1 do
		-- An exit callback may have removed entities after this one, or destroyed the group and all of them
		local entity = entities[idx]
		if entity ~= nil then
			removeMember(self, entity)
		end
	end
	-- Players without a character have no member to remove
	PlayerTracker.dropGroup(self.id)
	return self
end

return Group

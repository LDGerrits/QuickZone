--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)

local sharedPlayerGroup: Types.Group?
local sharedLocalPlayerGroup: Types.Group?
local bridgeRefreshPlayerGroup: ((Player) -> ())?

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

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

	local function onCharAdded(char: Model)
		cleanCharacter()

		task.spawn(function()
			-- To prioritize LocalPlayerGroup, do early return if it is local player and LocalPlayerGroup exists
			if
				IS_CLIENT
				and group == sharedPlayerGroup
				and player == Players.LocalPlayer
				and sharedLocalPlayerGroup
			then
				return
			end

			local hrp = char:WaitForChild('HumanoidRootPart', 10)

			if not hrp or not player:IsDescendantOf(Players) then
				return
			end

			if player.Character ~= char then
				return
			end

			if hrp:IsA('BasePart') then
				currentHrp = hrp

				group:add(hrp, { Player = player }) -- Custom data is needed to trigger specific player events

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
		updateRate = 20, -- Check at 20Hz
		precision = 0.5, -- Ignore movement smaller than 0.5 studs
		entities = { NPC1, NPC2, NPC3 } -- Add entities
	})
	```

	@tag Constructor
	@param config { updateRate: number?, precision: number?, entities: { Types.Entity }? }?
	@return Group
]=]
function Group.new(config: {
	updateRate: number?,
	precision: number?,
	entities: { Types.Entity }?,
}?): Types.Group
	local hz = config and config.updateRate
	assert(not hz or hz > 0, '[QuickZone] updateRate must be greater than 0')

	local n = config and config.precision
	assert(not n or n >= 0, '[QuickZone] precision must be non-negative')

	local id = State.nextGroupId
	State.nextGroupId += 1

	local updateRate = hz or Config.Scheduler.updateRate
	local precision = n or Config.Scheduler.precision

	local self: Types.InternalGroup = setmetatable({
		id = id,
		entities = {},
		entityIndices = {},
		entityData = {},
		config = {
			updateRate = updateRate,
			precisionSq = precision ^ 2,
		},
	}, Group) :: any

	State.groups[id] = self
	State.groupToObservers[id] = {}
	table.insert(State.groupList, self)

	if config and config.entities then
		self:addBulk(config.entities)
	end

	return self
end

--[=[ 
	Returns a singleton Group that automatically tracks all Players in the server.

	:::info Behavior
	* Automatically tracks the `HumanoidRootPart` of every player.
	* Handles `PlayerAdded` and `CharacterAdded` internally.
	* If a LocalPlayerGroup exists on the client, the local player is excluded 
	  from this group to avoid duplicate tracking.
	:::

	@tag Constructor
	@param config { updateRate: number?, precision: number?, entities: { Types.Entity }? }?
	@return Group
]=]
function Group.players(config: {
	updateRate: number?,
	precision: number?,
	entities: { Types.Entity }?,
}?): Types.Group
	if sharedPlayerGroup then
		if config then
			sharedPlayerGroup:setConfig(config)
			if config.entities then
				sharedPlayerGroup:addBulk(config.entities)
			end
		end
		return sharedPlayerGroup
	end

	local group = Group.new(config)
	sharedPlayerGroup = group

	local trackerStore = {} :: { [Player]: () -> () }
	local mainConnections = {} :: { RBXScriptConnection }

	bridgeRefreshPlayerGroup = function(player: Player)
		untrackPlayer(player, trackerStore)
		trackPlayer(group, player, trackerStore)
	end

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

	local originalDestroyHook = group.destroy
	group.destroy = function(self)
		for _, conn in mainConnections do
			conn:Disconnect()
		end
		for _, cleanup in trackerStore do
			cleanup()
		end

		table.clear(mainConnections)
		table.clear(trackerStore)

		bridgeRefreshPlayerGroup = nil
		sharedPlayerGroup = nil

		originalDestroyHook(self)
	end

	return group
end

--[=[ 
	Returns a singleton Group that tracks only the LocalPlayer.

	:::info Behavior
	* This group takes 'ownership of the local player's character.
	* When this group is destroyed, the local player is automatically handed back 
	  to the global `PlayerGroup` if it exists.
	:::

	@client
	@tag Constructor
	@param config { updateRate: number?, precision: number?, entities: { Types.Entity }? }?
	@return Group
]=]
function Group.localPlayer(config: {
	updateRate: number?,
	precision: number?,
	entities: { Types.Entity }?,
}?): Types.Group
	assert(IS_CLIENT, '[QuickZone] QuickZone.LocalPlayerGroup can only be called on the Client.')

	if sharedLocalPlayerGroup then
		if config then
			sharedLocalPlayerGroup:setConfig(config)
			if config.entities then
				sharedLocalPlayerGroup:addBulk(config.entities)
			end
		end
		return sharedLocalPlayerGroup
	end

	local group = Group.new(config)
	sharedLocalPlayerGroup = group

	local lp = Players.LocalPlayer
	local trackers = {}

	trackPlayer(group, lp, trackers)

	local originalDestroyHook = group.destroy
	group.destroy = function(self)
		untrackPlayer(lp, trackers)
		sharedLocalPlayerGroup = nil

		-- The player should immediately be handed over to PlayerGroup
		if bridgeRefreshPlayerGroup then
			bridgeRefreshPlayerGroup(Players.LocalPlayer)
		end

		originalDestroyHook(self)
	end

	return group
end

--[=[ 
	Adds an entity to the group. If the entity is already in another group, 
	it is automatically removed from the old one first.

	#### Example: Adding Different Entity Types
	```lua
	-- Adding a BasePart and a Model with custom metadata (using chaining)
	myGroup:add(workspace.Part):add(workspace.NPCModel, { Type = 'Enemy', Level = 42 })

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
	@param metadata any? -- Optional data passed to Observer callbacks.
	@return Group
]=]
function Group.add(self: Types.InternalGroup, entity: Types.Entity, metadata: any?): Types.Group
	local oldGroupId = State.entityToGroup[entity]
	if oldGroupId then
		if oldGroupId == self.id then
			return self
		end
		local oldGroup = State.groups[oldGroupId]
		if oldGroup then
			oldGroup:remove(entity)
		end
	end

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
		warn(string.format('[QuickZone] Invalid entity (%s). Expected BasePart, Model, etc.', tostring(entity)))
		return self
	end

	local data = {
		lastPosition = Vector3.zero,
		strategy = strat,
		isDirty = true,
		activeObserverMemberships = {},
	}

	local idx = #self.entities + 1
	self.entities[idx] = entity
	self.entityIndices[entity] = idx
	self.entityData[entity] = data

	State.entityToGroup[entity] = self.id

	if metadata then
		if not State.entityMetadata[entity] then
			State.entityMetadata[entity] = {}
		end
		State.entityMetadata[entity] = metadata
	end

	return self
end

--[=[ 
	Adds multiple entities to the group.

	```lua
	-- Add an entire folder of NPCs at once
	myGroup:addBulk(workspace.Enemies:GetChildren(), { Team = "Red" })
	```

	@method addBulk
	@within Group
	@param entities { Entity } -- Array of entities to add.
	@param metadata any? -- Optional metadata applied to all added entities.
	@return Group
]=]
function Group.addBulk(self: Types.InternalGroup, entities: { Types.Entity }, metadata: any?): Types.Group
	for _, entity in entities do
		self:add(entity, metadata)
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
	if State.entityToGroup[entity] ~= self.id then
		return self
	end

	local data = self.entityData[entity]

	-- Trigger exit
	for observerId, oldZoneId in data.activeObserverMemberships do
		if State.observerTrackingEntities[observerId] then
			State.observerTrackingEntities[observerId][entity] = nil
		end

		local cbs = State.observerExitedCallbacks[observerId]
		if not cbs then
			continue
		end

		local safety = State.observerSafety[observerId]
		local z = State.zoneIdToZoneObj[oldZoneId]
		local cd = State.entityMetadata[entity]
		for _, fn in cbs do
			if safety then
				task.spawn(fn, entity, z, cd)
			else
				fn(entity, z, cd)
			end
		end
	end

	-- Swap-remove from Array
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

	self.entityData[entity] = nil
	State.entityToGroup[entity] = nil
	State.entityMetadata[entity] = nil

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
	for i = #entities, 1, -1 do
		self:remove(entities[i])
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
	local groupId = State.entityToGroup[entity]
	return groupId and groupId == self.id
end

--[=[ 
	Updates the group's configuration. 

	:::tip Precision
	A higher `precision` value (e.g., 2.0) means entities must move further 
	before a re-calculation is triggered, improving performance for large groups.
	:::

	@method setConfig
	@within Group
	@param config { updateRate: number?, precision: number?, safety: boolean? }
	@return Group
]=]
function Group.setConfig(
	self: Types.InternalGroup,
	config: {
		updateRate: number?,
		precision: number?,
	}
): Types.Group
	local hz = config.updateRate
	assert(not hz or hz > 0, '[QuickZone] updateRate must be greater than 0')

	local n = config.precision
	assert(not n or n >= 0, '[QuickZone] precision must be non-negative')

	if hz then
		self.config.updateRate = hz
	end
	if n then
		self.config.precisionSq = n ^ 2
	end

	return self
end

--[=[
	Set the update rate of the group.

	@method setUpdateRate
	@within Group
	@param updateRate number
	@return Group
]=]
function Group.setUpdateRate(self: Types.InternalGroup, updateRate: number): Types.Group
	self.config.updateRate = updateRate
	return self
end

--[=[
	Set the current precision of the group.

	@method setPrecision
	@within Group
	@param precision number
	@return Group
]=]
function Group.setPrecision(self: Types.InternalGroup, precision: number): Types.Group
	self.config.precisionSq = precision ^ 2
	return self
end

--[=[
	Returns the current configuration settings for the group.

	@method getConfig
	@within Group
	@return { updateRate: number, precision: number, safety: boolean }
]=]
function Group.getConfig(self: Types.InternalGroup): {
	updateRate: number,
	precision: number,
}
	local config = self.config
	return {
		updateRate = config.updateRate,
		precision = math.sqrt(config.precisionSq),
	}
end

--[=[
	Returns the current update rate of the group.

	@method getUpdateRate
	@within Group
	@return number
]=]
function Group.getUpdateRate(self: Types.InternalGroup): number
	return self.config.updateRate
end

--[=[
	Returns the current precision of the group.

	@method getPrecision
	@within Group
	@return number
]=]
function Group.getPrecision(self: Types.InternalGroup): number
	return math.sqrt(self.config.precisionSq)
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
	Cleans up the group, removes all tracked entities, and detaches any 
	associated observers.
	
	@tag Destructor
	@method destroy
	@within Group
]=]
function Group.destroy(self: Types.InternalGroup): ()
	-- Must iterate backwards because remove() modifies array length
	for i = #self.entities, 1, -1 do
		self:remove(self.entities[i])
	end

	State.groupToObservers[self.id] = nil
	State.groups[self.id] = nil

	local listIdx = table.find(State.groupList, self)
	if listIdx then
		table.remove(State.groupList, listIdx)
	end

	setmetatable(self :: any, nil)
end

return Group

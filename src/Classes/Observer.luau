--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Config = require(script.Parent.Parent.Config)
local Geometry = require(script.Parent.Parent.Core.Geometry)
local LinearBVH = require(script.Parent.Parent.Core.LinearBVH)
local updateProfile = require(script.Parent.Parent.Core.updateProfile)
local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

local IS_CLIENT = RunService:IsClient()

local function updateAllEntitiesForObserver(observerId: number)
	for groupId, observers in State.groupToObservers do
		if not observers[observerId] then
			continue
		end

		local group = State.groups[groupId]
		if not group then
			continue
		end

		for _, entity in group.entities do
			updateProfile(entity)
		end
	end
end

local function disconnectObserverFromGroup(observerId: number, group: Types.InternalGroup)
	local safety = State.observerSafety[observerId]

	for _, entity in group.entities do
		local data = State.entityData[entity]
		if not data then
			continue
		end

		updateProfile(entity)

		local activeObservers = State.entityToObservers[entity] or {}
		local oldZoneId = data.activeObserverMemberships[observerId]

		if not oldZoneId or activeObservers[observerId] then
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

--[=[ 
	Observers are the logical bridge between Groups and Zones.
	They monitor specific groups and trigger events when entities within those 
	groups enter or exit any zones associated with the observer.

	@class Observer
]=]
local Observer = {}
Observer.__index = Observer

--[=[ 
	Creates an Observer. Observers listen for entities entering or exiting assigned Zones.

	```lua
	local observer = QuickZone.Observer.new({
		priority = 20, -- The priority value is used to resolve overlaps
		updateRate = 20, -- Check at 20Hz
		precision = 0.5, -- Ignore movement smaller than 0.5 studs
		enabled = false, -- Observer will not start processing spatial checks
		safety = false, -- Do not wrap callbacks in task.spawn
		groups = { enemyGroup, playerGroup } -- Immediately subscribe to these groups
	})
	```

	:::info Resolution Priority
	When an entity is inside multiple zones watched by different observers, 
	higher priority observers take complete control.
	:::

	@tag Constructor
	@param config { priority: number?, enabled: boolean?, safety: boolean?, groups: { Types.Group }?, }?
	@return Observer
]=]
function Observer.new(config: {
	groups: { Types.Group }?,
	priority: number?,
	updateRate: number?,
	precision: number?,
	enabled: boolean?,
	safety: boolean?,
}?): Types.Observer
	local id = State.nextObserverId
	State.nextObserverId += 1

	local self: Types.InternalObserver = setmetatable({
		id = id,
	}, Observer) :: any

	State.observerPriorityMap[id] = config and config.priority or 0
	State.observerUpdateRate[id] = config and config.updateRate or Config.Observer.updateRate
	State.observerPrecisionSq[id] = (config and config.precision or Config.Observer.precision) ^ 2

	State.observerEnteredCallbacks[id] = {}
	State.observerExitedCallbacks[id] = {}
	State.observerTransitionedCallbacks[id] = {}
	State.observerTrackingEntities[id] = {}
	State.observerIdToObserverObj[id] = self
	State.observerEnabled[id] = if config and config.enabled ~= nil then config.enabled else true
	State.observerSafety[id] = if config and config.safety ~= nil then config.safety else Config.Observer.safety

	if config and config.groups then
		for _, group in config.groups do
			self:subscribe(group)
		end
	end

	return self
end

--[=[ 
	Links this observer to the specified group. The observer will only
	track entities that belong to subscribed groups.

	```lua
	observer:subscribe(playerGroup):subscribe(enemyGroup)
	```

	@method subscribe
	@within Observer
	@param group Group -- The group to monitor.
	@return Observer
]=]
function Observer.subscribe(self: Types.InternalObserver, group: Types.InternalGroup): Types.Observer
	local groupId = group.id
	if not State.groupToObservers[groupId] then
		State.groupToObservers[groupId] = {}
	end
	State.groupToObservers[groupId][self.id] = true

	for _, entity in group.entities do
		updateProfile(entity)
	end

	return self
end

--[=[ 
	Stops the observer from monitoring the specified group.

	@method unsubscribe
	@within Observer
	@param group Group -- The group to stop monitoring.
	@return Observer
]=]
function Observer.unsubscribe(self: Types.InternalObserver, group: Types.InternalGroup): Types.Observer
	local groupId = group.id

	if State.groupToObservers[groupId] then
		State.groupToObservers[groupId][self.id] = nil
	end

	disconnectObserverFromGroup(self.id, group)

	return self
end

--[=[ 
	Observes entities entering and exiting the zone. 
	The callback executes on entry and expects a function to be returned, 
	which is executed on exit.

	```lua
	observer:observe(function(entity, zone)
		print("Entered", entity)
		local highlight = Instance.new("Highlight", entity)

		-- Return cleanup function
		return function()
			print("Exited", entity)
			highlight:Destroy()
		end
	end)
	```

	@method observe
	@within Observer
	@param callback (entity: Entity, zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observe(self: Types.InternalObserver, callback: (Types.Entity, Types.Zone) -> (() -> ())?): () -> ()
	local cleanups = {} :: { [Types.Entity]: () -> () }
	local activeIds = {} :: { [Types.Entity]: number }
	local nextId = 0 -- sessionId for each entity

	local cleanupEnter = self:onEntered(function(entity, zone)
		nextId += 1
		local myId = nextId
		activeIds[entity] = myId

		local cleanup = callback(entity, zone)

		if activeIds[entity] ~= myId then
			if type(cleanup) == 'function' then
				cleanup()
			end
			return
		end

		if type(cleanup) == 'function' then
			cleanups[entity] = cleanup
		end
	end)

	local cleanupExit = self:onExited(function(entity, _)
		activeIds[entity] = nil

		local cleanup = cleanups[entity]
		if cleanup then
			cleanups[entity] = nil
			cleanup()
		end
	end)

	return function()
		cleanupEnter()
		cleanupExit()

		table.clear(activeIds)

		for entity, cleanup in cleanups do
			cleanups[entity] = nil
			task.spawn(cleanup)
		end
	end
end

--[=[ 
	Fires when any entity from a subscribed group enters a zone attached to this observer.

	```lua
	local disconnect = observer:onEntered(function(entity, zone)
		print(entity.Name .. ' entered ' .. zone.id)
	end)
	```

	@tag Event
	@method onEntered
	@within Observer
	@param callback (entity: Entity, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onEntered(self: Types.InternalObserver, callback: (Types.Entity, Types.Zone) -> ()): () -> ()
	table.insert(State.observerEnteredCallbacks[self.id], callback)
	return function()
		local idx = table.find(State.observerEnteredCallbacks[self.id], callback)
		if idx then
			table.remove(State.observerEnteredCallbacks[self.id], idx)
		end
	end
end

--[=[ 
	Fires when an entity exits all zones attached to this observer.

	@tag Event
	@method onExited
	@within Observer
	@param callback (entity: Entity, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onExited(self: Types.InternalObserver, callback: (Types.Entity, Types.Zone) -> ()): () -> ()
	table.insert(State.observerExitedCallbacks[self.id], callback)
	return function()
		local idx = table.find(State.observerExitedCallbacks[self.id], callback)
		if idx then
			table.remove(State.observerExitedCallbacks[self.id], idx)
		end
	end
end

--[=[
	Observes players entering and exiting the zone.
	
	```lua
	observer:observePlayer(function(player, zone)
		print(player.Name .. " entered!")
		
		-- Return cleanup (optional)
		return function()
			print(player.Name .. " left!")
		end
	end)
	```

	@method observePlayer
	@within Observer
	@param callback (player: Player, zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observePlayer(self: Types.InternalObserver, callback: (Player, Types.Zone) -> (() -> ())?): () -> ()
	local cleanups = {} :: { [Player]: () -> () }
	local activeIds = {} :: { [Player]: number }
	local nextId = 0

	local cleanupEnter = self:onPlayerEntered(function(player, zone)
		nextId += 1
		local myId = nextId
		activeIds[player] = myId

		local cleanup = callback(player, zone)

		if activeIds[player] ~= myId then
			if type(cleanup) == 'function' then
				cleanup()
			end
			return
		end

		if type(cleanup) == 'function' then
			cleanups[player] = cleanup
		end
	end)

	local cleanupExit = self:onPlayerExited(function(player, _)
		activeIds[player] = nil

		local cleanup = cleanups[player]
		if cleanup then
			cleanups[player] = nil
			cleanup()
		end
	end)

	return function()
		cleanupEnter()
		cleanupExit()

		table.clear(activeIds)

		for player, cleanup in cleanups do
			cleanups[player] = nil
			task.spawn(cleanup)
		end
	end
end

--[=[ 
	Specialized event for Player entities.

	```lua
	observer:onPlayerEntered(function(player, zone)
		print(player.Name .. " entered safe zone " .. zone:getId())
		
		-- Play a sound
		local sound = workspace.Sounds.SafeZoneEnter:Clone()
		sound.Parent = player.Character.PrimaryPart
		sound:Play()
		game.Debris:AddItem(sound, 2)
	end)
	```

	@tag Event
	@method onPlayerEntered
	@within Observer
	@param callback (player: Player, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onPlayerEntered(self: Types.InternalObserver, callback: (Player, Types.Zone) -> ()): () -> ()
	return self:onEntered(function(entity, zone)
		local player = State.entityToPlayer[entity]
		if player then
			callback(player, zone)
		end
	end)
end

--[=[ 
	A specialized event for Player entities. Fires when a player's character 
	exits all zones attached to this observer.

	@tag Event
	@method onPlayerExited
	@within Observer
	@param callback (player: Player, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onPlayerExited(self: Types.InternalObserver, callback: (Player, Types.Zone) -> ()): () -> ()
	return self:onExited(function(entity, zone)
		local player = State.entityToPlayer[entity]
		if player then
			callback(player, zone)
		end
	end)
end

--[=[
	Observes the LocalPlayer.

	```lua
	observer:observeLocalPlayer(function(zone)
		local blur = Instance.new("BlurEffect", game.Lighting)
		return function()
			blur:Destroy()
		end
	end)
	```

	@client
	@method observeLocalPlayer
	@within Observer
	@param callback (zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observeLocalPlayer(self: Types.InternalObserver, callback: (Types.Zone) -> (() -> ())?): () -> ()
	assert(IS_CLIENT, '[QuickZone] Observer:observeLocalPlayer can only be called on the Client.')

	local currentCleanup = nil :: (() -> ())?
	local currentId = 0

	local cleanupEnter = self:onLocalPlayerEntered(function(zone)
		currentId += 1
		local myId = currentId

		local cleanup = callback(zone)

		if currentId ~= myId then
			if type(cleanup) == 'function' then
				cleanup()
			end
			return
		end

		if type(cleanup) == 'function' then
			currentCleanup = cleanup
		end
	end)

	local cleanupExit = self:onLocalPlayerExited(function(_)
		currentId = 0

		if currentCleanup then
			local cleanup = currentCleanup
			currentCleanup = nil
			cleanup()
		end
	end)

	return function()
		cleanupEnter()
		cleanupExit()

		currentId = 0

		if currentCleanup then
			local cleanup = currentCleanup
			currentCleanup = nil
			task.spawn(cleanup)
		end
	end
end

--[=[ 
	Specialized event for the LocalPlayer.

	```lua
	observer:onLocalPlayerEntered(function(zone)
		print("You entered zone " .. zone:getId())
		
		local char = player.Character
		if char and char:FindFirstChild("Humanoid") then
			char.Humanoid.WalkSpeed = 24
		end
	end)
	```

	@client
	@tag Event
	@method onLocalPlayerEntered
	@within Observer
	@param callback (zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onLocalPlayerEntered(self: Types.InternalObserver, callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[QuickZone] Observer:onLocalPlayerEntered can only be called on the Client.')
	return self:onEntered(function(entity, zone)
		local player = State.entityToPlayer[entity]
		if player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

--[=[ 
	A specialized event for the LocalPlayer. Fires when the local player's 
	character exits all zones attached to this observer.

	@client
	@tag Event
	@method onLocalPlayerExited
	@within Observer
	@param callback (zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onLocalPlayerExited(self: Types.InternalObserver, callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[QuickZone] Observer:onLocalPlayerExited can only be called on the Client.')
	return self:onExited(function(entity, zone)
		local player = State.entityToPlayer[entity]
		if player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

--[=[ 
	Observes a Group's presence within the observer's zones.
	The callback fires when the first entity of a group enters, and the 
	returned cleanup function fires when the last entity of the group leaves.

	```lua
	observer:observeGroup(function(group, zone)
		print("Group " .. group:getId() .. " has arrived!")
		return function()
			print("Group " .. group:getId() .. " has left entirely.")
		end
	end)
	```

	@method observeGroup
	@within Observer
	@param callback (group: Group, zone: Zone) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function Observer.observeGroup(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone) -> (() -> ())?
): () -> ()
	local activeMembers = {} :: { [number]: { [Types.Entity]: boolean } }
	local cleanups = {} :: { [number]: () -> () }

	return self:observe(function(entity, zone)
		local groups = State.entityToGroups[entity]
		if not groups then
			return
		end

		for groupId, _ in groups do
			local group = State.groups[groupId]
			if not group or not State.groupToObservers[groupId][self.id] then
				continue
			end

			if not activeMembers[groupId] then
				activeMembers[groupId] = {}
			end

			if next(activeMembers[groupId]) == nil then
				activeMembers[groupId][entity] = true
				local groupCleanup = callback(group, zone)
				if typeof(groupCleanup) == 'function' then
					cleanups[groupId] = groupCleanup
				end
			else
				activeMembers[groupId][entity] = true
			end
		end

		return function()
			for groupId, members in activeMembers do
				if not members[entity] then
					continue
				end

				members[entity] = nil
				if next(members) == nil then
					activeMembers[groupId] = nil
					local groupCleanup = cleanups[groupId]
					if groupCleanup then
						groupCleanup()
						cleanups[groupId] = nil
					end
				end
			end
		end
	end)
end

--[=[ 
	Fires when the first member of a Group enters any zone attached to this observer.
	Subsequent entries by other members of the same group will not trigger this event
	until the group has completely exited and re-entered.

	@tag Event
	@method onGroupEntered
	@within Observer
	@param callback (group: Group, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onGroupEntered(self: Types.InternalObserver, callback: (Types.Group, Types.Zone) -> ()): () -> ()
	local activeMembers = {} :: { [number]: { [Types.Entity]: boolean } }

	return self:observe(function(entity, zone)
		local groups = State.entityToGroups[entity]
		if not groups then
			return
		end

		for groupId, _ in groups do
			if not State.groupToObservers[groupId] or not State.groupToObservers[groupId][self.id] then
				continue
			end

			if not activeMembers[groupId] then
				activeMembers[groupId] = {}
			end

			local isFirst = next(activeMembers[groupId]) == nil
			activeMembers[groupId][entity] = true

			if isFirst then
				local group = State.groups[groupId]
				if group then
					callback(group, zone)
				end
			end
		end

		return function()
			for groupId, members in activeMembers do
				if not members[entity] then
					continue
				end

				members[entity] = nil
				if next(members) == nil then
					activeMembers[groupId] = nil
				end
			end
		end
	end)
end

--[=[ 
	Fires when the last remaining member of a Group exits all zones attached to 
	this observer. This is useful for "cleared" states or stopping group-wide effects.

	@tag Event
	@method onGroupExited
	@within Observer
	@param callback (group: Group, zone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onGroupExited(self: Types.InternalObserver, callback: (Types.Group, Types.Zone) -> ()): () -> ()
	local activeMembers = {} :: { [number]: { [Types.Entity]: boolean } }

	return self:observe(function(entity, zone)
		local groups = State.entityToGroups[entity]
		if not groups then
			return
		end

		for groupId, _ in groups do
			if not State.groupToObservers[groupId] or not State.groupToObservers[groupId][self.id] then
				continue
			end

			if not activeMembers[groupId] then
				activeMembers[groupId] = {}
			end
			activeMembers[groupId][entity] = true
		end

		return function()
			for groupId, members in activeMembers do
				if not members[entity] then
					continue
				end

				members[entity] = nil
				if next(members) == nil then
					activeMembers[groupId] = nil
					local group = State.groups[groupId]
					if group then
						callback(group, zone)
					end
				end
			end
		end
	end)
end

--[=[ 
	Fires when an entity seamlessly transitions from one attached zone to another 
	overlapping attached zone. If `targetEntity` is provided, the event will silently 
	filter out all other entities.

	@tag Event
	@method onTransitioned
	@within Observer
	@param callback (entity: Entity, newZone: Zone, oldZone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onTransitioned(
	self: Types.InternalObserver,
	callback: (Types.Entity, Types.Zone, Types.Zone) -> ()
): () -> ()
	table.insert(State.observerTransitionedCallbacks[self.id], callback)

	return function()
		local idx = table.find(State.observerTransitionedCallbacks[self.id], callback)
		if idx then
			table.remove(State.observerTransitionedCallbacks[self.id], idx)
		end
	end
end

--[=[ 
	Specialized event for Player entities transitioning between overlapping zones.
	If `targetPlayer` is provided, the event will only fire for that specific player.
	
	@tag Event
	@method onPlayerTransitioned
	@within Observer
	@param callback (player: Player, newZone: Zone, oldZone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onPlayerTransitioned(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Zone) -> ()
): () -> ()
	local wrapper = function(entity, newZone, oldZone)
		local player = State.entityToPlayer[entity]
		if player then
			callback(player, newZone, oldZone)
		end
	end

	table.insert(State.observerTransitionedCallbacks[self.id], wrapper)

	return function()
		local idx = table.find(State.observerTransitionedCallbacks[self.id], wrapper)
		if idx then
			table.remove(State.observerTransitionedCallbacks[self.id], idx)
		end
	end
end

--[=[ 
	Specialized event for the LocalPlayer transitioning between overlapping zones.
	
	@client
	@tag Event
	@method onLocalPlayerTransitioned
	@within Observer
	@param callback (newZone: Zone, oldZone: Zone) -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onLocalPlayerTransitioned(
	self: Types.InternalObserver,
	callback: (Types.Zone, Types.Zone) -> ()
): () -> ()
	assert(IS_CLIENT, '[QuickZone] Observer:onLocalPlayerTransitioned can only be called on the Client.')

	local wrapper = function(entity, newZone, oldZone)
		local player = State.entityToPlayer[entity]
		if player == Players.LocalPlayer then
			callback(newZone, oldZone)
		end
	end

	table.insert(State.observerTransitionedCallbacks[self.id], wrapper)

	return function()
		local idx = table.find(State.observerTransitionedCallbacks[self.id], wrapper)
		if idx then
			table.remove(State.observerTransitionedCallbacks[self.id], idx)
		end
	end
end

--[=[ 
	Enables or disables the observer. When disabled, it will no longer process
	spatial checks or fire events.

	@method setEnabled
	@within Observer
	@param enabled boolean
	@return Observer
]=]
function Observer.setEnabled(self: Types.InternalObserver, enabled: boolean): Types.Observer
	local wasEnabled = self:isEnabled()

	if wasEnabled == enabled then
		return self
	end

	local id = self.id
	State.observerEnabled[id] = enabled
	State.spatialVersion += 1

	if not enabled then
		for groupId, observersMap in State.groupToObservers do
			if not observersMap[id] then
				continue
			end

			local group = State.groups[groupId]
			if not group then
				continue
			end

			disconnectObserverFromGroup(id, group)
		end
	end

	updateAllEntitiesForObserver(self.id)

	return self
end

--[=[
	Whether to wrap callbacks in task.spawn (safe) or not (unsafe).

	@method setSafety
	@within Observer
	@param enabled boolean
	@return Observer
]=]
function Observer.setSafety(self: Types.InternalObserver, enabled: boolean): Types.Observer
	State.observerSafety[self.id] = enabled
	return self
end

--[=[ 
	Updates the resolution priority of the observer.

	@method setPriority
	@within Observer
	@param p number
	@return Observer
]=]
function Observer.setPriority(self: Types.InternalObserver, p: number): Types.Observer
	State.observerPriorityMap[self.id] = p
	State.spatialVersion += 1
	return self
end

--[=[ 
	Updates the update frequency for this observer.

	@method setUpdateRate
	@within Observer
	@param hz number
	@return Observer
]=]
function Observer.setUpdateRate(self: Types.InternalObserver, hz: number): Types.Observer
	assert(hz >= 0, '[QuickZone] updateRate must be non-negative')
	State.observerUpdateRate[self.id] = hz
	updateAllEntitiesForObserver(self.id)
	return self
end

--[=[ 
	Updates the precision in studs for this observer.

	@method setPrecision
	@within Observer
	@param n number
	@return Observer
]=]
function Observer.setPrecision(self: Types.InternalObserver, n: number): Types.Observer
	assert(n >= 0, '[QuickZone] precision must be non-negative')
	State.observerPrecisionSq[self.id] = n ^ 2
	updateAllEntitiesForObserver(self.id)
	return self
end

--[=[ 
	Checks if the observer is currently enabled.

	@method isEnabled
	@within Observer
	@return boolean
]=]
function Observer.isEnabled(self: Types.InternalObserver): boolean
	return State.observerEnabled[self.id] ~= false
end

--[=[ 
	Checks if a specific player's character is currently inside a zone 
	attached to this observer.

	@method isPlayerInside
	@within Observer
	@param player Player
	@return boolean
]=]
function Observer.isPlayerInside(self: Types.InternalObserver, player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return false
	end

	return self:isEntityInside(hrp)
end

--[=[ 
	Checks if the local player's character is currently inside a zone 
	attached to this observer.

	@client
	@method isLocalPlayerInside
	@within Observer
	@return boolean
]=]
function Observer.isLocalPlayerInside(self: Types.InternalObserver): boolean
	if not IS_CLIENT then
		error('[QuickZone] Observer:isLocalPlayerInside can only be called on the Client.', 2)
	end

	return self:isPlayerInside(Players.LocalPlayer)
end

--[=[ 
	Checks if a specific entity is currently inside a zone attached to this observer.

	@method isEntityInside
	@within Observer
	@param entity Entity
	@return boolean
]=]
function Observer.isEntityInside(self: Types.InternalObserver, entity: Types.Entity): boolean
	local data = State.entityData[entity]
	if not data then
		return false
	end

	return data.activeObserverMemberships[self.id] ~= nil
end

--[=[ 
	Checks if a specific point in world space is inside any zone attached to this observer.
	
	@method isPointInside
	@within Observer
	@param position Vector3
	@return boolean
]=]
function Observer.isPointInside(self: Types.InternalObserver, position: Vector3): boolean
	local isInside = false

	if State.dynamicRootNode then
		LinearBVH.queryPoint(State.dynamicRootNode, position, function(zoneId)
			if isInside then
				return
			end
			local observers = State.zoneAttachedObservers[zoneId]
			if observers and table.find(observers, self.id) then
				if Geometry.isPointInZone(position, zoneId, true) then
					isInside = true
				end
			end
		end)

		if isInside then
			return true
		end
	end

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			if isInside then
				return
			end
			local observers = State.zoneAttachedObservers[zoneId]
			if observers and table.find(observers, self.id) then
				if Geometry.isPointInZone(position, zoneId, false) then
					isInside = true
				end
			end
		end)
	end

	return isInside
end

--[=[ 
	Checks if the observer wraps callbacks in task.spawn (safe) or not (unsafe).

	@method isSafe
	@within Observer
	@return boolean
]=]
function Observer.isSafe(self: Types.InternalObserver): boolean
	return State.observerSafety[self.id]
end

--[=[ 
	Returns the unique internal ID of the observer.

	@method getId
	@within Observer
	@return number
]=]
function Observer.getId(self: Types.InternalObserver): number
	return self.id
end

--[=[ 
	Returns the current resolution priority.

	@method getPriority
	@within Observer
	@return number
]=]
function Observer.getPriority(self: Types.InternalObserver): number
	return State.observerPriorityMap[self.id]
end

--[=[ 
	Returns the current update frequency for this observer.

	@method getUpdateRate
	@within Observer
	@return number
]=]
function Observer.getUpdateRate(self: Types.InternalObserver): number
	return State.observerUpdateRate[self.id]
end

--[=[ 
	Updates the precision for this observer.

	@method getPrecision
	@within Observer
	@return number
]=]
function Observer.getPrecision(self: Types.InternalObserver): number
	return math.sqrt(State.observerPrecisionSq[self.id])
end

--[=[ 
	Returns a list of all tracked entities currently inside zones attached to this observer.

	@method getEntitiesInside
	@within Observer
	@return { Entity }
]=]
function Observer.getEntitiesInside(self: Types.InternalObserver): { Types.Entity }
	local entities = State.observerTrackingEntities[self.id]
	if not entities then
		return {}
	end
	local results = {}
	for entity, _ in entities do
		table.insert(results, entity)
	end
	return results
end

--[=[ 
	Returns a list of all players currently inside zones attached to this observer.

	@method getPlayersInside
	@within Observer
	@return { Player }
]=]
function Observer.getPlayersInside(self: Types.InternalObserver): { Player }
	local result = {}
	local entities = State.observerTrackingEntities[self.id]

	for entity in entities do
		local player = State.entityToPlayer[entity]
		if player and not table.find(result, player) then
			table.insert(result, player)
		end
	end
	return result
end

--[=[ 
	Returns the list of Zones currently attached to this observer.

	@method getZones
	@within Observer
	@return { Zone }
]=]
function Observer.getZones(self: Types.InternalObserver): { Types.Zone }
	local results = {}
	for zoneId, attachedList in State.zoneAttachedObservers do
		if not table.find(attachedList, self.id) then
			continue
		end

		local zone = State.zoneIdToZoneObj[zoneId]
		if zone then
			table.insert(results, zone)
		end
	end
	return results
end

--[=[ 
	Returns the list of Groups currently monitored by this observer.
	
	@method getGroups
	@within Observer
	@return { Group }
]=]
function Observer.getGroups(self: Types.InternalObserver): { Types.Group }
	local result = {}

	for groupId, observersMap in State.groupToObservers do
		if not observersMap[self.id] then
			continue
		end

		local group = State.groups[groupId]
		if group then
			table.insert(result, group)
		end
	end

	return result
end

--[=[ 
	Returns the specific Zone this entity is currently tracked under for this Observer.

	@method getEntityInZone
	@within Observer
	@param entity Entity -- The entity to get the zone for
	@return Zone?
]=]
function Observer.getZoneOfEntity(self: Types.InternalObserver, entity: Types.Entity): Types.Zone?
	local data = State.entityData[entity]
	if not data then
		return nil
	end

	local zoneId = data.activeObserverMemberships[self.id]
	if zoneId then
		return State.zoneIdToZoneObj[zoneId]
	end
	return nil
end

--[=[ 
	Returns the specific Zone a player is currently tracked under for this Observer.

	@method getPlayerInZone
	@within Observer
	@param player Player -- The player to get the zone for
	@return Zone?
]=]
function Observer.getZoneOfPlayer(self: Types.InternalObserver, player: Player): Types.Zone?
	local character = player.Character
	if not character then
		return nil
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return nil
	end

	return self:getZoneOfEntity(hrp)
end

--[=[ 
	Iterates over all entities currently inside zones attached to this observer.
	This provides a zero-allocation way to loop through entities, ideal for high-frequency 
	checks.

	```lua
	for entity in observer:iterEntitiesInside() do
		print(entity.Name .. " is inside!")
	end
	```

	@method iterEntitiesInside
	@within Observer
	@return () -> Entity?
]=]
function Observer.iterEntitiesInside(self: Types.InternalObserver): () -> Types.Entity?
	local entities = State.observerTrackingEntities[self.id]
	local entity = nil

	return function()
		entity = next(entities, entity)
		return entity
	end
end

--[=[ 
	Iterates over all players currently inside zones attached to this observer.
	Minimizes GC pressure for high-frequency polling.

	@method iterPlayersInside
	@within Observer
	@return () -> Player?
]=]
function Observer.iterPlayersInside(self: Types.InternalObserver): () -> Player?
	local entities = State.observerTrackingEntities[self.id]
	local entity = nil

	return function()
		while true do
			entity = next(entities, entity)

			if not entity then
				return nil
			end

			local player = State.entityToPlayer[entity]
			if not player then
				continue
			end

			return player
		end
	end
end

--[=[ 
	Iterates over all tracked entities and returns both the Entity and the specific 
	Zone they are currently in for this observer.

	```lua
	for entity, zone in observer:iterZonesOfEntities() do
		print(entity.Name .. " is in " .. zone:getId())
	end
	```

	@method iterZonesOfEntities
	@within Observer
	@return () -> (Entity?, Zone?)
]=]
function Observer.iterZonesOfEntities(self: Types.InternalObserver): () -> (Types.Entity?, Types.Zone?)
	local entities = State.observerTrackingEntities[self.id]
	local entity = nil

	return function()
		while true do
			entity = next(entities, entity)

			if not entity then
				return nil
			end

			local data = State.entityData[entity]
			if not data then
				continue
			end

			local zoneId = data.activeObserverMemberships[self.id]
			if not zoneId then
				continue
			end

			local zone = State.zoneIdToZoneObj[zoneId]
			if not zone then
				continue
			end

			return entity, zone
		end
	end
end

--[=[ 
	Iterates over all tracked players and returns both the Player and the specific 
	Zone their primary entity is currently in for this observer.

	@method iterZonesOfPlayers
	@within Observer
	@return () -> (Player?, Types.Zone?)
]=]
function Observer.iterZonesOfPlayers(self: Types.InternalObserver): () -> (Player?, Types.Zone?)
	local entities = State.observerTrackingEntities[self.id]
	local entity = nil

	return function()
		while true do
			entity = next(entities, entity)

			if not entity then
				return nil
			end

			local player = State.entityToPlayer[entity]
			if not player then
				continue
			end

			local data = State.entityData[entity]
			if not data then
				continue
			end

			local zoneId = data.activeObserverMemberships[self.id]
			if not zoneId then
				continue
			end

			local zone = State.zoneIdToZoneObj[zoneId]
			if not zone then
				continue
			end

			return player, zone
		end
	end
end

--[=[ 
	Fires when `destroy()` is called on the observer

	```lua
	local disconnect = myObserver:onDestroy(function()
		print('Observer was destroyed!')
	end)
	```

	@tag Event
	@method onDestroy
	@within Observer
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Observer.onDestroy(self: Types.InternalObserver, callback: () -> ()): () -> ()
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
	Cleans up the observer, disables tracking, and unsubscribes it from all groups and zones.
	
	@tag Destructor
	@method destroy
	@within Observer
]=]
function Observer.destroy(self: Types.InternalObserver): ()
	if self.onDestroyCallbacks then
		for _, callback in self.onDestroyCallbacks do
			task.spawn(callback)
		end
		table.clear(self.onDestroyCallbacks)
	end

	self:setEnabled(false)

	local id = self.id
	for _, observers in State.groupToObservers do
		observers[id] = nil
	end

	for _, attachedList in State.zoneAttachedObservers do
		local idx = table.find(attachedList, id)
		while idx do
			table.remove(attachedList, idx)
			idx = table.find(attachedList, id)
		end
	end

	State.observerPriorityMap[id] = nil
	State.observerEnteredCallbacks[id] = nil
	State.observerExitedCallbacks[id] = nil
	State.observerTransitionedCallbacks[id] = nil
	State.observerTrackingEntities[id] = nil
	State.observerIdToObserverObj[id] = nil
	State.observerEnabled[id] = nil
	State.observerSafety[id] = nil

	State.spatialVersion += 1
	setmetatable(self :: any, nil)
end

return Observer

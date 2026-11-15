--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Callbacks = require(script.Parent.Parent.Core.Callbacks)
local GroupPresence = require(script.Parent.Parent.Core.GroupPresence)
local References = require(script.Parent.Parent.Core.References)
local Registry = require(script.Parent.Parent.Core.Registry)
local Types = require(script.Parent.Parent.Types)
local Log = require(script.Parent.Parent.Utils.Log)

local isPlayer = References.isPlayer

local IS_CLIENT = RunService:IsClient()

local checkCallback = Log.checkCallback

-- Also true after destroy, so a late cleanup still runs in its own thread
local function isSafe(observerId: number): boolean
	return Registry.observerSafety[observerId] ~= false
end

local function forPlayers(callback: (Player, Types.Zone, Types.Entity) -> any): (any, Types.Zone, Types.Entity) -> any
	checkCallback(callback)
	return function(reference, zone, entity)
		if isPlayer(reference) then
			return callback(reference, zone, entity)
		end
		return nil
	end
end

local function forLocalPlayer(
	methodName: string,
	callback: (Types.Zone, Types.Entity) -> any
): (any, Types.Zone, Types.Entity) -> any
	checkCallback(callback)
	if not IS_CLIENT then
		Log.fatal('Observer:%s can only be called on the Client.', nil, methodName)
	end
	return function(reference, zone, entity)
		if reference == Players.LocalPlayer then
			return callback(zone, entity)
		end
		return nil
	end
end

local function groupEvent(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone, Types.Entity) -> (),
	onArrive: boolean
): () -> ()
	checkCallback(callback)
	local observerId = self.id
	local function fire(_, group, zone, entity)
		Callbacks.call(callback, isSafe(observerId), group, zone, entity)
	end
	local function ignore() end
	return GroupPresence.track(observerId, if onArrive then fire else ignore, if onArrive then ignore else fire)
end

local ObserverEvents = {}

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
	@param callback (entity: any, zone: Zone, physicalEntity: Entity) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.observe(
	self: Types.InternalObserver,
	callback: (any, Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	checkCallback(callback)
	local cleanups = {} :: { [Types.Entity]: () -> () }
	local activeIds = {} :: { [Types.Entity]: number }
	local nextGeneration = 0

	local cleanupEnter = self:onEnter(function(reference, zone, entity: any)
		nextGeneration += 1
		local generation = nextGeneration
		activeIds[entity] = generation

		local cleanup = callback(reference, zone, entity)

		if activeIds[entity] ~= generation then
			if type(cleanup) == 'function' then
				cleanup()
			end
			return
		end

		if type(cleanup) == 'function' then
			cleanups[entity] = cleanup
		end
	end)

	local cleanupExit = self:onExit(function(_, _, entity: any)
		activeIds[entity] = nil

		local cleanup = cleanups[entity]
		if cleanup then
			cleanups[entity] = nil
			cleanup()
		end
	end)

	local function disconnect()
		cleanupEnter()
		cleanupExit()

		table.clear(activeIds)

		for entity, cleanup in cleanups do
			cleanups[entity] = nil
			task.spawn(cleanup)
		end
	end

	local disconnectDestroy = self:onDestroy(disconnect)

	return function()
		disconnectDestroy()
		disconnect()
	end
end

--[=[ 
	Fires when any entity from a subscribed group enters a zone attached to this observer.

	```lua
	local disconnect = observer:onEnter(function(entity, zone)
		print(entity.Name .. ' entered ' .. zone.id)
	end)
	```

	@tag Event
	@method onEnter
	@within Observer
	@param callback (entity: any, zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onEnter(self: Types.InternalObserver, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	checkCallback(callback)
	return Callbacks.connect(Callbacks.observerEnteredCallbacks, self.id, callback)
end

--[=[ 
	Fires when an entity exits all zones attached to this observer.

	@tag Event
	@method onExit
	@within Observer
	@param callback (entity: any, zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onExit(self: Types.InternalObserver, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	checkCallback(callback)
	return Callbacks.connect(Callbacks.observerExitedCallbacks, self.id, callback)
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
	@param callback (player: Player, zone: Zone, physicalEntity: Entity) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.observePlayer(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	return self:observe(forPlayers(callback))
end

--[=[ 
	Specialized event for Player entities.

	```lua
	observer:onPlayerEnter(function(player, zone)
		print(player.Name .. " entered safe zone " .. zone:getId())
		
		-- Play a sound
		local sound = workspace.Sounds.SafeZoneEnter:Clone()
		sound.Parent = player.Character.PrimaryPart
		sound:Play()
		game.Debris:AddItem(sound, 2)
	end)
	```

	@tag Event
	@method onPlayerEnter
	@within Observer
	@param callback (player: Player, zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onPlayerEnter(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onEnter(forPlayers(callback))
end

--[=[ 
	A specialized event for Player entities. Fires when a player's character 
	exits all zones attached to this observer.

	@tag Event
	@method onPlayerExit
	@within Observer
	@param callback (player: Player, zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onPlayerExit(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onExit(forPlayers(callback))
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
	@param callback (zone: Zone, physicalEntity: Entity) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.observeLocalPlayer(
	self: Types.InternalObserver,
	callback: (Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	return self:observe(forLocalPlayer('observeLocalPlayer', callback))
end

--[=[ 
	Specialized event for the LocalPlayer.

	```lua
	observer:onLocalPlayerEnter(function(zone)
		print("You entered zone " .. zone:getId())
		
		local char = player.Character
		if char and char:FindFirstChild("Humanoid") then
			char.Humanoid.WalkSpeed = 24
		end
	end)
	```

	@client
	@tag Event
	@method onLocalPlayerEnter
	@within Observer
	@param callback (zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onLocalPlayerEnter(
	self: Types.InternalObserver,
	callback: (Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onEnter(forLocalPlayer('onLocalPlayerEnter', callback))
end

--[=[ 
	A specialized event for the LocalPlayer. Fires when the local player's 
	character exits all zones attached to this observer.

	@client
	@tag Event
	@method onLocalPlayerExit
	@within Observer
	@param callback (zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onLocalPlayerExit(
	self: Types.InternalObserver,
	callback: (Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onExit(forLocalPlayer('onLocalPlayerExit', callback))
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
	@param callback (group: Group, zone: Zone, physicalEntity: Entity) -> (() -> ())?
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.observeGroup(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone, Types.Entity) -> (() -> ())?
): () -> ()
	checkCallback(callback)
	local observerId = self.id
	local cleanups = {} :: { [number]: () -> () }
	-- Bumped on arrive and leave, so a cleanup returned after its group left still runs
	local generations = {} :: { [number]: number }
	local disconnected = false

	local disconnectTracker = GroupPresence.track(observerId, function(groupId, group, zone, entity)
		local generation = (generations[groupId] or 0) + 1
		generations[groupId] = generation
		Callbacks.call(function()
			local cleanup = callback(group, zone, entity)
			if type(cleanup) ~= 'function' then
				return
			end
			if disconnected or generations[groupId] ~= generation then
				cleanup()
			else
				cleanups[groupId] = cleanup
			end
		end, isSafe(observerId))
	end, function(groupId)
		generations[groupId] = (generations[groupId] or 0) + 1
		local cleanup = cleanups[groupId]
		if cleanup then
			cleanups[groupId] = nil
			Callbacks.call(cleanup, isSafe(observerId))
		end
	end)

	return function()
		if disconnected then
			return
		end
		disconnected = true
		disconnectTracker()
		for groupId, cleanup in cleanups do
			cleanups[groupId] = nil
			task.spawn(cleanup)
		end
	end
end

--[=[ 
	Fires when the first member of a Group enters any zone attached to this observer.
	Subsequent entries by other members of the same group will not trigger this event
	until the group has completely exited and re-entered.

	@tag Event
	@method onGroupEnter
	@within Observer
	@param callback (group: Group, zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onGroupEnter(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone, Types.Entity) -> ()
): () -> ()
	return groupEvent(self, callback, true)
end

--[=[ 
	Fires when the last remaining member of a Group exits all zones attached to 
	this observer. This is useful for "cleared" states or stopping group-wide effects.

	@tag Event
	@method onGroupExit
	@within Observer
	@param callback (group: Group, zone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onGroupExit(
	self: Types.InternalObserver,
	callback: (Types.Group, Types.Zone, Types.Entity) -> ()
): () -> ()
	return groupEvent(self, callback, false)
end

--[=[ 
	Fires when an entity seamlessly transitions from one attached zone to another 
	overlapping attached zone.

	@tag Event
	@method onTransition
	@within Observer
	@param callback (entity: any, newZone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onTransition(
	self: Types.InternalObserver,
	callback: (any, Types.Zone, Types.Entity) -> ()
): () -> ()
	checkCallback(callback)
	return Callbacks.connect(Callbacks.observerTransitionedCallbacks, self.id, callback)
end

--[=[ 
	Specialized event for Player entities transitioning between overlapping zones.
	
	@tag Event
	@method onPlayerTransition
	@within Observer
	@param callback (player: Player, newZone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onPlayerTransition(
	self: Types.InternalObserver,
	callback: (Player, Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onTransition(forPlayers(callback))
end

--[=[ 
	Specialized event for the LocalPlayer transitioning between overlapping zones.
	
	@client
	@tag Event
	@method onLocalPlayerTransition
	@within Observer
	@param callback (newZone: Zone, physicalEntity: Entity) -> ()
	@return () -> () -- Disconnect function
]=]
function ObserverEvents.onLocalPlayerTransition(
	self: Types.InternalObserver,
	callback: (Types.Zone, Types.Entity) -> ()
): () -> ()
	return self:onTransition(forLocalPlayer('onLocalPlayerTransition', callback))
end

return ObserverEvents

--!strict
--[=[ 
	@class Observer

	Observers are the logical bridge between Groups and Zones.
	They monitor specific groups and trigger events when entities within those 
	groups enter or exit any zones associated with the observer.
]=]

local Config = require(script.Parent.Parent.Config)
local Registry = require(script.Parent.Parent.Core.Registry)
local Wiring = require(script.Parent.Parent.Core.Wiring)
local Types = require(script.Parent.Parent.Types)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Log = require(script.Parent.Parent.Utils.Log)
local Checks = require(script.Parent.Checks)
local ObserverEvents = require(script.Parent.ObserverEvents)
local ObserverQueries = require(script.Parent.ObserverQueries)
local Zones = require(script.Parent.Zones)

local checkZone = Checks.checkZone

local hasAttachedMap = {} :: { [number]: boolean }
local hasSubscribedMap = {} :: { [number]: boolean }

-- Settings are checked where they are given, as a NaN would quietly break every later tick
local function checkPriority(p: any): number
	if type(p) ~= 'number' or p ~= p then
		Log.fatal('priority must be a number, got %s.', nil, tostring(p))
	end
	return p
end

local function checkUpdateRate(hz: any): number
	if type(hz) ~= 'number' or not (hz > 0) then
		Log.fatal('updateRate must be greater than 0. Use setEnabled(false) to stop an observer.', nil)
	end
	return hz
end

local function checkPrecision(n: any): number
	if type(n) ~= 'number' or not (n >= 0) then
		Log.fatal('precision must be non-negative.', nil)
	end
	return n
end

local function checkGroup(group: any)
	-- A destroyed group is no longer registered, and gets its own error below
	local isGroup = type(group) == 'table'
		and type(group.id) == 'number'
		and (Registry.groups[group.id] == group or Destroyed.isDestroyed(group))
	if not isGroup then
		Log.fatal('Expected a Group, got %s.', nil, tostring(group))
	end
	if Destroyed.isDestroyed(group) then
		Log.fatal('Group %d is destroyed.', nil, group.id)
	end
end

local Observer = {}
Observer.__index = Observer

--[=[ 
	Creates an Observer. Observers listen for entities subscribed Groups entering or exiting attached Zones.

	```lua
	local observer = QuickZone.Observer.new({
		groups = { enemyGroup, playerGroup }, -- Immediately subscribe to these groups
		zones = { damageZone }, -- Immediately attach to these zones
		priority = 20, -- The priority value is used to resolve overlaps (defaults to 0)
		updateRate = 20, -- Check at 20Hz (defaults to 30)
		precision = 0.5, -- Ignore movement smaller than 0.5 studs (defaults to 0.1)
		enabled = false, -- Observer will not start processing spatial checks (defaults to true)
		safety = false, -- Call callbacks directly instead of through task.spawn (defaults to true)
	})
	```

	:::warning Safety 
	If safety is set to false, callbacks run directly and must not yield. One that yields holds back every
	update until it resumes, and QuickZone warns about it. Errors are still reported rather than thrown.
	Only set it to false if you do not want the overhead of virtual threads.
	:::

	:::info Resolution Priority
	When an entity is inside multiple zones watched by different observers, 
	higher priority observers take complete control.
	:::

	:::note Dynamic Instantiation
	QuickZone will warn you if an Observer is created without groups or zones. 
	To suppress this warning when building observers dynamically, 
	explicitly pass an empty table (`zones = {}`) or instantiate the observer as disabled (`enabled = false`).
	:::

	@tag Constructor
	@tag Chainable
	@param config { groups: { Types.Group }?, zones: { Types.Zone | Types.Zones }?, priority: number?, updateRate: number?, precision: number?, enabled: boolean?, safety: boolean? }?
	@return Observer
]=]
function Observer.new<T>(config: {
	groups: { Types.Group<T> }?,
	zones: { Types.Zone | Types.Zones }?,
	priority: number?,
	updateRate: number?,
	precision: number?,
	enabled: boolean?,
	safety: boolean?,
}?): Types.Observer
	local priority = checkPriority(config and config.priority or 0)
	local updateRate = checkUpdateRate(config and config.updateRate or Config.Observer.updateRate)
	local precision = checkPrecision(config and config.precision or Config.Observer.precision)
	-- All checked before anything is registered, so a bad entry can't leave a half-made observer behind
	for _, zone in config and config.zones or {} do
		checkZone(zone)
	end
	for _, group in config and config.groups or {} do
		checkGroup(group)
	end

	local id = Registry.nextObserverId
	Registry.nextObserverId += 1

	local self: Types.InternalObserver<T> = setmetatable({
		id = id,
		phase = 'alive',
	}, Observer) :: any

	Registry.observerIdToObserverObj[id] = self
	Wiring.addObserver(id, {
		priority = priority,
		updateRate = updateRate,
		precision = precision,
		enabled = if config and config.enabled ~= nil then not not config.enabled else true,
		safety = if config and config.safety ~= nil then not not config.safety else Config.Observer.safety,
	})

	hasAttachedMap[id] = false
	hasSubscribedMap[id] = false

	if config and config.zones then
		for _, zone in config.zones do
			self:attach(zone)
		end
	end

	if config and config.groups then
		for _, group in config.groups do
			self:subscribe(group)
		end
	end

	-- If a user passes a table, the warning is suppressed
	local explicitlyPassedZones = config and config.zones ~= nil
	local explicitlyPassedGroups = config and config.groups ~= nil

	-- Without a table nothing was attached or subscribed above, so whether one came later is checked when deferred
	local missingZones = not explicitlyPassedZones
	local missingGroups = not explicitlyPassedGroups

	if missingZones or missingGroups then
		local creationTrace = debug.traceback('', 2)

		task.defer(function()
			-- Ensure the observer wasn't destroyed or disabled
			if Destroyed.isDestroyed(self) or not self:isEnabled() then
				return
			end

			-- Check if :attach() or :subscribe() was used instead
			if missingZones and not hasAttachedMap[id] then
				Log.warn('Observer %d has no attached zones. It will not detect spatial queries.', creationTrace, id)
			end
			if missingGroups and not hasSubscribedMap[id] then
				Log.warn('Observer %d has no subscribed groups. It will not track any entities.', creationTrace, id)
			end
		end)
	end

	return self
end

--[=[ 
	Links this observer to the specified group. The observer will only
	track entities that belong to subscribed groups.

	```lua
	observer:subscribe(playerGroup):subscribe(enemyGroup)
	```

	@tag Chainable
	@method subscribe
	@within Observer
	@param group Group -- The group to monitor.
	@return Observer
]=]
function Observer.subscribe(self: Types.InternalObserver, group: Types.InternalGroup): Types.Observer
	checkGroup(group)
	-- From a callback during its destroy, which has let go of its groups or is about to
	if Destroyed.isDestroyed(self) then
		return self
	end
	hasSubscribedMap[self.id] = true

	Wiring.subscribe(self.id, group.id)
	return self
end

--[=[ 
	Stops the observer from monitoring the specified group.

	@tag Chainable
	@method unsubscribe
	@within Observer
	@param group Group -- The group to stop monitoring.
	@return Observer
]=]
function Observer.unsubscribe(self: Types.InternalObserver, group: Types.InternalGroup): Types.Observer
	-- Destroying a group already unsubscribed it
	if Destroyed.isDestroyed(group) then
		return self
	end
	checkGroup(group)

	Wiring.unsubscribe(self.id, group.id)
	return self
end

--[=[ 
	Attaches the Observer to a zone. The observer will begin 
	monitoring this area for entity overlaps.

	```lua
	-- You are also able to chain calls
	observer:attach(zone1)
		:attach(zone2)
		:attach(zone3)
	```

	@tag Chainable
	@method attach
	@within Observer
	@param zone Zone | Zones -- The zone to link.
	@return Observer
]=]
function Observer.attach(self: Types.InternalObserver, zone: any)
	checkZone(zone)
	-- From a callback during its destroy, which has let go of its zones or is about to
	if Destroyed.isDestroyed(self) then
		return self
	end
	hasAttachedMap[self.id] = true

	if getmetatable(zone) == Zones then
		zone:_attachObserver(self)
	elseif not Destroyed.isDestroyed(zone) then
		Wiring.attach(zone.slot, self.id)
	end
	return self
end

--[=[ 
	Detaches the Observer from the zone. Its entities in the zone leave on the next update,
	or move to another of its zones that holds them.

	@tag Chainable
	@method detach
	@within Observer
	@param zone Zone | Zones -- The zone to unlink.
	@return Observer
]=]
function Observer.detach(self: Types.InternalObserver, zone: any)
	-- Destroying a zone already detached it
	if Destroyed.isDestroyed(zone) then
		return self
	end
	checkZone(zone)

	if getmetatable(zone) == Zones then
		zone:_detachObserver(self)
	else
		Wiring.detach(zone.slot, self.id)
	end
	return self
end

--[=[ 
	Enables or disables the observer. When disabled, it fires no events. Its entities are still
	checked each update, so it stays cheap to enable again but costs about as much as an enabled one.

	@tag Chainable
	@method setEnabled
	@within Observer
	@param enabled boolean
	@return Observer
]=]
function Observer.setEnabled(self: Types.InternalObserver, enabled: boolean): Types.Observer
	Wiring.setEnabled(self.id, not not enabled)
	return self
end

--[=[
	Whether to wrap callbacks in task.spawn (safe) or not (unsafe).

	:::warning Safety 
	Unsafe callbacks run directly and must not yield. One that yields holds back every update until it resumes,
	and QuickZone warns about it.
	:::

	@tag Chainable
	@method setSafety
	@within Observer
	@param enabled boolean
	@return Observer
]=]
function Observer.setSafety(self: Types.InternalObserver, enabled: boolean): Types.Observer
	Wiring.setSafety(self.id, not not enabled)
	return self
end

--[=[ 
	Updates the resolution priority of the observer.

	@tag Chainable
	@method setPriority
	@within Observer
	@param p number
	@return Observer
]=]
function Observer.setPriority(self: Types.InternalObserver, p: number): Types.Observer
	Wiring.setPriority(self.id, checkPriority(p))
	return self
end

--[=[ 
	Updates the update frequency for this observer, in checks per second. Must be greater than 0;
	use `setEnabled(false)` to stop an observer.

	@tag Chainable
	@method setUpdateRate
	@within Observer
	@param hz number
	@return Observer
]=]
function Observer.setUpdateRate(self: Types.InternalObserver, hz: number): Types.Observer
	Wiring.setUpdateRate(self.id, checkUpdateRate(hz))
	return self
end

--[=[ 
	Updates the precision in studs for this observer.

	@tag Chainable
	@method setPrecision
	@within Observer
	@param n number
	@return Observer
]=]
function Observer.setPrecision(self: Types.InternalObserver, n: number): Types.Observer
	Wiring.setPrecision(self.id, checkPrecision(n))
	return self
end

--[=[ 
	Checks if the observer is currently enabled.

	@method isEnabled
	@within Observer
	@return boolean
]=]
function Observer.isEnabled(self: Types.InternalObserver): boolean
	return Registry.observerEnabled[self.id] ~= false
end

--[=[ 
	Checks if the observer wraps callbacks in task.spawn (safe) or not (unsafe).

	@method isSafe
	@within Observer
	@return boolean
]=]
function Observer.isSafe(self: Types.InternalObserver): boolean
	return Registry.observerSafety[self.id]
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
	return Registry.observerPriorityMap[self.id]
end

--[=[ 
	Returns the current update frequency for this observer.

	@method getUpdateRate
	@within Observer
	@return number
]=]
function Observer.getUpdateRate(self: Types.InternalObserver): number
	return Registry.observerUpdateRate[self.id]
end

--[=[ 
	Returns the precision of this observer, in studs.

	@method getPrecision
	@within Observer
	@return number
]=]
function Observer.getPrecision(self: Types.InternalObserver): number
	return math.sqrt(Registry.observerPrecisionSq[self.id])
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
	return Destroyed.connect(self, callback)
end

--[=[ 
	Cleans up the observer, disables tracking, and unsubscribes it from all groups and zones.
	Destroying it again does nothing. Its other methods raise an error once it is destroyed.
	
	@tag Destructor
	@method destroy
	@within Observer
]=]
function Observer.destroy(self: Types.InternalObserver): ()
	-- A callback below may destroy the observer again
	if not Destroyed.begin(self) then
		return
	end

	Destroyed.fireCallbacks(self.onDestroyCallbacks)

	local id = self.id
	Wiring.removeObserver(id)
	Registry.observerIdToObserverObj[id] = nil

	hasAttachedMap[id] = nil
	hasSubscribedMap[id] = nil

	Destroyed.finish(self)
end

-- Its events and queries are kept in their own files
for name, method in ObserverEvents do
	(Observer :: any)[name] = method
end
for name, method in ObserverQueries do
	(Observer :: any)[name] = method
end

return Observer

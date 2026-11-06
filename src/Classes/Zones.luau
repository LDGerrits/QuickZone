--!strict
--[=[
	@class Zones

	Zones manages multiple individual `Zone` objects as a single, unified entity. 
	This allows you to create complex shapes and structures by combining multiple zones together. 
	Attaching a `Zones` to an observer attaches every zone in it. Zones added to or removed from it later are
	attached and detached accordingly.
]=]

local State = require(script.Parent.Parent.Core.State)
local Types = require(script.Parent.Parent.Types)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)

local Zones = {}
Zones.__index = Zones

function Zones.new(config: { isDynamic: boolean?, autoSync: boolean?, metadata: any? }?): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local self: Types.InternalZones = setmetatable({
		-- Auto-synced zones are always dynamic
		dynamic = not not (isDynamic or autoSync),
		metadata = metadata,
		autoSync = not not autoSync,
		zones = {} :: { [Types.Zone]: boolean },
		observers = {} :: { [Types.Observer<any>]: boolean },
		onDestroyObserverCleanups = {} :: { [Types.Observer<any>]: () -> () },
		onDestroyZoneCleanups = {} :: { [Types.Zone]: () -> () },
	}, Zones) :: any

	return self
end

-- private, use Observer:attach
function Zones.attach(self: Types.InternalZones, observer: any): Types.Zones
	if self.observers[observer] then
		return self
	end
	self.observers[observer] = true

	self.onDestroyObserverCleanups[observer] = observer:onDestroy(function()
		self:detach(observer)
	end)

	for zone, _ in self.zones do
		observer:attach(zone)
	end

	return self
end

-- private, use Observer:detach
function Zones.detach(self: Types.InternalZones, observer: any): Types.Zones
	if not self.observers[observer] then
		return self
	end
	self.observers[observer] = nil

	local cleanup = self.onDestroyObserverCleanups[observer]
	if cleanup then
		cleanup()
		self.onDestroyObserverCleanups[observer] = nil
	end

	for zone, _ in self.zones do
		observer:detach(zone)
	end

	return self
end

--[=[ 
	Syncs every underlying zone to its part, as `Zone:sync` does. Static zones force a rebuild of the
	static tree, so prefer dynamic zones for parts that move often.

	@tag Chainable
	@method sync
	@within Zones
	@return Zones
]=]
function Zones.sync(self: Types.InternalZones): Types.Zones
	for zone, _ in self.zones do
		if zone:getReference() then
			zone:sync()
		end
	end
	return self
end

--[=[ 
	Returns an array of all individual Zone objects currently managed.

	@method getZones
	@within Zones
	@return { Zone }
]=]
function Zones.getZones(self: Types.InternalZones): { Types.Zone }
	local result = {}
	for zone, _ in self.zones do
		table.insert(result, zone)
	end
	return result
end

--[=[ 
	Returns whether Zones is set to dynamic.

	@method isDynamic
	@within Zones
	@return boolean
]=]
function Zones.isDynamic(self: Types.InternalZones): boolean
	return self.dynamic
end

--[=[ 
	Checks if a given Vector3 point resides inside of the underlying zones.

	@method isPointInside
	@within Zones
	@param point Vector3
	@return boolean
]=]
function Zones.isPointInside(self: Types.InternalZones, point: Vector3): boolean
	for zone, _ in self.zones do
		if zone:isPointInside(point) then
			return true
		end
	end
	return false
end

--[=[ 
	Enables or disables automatic polling and syncing to the tracked BaseParts for all underlying zones.
	If any zones are currently static, they will automatically be set to dynamic.

	@tag Chainable
	@method setAutoSync
	@within Zones
	@param autoSync boolean
	@return Zones
]=]
function Zones.setAutoSync(self: Types.InternalZones, autoSync: boolean): Types.Zones
	-- Applied to every zone even when unchanged, as single zones may have been changed directly
	autoSync = not not autoSync
	self.autoSync = autoSync
	if autoSync then
		self.dynamic = true
	end

	for zone, _ in self.zones do
		zone:setAutoSync(autoSync)
	end

	return self
end

--[=[ 
	Promotes or demotes all underlying zones between the Static and Dynamic trees.
	
	:::info Performance
	Changing a zone's dynamic state forces both the static and dynamic trees to rebuild. 
	:::

	@tag Chainable
	@method setDynamic
	@within Zones
	@param isDynamic boolean
	@return Zones
]=]
function Zones.setDynamic(self: Types.InternalZones, isDynamic: boolean): Types.Zones
	-- Applied to every zone even when unchanged, as single zones may have been changed directly. Static
	-- zones stop auto-syncing, as each zone does
	isDynamic = not not isDynamic
	self.dynamic = isDynamic
	if not isDynamic then
		self.autoSync = false
	end

	for zone, _ in self.zones do
		zone:setDynamic(isDynamic)
	end

	return self
end

--[=[
	Sets metadata to all underlying zones.

	@tag Chainable
	@method setMetadata
	@within Zones
	@param metadata any
	@return Zones
]=]
function Zones.setMetadata(self: Types.InternalZones, metadata: any): Types.Zones
	self.metadata = metadata
	for zone, _ in self.zones do
		zone:setMetadata(metadata)
	end
	return self
end

--[=[ 
	Returns the metadata.

	@method getMetadata
	@within Zones
	@return any
]=]
function Zones.getMetadata(self: Types.InternalZones): any?
	return self.metadata
end

--[=[ 
	Checks if a specific Zone object is managed by this Zones collection.

	@method contains
	@within Zones
	@param zone Zone
	@return boolean
]=]
function Zones.contains(self: Types.InternalZones, zone: Types.Zone): boolean
	return self.zones[zone] == true
end

--[=[
	Returns an iterator for all Zones within this group.
	Safe to use while zones are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterZones
	@within Zones
	@return () -> Zone?
]=]
function Zones.iterZones(self: Types.InternalZones): () -> Types.Zone?
	local nextZone = Snapshot.keys(self.zones)
	return function(): Types.Zone?
		return (nextZone())
	end
end

--[=[ 
	Returns an array of all references from the underlying zones.

	@method getReferences
	@within Zones
	@return { BasePart | Attachment | Bone }
]=]
function Zones.getReferences(self: Types.InternalZones): { BasePart | Attachment | Bone }
	local results = {}
	for zone, _ in self.zones do
		local ref = zone:getReference()
		if ref then
			table.insert(results, ref)
		end
	end
	return results
end

--[=[
	Returns an iterator for all references within this group of zones.
	Safe to use while zones are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.
	Yields both the reference and the specific Zone it belongs to.

	@method iterReferences
	@within Zones
	@return () -> ((BasePart | Attachment | Bone)?, Zone?)
]=]
function Zones.iterReferences(self: Types.InternalZones): () -> ((BasePart | Attachment | Bone)?, Types.Zone?)
	local nextZone = Snapshot.keys(self.zones)

	return function()
		while true do
			local zone = nextZone()
			if not zone then
				return nil, nil
			end

			local ref = zone:getReference()
			if ref then
				return ref, zone
			end
		end
	end
end

--[=[ 
	Fires when `destroy()` is called on zones

	@tag Event
	@method onDestroy
	@within Zones
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Zones.onDestroy(self: Types.InternalZones, callback: () -> ()): () -> ()
	return Destroyed.connect(self, callback)
end

--[=[ 
	Cleans up the zones, removes them from the LBVH tree, and detaches all observers.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::
	
	@tag Destructor
	@method destroy
	@within Zones
]=]
function Zones.destroy(self: Types.InternalZones)
	-- A callback below may destroy the zones again
	if self.destroyed then
		return
	end
	self.destroyed = true

	-- Its zones go together, so an entity in several of them leaves once rather than moving through each
	local zoneIds = {}
	for zone in self.zones do
		local id = zone:getId()
		table.insert(zoneIds, id)
		State.zonesBeingDestroyed[id] = true
	end

	Destroyed.fireCallbacks(self.onDestroyCallbacks)

	for _, cleanup in self.onDestroyObserverCleanups do
		cleanup()
	end

	for zone, cleanup in self.onDestroyZoneCleanups do
		cleanup()
		zone:destroy()
	end
	-- Also for zones a callback took out before they were destroyed. Ids are never reused
	for _, id in zoneIds do
		State.zonesBeingDestroyed[id] = nil
	end

	table.clear(self.zones)
	table.clear(self.observers)
	table.clear(self.onDestroyObserverCleanups)
	table.clear(self.onDestroyZoneCleanups)

	setmetatable(self :: any, nil)
end

-- private
function Zones.add(self: Types.InternalZones, zone: Types.Zone)
	if self.zones[zone] then
		return
	end

	if self.metadata ~= nil and zone:getMetadata() == nil then
		zone:setMetadata(self.metadata)
	end

	zone:setDynamic(self.dynamic)
	zone:setAutoSync(self.autoSync)

	self.zones[zone] = true

	self.onDestroyZoneCleanups[zone] = zone:onDestroy(function()
		self:remove(zone)
	end)

	for observer, _ in self.observers do
		observer:attach(zone)
	end
end

-- private
function Zones.remove(self: Types.InternalZones, zone: Types.Zone)
	if not self.zones[zone] then
		return
	end
	self.zones[zone] = nil

	local cleanup = self.onDestroyZoneCleanups[zone]
	if cleanup then
		cleanup()
		self.onDestroyZoneCleanups[zone] = nil
	end

	for observer, _ in self.observers do
		observer:detach(zone)
	end
end

return Zones

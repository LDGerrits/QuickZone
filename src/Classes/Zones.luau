--!strict

local Types = require(script.Parent.Parent.Types)

--[=[ 
	Zones manages multiple individual `Zone` objects as a single, unified entity. 
	This allows you to create complex shapes and structures by combining multiple zones together. 
	You can attach observers to a `Zones` instance, and they will be automatically attached to all contained zones. 
	When a zone is added or removed from the `Zones` instance, observers will be updated accordingly.

	@class Zones
]=]
local Zones = {}
Zones.__index = Zones

--[=[ 
	Constructs a Zones object.

	@tag Constructor
	@param config { isDynamic: boolean?, metadata: any? }?
	@return Zones
]=]
function Zones.new(config: { isDynamic: boolean?, autoSyncToParts: boolean?, metadata: any? }?): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config then config.metadata else nil
	local autoSyncToParts = if config and config.autoSyncToParts ~= nil then config.autoSyncToParts else false

	local self: Types.InternalZones = setmetatable({
		dynamic = isDynamic,
		metadata = metadata,
		autoSyncToParts = autoSyncToParts,
		zones = {} :: { [Types.Zone]: boolean },
		observers = {} :: { [Types.Observer]: boolean },
		onDestroyObserverCleanups = {} :: { [Types.Observer]: () -> () },
		onDestroyZoneCleanups = {} :: { [Types.Zone]: () -> () },
	}, Zones) :: any

	return self
end

--[=[ 
	Attaches an Observer to all underlying zones.

	@method attach
	@within Zones
	@param observer Observer
	@return Zones
]=]
function Zones.attach(self: Types.InternalZones, observer: Types.Observer): Types.Zones
	if self.observers[observer] then
		return self
	end
	self.observers[observer] = true

	self.onDestroyObserverCleanups[observer] = observer:onDestroy(function()
		self:detach(observer)
	end)

	for zone, _ in self.zones do
		zone:attach(observer)
	end

	return self
end

--[=[ 
	Detaches an Observer from all underlying zones.

	@method detach
	@within Zones
	@param observer Observer
	@return Zones
]=]
function Zones.detach(self: Types.InternalZones, observer: Types.Observer): Types.Zones
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
		zone:detach(observer)
	end
	return self
end

--[=[ 
	Forces all dynamic underlying zones to recalculate their spatial geometry 
	based on the current physical CFrame, Size and Shape of their attached BaseParts.

	@method syncToParts
	@within Zones
	@return Zones
]=]
function Zones.syncToParts(self: Types.InternalZones): Types.Zones
	if not self.dynamic then
		return self
	end
	for zone, _ in self.zones do
		zone:syncToPart()
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
	Returns an array of all Observers currently attached.

	@method getObservers
	@within Zones
	@return { Observer }
]=]
function Zones.getObservers(self: Types.InternalZones): { Types.Observer }
	local result = {}
	for observer, _ in self.observers do
		table.insert(result, observer)
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

	@method setAutoSyncToParts
	@within Zones
	@param autoSyncToParts boolean
	@return Zones
]=]
function Zones.setAutoSyncToParts(self: Types.InternalZones, autoSyncToParts: boolean): Types.Zones
	if self.autoSyncToParts == autoSyncToParts then
		return self
	end

	self.autoSyncToParts = autoSyncToParts

	for zone, _ in self.zones do
		zone:setAutoSyncToPart(autoSyncToParts)
	end

	return self
end

--[=[ 
	Promotes or demotes all underlying zones between the Static and Dynamic trees.
	
	:::info Performance
	Changing a zone's dynamic state forces both the static and dynamic trees to rebuild. 
	:::

	@method setDynamic
	@within Zones
	@param isDynamic boolean
	@return Zones
]=]
function Zones.setDynamic(self: Types.InternalZones, isDynamic: boolean): Types.Zones
	if self.dynamic == isDynamic then
		return self
	end

	self.dynamic = isDynamic

	for zone, _ in self.zones do
		zone:setDynamic(isDynamic)
	end

	return self
end

--[=[
	Sets metadata to all underlying zones.

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
	Fires when `destroy()` is called on zones

	@tag Event
	@method onDestroy
	@within Zones
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Zones.onDestroy(self: Types.InternalZones, callback: () -> ()): () -> ()
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
	Cleans up the zones, removes them from the LBVH tree, and detaches all observers.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::
	
	@tag Destructor
	@method destroy
	@within Zones
]=]
function Zones.destroy(self: Types.InternalZones)
	if self.onDestroyCallbacks then
		for _, callback in self.onDestroyCallbacks do
			task.spawn(callback)
		end
		table.clear(self.onDestroyCallbacks)
	end

	for _, cleanup in self.onDestroyObserverCleanups do
		cleanup()
	end

	for zone, cleanup in self.onDestroyZoneCleanups do
		cleanup()
		zone:destroy()
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

	if self.dynamic and not zone:isDynamic() then
		zone:setDynamic(true)
	end

	if self.autoSyncToParts then
		zone:setAutoSyncToPart(true)
	end

	self.zones[zone] = true

	self.onDestroyZoneCleanups[zone] = zone:onDestroy(function()
		self:remove(zone)
	end)

	for observer, _ in self.observers do
		zone:attach(observer)
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
		zone:detach(observer)
	end
end

return Zones

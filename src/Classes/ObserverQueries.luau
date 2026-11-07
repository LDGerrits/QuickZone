--!strict

-- The Observer's queries: what is inside it, and where

local Entities = require(script.Parent.Parent.Core.Entities)
local Links = require(script.Parent.Parent.Core.Links)
local Memberships = require(script.Parent.Parent.Core.Memberships)
local References = require(script.Parent.Parent.Core.References)
local Registry = require(script.Parent.Parent.Core.Registry)
local ZoneShapes = require(script.Parent.Parent.Core.ZoneShapes)
local Types = require(script.Parent.Parent.Types)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)
local Checks = require(script.Parent.Checks)
local Zones = require(script.Parent.Zones)

local isPlayer = References.isPlayer
local checkZone = Checks.checkZone
local leavesAtPoint = ZoneShapes.leavesAtPoint
local leafContainsPoint = ZoneShapes.leafContainsPoint

local zoneAttachedObservers = Links.zoneAttachedObservers

local queryHits = {} :: { number }

-- Iterates the entities the observer has in a zone, as their references. Safe while entities enter and leave,
-- also when the loop yields across ticks, as each is checked again when reached
local function iterTracked(
	observerId: number,
	zoneIds: { [number]: true }?,
	playersOnly: boolean
): () -> (any?, Types.Zone?)
	local nextEntity = Snapshot.keys(Memberships.observerTrackingEntities[observerId] or {})
	return function()
		while true do
			local entity, zoneId = nextEntity()
			if entity == nil then
				return nil, nil
			elseif zoneIds and not zoneIds[zoneId :: number] then
				continue
			end

			local ref = References.entityToReference[entity] or entity
			if playersOnly and not isPlayer(ref) then
				continue
			end
			return ref, Registry.zoneIdToZoneObj[zoneId :: number]
		end
	end
end

-- The ids of a Zone, or of every zone in a Zones. Its entities are found while it is destroyed, until it is dead
local function zoneIdsOf(zone: any): { [number]: true }
	local ids = {}
	if Destroyed.isDead(zone) then
		return ids
	end
	checkZone(zone)
	if getmetatable(zone) == Zones then
		for _, inner in zone:getZones() do
			ids[inner:getId()] = true
		end
	else
		ids[zone:getId()] = true
	end
	return ids
end

local ObserverQueries = {}

--[=[ 
	Checks if a specific point in world space is inside any zone attached to this observer.
	
	@method isPointInside
	@within Observer
	@param position Vector3
	@return boolean
]=]
function ObserverQueries.isPointInside(self: Types.InternalObserver, position: Vector3): boolean
	local observerId = self.id

	local hitCount = leavesAtPoint(position, queryHits)
	for i = 1, hitCount do
		local hitId = queryHits[i]

		local observers = zoneAttachedObservers[hitId]
		if not observers or not table.find(observers, observerId) then
			continue
		end

		if leafContainsPoint(hitId, position) then
			return true
		end
	end

	return false
end

--[=[ 
	Returns a list of all tracked entities currently inside zones attached to this observer.

	@method getEntitiesInside
	@within Observer
	@return { any }
]=]
function ObserverQueries.getEntitiesInside(self: Types.InternalObserver): { any }
	local results = {}
	for entity in Memberships.observerTrackingEntities[self.id] do
		table.insert(results, References.entityToReference[entity] or entity)
	end
	return results
end

--[=[ 
	Returns a list of all players currently inside zones attached to this observer.

	@method getPlayersInside
	@within Observer
	@return { Player }
]=]
function ObserverQueries.getPlayersInside(self: Types.InternalObserver): { Player }
	local results = {}
	for entity in Memberships.observerTrackingEntities[self.id] do
		-- Only a player's current HumanoidRootPart has the player as its reference, so none comes twice
		local ref = References.entityToReference[entity]
		if isPlayer(ref) then
			table.insert(results, ref)
		end
	end
	return results
end

--[=[ 
	Returns the list of Zones currently attached to this observer.

	@method getZones
	@within Observer
	@return { Zone }
]=]
function ObserverQueries.getZones(self: Types.InternalObserver): { Types.Zone }
	local results = {}
	for slot, attachedList in Links.zoneAttachedObservers do
		if not table.find(attachedList, self.id) then
			continue
		end

		local zone = Registry.zoneSlotToZoneObj[slot]
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
function ObserverQueries.getGroups(self: Types.InternalObserver): { Types.Group }
	local result = {}

	for groupId, observersMap in Links.groupToObservers do
		if not observersMap[self.id] then
			continue
		end

		local group = Registry.groups[groupId]
		if group then
			table.insert(result, group)
		end
	end

	return result
end

--[=[ 
	Returns the specific Zone this entity is currently tracked under for this Observer.

	@method getZoneOfEntity
	@within Observer
	@param entity Entity -- The entity to get the zone for
	@return Zone?
]=]
function ObserverQueries.getZoneOfEntity(self: Types.InternalObserver, entity: any): Types.Zone?
	entity = References.entityOf(entity)

	local data = Entities.entityData[entity]
	if not data then
		return nil
	end

	local zoneId = data.activeObserverMemberships[self.id]
	if zoneId then
		return Registry.zoneIdToZoneObj[zoneId]
	end
	return nil
end

--[=[ 
	Returns the specific Zone a player is currently tracked under for this Observer.

	@method getZoneOfPlayer
	@within Observer
	@param player Player -- The player to get the zone for
	@return Zone?
]=]
function ObserverQueries.getZoneOfPlayer(self: Types.InternalObserver, player: Player): Types.Zone?
	return self:getZoneOfEntity(player)
end

--[=[ 
	Returns an array of all entities currently inside a specific zone attached to this observer.

	@method getEntitiesInZone
	@within Observer
	@param zone Zone | Zones
	@return { any }
]=]
function ObserverQueries.getEntitiesInZone(self: Types.InternalObserver, zone: Types.Zone | Types.Zones): { any }
	local results = {}

	for entity in self:iterEntitiesInZone(zone) do
		table.insert(results, entity)
	end

	return results
end

--[=[ 
	Returns an array of all players currently inside a specific zone attached to this observer.

	@method getPlayersInZone
	@within Observer
	@param zone Zone | Zones
	@return { Player }
]=]
function ObserverQueries.getPlayersInZone(self: Types.InternalObserver, zone: Types.Zone | Types.Zones): { Player }
	local results = {}

	for player in self:iterPlayersInZone(zone) do
		table.insert(results, player)
	end

	return results
end

--[=[ 
	Returns an iterator for all Zones currently attached to this observer.
	Safe to use while zones are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterZones
	@within Observer
	@return () -> Zone?
]=]
function ObserverQueries.iterZones(self: Types.InternalObserver): () -> Types.Zone?
	local nextSlot = Snapshot.keys(zoneAttachedObservers)
	local observerId = self.id

	return function(): Types.Zone?
		while true do
			local slot, attachedList = nextSlot()
			if not slot then
				return nil
			end

			if not table.find(attachedList :: { number }, observerId) then
				continue
			end

			local zone = Registry.zoneSlotToZoneObj[slot]
			if zone then
				return zone
			end
		end
	end
end

--[=[ 
	Returns an iterator for all Groups currently monitored by this observer.
	Safe to use while groups are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterGroups
	@within Observer
	@return () -> Group?
]=]
function ObserverQueries.iterGroups(self: Types.InternalObserver): () -> Types.Group?
	local nextGroupId = Snapshot.keys(Links.groupToObservers)
	local observerId = self.id

	return function(): Types.Group?
		while true do
			local groupId, observersMap = nextGroupId()
			if not groupId then
				return nil
			end

			if not (observersMap :: { [number]: boolean })[observerId] then
				continue
			end

			local group = Registry.groups[groupId]
			if group then
				return group
			end
		end
	end
end

--[=[ 
	Iterates over all entities currently inside zones attached to this observer.
	Yields both the Entity and the specific Zone they are in. Safe to use while entities enter and leave,
	also when the loop yields.

	@method iterEntitiesInside
	@within Observer
	@return () -> (Entity?, Zone?)
]=]
function ObserverQueries.iterEntitiesInside(self: Types.InternalObserver): () -> (any?, Types.Zone?)
	return iterTracked(self.id, nil, false)
end

--[=[ 
	Iterates over all players currently inside zones attached to this observer.
	Yields both the Player and the specific Zone they are in. Safe to use while players enter and leave,
	also when the loop yields.

	@method iterPlayersInside
	@within Observer
	@return () -> (Player?, Zone?)
]=]
function ObserverQueries.iterPlayersInside(self: Types.InternalObserver): () -> (Player?, Types.Zone?)
	return iterTracked(self.id, nil, true)
end

--[=[ 
	Iterates over all entities currently inside a specific zone, or any zone of a Zones,
	attached to this observer. Safe to use while entities enter and leave, also when the loop yields.

	@method iterEntitiesInZone
	@within Observer
	@param zone Zone | Zones
	@return () -> Entity?
]=]
function ObserverQueries.iterEntitiesInZone(
	self: Types.InternalObserver,
	zone: Types.Zone | Types.Zones
): () -> Types.Entity?
	local iterate = iterTracked(self.id, zoneIdsOf(zone), false)
	return function(): Types.Entity?
		return (iterate())
	end
end

--[=[ 
	Iterates over all players currently inside a specific zone, or any zone of a Zones,
	attached to this observer. Safe to use while players enter and leave, also when the loop yields.

	@method iterPlayersInZone
	@within Observer
	@param zone Zone | Zones
	@return () -> Player?
]=]
function ObserverQueries.iterPlayersInZone(self: Types.InternalObserver, zone: Types.Zone | Types.Zones): () -> Player?
	local iterate = iterTracked(self.id, zoneIdsOf(zone), true)
	return function(): Player?
		return (iterate())
	end
end

return ObserverQueries

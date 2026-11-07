--!strict

-- QuickZone's queries over everything that exists: entities, groups, observers and zones

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Parent.Core.Entities)
local PlayerTracker = require(script.Parent.Parent.Core.PlayerTracker)
local References = require(script.Parent.Parent.Core.References)
local Registry = require(script.Parent.Parent.Core.Registry)
local ZoneShapes = require(script.Parent.Parent.Core.ZoneShapes)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)

type Zone = Types.Zone
type Entity = Types.Entity

local isPlayer = References.isPlayer
local entityOf = References.entityOf

local leavesAtPoint = ZoneShapes.leavesAtPoint
local leafContainsPoint = ZoneShapes.leafContainsPoint
local containsPoint = ZoneShapes.containsPoint

local zoneIdToZoneObj = Registry.zoneIdToZoneObj
local zoneSlotToZoneObj = Registry.zoneSlotToZoneObj
local entityData = Entities.entityData
local observerIdToObserverObj = Registry.observerIdToObserverObj
local groups = Registry.groups
local entityToGroups = Entities.entityToGroups
local entityToReference = References.entityToReference
local referenceToEntity = References.referenceToEntity

local queryHits = {} :: { number }
-- Candidate lists of finished iterZonesAtPoint iterators, for reuse
local spareCandidates = {} :: { { Types.InternalZone } }

local WorldQueries = {}

--[=[
	Returns the physical Entity associated with the reference.

	@method getEntityOfReference
	@within QuickZone
	@param reference any
	@return Entity?
]=]
function WorldQueries:getEntityOfReference(reference: any): Types.Entity?
	local entity = referenceToEntity[reference]
	if entity then
		return entity
	end

	entity = reference
	if typeof(entity) == 'Instance' then
		if
			entity:IsA('BasePart')
			or entity:IsA('Attachment')
			or entity:IsA('Bone')
			or entity:IsA('Camera')
			or entity:IsA('Model')
		then
			return entity
		end
	elseif typeof(entity) == 'table' then
		if entity.Position or entity.CFrame or entity.Transform or entity.WorldPosition or entity.GetPivot then
			return entity
		end
	end

	return nil
end

--[=[
	Returns the reference associated with the Entity.

	@method getReferenceOfEntity
	@within QuickZone
	@param entity Entity
	@return any
]=]
function WorldQueries:getReferenceOfEntity(entity: any): any
	return entityToReference[entity] or entity
end

--[=[ 
	Returns an array of all Observers currently existing.

	@method getObservers
	@within QuickZone
	@return { Observer }
]=]
function WorldQueries:getObservers(): { Types.Observer<any> }
	local result = {}
	for _, observer in observerIdToObserverObj do
		table.insert(result, observer)
	end
	return (result :: any) :: { Types.Observer<any> }
end

--[=[ 
	Returns an array of all Groups (including PlayerGroups) currently 
	registered.

	@method getGroups
	@within QuickZone
	@return { Group }
]=]
function WorldQueries:getGroups(): { Types.Group }
	local result = {}
	for _, group in groups do
		table.insert(result, group)
	end
	return result
end

--[=[ 
	Returns an array containing every Zone currently registered.
	This includes both static and dynamic zones.

	@method getZones
	@within QuickZone
	@return { Zone }
]=]
function WorldQueries:getZones(): { Types.Zone }
	local result = {}
	for _, zone in zoneIdToZoneObj do
		table.insert(result, zone)
	end
	return result
end

--[=[ 
	Returns a flattened array of every entity currently 
	being tracked across all Groups.

	@method getEntities
	@within QuickZone
	@return { any }
]=]
function WorldQueries:getEntities(): { any }
	local result = {}
	local count = 0

	for entity in entityData do
		count += 1
		result[count] = entityToReference[entity] or entity
	end

	return result
end

--[=[ 
	Performs a spatial query to find all Zones containing the given point.

	@method getZonesAtPoint
	@within QuickZone
	@param position Vector3 -- The world position to check.
	@return { Zone }
]=]
function WorldQueries:getZonesAtPoint(position: Vector3): { Zone }
	local results = {}
	local count = 0

	local hitCount = leavesAtPoint(position, queryHits)
	for i = 1, hitCount do
		local slot = queryHits[i]
		if leafContainsPoint(slot, position) then
			local zone = zoneSlotToZoneObj[slot]
			if zone then
				count += 1
				results[count] = zone
			end
		end
	end

	return results
end

--[=[ 
	Returns an array of all Zones the given entity is actively inside, 
	based on its observer memberships.

	@method getZonesOfEntity
	@within QuickZone
	@param entity any
	@return { Zone }
]=]
function WorldQueries:getZonesOfEntity(entity: any): { Types.Zone }
	entity = entityOf(entity)
	local data = entityData[entity]
	if not data then
		return {}
	end

	local results = {}
	local seenZones = {} -- In case multiple observers track the entity in the same zone

	for _, zoneId in data.activeObserverMemberships do
		if seenZones[zoneId] then
			continue
		end
		seenZones[zoneId] = true

		local zone = zoneIdToZoneObj[zoneId]
		if zone then
			table.insert(results, zone)
		end
	end

	return results
end

--[=[ 
	Returns an array of all Groups that the specified entity is currently in.

	@method getGroupsOfEntity
	@within QuickZone
	@param entity any
	@return { Group }
]=]
function WorldQueries:getGroupsOfEntity(entity: any): { Types.Group }
	entity = entityOf(entity)
	local groupIds = entityToGroups[entity]
	if not groupIds then
		-- A player without a character is still in the groups it was added to
		return if isPlayer(entity) then PlayerTracker.groupsOf(entity) else {}
	end

	local results = {}
	local count = 0

	for groupId in groupIds do
		local group = groups[groupId]
		if group then
			count += 1
			results[count] = group
		end
	end

	return results
end

--[=[
	Returns an iterator for all Groups.
	Safe to use while groups are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterGroups
	@within QuickZone
	@return () -> Group?
]=]
function WorldQueries:iterGroups(): () -> Types.Group?
	local nextGroup = Snapshot.keys(groups)
	return function(): Types.Group?
		local _, group = nextGroup()
		return group
	end
end

--[=[
	Returns an iterator for all Zones.
	Safe to use while zones are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterZones
	@within QuickZone
	@return () -> Zone?
]=]
function WorldQueries:iterZones(): () -> Types.Zone?
	local nextZone = Snapshot.keys(zoneIdToZoneObj)
	return function(): Types.Zone?
		local _, zone = nextZone()
		return zone
	end
end

--[=[
	Returns an iterator for all entities.
	Safe to use while entities are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterEntities
	@within QuickZone
	@return () -> any?
]=]
function WorldQueries:iterEntities(): () -> any?
	local nextEntity = Snapshot.keys(entityData)
	return function(): any?
		local entity = nextEntity()
		if entity ~= nil then
			return entityToReference[entity] or entity
		end
		return nil
	end
end

--[=[
	Returns an iterator for all Observers.
	Safe to use while observers are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterObservers
	@within QuickZone
	@return () -> Observer?
]=]
function WorldQueries:iterObservers(): () -> Types.Observer<any>?
	local nextObserver = Snapshot.keys(observerIdToObserverObj)
	return function(): Types.Observer<any>?
		local _, observer = nextObserver()
		return observer
	end
end

--[=[ 
	Returns an iterator for all Groups that the specified entity is currently in.
	Safe to use while groups are added and removed: those removed before the loop reaches them
	are skipped, those added are not visited. Finishing the loop lets the next one reuse its memory.

	@method iterGroupsOfEntity
	@within QuickZone
	@param entity any
	@return () -> Group?
]=]
function WorldQueries:iterGroupsOfEntity(entity: any): () -> Types.Group?
	entity = entityOf(entity)

	local groupIds = entityToGroups[entity]
	if not groupIds then
		-- A player without a character is still in the groups it was added to
		local list = if isPlayer(entity) then PlayerTracker.groupsOf(entity) else {}
		local i = 0
		return function(): Types.Group?
			while true do
				i += 1
				local group = list[i]
				if group == nil or not Destroyed.isDead(group) then
					return group
				end
			end
		end
	end

	local nextGroupId = Snapshot.keys(groupIds)
	return function(): Types.Group?
		while true do
			local groupId = nextGroupId()
			if groupId == nil then
				return nil
			end
			local group = groups[groupId]
			if group then
				return group
			end
		end
	end
end

--[=[ 
	Returns an iterator for all unique Zones the given entity is actively inside.

	@method iterZonesOfEntity
	@within QuickZone
	@param entity any
	@return () -> Zone?
]=]
function WorldQueries:iterZonesOfEntity(entity: any): () -> Types.Zone?
	entity = entityOf(entity)

	local data = entityData[entity]
	if not data then
		return function()
			return nil
		end
	end

	local nextMembership = Snapshot.keys(data.activeObserverMemberships)
	local seenZones: { [number]: boolean } = {}

	return function(): Types.Zone?
		while true do
			local observerId, zoneId = nextMembership()
			if not observerId then
				return nil
			end

			if seenZones[zoneId :: number] then
				continue
			end

			seenZones[zoneId] = true
			local zone = zoneIdToZoneObj[zoneId]

			if zone then
				return zone
			end
		end
	end
end

--[=[
	Returns an iterator that returns every Zone intersecting the given point.
	Ideal for ECS queries. Safe to `break` out of early.

	:::info Changes while iterating
	The zones whose bounds hold the point are found when the iterator is created. Each is checked against
	the point when it is reached, so zones destroyed or moved away in between are skipped, and zones that
	arrive in between are not yielded. Finishing the loop lets the next iterator reuse its memory, so prefer
	that in hot paths.
	:::

	@method iterZonesAtPoint
	@within QuickZone
	@param point Vector3
	@return () -> Zone?
]=]
function WorldQueries:iterZonesAtPoint(point: Vector3): () -> Types.Zone?
	local list = table.remove(spareCandidates) or {}
	local count = 0

	local hitCount = leavesAtPoint(point, queryHits)
	for i = 1, hitCount do
		local zone = zoneSlotToZoneObj[queryHits[i]]
		if zone then
			count += 1
			list[count] = zone
		end
	end

	local candidates: { Types.InternalZone }? = list
	local index = 0

	return function(): Types.Zone?
		if not candidates then
			return nil
		end

		while index < count do
			index += 1
			local zone = candidates[index]
			if not Destroyed.isDead(zone) and containsPoint(zone.slot, point) then
				return zone
			end
		end

		-- Finished, so the list can be reused
		table.clear(candidates)
		table.insert(spareCandidates, candidates)
		candidates = nil

		return nil
	end
end

return WorldQueries

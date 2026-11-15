--!native
--!optimize 2
--!strict

-- The zone each observer has an entity in. Writes go through here to keep tracking and occupants in step

local Callbacks = require(script.Parent.Callbacks)
local Entities = require(script.Parent.Entities)
local Links = require(script.Parent.Links)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local ZoneShapes = require(script.Parent.ZoneShapes)
local Types = require(script.Parent.Parent.Types)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)

local entityData = Entities.entityData
local entityToGroups = Entities.entityToGroups
local entityToReference = References.entityToReference
local groupToObservers = Links.groupToObservers
local observers = Registry.observers
local slotObservers = Links.slotObservers
local zoneIdToZoneObj = Registry.zoneIdToZoneObj
local zoneSlotIds = ZoneShapes.zoneSlotIds
local staleSlots = ZoneShapes.staleSlots

local Memberships = {}

-- Entities observers have in each zone
Memberships.zoneOccupants = {} :: { [number]: number }
-- Zones on their way out, which entities can't move into: one being destroyed, and the rest of a Zones destroyed
-- with it, so an entity in several leaves once rather than moving through each
Memberships.zonesBeingDestroyed = {} :: { [number]: true }

local zoneOccupants = Memberships.zoneOccupants
local zonesBeingDestroyed = Memberships.zonesBeingDestroyed

local leafHits = {} :: { number }

local fire = Callbacks.fire

local function addOccupant(zoneId: number)
	zoneOccupants[zoneId] = (zoneOccupants[zoneId] or 0) + 1
end

local function removeOccupant(zoneId: number)
	local count = zoneOccupants[zoneId]
	if count then
		zoneOccupants[zoneId] = if count > 1 then count - 1 else nil
	end
end

-- Whether group G brings entity E into observer O. isSubscribed asks it of any of E's groups, and Routing's
-- entityToObservers holds its answers per entity
function Memberships.bringsIn(groupId: number, entity: Types.Entity, observerId: number): boolean
	local groups = entityToGroups[entity]
	local subscribed = groupToObservers[groupId]
	return groups ~= nil and groups[groupId] == true and subscribed ~= nil and subscribed[observerId] == true
end

function Memberships.isSubscribed(entity: Types.Entity, observerId: number): boolean
	local groups = entityToGroups[entity]
	if not groups then
		return false
	end

	for groupId in groups do
		local subscribed = groupToObservers[groupId]
		if subscribed and subscribed[observerId] then
			return true
		end
	end

	return false
end

function Memberships.move(observerId: number, entity: Types.Entity, data: Types.EntityData, zoneId: number)
	local memberships = data.activeObserverMemberships
	local oldZoneId = memberships[observerId]
	local observer = observers[observerId]
	-- Destroyed observers track nothing
	if oldZoneId == zoneId or not observer then
		return
	end

	memberships[observerId] = zoneId
	observer.tracked[entity] = zoneId
	if oldZoneId then
		removeOccupant(oldZoneId)
	end
	addOccupant(zoneId)
end

function Memberships.exit(observerId: number, entity: Types.Entity, data: Types.EntityData)
	local zoneId = data.activeObserverMemberships[observerId]
	if not zoneId then
		return
	end

	data.activeObserverMemberships[observerId] = nil
	removeOccupant(zoneId)

	local observer = observers[observerId]
	if observer then
		observer.tracked[entity] = nil
		local reference = entityToReference[entity] or entity
		fire(observer.exited, observerId, reference, zoneIdToZoneObj[zoneId], entity, observer.safety)
	end
end

local function canMoveInto(slot: number, observerId: number): boolean
	local otherId = zoneSlotIds[slot]
	local attached = slotObservers[slot]
	return otherId ~= nil
		and not zonesBeingDestroyed[otherId]
		and attached ~= nil
		and table.find(attached, observerId) ~= nil
end

-- Uses the position the entity was last checked at
local function otherZoneOf(observerId: number, data: Types.EntityData): number?
	local position = data.lastPosition
	local hitCount = ZoneShapes.leavesAtPoint(position, leafHits)
	for i = 1, hitCount do
		local slot = leafHits[i]
		if canMoveInto(slot, observerId) and ZoneShapes.leafContainsPoint(slot, position) then
			return zoneSlotIds[slot]
		end
	end

	-- The trees miss zones made or moved since they were built
	for slot in staleSlots do
		if canMoveInto(slot, observerId) and ZoneShapes.containsPoint(slot, position) then
			return zoneSlotIds[slot]
		end
	end
	return nil
end

-- Entities another of the observer's zones holds move there, rather than exiting and entering next tick
local function leaveDestroyedZone(observer: Types.InternalObserver, zoneId: number)
	local observerId = observer.id

	-- Collected first, as a callback may update and add entities to the map
	local leaving = {}
	for entity, trackedZoneId in observer.tracked do
		if trackedZoneId == zoneId then
			table.insert(leaving, entity)
		end
	end

	for _, entity in leaving do
		local data = entityData[entity]
		if not data or data.activeObserverMemberships[observerId] ~= zoneId then
			continue
		end
		local otherId = otherZoneOf(observerId, data)
		if otherId then
			Memberships.move(observerId, entity, data, otherId)
			local reference = entityToReference[entity] or entity
			fire(
				observer.transitioned,
				observerId,
				reference,
				zoneIdToZoneObj[otherId],
				entity,
				observer.safety,
				otherId
			)
		else
			Memberships.exit(observerId, entity, data)
		end
	end
end

function Memberships.exitObserver(observer: Types.InternalObserver)
	local observerId = observer.id
	-- A snapshot, as callbacks may change the map
	for entity in Snapshot.keys(observer.tracked) do
		local data = entityData[entity]
		if data then
			Memberships.exit(observerId, entity, data)
		end
	end
end

-- Goes through every observer, as ones detached since the last tick may still hold entities
function Memberships.leaveZone(zoneId: number)
	if not zoneOccupants[zoneId] then
		return
	end

	-- A snapshot, as callbacks may create or destroy observers
	for _, observer in Snapshot.keys(observers) do
		leaveDestroyedZone(observer :: Types.InternalObserver, zoneId)
		if not zoneOccupants[zoneId] then
			break
		end
	end

	zoneOccupants[zoneId] = nil
end

function Memberships.exitUnsubscribed(entity: Types.Entity, data: Types.EntityData)
	-- Collected first, as a callback may update and add memberships
	local leaving: { number }? = nil
	for observerId in data.activeObserverMemberships do
		if not Memberships.isSubscribed(entity, observerId) then
			leaving = leaving or {}
			table.insert(leaving :: { number }, observerId)
		end
	end

	if leaving then
		for _, observerId in leaving do
			if not Memberships.isSubscribed(entity, observerId) then
				Memberships.exit(observerId, entity, data)
			end
		end
	end
end

function Memberships.setZoneDestroying(zoneId: number, destroying: boolean)
	if destroying then
		zonesBeingDestroyed[zoneId] = true
	else
		zonesBeingDestroyed[zoneId] = nil
	end
end

return Memberships

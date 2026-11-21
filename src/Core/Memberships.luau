--!native
--!optimize 2
--!strict

local Callbacks = require(script.Parent.Callbacks)
local Entities = require(script.Parent.Entities)
local Links = require(script.Parent.Links)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local ZoneShapes = require(script.Parent.ZoneShapes)
local Types = require(script.Parent.Parent.Types)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)

local entityData = Entities.entityData
local entityToReference = References.entityToReference
local groups = Registry.groups
local observers = Registry.observers
local slotObservers = Links.slotObservers
local zoneIdToZoneObj = Registry.zoneIdToZoneObj
local zoneSlotIds = ZoneShapes.zoneSlotIds
local staleSlots = ZoneShapes.staleSlots

local Memberships = {}

Memberships.zoneOccupants = {} :: { [number]: number }
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
		if count > 1 then
			zoneOccupants[zoneId] = count - 1
		else
			zoneOccupants[zoneId] = nil
		end
	end
end

function Memberships.bringsIn(groupId: number, entity: Types.Entity, observerId: number): boolean
	return Entities.isIn(entity, groupId) and Links.subscribes(observerId, groupId)
end

function Memberships.isSubscribed(entity: Types.Entity, observerId: number): boolean
	local data = entityData[entity]
	if not data then
		return false
	end

	for groupId in data.groups do
		local group = groups[groupId]
		if group and group.subscribers[observerId] then
			return true
		end
	end

	return false
end

function Memberships.move(observerId: number, entity: Types.Entity, data: Types.EntityData, zoneId: number)
	local memberships = data.activeObserverMemberships
	local oldZoneId = memberships[observerId]
	local observer = observers[observerId]
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
		fire(observer.exitedCallbacks, observerId, reference, zoneIdToZoneObj[zoneId], entity, observer.safety)
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

local function otherZoneOf(observerId: number, data: Types.EntityData): number?
	local position = data.lastPosition
	local hitCount = ZoneShapes.leavesAtPoint(position, leafHits)
	for i = 1, hitCount do
		local slot = leafHits[i]
		if canMoveInto(slot, observerId) and ZoneShapes.leafContainsPoint(slot, position) then
			return zoneSlotIds[slot]
		end
	end

	for slot in staleSlots do
		if canMoveInto(slot, observerId) and ZoneShapes.containsPoint(slot, position) then
			return zoneSlotIds[slot]
		end
	end
	return nil
end

local function leaveDestroyedZone(observer: Types.InternalObserver, zoneId: number)
	local observerId = observer.id

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
				observer.transitionedCallbacks,
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
	for entity in Snapshot.keys(observer.tracked) do
		local data = entityData[entity]
		if data then
			Memberships.exit(observerId, entity, data)
		end
	end
end

function Memberships.leaveZone(zoneId: number)
	if not zoneOccupants[zoneId] then
		return
	end

	for _, observer in Snapshot.keys(observers) do
		leaveDestroyedZone(observer :: Types.InternalObserver, zoneId)
		if not zoneOccupants[zoneId] then
			break
		end
	end

	zoneOccupants[zoneId] = nil
end

function Memberships.exitUnsubscribed(entity: Types.Entity, data: Types.EntityData)
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

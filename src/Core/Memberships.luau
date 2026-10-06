--!strict

-- The zone each observer has an entity in. Writes go through here, which keeps the observer's
-- tracking and the zone's occupants in step with it. Exits re-read state, as callbacks may change it

local Callbacks = require(script.Parent.Callbacks)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

local entityData = State.entityData
local entityToGroups = State.entityToGroups
local entityToReference = State.entityToReference
local groupToObservers = State.groupToObservers
local observerTrackingEntities = State.observerTrackingEntities
local observerExitedCallbacks = State.observerExitedCallbacks
local observerSafety = State.observerSafety
local zoneIdToZoneObj = State.zoneIdToZoneObj
local zoneOccupants = State.zoneOccupants

local fire = Callbacks.fire

local function addOccupant(zoneId: number, observerId: number)
	local occupants = zoneOccupants[zoneId]
	if not occupants then
		occupants = {}
		zoneOccupants[zoneId] = occupants
	end
	occupants[observerId] = (occupants[observerId] or 0) + 1
end

local function removeOccupant(zoneId: number, observerId: number)
	local occupants = zoneOccupants[zoneId]
	if not occupants then
		return
	end

	local count = (occupants[observerId] or 0) - 1
	if count > 0 then
		occupants[observerId] = count
		return
	end

	occupants[observerId] = nil
	if next(occupants) == nil then
		zoneOccupants[zoneId] = nil
	end
end

local Memberships = {}

-- Whether the observer still watches one of the entity's groups
function Memberships.isSubscribed(entity: Types.Entity, observerId: number): boolean
	local groups = entityToGroups[entity]
	if not groups then
		return false
	end

	for groupId in groups do
		local observers = groupToObservers[groupId]
		if observers and observers[observerId] then
			return true
		end
	end

	return false
end

-- Puts the entity in the observer's zone, returns the zone it was in
function Memberships.set(observerId: number, entity: Types.Entity, data: Types.EntityData, zoneId: number): number?
	local memberships = data.activeObserverMemberships
	local oldZoneId = memberships[observerId]
	if oldZoneId == zoneId then
		return oldZoneId
	end

	memberships[observerId] = zoneId
	observerTrackingEntities[observerId][entity] = zoneId
	if oldZoneId then
		removeOccupant(oldZoneId, observerId)
	end
	addOccupant(zoneId, observerId)

	return oldZoneId
end

-- Takes the entity out of the observer's zone and fires the observer's exits
function Memberships.exit(observerId: number, entity: Types.Entity, data: Types.EntityData)
	local zoneId = data.activeObserverMemberships[observerId]
	if not zoneId then
		return
	end

	data.activeObserverMemberships[observerId] = nil
	local tracked = observerTrackingEntities[observerId]
	if tracked then
		tracked[entity] = nil
	end
	removeOccupant(zoneId, observerId)

	local reference = entityToReference[entity] or entity
	fire(observerExitedCallbacks, observerId, reference, zoneIdToZoneObj[zoneId], entity, observerSafety[observerId])
end

-- Exits the observer's entities in the zone
function Memberships.exitZone(observerId: number, zoneId: number)
	local tracked = observerTrackingEntities[observerId]
	if not tracked then
		return
	end

	-- Collected first, as a callback may update and add entities to the map
	local leaving = {}
	for entity, trackedZoneId in tracked do
		if trackedZoneId == zoneId then
			table.insert(leaving, entity)
		end
	end

	for _, entity in leaving do
		local data = entityData[entity]
		if data and data.activeObserverMemberships[observerId] == zoneId then
			Memberships.exit(observerId, entity, data)
		end
	end
end

-- Exits the entity from every observer that no longer watches one of its groups
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

return Memberships

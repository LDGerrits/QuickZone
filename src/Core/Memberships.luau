--!native
--!optimize 2
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
local observerGroupTrackers = State.observerGroupTrackers
local observerSafety = State.observerSafety
local zoneIdToZoneObj = State.zoneIdToZoneObj
local zoneOccupants = State.zoneOccupants

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

-- Runs the observer's group trackers. Lists are replaced rather than changed, so this one can't shift under
-- the loop, and a tracker disconnected meanwhile does nothing
local function runTrackers(observerId: number, entity: Types.Entity?, destroyedGroupId: number?)
	for _, track in observerGroupTrackers[observerId] or {} do
		track(entity, destroyedGroupId)
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

-- Moves the entity into the observer's zone, returns the zone it was in
function Memberships.move(observerId: number, entity: Types.Entity, data: Types.EntityData, zoneId: number): number?
	local memberships = data.activeObserverMemberships
	local oldZoneId = memberships[observerId]
	local tracked = observerTrackingEntities[observerId]
	-- Destroyed observers track nothing
	if oldZoneId == zoneId or not tracked then
		return oldZoneId
	end

	memberships[observerId] = zoneId
	tracked[entity] = zoneId
	if oldZoneId then
		removeOccupant(oldZoneId)
	end
	addOccupant(zoneId)

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
	removeOccupant(zoneId)

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

-- Exits every entity the observer has in a zone
function Memberships.exitObserver(observerId: number)
	local tracked = observerTrackingEntities[observerId]
	if not tracked then
		return
	end

	-- Collected first, as callbacks may change the map
	local leaving = {}
	for entity in tracked do
		table.insert(leaving, entity)
	end

	for _, entity in leaving do
		local data = entityData[entity]
		if data then
			Memberships.exit(observerId, entity, data)
		end
	end
end

-- Exits every observer's entities in the zone, including observers that detached from it since the last tick
function Memberships.exitAllFromZone(zoneId: number)
	if not zoneOccupants[zoneId] then
		return
	end

	-- Collected first, as callbacks may create or destroy observers
	local observerIds = {}
	for observerId in observerTrackingEntities do
		table.insert(observerIds, observerId)
	end
	for _, observerId in observerIds do
		Memberships.exitZone(observerId, zoneId)
		if not zoneOccupants[zoneId] then
			break
		end
	end

	zoneOccupants[zoneId] = nil
end

-- Tells the group trackers of the observers the entity is in that its groups, or their observers, changed.
-- Only those of observerId when given
function Memberships.groupsChanged(entity: Types.Entity, observerId: number?)
	local data = entityData[entity]
	if not data then
		return
	end

	-- Collected first, as trackers run callbacks that may change memberships
	local observerIds: { number }? = nil
	for id in data.activeObserverMemberships do
		if observerGroupTrackers[id] and (observerId == nil or id == observerId) then
			observerIds = observerIds or {}
			table.insert(observerIds :: { number }, id)
		end
	end

	if observerIds then
		for _, id in observerIds do
			runTrackers(id, entity, nil)
		end
	end
end

-- Tells every group tracker that a group is being destroyed. A tracker may still count entities that left
-- before it heard, so it can't wait for their exits
function Memberships.groupDestroyed(groupId: number)
	local observerIds = {}
	for id in observerGroupTrackers do
		table.insert(observerIds, id)
	end
	for _, id in observerIds do
		runTrackers(id, nil, groupId)
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

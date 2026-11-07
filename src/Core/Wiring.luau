--!strict

-- What an observer watches and how it is set, with what each change sets off, in the order it must happen:
-- attaching and detaching zones, moving a zone between trees, letting go of a zone being destroyed, subscribing
-- groups, and the observer's settings. The only writer of the observer settings in Registry

local Types = require(script.Parent.Parent.Types)
local Callbacks = require(script.Parent.Callbacks)
local Entities = require(script.Parent.Entities)
local Links = require(script.Parent.Links)
local Memberships = require(script.Parent.Memberships)
local Registry = require(script.Parent.Registry)
local Routing = require(script.Parent.Routing)
local ZoneShapes = require(script.Parent.ZoneShapes)

export type ObserverSettings = {
	priority: number,
	updateRate: number,
	precision: number,
	enabled: boolean,
	safety: boolean,
}

local Wiring = {}

-- Tells the observer's group trackers that the group's members may count for it now, or no longer
local function retrackMembers(observerId: number, groupId: number)
	if Callbacks.observerGroupTrackers[observerId] then
		-- Cloned, as tracker callbacks may change the group
		for _, entity in table.clone(Entities.groupEntities[groupId] :: { Types.Entity }) do
			Memberships.groupsChanged(entity, observerId)
		end
	end
end

-- Rechecks the group's members, and exits those the observer no longer watches
local function disconnectFromGroup(observerId: number, groupId: number)
	-- Cloned, as exit callbacks may remove entities from the group, swapping later ones into visited slots
	for _, entity in table.clone(Entities.groupEntities[groupId] :: { Types.Entity }) do
		local data = Entities.entityData[entity]
		if not data then
			continue
		end

		Routing.recheck(entity)

		-- Disabled observers let go of every entity
		if Registry.observerEnabled[observerId] and Memberships.isSubscribed(entity, observerId) then
			continue
		end

		Memberships.exit(observerId, entity, data)
	end
end

-- Zones

function Wiring.attach(slot: number, observerId: number)
	if Links.attach(slot, observerId) then
		Routing.changeZoneCount(observerId, ZoneShapes.isDynamic(slot), 1)
		ZoneShapes.touch(slot)
	end
end

function Wiring.detach(slot: number, observerId: number)
	if Links.detach(slot, observerId) then
		Routing.changeZoneCount(observerId, ZoneShapes.isDynamic(slot), -1)
		-- Its entities leave on the next tick, unless the zone is destroyed first
		ZoneShapes.touch(slot)
	end
end

-- Moves the zone to the other tree, and its observers' zone counts with it. False when it was there already
function Wiring.setZoneDynamic(slot: number, isDynamic: boolean): boolean
	if ZoneShapes.isDynamic(slot) == isDynamic then
		return false
	end

	ZoneShapes.setDynamic(slot, isDynamic)

	local attached = Links.zoneAttachedObservers[slot]
	if attached then
		for _, observerId in attached do
			Routing.changeZoneCount(observerId, not isDynamic, -1)
			Routing.changeZoneCount(observerId, isDynamic, 1)
		end
	end
	return true
end

-- Lets go of a zone being destroyed: its observers first, before any callback, so a callback that updates can't
-- move entities back in, then its entities leave or move on while the zone object is still alive
function Wiring.unwireZone(slot: number, zoneId: number)
	local attached = Links.detachAll(slot)
	if attached then
		local isDynamic = ZoneShapes.isDynamic(slot)
		for _, observerId in attached do
			Routing.changeZoneCount(observerId, isDynamic, -1)
		end
	end

	Memberships.leaveZone(zoneId)
end

-- Groups

function Wiring.subscribe(observerId: number, groupId: number)
	Links.subscribe(observerId, groupId)

	for _, entity in Entities.groupEntities[groupId] do
		Routing.recheck(entity)
	end

	-- Members already inside through other groups bring this one in
	retrackMembers(observerId, groupId)
end

function Wiring.unsubscribe(observerId: number, groupId: number)
	Links.unsubscribe(observerId, groupId)
	disconnectFromGroup(observerId, groupId)
	-- Members that stay inside through other groups no longer bring this one in
	retrackMembers(observerId, groupId)
end

-- Observers

-- Registers a new observer whose settings were checked
function Wiring.addObserver(observerId: number, settings: ObserverSettings)
	Registry.observerPriorityMap[observerId] = settings.priority
	Registry.observerUpdateRate[observerId] = settings.updateRate
	Registry.observerPrecisionSq[observerId] = settings.precision ^ 2
	Registry.observerEnabled[observerId] = settings.enabled
	Registry.observerSafety[observerId] = settings.safety
	Callbacks.addObserver(observerId)
	Memberships.addObserver(observerId)
	Routing.addObserver(observerId)
end

-- Lets go of everything a destroyed observer has, once its onDestroy callbacks ran
function Wiring.removeObserver(observerId: number)
	-- Exits every entity. Destroyed from an exit callback, the loop that fired it may not have reached them all
	Wiring.setEnabled(observerId, false)
	Memberships.exitObserver(observerId)

	-- Unlinked entities must be rerouted, also when the observer was already disabled
	Routing.rerouteObserver(observerId)
	Links.unsubscribeAll(observerId)

	for slot, attached in Links.zoneAttachedObservers do
		if table.find(attached, observerId) then
			Wiring.detach(slot, observerId)
		end
	end

	Registry.observerPriorityMap[observerId] = nil
	Registry.observerEnabled[observerId] = nil
	Registry.observerSafety[observerId] = nil
	Registry.observerUpdateRate[observerId] = nil
	Registry.observerPrecisionSq[observerId] = nil
	Callbacks.dropObserver(observerId)
	Memberships.dropObserver(observerId)
	Routing.dropObserver(observerId)
end

function Wiring.setEnabled(observerId: number, enabled: boolean)
	if (Registry.observerEnabled[observerId] ~= false) == enabled then
		return
	end

	Registry.observerEnabled[observerId] = enabled
	Routing.recheckAll()

	if not enabled then
		-- Cloned, as exit callbacks may subscribe groups. The live set is checked per group, as they may also
		-- unsubscribe them
		for groupId, observers in table.clone(Links.groupToObservers) do
			if observers[observerId] and Registry.groups[groupId] then
				disconnectFromGroup(observerId, groupId)
			end
		end
	end

	Routing.rerouteObserver(observerId)
end

function Wiring.setPriority(observerId: number, priority: number)
	Registry.observerPriorityMap[observerId] = priority
	Routing.recheckAll()
end

function Wiring.setUpdateRate(observerId: number, hz: number)
	Registry.observerUpdateRate[observerId] = hz
	Routing.rerouteObserver(observerId)
end

function Wiring.setPrecision(observerId: number, precision: number)
	Registry.observerPrecisionSq[observerId] = precision ^ 2
	Routing.rerouteObserver(observerId)
end

function Wiring.setSafety(observerId: number, safety: boolean)
	Registry.observerSafety[observerId] = safety
end

return Wiring

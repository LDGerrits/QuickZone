--!strict

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local GroupPresence = require(script.Parent.GroupPresence)
local Links = require(script.Parent.Links)
local Memberships = require(script.Parent.Memberships)
local Registry = require(script.Parent.Registry)
local Routing = require(script.Parent.Routing)
local ZoneShapes = require(script.Parent.ZoneShapes)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)

local observers = Registry.observers

local Wiring = {}

local function disconnectFromGroup(observerId: number, groupId: number)
	for _, entity in table.clone(Registry.groups[groupId].members) do
		local data = Entities.entityData[entity]
		if not data then
			continue
		end

		Routing.recheck(entity)

		local observer = observers[observerId]
		if observer and observer.enabled and Memberships.isSubscribed(entity, observerId) then
			continue
		end

		Memberships.exit(observerId, entity, data)
	end
end

function Wiring.attach(slot: number, observerId: number)
	if Links.attach(slot, observerId) then
		Routing.changeZoneCount(observerId, ZoneShapes.isDynamic(slot), 1)
		ZoneShapes.touch(slot)
	end
end

function Wiring.detach(slot: number, observerId: number)
	if Links.detach(slot, observerId) then
		Routing.changeZoneCount(observerId, ZoneShapes.isDynamic(slot), -1)
		ZoneShapes.touch(slot)
	end
end

function Wiring.setZoneDynamic(slot: number, isDynamic: boolean)
	if ZoneShapes.isDynamic(slot) == isDynamic then
		return
	end

	ZoneShapes.setDynamic(slot, isDynamic)

	local attached = Links.slotObservers[slot]
	if attached then
		for _, observerId in attached do
			Routing.changeZoneCount(observerId, not isDynamic, -1)
			Routing.changeZoneCount(observerId, isDynamic, 1)
		end
	end
end

function Wiring.addZone(
	zone: Types.InternalZone,
	isDynamic: boolean,
	cframe: CFrame,
	halfSize: Vector3,
	shapeType: number,
	part: BasePart?
)
	local slot = ZoneShapes.allocateSlot(zone.id)
	zone.slot = slot
	ZoneShapes.add(slot, isDynamic, cframe, halfSize, shapeType, part)
	Registry.zoneIdToZoneObj[zone.id] = zone
	Registry.zoneSlotToZoneObj[slot] = zone
end

function Wiring.removeZone(zone: Types.InternalZone)
	local id = zone.id
	local slot = zone.slot

	Memberships.setZoneDestroying(id, true)
	local isDynamic = ZoneShapes.isDynamic(slot)
	for _, observerId in (Links.detachAll(slot) or {}) :: { number } do
		Routing.changeZoneCount(observerId, isDynamic, -1)
	end
	Memberships.leaveZone(id)

	Destroyed.fireCallbacks(zone.onDestroyCallbacks)

	Registry.zoneIdToZoneObj[id] = nil
	Registry.zoneSlotToZoneObj[slot] = nil
	ZoneShapes.remove(slot)
	Memberships.setZoneDestroying(id, false)
end

function Wiring.destroyZones(zoneIds: { number }, destroy: () -> ())
	for _, id in zoneIds do
		Memberships.setZoneDestroying(id, true)
	end
	destroy()
	for _, id in zoneIds do
		Memberships.setZoneDestroying(id, false)
	end
end

function Wiring.subscribe(observerId: number, groupId: number)
	Links.subscribe(observerId, groupId)

	for _, entity in Registry.groups[groupId].members do
		Routing.recheck(entity)
	end

	GroupPresence.subscriptionChanged(observerId, groupId)
end

function Wiring.unsubscribe(observerId: number, groupId: number)
	Links.unsubscribe(observerId, groupId)
	disconnectFromGroup(observerId, groupId)
	GroupPresence.subscriptionChanged(observerId, groupId)
end

function Wiring.addObserver(observer: Types.InternalObserver)
	observers[observer.id] = observer
end

function Wiring.removeObserver(observer: Types.InternalObserver)
	local observerId = observer.id
	Wiring.setEnabled(observerId, false)
	Memberships.exitObserver(observer)

	Routing.rerouteObserver(observerId)
	Links.unsubscribeAll(observerId)

	for slot, attached in Links.slotObservers do
		if table.find(attached, observerId) then
			Wiring.detach(slot, observerId)
		end
	end

	observers[observerId] = nil
	observer.enteredCallbacks = {}
	observer.exitedCallbacks = {}
	observer.transitionedCallbacks = {}
	observer.trackers = nil
end

function Wiring.setEnabled(observerId: number, enabled: boolean)
	local observer = observers[observerId]
	if observer.enabled == enabled then
		return
	end

	observer.enabled = enabled
	Routing.recheckAll()

	if not enabled then
		for groupId in table.clone(Registry.groups) do
			if Links.subscribes(observerId, groupId) then
				disconnectFromGroup(observerId, groupId)
			end
		end
	end

	Routing.rerouteObserver(observerId)
end

function Wiring.setPriority(observerId: number, priority: number)
	observers[observerId].priority = priority
	Routing.recheckAll()
end

function Wiring.setUpdateRate(observerId: number, hz: number)
	observers[observerId].updateRate = hz
	Routing.rerouteObserver(observerId)
end

function Wiring.setPrecision(observerId: number, precision: number)
	observers[observerId].precisionSq = precision ^ 2
	Routing.rerouteObserver(observerId)
end

function Wiring.setSafety(observerId: number, safety: boolean)
	observers[observerId].safety = safety
end

return Wiring

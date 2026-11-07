--!strict

-- Owns the links between observers and the groups and zones they watch, and how many static and dynamic zones each
-- observer has. Others read the tables, only this module writes them

local Routing = require(script.Parent.Routing)
local State = require(script.Parent.State)

local groupToObservers = State.groupToObservers
local zoneAttachedObservers = State.zoneAttachedObservers
local zoneSoleObserver = State.zoneSoleObserver
local observerStaticCount = State.observerStaticCount
local observerDynamicCount = State.observerDynamicCount

local Links = {}

local function changeZoneCount(observerId: number, isDynamic: boolean, delta: number)
	local dict = isDynamic and observerDynamicCount or observerStaticCount
	local current = dict[observerId] or 0
	local newCount = current + delta
	dict[observerId] = newCount

	-- Only flag entities dirty if the observer's topology fundamentally changed
	if (current == 0 and newCount == 1) or (current == 1 and newCount == 0) then
		-- Only force a global logic override when an observer loses its last zone
		if current == 1 and newCount == 0 then
			State.logicVersion += 1
		end

		for groupId, observers in groupToObservers do
			if not observers[observerId] then
				continue
			end

			local group = State.groups[groupId]
			if not group then
				continue
			end

			for _, entity in group.entities do
				Routing.markTopology(entity)
			end
		end
	end
end

function Links.addGroup(groupId: number)
	groupToObservers[groupId] = {}
end

function Links.dropGroup(groupId: number)
	groupToObservers[groupId] = nil
end

function Links.addObserver(observerId: number)
	observerStaticCount[observerId] = 0
	observerDynamicCount[observerId] = 0
end

-- Unlinks the observer from every group, as it is destroyed
function Links.unsubscribeAll(observerId: number)
	for _, observers in groupToObservers do
		observers[observerId] = nil
	end
end

-- Drops the zone counts of a destroyed observer, once its zones detached through Zone, which also touches their trees
function Links.dropObserver(observerId: number)
	observerStaticCount[observerId] = nil
	observerDynamicCount[observerId] = nil
end

function Links.subscribe(observerId: number, groupId: number)
	local observers = groupToObservers[groupId]
	if not observers then
		observers = {}
		groupToObservers[groupId] = observers
	end
	observers[observerId] = true
end

function Links.unsubscribe(observerId: number, groupId: number)
	local observers = groupToObservers[groupId]
	if observers then
		observers[observerId] = nil
	end
end

-- Attaches the observer to the zone in the slot. False when it was attached already
function Links.attach(slot: number, observerId: number, isDynamic: boolean): boolean
	local attached = zoneAttachedObservers[slot] or {}
	zoneAttachedObservers[slot] = attached

	if table.find(attached, observerId) then
		return false
	end
	table.insert(attached, observerId)
	zoneSoleObserver[slot] = if #attached == 1 then attached[1] else nil
	changeZoneCount(observerId, isDynamic, 1)
	return true
end

-- Detaches the observer from the zone in the slot. False when it wasn't attached
function Links.detach(slot: number, observerId: number, isDynamic: boolean): boolean
	local attached = zoneAttachedObservers[slot]
	if not attached then
		return false
	end

	local idx = table.find(attached, observerId)
	if idx then
		local lastIdx = #attached
		if idx ~= lastIdx then
			attached[idx] = attached[lastIdx]
		end
		attached[lastIdx] = nil
		zoneSoleObserver[slot] = if #attached == 1 then attached[1] else nil
		changeZoneCount(observerId, isDynamic, -1)
	end

	if #attached == 0 then
		zoneAttachedObservers[slot] = nil
	end
	return idx ~= nil
end

-- Detaches every observer from the zone in the slot, as it is destroyed
function Links.detachAll(slot: number, isDynamic: boolean)
	local attached = zoneAttachedObservers[slot]
	zoneAttachedObservers[slot] = nil
	zoneSoleObserver[slot] = nil

	if attached then
		for _, observerId in attached do
			changeZoneCount(observerId, isDynamic, -1)
		end
	end
end

-- Moves the zone in the slot to the other tree in its observers' counts
function Links.moveZoneCounts(slot: number, isDynamic: boolean)
	local attached = zoneAttachedObservers[slot]
	if attached then
		for _, observerId in attached do
			changeZoneCount(observerId, not isDynamic, -1)
			changeZoneCount(observerId, isDynamic, 1)
		end
	end
end

return Links

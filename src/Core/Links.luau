--!strict

-- Owns the links between observers and the groups and zones they watch. Others read the tables, only this module
-- writes them

local Links = {}

-- Observers of each group
Links.groupToObservers = {} :: { [number]: { [number]: boolean } }
-- Observers each zone is attached to, keyed by slot
Links.zoneAttachedObservers = {} :: { [number]: { number } }
-- Observer of zones attached to exactly one
Links.zoneSoleObserver = {} :: { [number]: number }

local groupToObservers = Links.groupToObservers
local zoneAttachedObservers = Links.zoneAttachedObservers
local zoneSoleObserver = Links.zoneSoleObserver

function Links.addGroup(groupId: number)
	groupToObservers[groupId] = {}
end

function Links.dropGroup(groupId: number)
	groupToObservers[groupId] = nil
end

-- The ids of the groups the observer watches, as a new list
function Links.groupIdsOf(observerId: number): { number }
	local list = {}
	for groupId, observers in groupToObservers do
		if observers[observerId] then
			table.insert(list, groupId)
		end
	end
	return list
end

-- Unlinks the observer from every group, as it is destroyed
function Links.unsubscribeAll(observerId: number)
	for _, observers in groupToObservers do
		observers[observerId] = nil
	end
end

-- The group's set exists, as only live groups are subscribed
function Links.subscribe(observerId: number, groupId: number)
	groupToObservers[groupId][observerId] = true
end

function Links.unsubscribe(observerId: number, groupId: number)
	local observers = groupToObservers[groupId]
	if observers then
		observers[observerId] = nil
	end
end

-- Attaches the observer to the zone in the slot. False when it was attached already
function Links.attach(slot: number, observerId: number): boolean
	local attached = zoneAttachedObservers[slot] or {}
	zoneAttachedObservers[slot] = attached

	if table.find(attached, observerId) then
		return false
	end
	table.insert(attached, observerId)
	zoneSoleObserver[slot] = if #attached == 1 then attached[1] else nil
	return true
end

-- Detaches the observer from the zone in the slot. False when it wasn't attached
function Links.detach(slot: number, observerId: number): boolean
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
	end

	if #attached == 0 then
		zoneAttachedObservers[slot] = nil
	end
	return idx ~= nil
end

-- Detaches every observer from the zone in the slot, as it is destroyed. Returns the observers it had
function Links.detachAll(slot: number): { number }?
	local attached = zoneAttachedObservers[slot]
	zoneAttachedObservers[slot] = nil
	zoneSoleObserver[slot] = nil
	return attached
end

return Links

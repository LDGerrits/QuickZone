--!strict

-- Owns observer links to groups and zones. Only this module writes them

local Links = {}

Links.groupToObservers = {} :: { [number]: { [number]: boolean } }
-- Keyed by zone slot
Links.zoneAttachedObservers = {} :: { [number]: { number } }
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

function Links.groupIdsOf(observerId: number): { number }
	local list = {}
	for groupId, observers in groupToObservers do
		if observers[observerId] then
			table.insert(list, groupId)
		end
	end
	return list
end

function Links.unsubscribeAll(observerId: number)
	for _, observers in groupToObservers do
		observers[observerId] = nil
	end
end

-- Only live groups are subscribed, so the set exists
function Links.subscribe(observerId: number, groupId: number)
	groupToObservers[groupId][observerId] = true
end

function Links.unsubscribe(observerId: number, groupId: number)
	local observers = groupToObservers[groupId]
	if observers then
		observers[observerId] = nil
	end
end

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

function Links.detachAll(slot: number): { number }?
	local attached = zoneAttachedObservers[slot]
	zoneAttachedObservers[slot] = nil
	zoneSoleObserver[slot] = nil
	return attached
end

return Links

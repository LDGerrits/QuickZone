--!strict

local Registry = require(script.Parent.Registry)

local groups = Registry.groups

local Links = {}

Links.slotObservers = {} :: { [number]: { number } }
Links.slotSoleObserver = {} :: { [number]: number }

local slotObservers = Links.slotObservers
local slotSoleObserver = Links.slotSoleObserver

function Links.subscribes(observerId: number, groupId: number): boolean
	local group = groups[groupId]
	return group ~= nil and group.subscribers[observerId] == true
end

function Links.unsubscribeAll(observerId: number)
	for _, group in groups do
		group.subscribers[observerId] = nil
	end
end

function Links.subscribe(observerId: number, groupId: number)
	groups[groupId].subscribers[observerId] = true
end

function Links.unsubscribe(observerId: number, groupId: number)
	local group = groups[groupId]
	if group then
		group.subscribers[observerId] = nil
	end
end

function Links.attach(slot: number, observerId: number): boolean
	local attached = slotObservers[slot] or {}
	slotObservers[slot] = attached

	if table.find(attached, observerId) then
		return false
	end
	table.insert(attached, observerId)
	if #attached == 1 then
		slotSoleObserver[slot] = attached[1]
	else
		slotSoleObserver[slot] = nil
	end
	return true
end

function Links.detach(slot: number, observerId: number): boolean
	local attached = slotObservers[slot]
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
		if #attached == 1 then
			slotSoleObserver[slot] = attached[1]
		else
			slotSoleObserver[slot] = nil
		end
	end

	if #attached == 0 then
		slotObservers[slot] = nil
	end
	return idx ~= nil
end

function Links.detachAll(slot: number): { number }?
	local attached = slotObservers[slot]
	slotObservers[slot] = nil
	slotSoleObserver[slot] = nil
	return attached
end

return Links

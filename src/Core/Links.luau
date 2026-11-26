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

-- Zones with one observer share that observer's frozen list, so most zones carry no list of their own. Only Links
-- writes to the lists, and a list of one is always the shared one.
local soleLists = {} :: { [number]: { number } }
Links.soleLists = soleLists

local function soleListOf(observerId: number): { number }
	local list = soleLists[observerId]
	if not list then
		list = table.freeze({ observerId })
		soleLists[observerId] = list
	end
	return list
end

function Links.attach(slot: number, observerId: number): boolean
	local attached = slotObservers[slot]
	if not attached then
		slotObservers[slot] = soleListOf(observerId)
		slotSoleObserver[slot] = observerId
		return true
	end

	if table.find(attached, observerId) then
		return false
	end
	if #attached == 1 then
		slotObservers[slot] = { attached[1], observerId }
		slotSoleObserver[slot] = nil
	else
		table.insert(attached, observerId)
	end
	return true
end

function Links.detach(slot: number, observerId: number): boolean
	local attached = slotObservers[slot]
	local idx = attached and table.find(attached, observerId)
	if not attached or not idx then
		return false
	end

	local count = #attached
	if count == 1 then
		slotObservers[slot] = nil
		slotSoleObserver[slot] = nil
	elseif count == 2 then
		local remaining = if idx == 1 then attached[2] else attached[1]
		slotObservers[slot] = soleListOf(remaining)
		slotSoleObserver[slot] = remaining
	else
		attached[idx] = attached[count]
		attached[count] = nil
	end
	return true
end

function Links.detachAll(slot: number): { number }?
	local attached = slotObservers[slot]
	slotObservers[slot] = nil
	slotSoleObserver[slot] = nil
	return attached
end

function Links.dropSoleList(observerId: number)
	soleLists[observerId] = nil
end

return Links

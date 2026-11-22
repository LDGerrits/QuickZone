--!strict

local Entities = require(script.Parent.Entities)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Parent.Types)

type CallbackList = { any }

local entityData = Entities.entityData
local observers = Registry.observers
local zoneIdToZoneObj = Registry.zoneIdToZoneObj

local Callbacks = {}

local firing = 0
local blanked = {} :: { [CallbackList]: true }

local function withTraceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function compact(list: CallbackList)
	local count = 0
	for _, callback in list do
		if callback then
			count += 1
			list[count] = callback
		end
	end
	for i = #list, count + 1, -1 do
		list[i] = nil
	end
end

function Callbacks.connect(list: CallbackList, callback: Types.ObserverCallback): () -> ()
	table.insert(list, callback)

	return function()
		local idx = table.find(list, callback)
		if not idx then
			return
		elseif firing > 0 then
			list[idx] = false
			blanked[list] = true
		else
			table.remove(list, idx)
		end
	end
end

function Callbacks.fire(
	callbacks: CallbackList,
	observerId: number,
	reference: any,
	zone: Types.Zone,
	entity: any,
	safety: boolean,
	zoneId: number?
)
	firing += 1

	for i = 1, #callbacks do
		local callback = callbacks[i]
		if not callback then
			continue
		end

		if i > 1 then
			local data = entityData[entity]
			local now = if data then data.activeObserverMemberships[observerId] else nil
			if now ~= zoneId then
				local observer = observers[observerId]
				if now == nil or not observer or callbacks ~= observer.enteredCallbacks then
					break
				end
				zoneId = now
				zone = zoneIdToZoneObj[now]
			end
		end

		if safety then
			task.spawn(callback, reference, zone, entity)
		else
			local ok, trace = xpcall(callback, withTraceback, reference, zone, entity)
			if not ok then
				task.spawn(error, trace, 0)
			end
		end
	end

	firing -= 1
	if firing == 0 and next(blanked) then
		for list in blanked do
			compact(list)
		end
		table.clear(blanked)
	end
end

-- How many fire calls are running, for the scheduler to put back when a tick's thread dies inside one
function Callbacks.depth(): number
	return firing
end

function Callbacks.restoreDepth(depth: number)
	firing = depth
	if firing == 0 and next(blanked) then
		for list in blanked do
			compact(list)
		end
		table.clear(blanked)
	end
end

function Callbacks.call<A...>(callback: (A...) -> ...any, safety: boolean, ...: A...)
	if safety then
		task.spawn(callback, ...)
	else
		local ok, trace = xpcall(callback, withTraceback, ...)
		if not ok then
			task.spawn(error, trace, 0)
		end
	end
end

return Callbacks

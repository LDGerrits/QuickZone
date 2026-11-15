--!strict

-- Observer enter, exit and transition callbacks and group trackers. Only this module writes the observers' lists

local Entities = require(script.Parent.Entities)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Parent.Types)

-- Entries are blanked to false while firing when disconnected
type CallbackList = { any }

local entityData = Entities.entityData
local observers = Registry.observers
local zoneIdToZoneObj = Registry.zoneIdToZoneObj

local Callbacks = {}

-- While firing, a disconnect blanks its entry so no list shifts under a loop; the last fire compacts
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

-- One of the observer's lists. zoneId is the entity's new zone, nil for exits
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

	-- Callbacks connected during the event wait for the next one
	for i = 1, #callbacks do
		local callback = callbacks[i]
		if not callback then
			continue
		end

		if i > 1 then
			-- Stop once a callback moved the entity, or later ones would see an entry after its own exit
			local data = entityData[entity]
			local now = if data then data.activeObserverMemberships[observerId] else nil
			if now ~= zoneId then
				-- Unless its zone was destroyed and it moved to another: later callbacks get that entry
				local observer = observers[observerId]
				if now == nil or not observer or callbacks ~= observer.entered then
					break
				end
				zoneId = now
				zone = zoneIdToZoneObj[now]
			end
		end

		-- Callbacks.call, inlined as events are many
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

-- Unsafe callbacks report errors instead of throwing, so they can't interrupt the state change that ran them
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

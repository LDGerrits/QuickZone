--!strict

-- Observer enter, exit and transition callbacks. Lists are keyed by observer id and only
-- changed through connect, so firing never sees a list shift under it

local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

type CallbackLists = { [number]: { (any, Types.Zone, Types.Entity) -> () } }

local entityData = State.entityData

local function withTraceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local Callbacks = {}

-- Adds a callback to lists[key], returns its disconnect function. Lists are replaced
-- rather than changed, so a list being fired never shifts under the loop
function Callbacks.connect(lists: CallbackLists, key: number, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	local list = lists[key]
	if not list then
		return function() end
	end

	local connected = table.clone(list)
	table.insert(connected, callback)
	lists[key] = connected

	return function()
		local current = lists[key]
		local idx = current and table.find(current, callback)
		if idx then
			local remaining = table.clone(current)
			table.remove(remaining, idx)
			lists[key] = remaining
		end
	end
end

-- Fires the callbacks in lists[key] for an entity now in zoneId, or out of the observer's zones when nil
function Callbacks.fire(
	lists: CallbackLists,
	key: number,
	reference: any,
	zone: Types.Zone,
	entity: any,
	safety: boolean,
	zoneId: number?
)
	local callbacks = lists[key]
	if not callbacks then
		return
	end

	for i, callback in callbacks do
		if i > 1 then
			-- Stop once an earlier callback moved the entity, as later ones would see this event after the
			-- next. An entry would then come after its own exit, and never be followed by one
			local data = entityData[entity]
			if (if data then data.activeObserverMemberships[key] else nil) ~= zoneId then
				break
			end

			-- Skip callbacks an earlier one disconnected
			local current = lists[key]
			if current ~= callbacks and not (current and table.find(current, callback)) then
				continue
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
end

-- Runs a callback in its own thread when safe. Unsafe callbacks run directly, but an error is reported instead
-- of thrown, so it can't interrupt the state change that ran it
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

--!strict

local Types = require(script.Parent.Parent.Types)

type CallbackLists = { [number]: { (any, Types.Zone, Types.Entity) -> () } }

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

-- Fires the callbacks in lists[key]. Unsafe callbacks run directly, but an error is
-- reported instead of thrown, so it can't interrupt the state change that fired it
function Callbacks.fire(
	lists: CallbackLists,
	key: number,
	reference: any,
	zone: Types.Zone,
	entity: any,
	safety: boolean
)
	local callbacks = lists[key]
	if not callbacks then
		return
	end

	for i, callback in callbacks do
		-- Skip callbacks an earlier one disconnected
		if i > 1 then
			local current = lists[key]
			if current ~= callbacks and not (current and table.find(current, callback)) then
				continue
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
end

return Callbacks

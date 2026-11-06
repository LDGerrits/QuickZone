--!strict

-- Observer enter, exit and transition callbacks. Lists are keyed by observer id and only
-- changed through connect, so firing never sees a list shift under it

local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)
local Log = require(script.Parent.Parent.Utils.Log)

type CallbackLists = { [number]: { (any, Types.Zone, Types.Entity) -> () } }

local entityData = State.entityData
local enteredLists = State.observerEnteredCallbacks
local zoneIdToZoneObj = State.zoneIdToZoneObj

-- How many fires are going on. Lists are only changed in place while none is, as one may be going through the
-- list. A plain count rather than one per list, as it is kept on every event
local firing = 0

local function withTraceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local Callbacks = {}

-- Adds a callback to lists[key], returns its disconnect function. While a fire goes on, lists are replaced
-- rather than changed, so none shifts under its loop. Otherwise in place, so connecting many stays cheap
function Callbacks.connect(lists: CallbackLists, key: number, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	-- Checked here, as a tick would only fail on it at the next event
	if type(callback) ~= 'function' then
		Log.fatal('Expected a function to connect, got %s.', nil, typeof(callback))
	end

	local list = lists[key]
	if not list then
		return function() end
	end

	if firing > 0 then
		list = table.clone(list)
		lists[key] = list
	end
	table.insert(list, callback)

	return function()
		local current = lists[key]
		local idx = current and table.find(current, callback)
		if idx then
			if firing > 0 then
				current = table.clone(current)
				lists[key] = current
			end
			table.remove(current :: { any }, idx)
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

	firing += 1

	for i, callback in callbacks do
		if i > 1 then
			-- Stop once an earlier callback moved the entity, as later ones would see this event after the
			-- next. An entry would then come after its own exit, and never be followed by one
			local data = entityData[entity]
			local now = if data then data.activeObserverMemberships[key] else nil
			if now ~= zoneId then
				-- Unless an entry moved on to another of the observer's zones, as its zone was destroyed. The
				-- entity is still inside, so later callbacks get the entry, into the zone it is in now
				if now == nil or lists ~= enteredLists then
					break
				end
				zoneId = now
				zone = zoneIdToZoneObj[now]
			end

			-- Skip callbacks an earlier one disconnected. A destroyed observer has no list, and its exits
			-- still reach every callback, as they would have without the destroy
			local current = lists[key]
			if current ~= callbacks and current ~= nil and not table.find(current, callback) then
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

	firing -= 1
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

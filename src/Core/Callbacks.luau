--!strict

-- Observer enter, exit and transition callbacks, in lists keyed by observer id

local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

type CallbackLists = { [number]: { any } }

local entityData = State.entityData
local enteredLists = State.observerEnteredCallbacks
local zoneIdToZoneObj = State.zoneIdToZoneObj

-- How many fires are going on. While any is, a disconnect blanks its entry rather than removing it, so no list
-- shifts under a loop. The last fire to end compacts the lists that were blanked
local firing = 0
local blanked = {} :: { [{ any }]: true }

local function withTraceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function compact(list: { any })
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

local Callbacks = {}

-- Adds a callback to lists[key], returns its disconnect function
function Callbacks.connect(lists: CallbackLists, key: number, callback: (any, Types.Zone, Types.Entity) -> ()): () -> ()
	local list = lists[key] :: { any }
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

	-- Up to the callbacks connected now, as those connected during the event wait for the next one
	for i = 1, #callbacks do
		local callback = callbacks[i]
		-- Disconnected by an earlier one
		if not callback then
			continue
		end

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

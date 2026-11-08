--!strict

-- Observer enter, exit and transition callbacks and group trackers. Only this module writes the lists

local Entities = require(script.Parent.Entities)
local Registry = require(script.Parent.Registry)
local Types = require(script.Parent.Parent.Types)

type CallbackLists = { [number]: { any } }

local entityData = Entities.entityData
local zoneIdToZoneObj = Registry.zoneIdToZoneObj

local Callbacks = {}

Callbacks.observerEnteredCallbacks = {} :: { [number]: { (any, Types.Zone, Types.Entity) -> () } }
Callbacks.observerExitedCallbacks = {} :: { [number]: { (any, Types.Zone, Types.Entity) -> () } }
Callbacks.observerTransitionedCallbacks = {} :: { [number]: { (any, Types.Zone, Types.Entity) -> () } }
-- Only set while the observer has trackers
Callbacks.observerGroupTrackers = {} :: { [number]: { (entity: any, destroyedGroupId: number?) -> () } }

local enteredLists = Callbacks.observerEnteredCallbacks

-- While firing, a disconnect blanks its entry so no list shifts under a loop; the last fire compacts
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

-- zoneId is the entity's new zone, nil for exits
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

	-- Callbacks connected during the event wait for the next one
	for i = 1, #callbacks do
		local callback = callbacks[i]
		if not callback then
			continue
		end

		if i > 1 then
			-- Stop once a callback moved the entity, or later ones would see an entry after its own exit
			local data = entityData[entity]
			local now = if data then data.activeObserverMemberships[key] else nil
			if now ~= zoneId then
				-- Unless its zone was destroyed and it moved to another: later callbacks get that entry
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

function Callbacks.addObserver(observerId: number)
	Callbacks.observerEnteredCallbacks[observerId] = {}
	Callbacks.observerExitedCallbacks[observerId] = {}
	Callbacks.observerTransitionedCallbacks[observerId] = {}
end

function Callbacks.dropObserver(observerId: number)
	Callbacks.observerEnteredCallbacks[observerId] = nil
	Callbacks.observerExitedCallbacks[observerId] = nil
	Callbacks.observerTransitionedCallbacks[observerId] = nil
	Callbacks.observerGroupTrackers[observerId] = nil
end

-- Group trackers are replaced rather than changed, so a list being run never shifts
function Callbacks.addGroupTracker(observerId: number, track: (entity: any, destroyedGroupId: number?) -> ())
	local trackers = Callbacks.observerGroupTrackers[observerId]
	local updated = if trackers then table.clone(trackers) else {}
	table.insert(updated, track)
	Callbacks.observerGroupTrackers[observerId] = updated
end

function Callbacks.removeGroupTracker(observerId: number, track: (entity: any, destroyedGroupId: number?) -> ())
	local current = Callbacks.observerGroupTrackers[observerId]
	local idx = current and table.find(current, track)
	if idx then
		local remaining = table.clone(current :: { (any) -> () })
		table.remove(remaining, idx)
		Callbacks.observerGroupTrackers[observerId] = if #remaining > 0 then remaining else nil
	end
end

return Callbacks

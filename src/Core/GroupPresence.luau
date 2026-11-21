--!strict

-- Which of an observer's groups are inside it: a group arrives when its first counted member is inside and leaves
-- when its last one goes. Only this module runs trackers:
--   an entity joins or leaves a group        Members   groupsChanged
--   an observer subscribes or unsubscribes   Wiring    subscriptionChanged
--   a group is destroyed                     Groups    groupDestroyed
--   an entity enters, moves or exits         the tracker's own entries in the observer's callback lists
-- Each tracker keeps its own state. Trackers decide at their own place among the observer's callbacks, so one
-- connected later may see a change the earlier one's callbacks already undid

local Types = require(script.Parent.Parent.Types)
local Snapshot = require(script.Parent.Parent.Utils.Snapshot)
local Callbacks = require(script.Parent.Callbacks)
local Entities = require(script.Parent.Entities)
local Memberships = require(script.Parent.Memberships)
local Registry = require(script.Parent.Registry)

local entityData = Entities.entityData
local groups = Registry.groups
local observers = Registry.observers
local zoneIdToZoneObj = Registry.zoneIdToZoneObj
local bringsIn = Memberships.bringsIn

export type OnPresence = (groupId: number, group: Types.Group, zone: Types.Zone, entity: Types.Entity) -> ()
type Tracker = Types.Tracker

local GroupPresence = {}

local function addTracker(observer: Types.InternalObserver, track: Tracker)
	local updated = if observer.trackers then table.clone(observer.trackers) else {}
	table.insert(updated, track)
	observer.trackers = updated
end

local function removeTracker(observer: Types.InternalObserver, track: Tracker)
	local current = observer.trackers
	local idx = current and table.find(current, track)
	if idx then
		local remaining = table.clone(current :: { Tracker })
		table.remove(remaining, idx)
		observer.trackers = if #remaining > 0 then remaining else nil
	end
end

local function trackersOf(observerId: number): { Tracker }?
	local observer = observers[observerId]
	return observer and observer.trackers
end

local function runTrackers(observerId: number, entity: Types.Entity?, destroyedGroupId: number?)
	local trackers = trackersOf(observerId)
	if trackers then
		for _, track in trackers do
			track(entity, destroyedGroupId)
		end
	end
end

-- Observers it is in may now count, or stop counting, one of its groups
function GroupPresence.groupsChanged(entity: Types.Entity)
	local data = entityData[entity]
	if not data then
		return
	end

	-- Collected first, as trackers run callbacks that may change memberships
	local observerIds: { number }? = nil
	for id in data.activeObserverMemberships do
		if trackersOf(id) then
			observerIds = observerIds or {}
			table.insert(observerIds :: { number }, id)
		end
	end

	if observerIds then
		for _, id in observerIds do
			runTrackers(id, entity, nil)
		end
	end
end

-- Starts counting the observer's groups, from the entities already inside, and returns a disconnect. Read from
-- state rather than replayed from events, as entities change groups while inside
function GroupPresence.track(observer: Types.InternalObserver, onArrive: OnPresence, onLeave: OnPresence): () -> ()
	local observerId = observer.id
	local present = {} :: { [number]: { [Types.Entity]: true } }
	local counted = {} :: { [Types.Entity]: { [number]: true } }
	local lastZones = {} :: { [Types.Entity]: Types.Zone }
	-- Also set by a callback halfway through a change
	local disconnected = false

	local function counts(entity: Types.Entity, groupId: number): boolean
		local data = entityData[entity]
		return data ~= nil
			and data.activeObserverMemberships[observerId] ~= nil
			and bringsIn(groupId, entity, observerId)
	end

	local function reconcile(entity: Types.Entity, exitZone: Types.Zone?)
		local data = entityData[entity]
		local zoneId = data and data.activeObserverMemberships[observerId]
		local current = if zoneId then zoneIdToZoneObj[zoneId] else exitZone
		if current and counted[entity] then
			lastZones[entity] = current
		end

		-- Collected first, as callbacks below may change groups and memberships
		local leaving: { number }? = nil
		local arriving: { number }? = nil
		local have = counted[entity]
		if have then
			for groupId in have do
				if not counts(entity, groupId) then
					leaving = leaving or {}
					table.insert(leaving :: { number }, groupId)
				end
			end
		end
		if data then
			for groupId in data.groups do
				if not (have and have[groupId]) and counts(entity, groupId) then
					arriving = arriving or {}
					table.insert(arriving :: { number }, groupId)
				end
			end
		end

		if leaving then
			for _, groupId in leaving do
				-- A callback may have disconnected, or settled it already
				local now = counted[entity]
				if disconnected or not (now and now[groupId]) or counts(entity, groupId) then
					continue
				end
				now[groupId] = nil
				if next(now) == nil then
					counted[entity] = nil
					lastZones[entity] = nil
				end
				local members = present[groupId]
				members[entity] = nil
				if next(members) == nil then
					present[groupId] = nil
					local group = groups[groupId]
					if group then
						onLeave(groupId, group, current :: Types.Zone, entity)
					end
				end
			end
		end

		if arriving then
			for _, groupId in arriving do
				local now = counted[entity]
				if disconnected or (now and now[groupId]) or not counts(entity, groupId) then
					continue
				end
				if not now then
					now = {}
					counted[entity] = now
					lastZones[entity] = current :: Types.Zone
				end
				(now :: { [number]: true })[groupId] = true
				local members = present[groupId]
				if members then
					members[entity] = true
				else
					present[groupId] = { [entity] = true }
					onArrive(groupId, groups[groupId], current :: Types.Zone, entity)
				end
			end
		end
	end

	local function onEvent(_, zone: Types.Zone, entity: Types.Entity)
		if not disconnected then
			reconcile(entity, zone)
		end
	end
	-- Entries in the observer's own lists, so each tracker decides at its place among the user's callbacks
	local disconnectEnter = Callbacks.connect(observer.enteredCallbacks, onEvent)
	local disconnectTransition = Callbacks.connect(observer.transitionedCallbacks, onEvent)
	local disconnectExit = Callbacks.connect(observer.exitedCallbacks, onEvent)

	-- Runs while the group still exists, and may count entities whose exit hasn't reached this tracker yet
	local function dropGroup(groupId: number)
		local members = present[groupId]
		if not members then
			return
		end
		present[groupId] = nil
		local last: Types.Entity?, zone: Types.Zone?
		for entity in members do
			last = entity
			zone = lastZones[entity]
			local have = counted[entity]
			if have then
				have[groupId] = nil
				if next(have) == nil then
					counted[entity] = nil
					lastZones[entity] = nil
				end
			end
		end
		local group = groups[groupId]
		if group then
			onLeave(groupId, group, zone :: Types.Zone, last :: Types.Entity)
		end
	end

	local function track(entity: Types.Entity?, destroyedGroupId: number?)
		if disconnected then
			return
		elseif destroyedGroupId then
			dropGroup(destroyedGroupId)
		else
			reconcile(entity :: Types.Entity, nil)
		end
	end
	addTracker(observer, track)

	local inside = {}
	for entity in observer.tracked do
		table.insert(inside, entity)
	end
	for _, entity in inside do
		reconcile(entity, nil)
	end

	return function()
		disconnected = true
		disconnectEnter()
		disconnectTransition()
		disconnectExit()
		removeTracker(observer, track)
	end
end

-- Members inside through other groups now bring this one in, or no longer do
function GroupPresence.subscriptionChanged(observerId: number, groupId: number)
	-- A callback during unsubscribe may have destroyed the group, which already let its trackers know
	local group = groups[groupId]
	if group and trackersOf(observerId) then
		-- Cloned: tracker callbacks may change the group
		for _, entity in table.clone(group.members) do
			local data = entityData[entity]
			if data and data.activeObserverMemberships[observerId] then
				runTrackers(observerId, entity, nil)
			end
		end
	end
end

-- While the group still exists. Every tracker, as one may still count entities that left before it heard
function GroupPresence.groupDestroyed(groupId: number)
	-- A snapshot, as trackers run callbacks that may connect and disconnect others
	for id in Snapshot.keys(observers) do
		runTrackers(id, nil, groupId)
	end
end

return GroupPresence

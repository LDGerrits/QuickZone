--!native
--!optimize 2
--!strict

-- Which observers watch each entity, at what rate, precision and trees, and the scheduler's buckets.
-- Others mark entities, only this module writes the routing

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local Registry = require(script.Parent.Registry)

local observers = Registry.observers

local entityData = Entities.entityData
local groups = Registry.groups

local Routing = {}

-- Raised to recheck every entity next tick
Routing.logicVersion = 0
Routing.dirtyProfiles = {} :: { [Types.Entity]: boolean }
Routing.dirtyTopology = {} :: { [Types.Entity]: boolean }
Routing.bucketList = {} :: { number }
Routing.buckets = {} :: { [number]: { Types.Entity } }

local dirtyProfiles = Routing.dirtyProfiles
local dirtyTopology = Routing.dirtyTopology
local bucketList = Routing.bucketList
local buckets = Routing.buckets

-- Works out rate, precision and trees again at the next tick
function Routing.reroute(entity: Types.Entity)
	dirtyProfiles[entity] = true
	dirtyTopology[entity] = true
end

-- Also checked next tick when standing still, as another observer may take it over
function Routing.recheck(entity: Types.Entity)
	Routing.reroute(entity)
	local data = entityData[entity]
	if data then
		data.logicVersion = -1
	end
end

function Routing.leaveBucket(entity: Types.Entity, data: Types.EntityData)
	local bucket = buckets[data.updateRate]
	local idx = data.bucketIndex
	-- Already out: the slot is empty or holds the entity swapped into it
	if not bucket or bucket[idx] ~= entity then
		return
	end

	local last = #bucket
	local lastEntity = bucket[last]
	bucket[idx] = lastEntity
	entityData[lastEntity].bucketIndex = idx
	bucket[last] = nil
	data.bucketIndex = 0
end

local function processProfileChange(entity: Types.Entity, data: Types.EntityData)
	local linkedObservers = data.observers
	if linkedObservers then
		table.clear(linkedObservers)
	else
		linkedObservers = {}
	end

	local minPrecSq = math.huge
	local maxRate = 0

	for groupId, _ in data.groups do
		local group = groups[groupId]
		if not group then
			continue
		end

		for observerId, _ in group.subscribers do
			(linkedObservers :: { [number]: true })[observerId] = true

			local observer = observers[observerId]
			local prec = observer.precisionSq
			local rate = observer.updateRate

			if prec < minPrecSq then
				minPrecSq = prec
			end
			if rate > maxRate then
				maxRate = rate
			end
		end
	end

	if data.updateRate ~= maxRate then
		Routing.leaveBucket(entity, data)

		if maxRate > 0 then
			if not buckets[maxRate] then
				buckets[maxRate] = {}
				table.insert(bucketList, maxRate)
				table.sort(bucketList, function(a: number, b: number)
					return a > b
				end)
			end

			local newBucket = buckets[maxRate]
			local newIdx = #newBucket + 1
			newBucket[newIdx] = entity
			data.bucketIndex = newIdx
		end

		data.updateRate = maxRate
	end

	-- Rate 0 means no observer watches the entity
	if maxRate > 0 then
		data.precisionSq = minPrecSq
		data.observers = linkedObservers
	else
		data.observers = nil
	end
end

local function processTopologyChange(data: Types.EntityData)
	local needsStatic = false
	local needsDynamic = false
	local linkedObservers = data.observers

	if linkedObservers then
		for observerId, _ in linkedObservers do
			-- Settled profiles only route to live observers, but a stale route must not error the tick
			local observer = observers[observerId]
			if not observer then
				continue
			end
			if observer.staticZoneCount > 0 then
				needsStatic = true
			end
			if observer.dynamicZoneCount > 0 then
				needsDynamic = true
			end
			if needsStatic and needsDynamic then
				break
			end
		end
	end

	data.needsStatic = needsStatic
	data.needsDynamic = needsDynamic
end

-- Every member of a group the observer subscribes to
local function markMembersOf(observerId: number, alsoProfiles: boolean)
	for _, group in groups do
		if group.subscribers[observerId] then
			for _, entity in group.members do
				dirtyTopology[entity] = true
				if alsoProfiles then
					dirtyProfiles[entity] = true
				end
			end
		end
	end
end

function Routing.rerouteObserver(observerId: number)
	markMembersOf(observerId, true)
end

function Routing.recheckAll()
	Routing.logicVersion += 1
end

function Routing.changeZoneCount(observerId: number, isDynamic: boolean, delta: number)
	local observer = observers[observerId]
	local current = if isDynamic then observer.dynamicZoneCount else observer.staticZoneCount
	local newCount = current + delta
	if isDynamic then
		observer.dynamicZoneCount = newCount
	else
		observer.staticZoneCount = newCount
	end

	-- Delta is always 1 or -1, so only crossing zero changes which trees entities need
	if current == 0 or newCount == 0 then
		if newCount == 0 then
			Routing.recheckAll()
		end
		markMembersOf(observerId, false)
	end
end

function Routing.forget(entity: Types.Entity, data: Types.EntityData)
	Routing.leaveBucket(entity, data)
	data.observers = nil
	dirtyProfiles[entity] = nil
	dirtyTopology[entity] = nil
end

function Routing.settle(onBucketDropped: (rate: number) -> ())
	for entity, _ in dirtyProfiles do
		dirtyProfiles[entity] = nil
		local data = entityData[entity]
		if data then
			processProfileChange(entity, data)
		end
	end

	-- After profiles, as topology reads the observers they route to
	for entity, _ in dirtyTopology do
		dirtyTopology[entity] = nil
		local data = entityData[entity]
		if data then
			processTopologyChange(data)
		end
	end

	-- Only here, as callbacks can't shrink the list while a tick walks it
	for i = #bucketList, 1, -1 do
		local rate = bucketList[i]
		if #buckets[rate] == 0 then
			buckets[rate] = nil
			onBucketDropped(rate)
			table.remove(bucketList, i)
		end
	end
end

return Routing

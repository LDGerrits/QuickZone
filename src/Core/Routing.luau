--!native
--!optimize 2
--!strict

-- Works out which observers watch each entity, at what rate and precision, and in which trees, and keeps the
-- buckets the scheduler goes through and each observer's zone counts. Others mark entities to route here, only
-- this module writes the routing

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local Links = require(script.Parent.Links)
local Registry = require(script.Parent.Registry)

local observerPrecisionSq = Registry.observerPrecisionSq
local observerUpdateRate = Registry.observerUpdateRate

local entityData = Entities.entityData
local entityToGroups = Entities.entityToGroups
local groupToObservers = Links.groupToObservers
local zoneAttachedObservers = Links.zoneAttachedObservers

local Routing = {}

-- Raised to check every entity again at the next tick
Routing.logicVersion = 0
Routing.entityToObservers = {} :: { [Types.Entity]: { [number]: boolean } }
Routing.dirtyProfiles = {} :: { [Types.Entity]: boolean }
Routing.dirtyTopology = {} :: { [Types.Entity]: boolean }
Routing.bucketList = {} :: { number }
Routing.buckets = {} :: { [number]: { Types.Entity } }
-- How many static and dynamic zones each observer has, which decides the trees its entities are checked in
Routing.observerDynamicCount = {} :: { [number]: number }
Routing.observerStaticCount = {} :: { [number]: number }

local observerStaticCount = Routing.observerStaticCount
local observerDynamicCount = Routing.observerDynamicCount
local entityToObservers = Routing.entityToObservers
local dirtyProfiles = Routing.dirtyProfiles
local dirtyTopology = Routing.dirtyTopology
local bucketList = Routing.bucketList
local buckets = Routing.buckets

-- The entity's observers changed their settings, so its rate, precision and trees are worked out at the next tick
function Routing.reroute(entity: Types.Entity)
	dirtyProfiles[entity] = true
	dirtyTopology[entity] = true
end

-- The entity's groups or their observers changed. Rerouted, and checked at the next tick also when it stands
-- still, as another observer may take it over
function Routing.recheck(entity: Types.Entity)
	Routing.reroute(entity)
	local data = entityData[entity]
	if data then
		data.logicVersion = -1
	end
end

-- Takes an entity out of the bucket of its update rate, swapping the last one into its place
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

local function processProfileChange(entity: Types.Entity)
	local groups = entityToGroups[entity]
	if not groups then
		return
	end

	-- Track linked observers for quick lookup in hot loop
	local linkedObservers = entityToObservers[entity]
	if linkedObservers then
		table.clear(linkedObservers)
	else
		linkedObservers = {}
	end

	local minPrecSq = math.huge
	local maxRate = 0

	-- Find the highest settings across all subscribed observers
	for groupId, _ in groups do
		local observers = groupToObservers[groupId]
		if not observers then
			continue
		end

		for observerId, _ in observers do
			linkedObservers[observerId] = true

			local prec = observerPrecisionSq[observerId]
			local rate = observerUpdateRate[observerId]

			if prec < minPrecSq then
				minPrecSq = prec
			end
			if rate > maxRate then
				maxRate = rate
			end
		end
	end

	local data = entityData[entity]

	-- Swap buckets
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

	-- Rates are above 0, so a rate of 0 means no observer watches the entity
	if maxRate > 0 then
		data.precisionSq = minPrecSq
		entityToObservers[entity] = linkedObservers
	else
		entityToObservers[entity] = nil
	end
end

local function processTopologyChange(entity: Types.Entity)
	local data = entityData[entity]
	if not data then
		return
	end

	local needsStatic = false
	local needsDynamic = false
	local linkedObservers = entityToObservers[entity]

	if linkedObservers then
		for observerId, _ in linkedObservers do
			if (observerStaticCount[observerId] or 0) > 0 then
				needsStatic = true
			end
			if (observerDynamicCount[observerId] or 0) > 0 then
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

-- The trees the entity's observers query changed, so the entity is placed again at the next tick
local function markTopology(entity: Types.Entity)
	dirtyTopology[entity] = true
end

-- Checks every entity again at the next tick, also those that stand still
function Routing.recheckAll()
	Routing.logicVersion += 1
end

function Routing.addObserver(observerId: number)
	observerStaticCount[observerId] = 0
	observerDynamicCount[observerId] = 0
end

-- Drops the zone counts of a destroyed observer, once its zones have detached
function Routing.dropObserver(observerId: number)
	observerStaticCount[observerId] = nil
	observerDynamicCount[observerId] = nil
end

-- Counts a zone the observer gained or lost in a tree
function Routing.changeZoneCount(observerId: number, isDynamic: boolean, delta: number)
	local dict = isDynamic and observerDynamicCount or observerStaticCount
	local current = dict[observerId] or 0
	local newCount = current + delta
	dict[observerId] = newCount

	-- Only flag entities dirty when the observer gains its first zone in the tree or loses its last, as the
	-- delta is always 1 or -1
	if current == 0 or newCount == 0 then
		-- Check every entity again when an observer loses its last zone
		if newCount == 0 then
			Routing.recheckAll()
		end

		for groupId, observers in groupToObservers do
			if not observers[observerId] then
				continue
			end

			local group = Registry.groups[groupId]
			if not group then
				continue
			end

			for _, entity in group.entities do
				markTopology(entity)
			end
		end
	end
end

-- Moves the zone in the slot to the other tree in its observers' counts
function Routing.moveZoneCounts(slot: number, isDynamic: boolean)
	local attached = zoneAttachedObservers[slot]
	if attached then
		for _, observerId in attached do
			Routing.changeZoneCount(observerId, not isDynamic, -1)
			Routing.changeZoneCount(observerId, isDynamic, 1)
		end
	end
end

-- Drops the routing of an entity that left its last group
function Routing.forget(entity: Types.Entity, data: Types.EntityData)
	Routing.leaveBucket(entity, data)
	entityToObservers[entity] = nil
	dirtyProfiles[entity] = nil
	dirtyTopology[entity] = nil
end

-- Routes the marked entities, at the start of a tick. onBucketDropped is told each rate whose bucket went
function Routing.settle(onBucketDropped: (rate: number) -> ())
	-- Route entities that have changed groups or observers since the last update
	for entity, _ in dirtyProfiles do
		dirtyProfiles[entity] = nil
		if entityData[entity] then
			processProfileChange(entity)
		end
	end

	-- Route entities of which the topology changed
	-- Must be after profile change
	for entity, _ in dirtyTopology do
		dirtyTopology[entity] = nil
		if entityData[entity] then
			processTopologyChange(entity)
		end
	end

	-- Drop buckets left empty by entities that changed rate or were removed. Only done here, as removals
	-- from callbacks can't shrink the list while a tick goes through it
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

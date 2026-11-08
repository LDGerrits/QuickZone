--!native
--!optimize 2
--!strict

-- Which observers watch each entity, at what rate, precision and trees, and the scheduler's buckets.
-- Others mark entities, only this module writes the routing

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local Links = require(script.Parent.Links)
local Registry = require(script.Parent.Registry)

local observerPrecisionSq = Registry.observerPrecisionSq
local observerUpdateRate = Registry.observerUpdateRate

local entityData = Entities.entityData
local entityToGroups = Entities.entityToGroups
local groupEntities = Entities.groupEntities
local groupToObservers = Links.groupToObservers

local Routing = {}

-- Raised to recheck every entity next tick
Routing.logicVersion = 0
Routing.entityToObservers = {} :: { [Types.Entity]: { [number]: boolean } }
Routing.dirtyProfiles = {} :: { [Types.Entity]: boolean }
Routing.dirtyTopology = {} :: { [Types.Entity]: boolean }
Routing.bucketList = {} :: { number }
Routing.buckets = {} :: { [number]: { Types.Entity } }
-- Zones per observer per tree, which decide the trees its entities query
Routing.observerDynamicCount = {} :: { [number]: number }
Routing.observerStaticCount = {} :: { [number]: number }

local observerStaticCount = Routing.observerStaticCount
local observerDynamicCount = Routing.observerDynamicCount
local entityToObservers = Routing.entityToObservers
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

local function processProfileChange(entity: Types.Entity)
	local groups = entityToGroups[entity]
	if not groups then
		return
	end

	local linkedObservers = entityToObservers[entity]
	if linkedObservers then
		table.clear(linkedObservers)
	else
		linkedObservers = {}
	end

	local minPrecSq = math.huge
	local maxRate = 0

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

function Routing.rerouteObserver(observerId: number)
	for groupId, observers in groupToObservers do
		local members = groupEntities[groupId]
		if members and observers[observerId] then
			for _, entity in members do
				Routing.reroute(entity)
			end
		end
	end
end

function Routing.recheckAll()
	Routing.logicVersion += 1
end

function Routing.addObserver(observerId: number)
	observerStaticCount[observerId] = 0
	observerDynamicCount[observerId] = 0
end

-- Call once the observer's zones have detached
function Routing.dropObserver(observerId: number)
	observerStaticCount[observerId] = nil
	observerDynamicCount[observerId] = nil
end

function Routing.changeZoneCount(observerId: number, isDynamic: boolean, delta: number)
	local dict = isDynamic and observerDynamicCount or observerStaticCount
	local current = dict[observerId] or 0
	local newCount = current + delta
	dict[observerId] = newCount

	-- Delta is always 1 or -1, so only crossing zero changes which trees entities need
	if current == 0 or newCount == 0 then
		if newCount == 0 then
			Routing.recheckAll()
		end

		for groupId, observers in groupToObservers do
			local members = groupEntities[groupId]
			if not (members and observers[observerId]) then
				continue
			end
			for _, entity in members do
				dirtyTopology[entity] = true
			end
		end
	end
end

function Routing.forget(entity: Types.Entity, data: Types.EntityData)
	Routing.leaveBucket(entity, data)
	entityToObservers[entity] = nil
	dirtyProfiles[entity] = nil
	dirtyTopology[entity] = nil
end

function Routing.settle(onBucketDropped: (rate: number) -> ())
	for entity, _ in dirtyProfiles do
		dirtyProfiles[entity] = nil
		if entityData[entity] then
			processProfileChange(entity)
		end
	end

	-- After profiles, as topology reads entityToObservers
	for entity, _ in dirtyTopology do
		dirtyTopology[entity] = nil
		if entityData[entity] then
			processTopologyChange(entity)
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

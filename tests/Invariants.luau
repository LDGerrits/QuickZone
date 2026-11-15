--!strict
-- What must hold between QuickZone's internal tables whenever no call into it is running. Run after every test, and
-- after every step of the model test. Returns the problems found, or nil
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local QuickZoneFolder = ReplicatedStorage.QuickZone
local Entities = require(QuickZoneFolder.Core.Entities)
local Links = require(QuickZoneFolder.Core.Links)
local Members = require(QuickZoneFolder.Core.Members)
local Memberships = require(QuickZoneFolder.Core.Memberships)
local References = require(QuickZoneFolder.Core.References)
local Registry = require(QuickZoneFolder.Core.Registry)
local Routing = require(QuickZoneFolder.Core.Routing)
local ZoneShapes = require(QuickZoneFolder.Core.ZoneShapes)

local MAX_PROBLEMS = 5

local Invariants = {}

local function sameKeys(a: { [any]: any }, b: { [any]: any }): boolean
	for key in a do
		if b[key] == nil then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Invariants.check(): string?
	local problems = {}
	local function problem(message: string)
		if #problems < MAX_PROBLEMS then
			table.insert(problems, message)
		end
	end

	local entityData = Entities.entityData
	local observers = Registry.observers
	local groupToObservers = Links.groupToObservers

	-- Observers: registered while alive under their own id, trackers only while they have some, and no blanked
	-- callbacks outside of firing
	for observerId, observer in observers do
		if observer.id ~= observerId or observer.phase == 'dead' then
			problem(`observer {observerId} is registered dead or under another id`)
		end
		if observer.trackers and #observer.trackers == 0 then
			problem(`observer {observerId} has an empty trackers list`)
		end
		for _, list in { observer.entered, observer.exited, observer.transitioned } do
			if table.find(list :: { any }, false) then
				problem(`observer {observerId} has a blanked callback outside of firing`)
			end
		end
	end

	-- Zones: ids, slots and objects agree, and each slot is in one tree
	local zoneIds = Registry.zoneIdToZoneObj
	local zoneSlots = Registry.zoneSlotToZoneObj
	for id, zone in zoneIds do
		if zoneSlots[zone.slot] ~= zone or ZoneShapes.zoneSlotIds[zone.slot] ~= id or zone.id ~= id then
			problem(`zone {id} disagrees with its slot {zone.slot}`)
		end
	end
	for slot, zone in zoneSlots do
		if zoneIds[zone.id] ~= zone then
			problem(`slot {slot} holds zone {zone.id}, which is not registered by id`)
		end
		local static = ZoneShapes.staticSlots[slot] == true
		local dynamic = ZoneShapes.dynamicSlots[slot] == true
		if static == dynamic then
			problem(`slot {slot} is static {static} and dynamic {dynamic}`)
		end
	end
	if count(ZoneShapes.zoneSlotIds) ~= count(zoneSlots) then
		problem('ZoneShapes.zoneSlotIds has slots without a zone')
	end
	for slot, zone in Registry.autoSyncZones do
		if zoneSlots[slot] ~= zone or not zone.autoSync or zone.reference == nil then
			problem(`slot {slot} syncs without a live zone set to autoSync with a reference`)
		end
	end
	if next(Memberships.zonesBeingDestroyed) then
		problem('Memberships.zonesBeingDestroyed is not empty outside of a destroy')
	end

	-- Zone links: lists of live observers without repeats, the sole observer cached, and the counts per tree
	local staticCount = {} :: { [number]: number }
	local dynamicCount = {} :: { [number]: number }
	for slot, attached in Links.slotObservers do
		if not zoneSlots[slot] then
			problem(`slot {slot} has observers but no zone`)
		end
		if #attached == 0 then
			problem(`slot {slot} has an empty observer list`)
		end
		local seen = {}
		for _, observerId in attached do
			if seen[observerId] or not observers[observerId] then
				problem(`slot {slot} lists observer {observerId} twice or after it was destroyed`)
			end
			seen[observerId] = true
			local counts = if ZoneShapes.dynamicSlots[slot] then dynamicCount else staticCount
			counts[observerId] = (counts[observerId] or 0) + 1
		end
		local sole = if #attached == 1 then attached[1] else nil
		if Links.slotSoleObserver[slot] ~= sole then
			problem(`slot {slot} caches sole observer {Links.slotSoleObserver[slot]}, expected {sole}`)
		end
	end
	for slot in Links.slotSoleObserver do
		if not Links.slotObservers[slot] then
			problem(`slot {slot} caches a sole observer without an observer list`)
		end
	end
	for observerId, observer in observers do
		local static = observer.staticZoneCount
		local dynamic = observer.dynamicZoneCount
		if static ~= (staticCount[observerId] or 0) or dynamic ~= (dynamicCount[observerId] or 0) then
			problem(
				`observer {observerId} counts {static} static and {dynamic} dynamic zones, has {staticCount[observerId] or 0} and {dynamicCount[observerId] or 0}`
			)
		end
	end

	-- Groups: every per-group table holds exactly the live groups
	local groups = Registry.groups
	local perGroup = {
		['Links.groupToObservers'] = groupToObservers,
		['Entities.groupEntities'] = Entities.groupEntities,
		['Entities.groupEntityIndices'] = Entities.groupEntityIndices,
		['Members.removalWatches'] = Members.removalWatches,
	} :: { [string]: { [number]: any } }
	for name, map in perGroup do
		if not sameKeys(map, groups) then
			problem(`{name} is not keyed by exactly the live groups`)
		end
	end
	for groupId in Members.autoCleanGroups do
		if not groups[groupId] then
			problem(`destroyed group {groupId} is still set to autoClean`)
		end
	end
	for groupId, subscribed in groupToObservers do
		for observerId in subscribed do
			if not observers[observerId] then
				problem(`group {groupId} is subscribed by destroyed observer {observerId}`)
			end
		end
	end

	-- Group members: list, index map and the entity's own groups agree
	for groupId, members in Entities.groupEntities do
		local indices = Entities.groupEntityIndices[groupId]
		if not indices then
			continue
		end
		if count(indices) ~= #members then
			problem(`group {groupId} lists {#members} members, indexes {count(indices)}`)
		end
		local autoClean = Members.autoCleanGroups[groupId] == true
		local watches = Members.removalWatches[groupId] or {}
		for idx, entity in members do
			if indices[entity] ~= idx then
				problem(`group {groupId} has {entity} at {idx}, indexed at {indices[entity]}`)
			end
			if not Entities.isIn(entity, groupId) or not entityData[entity] then
				problem(`group {groupId} lists {entity}, which is not in it`)
			end
			if (watches[entity :: any] ~= nil) ~= (autoClean and typeof(entity) == 'Instance') then
				problem(`group {groupId} watches {entity} for removal {watches[entity :: any] ~= nil}`)
			end
		end
		for entity in watches do
			if indices[entity] == nil then
				problem(`group {groupId} watches {entity}, which is not a member`)
			end
		end
	end

	-- Entities: data exactly while in a group, and each group lists it
	if not sameKeys(Entities.entityToGroups, entityData) then
		problem('Entities.entityToGroups is not keyed by exactly the entities with data')
	end
	for entity, entityGroups in Entities.entityToGroups do
		if next(entityGroups) == nil then
			problem(`{entity} has data but no groups`)
		end
		for groupId, isIn in entityGroups do
			local indices = Entities.groupEntityIndices[groupId]
			if isIn ~= true or not indices or indices[entity] == nil then
				problem(`{entity} is in group {groupId}, which does not list it`)
			end
		end
	end

	-- Routing: dirty marks only for tracked entities, and settled entities routed as their groups say
	for _, dirty in { Routing.dirtyProfiles, Routing.dirtyTopology } do
		for entity in dirty do
			if not entityData[entity] then
				problem(`{entity} is marked dirty without data`)
			end
		end
	end
	for entity in Routing.entityToObservers do
		if not entityData[entity] then
			problem(`{entity} is routed without data`)
		end
	end
	for entity, data in entityData do
		if Routing.dirtyProfiles[entity] then
			continue
		end
		local expected = {}
		local maxRate = 0
		local minPrecisionSq = math.huge
		for groupId in Entities.entityToGroups[entity] or {} do
			for observerId in groupToObservers[groupId] or {} do
				expected[observerId] = true
				local observer = observers[observerId]
				maxRate = math.max(maxRate, observer.updateRate)
				minPrecisionSq = math.min(minPrecisionSq, observer.precisionSq)
			end
		end
		local routed = Routing.entityToObservers[entity]
		if if maxRate > 0 then not (routed and sameKeys(routed, expected)) else routed ~= nil then
			problem(`{entity} is routed to the wrong observers`)
		end
		if data.updateRate ~= maxRate or (maxRate > 0 and data.precisionSq ~= minPrecisionSq) then
			problem(`{entity} has rate {data.updateRate} and precision {data.precisionSq}, expected {maxRate}`)
		end
		if Routing.dirtyTopology[entity] then
			continue
		end
		local needsStatic, needsDynamic = false, false
		for observerId in routed or {} do
			local observer = observers[observerId]
			needsStatic = needsStatic or observer.staticZoneCount > 0
			needsDynamic = needsDynamic or observer.dynamicZoneCount > 0
		end
		if data.needsStatic ~= needsStatic or data.needsDynamic ~= needsDynamic then
			problem(`{entity} queries static {data.needsStatic} dynamic {data.needsDynamic}, expected the opposite`)
		end
	end

	-- Buckets: one per rate in the sorted list, each entity at its own index
	local seenRates = {}
	for i, rate in Routing.bucketList do
		if seenRates[rate] or not Routing.buckets[rate] or (i > 1 and Routing.bucketList[i - 1] <= rate) then
			problem(`bucket list {table.concat(Routing.bucketList, ',')} is not sorted, unique and backed`)
			break
		end
		seenRates[rate] = true
	end
	for rate, bucket in Routing.buckets do
		if not seenRates[rate] then
			problem(`bucket {rate} is missing from the bucket list`)
		end
		for idx, entity in bucket do
			local data = entityData[entity]
			if not data or data.updateRate ~= rate or data.bucketIndex ~= idx then
				problem(`bucket {rate} has {entity} at {idx}, which does not belong there`)
			end
		end
	end
	for entity, data in entityData do
		if data.updateRate > 0 then
			local bucket = Routing.buckets[data.updateRate]
			if not bucket or bucket[data.bucketIndex] ~= entity then
				problem(`{entity} has rate {data.updateRate} but is not in its bucket`)
			end
		elseif data.bucketIndex ~= 0 then
			problem(`{entity} has no rate but bucket index {data.bucketIndex}`)
		end
	end

	-- Memberships: each one in the entity, the observer's tracked map and the zone's occupant count
	local occupants = {}
	for entity, data in entityData do
		for observerId, zoneId in data.activeObserverMemberships do
			local observer = observers[observerId]
			if not observer or observer.tracked[entity] ~= zoneId then
				problem(`{entity} is in zone {zoneId} for observer {observerId}, which does not track it there`)
			end
			if not zoneIds[zoneId] then
				problem(`{entity} is in destroyed zone {zoneId}`)
			end
			occupants[zoneId] = (occupants[zoneId] or 0) + 1
		end
	end
	for observerId, observer in observers do
		for entity, zoneId in observer.tracked do
			local data = entityData[entity]
			if not data or data.activeObserverMemberships[observerId] ~= zoneId then
				problem(`observer {observerId} tracks {entity} in zone {zoneId} without that membership`)
			end
		end
	end
	if not sameKeys(occupants, Memberships.zoneOccupants) then
		problem('Memberships.zoneOccupants counts zones without occupants, or misses some')
	end
	for zoneId, n in occupants do
		if Memberships.zoneOccupants[zoneId] ~= n then
			problem(`zone {zoneId} counts {Memberships.zoneOccupants[zoneId]} occupants, has {n}`)
		end
	end

	-- References: the reverse map points back
	for reference, entity in References.referenceToEntity do
		if References.entityToReference[entity] ~= reference then
			problem(`{reference} maps to {entity}, whose reference is {References.entityToReference[entity]}`)
		end
	end

	return if #problems > 0 then table.concat(problems, '; ') else nil
end

return Invariants

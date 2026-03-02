--!native
--!strict

local RunService = game:GetService('RunService')

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Geometry = require(script.Parent.Parent.Utils.Geometry)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local State = require(script.Parent.State)

local queryPoint = LinearBVH.queryPoint
local isPointInShape = Geometry.isPointInShape

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes
local zoneIdToZoneObj = State.zoneIdToZoneObj
local zoneAttachedObservers = State.zoneAttachedObservers
local autoSyncZones = State.autoSyncZones

local observerPriorityMap = State.observerPriorityMap
local observerTrackingEntities = State.observerTrackingEntities
local observerEnteredCallbacks = State.observerEnteredCallbacks
local observerExitedCallbacks = State.observerExitedCallbacks
local observerTransitionedCallbacks = State.observerTransitionedCallbacks
local observerEnabled = State.observerEnabled
local observerSafety = State.observerSafety
local observerPrecisionSq = State.observerPrecisionSq
local observerUpdateRate = State.observerUpdateRate
local observerStaticCount = State.observerStaticCount
local observerDynamicCount = State.observerDynamicCount

local entityData = State.entityData
local entityToObservers = State.entityToObservers
local entityToGroups = State.entityToGroups
local groupToObservers = State.groupToObservers
local bucketList = State.bucketList
local buckets = State.buckets
local dirtyProfiles = State.dirtyProfiles
local dirtyTopology = State.dirtyTopology

local ctx_pos: Vector3
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)
local ctx_linkedObservers: { [number]: boolean }
local ctx_currentMemberships: { [number]: number }

local frameBudget = Config.Scheduler.frameBudget
local autoSyncRate = Config.Scheduler.autoSyncRate
local autoSyncTimer = 0
local autoUpdateConnection: RBXScriptConnection?

local nextBucketIndex = 1 -- Round-robin pointer
local bucketLastProcessedIndex = {} :: { [number]: number }
local BUDGET_CHECK = 32

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME

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
	local currentRate = data.updateRate

	-- Swap buckets
	if currentRate ~= maxRate then
		-- Remove from old bucket
		if currentRate and currentRate > 0 and buckets[currentRate] then
			local oldBucket = buckets[currentRate]
			local idx = data.bucketIndex
			local maxEntities = #oldBucket
			local lastEntity = oldBucket[maxEntities]

			-- We swap and then pop to avoid shifting all entities down
			if idx ~= maxEntities then
				oldBucket[idx] = lastEntity
				if entityData[lastEntity] then
					entityData[lastEntity].bucketIndex = idx
				end
			end

			oldBucket[maxEntities] = nil

			if maxEntities == 1 then -- destroy empty bucket
				buckets[currentRate] = nil
				local listIdx = table.find(bucketList, currentRate)
				if listIdx then
					table.remove(bucketList, listIdx)
				end
			end
		end

		-- Add to new bucket
		if maxRate > 0 then
			if not buckets[maxRate] then
				buckets[maxRate] = {}
				table.insert(bucketList, maxRate)
				table.sort(bucketList, function(a, b)
					return a > b
				end)
			end

			local newBucket = buckets[maxRate]
			local newIdx = #newBucket + 1
			newBucket[newIdx] = entity
			data.bucketIndex = newIdx
		else
			data.bucketIndex = 0 -- Entity is not in a bucket, so no processing
		end

		data.updateRate = maxRate
	end

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

local function processZoneHit(zoneId: number)
	local observers = zoneAttachedObservers[zoneId]
	if not observers then
		return
	end

	for _, observerId in observers do
		if
			ctx_linkedObservers[observerId]
			and observerEnabled[observerId] ~= false
			and not ctx_candidatePriority[observerId]
		then
			local pri = observerPriorityMap[observerId] or 0

			if not ctx_candidatePriority[observerId] then
				ctx_cCount += 1
				ctx_candidateList[ctx_cCount] = observerId
				ctx_candidateIndex[observerId] = zoneId
				ctx_candidatePriority[observerId] = pri

				if pri > ctx_highestWin then
					ctx_highestWin = pri
				end
			elseif ctx_currentMemberships[observerId] == zoneId then
				-- Hold onto the zone for transitions
				ctx_candidateIndex[observerId] = zoneId
			end
		end
	end
end

local function queryCallbackStatic(zoneId: number)
	if isPointInShape(ctx_pos, staticCFrames[zoneId], staticHalfSizes[zoneId], staticTypes[zoneId]) then
		processZoneHit(zoneId)
	end
end

local function queryCallbackDynamic(zoneId: number)
	if isPointInShape(ctx_pos, dynamicCFrames[zoneId], dynamicHalfSizes[zoneId], dynamicTypes[zoneId]) then
		processZoneHit(zoneId)
	end
end

local function fireCallback(callbacks, entity, zone, safety)
	if safety then
		for _, cb in callbacks do
			task.spawn(cb, entity, zone)
		end
	else
		for _, cb in callbacks do
			cb(entity, zone)
		end
	end
end

local Scheduler = {}

function Scheduler.update(dt: number)
	local start = os.clock()

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

	-- Auto-sync zone positions if enabled
	if autoSyncRate > 0 then
		local syncInterval = 1 / autoSyncRate
		autoSyncTimer += dt

		if autoSyncTimer >= syncInterval then
			autoSyncTimer = 0
			local needsRebuild = false

			for id, zone in autoSyncZones do
				local reference = zone.reference
				if not reference then
					continue
				end

				local newCF = reference:IsA('Attachment') and reference.WorldCFrame or reference.CFrame
				local oldCF = dynamicCFrames[id]

				if oldCF == newCF then
					continue
				end

				dynamicCFrames[id] = newCF
				needsRebuild = true
			end

			if needsRebuild then
				State.pendingDynamicRebuild = true
			end
		end
	end

	Scheduler.rebuildTrees()

	if (os.clock() - start) > frameBudget then
		return
	end

	local staticTree = State.staticTree
	local dynamicTree = State.dynamicTree

	local numBuckets = #bucketList
	if numBuckets == 0 then
		return
	end

	-- Pointer may have gotten out of bounds
	if nextBucketIndex > numBuckets then
		nextBucketIndex = 1
	end

	local dynamicVersion = State.dynamicVersion
	local staticVersion = State.staticVersion
	local logicVersion = State.logicVersion

	-- Round-robin scheduling to prevent starvation
	for _ = 1, numBuckets do
		local rate = bucketList[nextBucketIndex]
		nextBucketIndex = (nextBucketIndex % numBuckets) + 1

		local list = buckets[rate]
		local totalEntities = #list
		if totalEntities == 0 then
			continue
		end

		local rawQuota = math.ceil(totalEntities * rate * dt)
		local workQuota = math.clamp(rawQuota, 1, totalEntities)

		local processed = 0
		local idx = bucketLastProcessedIndex[rate] or 1
		if idx > totalEntities then
			idx = 1
		end

		local budgetCheckCountdown = BUDGET_CHECK

		while processed < workQuota do
			local entity = list[idx]
			local data = entityData[entity] :: Types.EntityData

			-- Strategy
			local pos
			local strategy = data.strategy
			if strategy == STRAT_POS then
				pos = (entity :: BasePart).Position
			elseif strategy == STRAT_WORLD then
				pos = (entity :: Attachment).WorldPosition
			elseif strategy == STRAT_CFRAME then
				pos = (entity :: BasePart).CFrame.Position
			elseif strategy == STRAT_PRIM then
				local prim = (entity :: Model).PrimaryPart
				pos = prim and prim.Position or (entity :: Model):GetPivot().Position
			else
				pos = (entity :: any):GetPivot().Position
			end

			local needsStatic = data.needsStatic
			local needsDynamic = data.needsDynamic

			local shouldCheck = (data.logicVersion ~= logicVersion)
				or (needsDynamic and data.dynamicVersion ~= dynamicVersion)
				or (needsStatic and data.staticVersion ~= staticVersion)

			if not shouldCheck then
				local lp = data.lastPosition
				local dx = pos.X - lp.X
				local dy = pos.Y - lp.Y
				local dz = pos.Z - lp.Z
				if (dx * dx + dy * dy + dz * dz) >= data.precisionSq then
					shouldCheck = true
				end
			end

			if shouldCheck then
				data.lastPosition = pos
				data.dynamicVersion = dynamicVersion
				data.logicVersion = logicVersion
				data.staticVersion = staticVersion

				ctx_linkedObservers = entityToObservers[entity]
				ctx_currentMemberships = data.activeObserverMemberships

				ctx_pos = pos
				ctx_cCount = 0
				ctx_highestWin = -math.huge

				if needsDynamic then
					queryPoint(dynamicTree, pos, queryCallbackDynamic)
				end

				if needsStatic then
					queryPoint(staticTree, pos, queryCallbackStatic)
				end

				local current = data.activeObserverMemberships

				-- Exits
				for observerId, oldZoneId in current do
					local newPri = ctx_candidatePriority[observerId]
					if newPri and newPri >= ctx_highestWin then
						continue
					end

					current[observerId] = nil
					if observerTrackingEntities[observerId] then
						observerTrackingEntities[observerId][entity] = nil
					end

					local cbs = observerExitedCallbacks[observerId]
					if not cbs then
						continue
					end

					local safety = observerSafety[observerId]
					local z = zoneIdToZoneObj[oldZoneId]
					fireCallback(cbs, entity, z, safety)
				end

				-- Entries & Transitions
				for i = 1, ctx_cCount do
					local observerId = ctx_candidateList[i]
					local pri = ctx_candidatePriority[observerId]
					local zoneIdx = ctx_candidateIndex[observerId]

					if pri < ctx_highestWin then
						continue
					end

					local currentZoneId = current[observerId]
					if currentZoneId == zoneIdx then
						continue
					end

					-- Update the tracker.
					current[observerId] = zoneIdx
					local safety = observerSafety[observerId]

					if not currentZoneId then -- New entry
						observerTrackingEntities[observerId][entity] = true

						local cbs = observerEnteredCallbacks[observerId]
						if not cbs then
							continue
						end

						local z = zoneIdToZoneObj[zoneIdx]
						fireCallback(cbs, entity, z, safety)
					else -- Transition
						local cbs = observerTransitionedCallbacks[observerId]
						if not cbs then
							continue
						end

						local newZoneObj = zoneIdToZoneObj[zoneIdx]
						local oldZoneObj = zoneIdToZoneObj[currentZoneId]
						if safety then
							for _, cb in cbs do
								task.spawn(cb, entity, newZoneObj, oldZoneObj)
							end
						else
							for _, cb in cbs do
								cb(entity, newZoneObj, oldZoneObj)
							end
						end
					end
				end

				table.clear(ctx_candidatePriority)
				table.clear(ctx_candidateIndex)
				table.clear(ctx_candidateList)
			end

			idx += 1
			if idx > totalEntities then
				idx = 1
			end
			processed += 1

			-- Global budget check
			budgetCheckCountdown -= 1
			if budgetCheckCountdown == 0 then
				budgetCheckCountdown = BUDGET_CHECK
				if (os.clock() - start) > frameBudget then
					break
				end
			end
		end

		bucketLastProcessedIndex[rate] = idx

		if (os.clock() - start) > frameBudget then
			break
		end
	end
end

function Scheduler.setAutoUpdate(enabled: boolean)
	if enabled then
		if not autoUpdateConnection then
			autoUpdateConnection = RunService.PostSimulation:Connect(Scheduler.update)
		end
	else
		if autoUpdateConnection then
			autoUpdateConnection:Disconnect()
			autoUpdateConnection = nil
		end
	end
end

function Scheduler.setAutoSyncRate(hz: number)
	if hz <= 0 then
		autoSyncRate = 0
	else
		autoSyncRate = hz
	end
end

function Scheduler.setFrameBudget(n: number)
	assert(n > 0, '[QuickZone] frameBudget must be greater than 0')

	frameBudget = n
end

function Scheduler.rebuildTrees()
	if State.pendingDynamicRebuild then
		State.dynamicTree = LinearBVH.build(dynamicCFrames, dynamicHalfSizes)
		State.pendingDynamicRebuild = false
		State.dynamicVersion += 1
	end

	if State.pendingStaticRebuild then
		State.staticTree = LinearBVH.build(staticCFrames, staticHalfSizes)
		State.pendingStaticRebuild = false
		State.staticVersion += 1
	end
end

Scheduler.setAutoUpdate(Config.Scheduler.autoUpdate)

return Scheduler

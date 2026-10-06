--!native
--!optimize 2
--!strict

local RunService = game:GetService('RunService')

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Callbacks = require(script.Parent.Callbacks)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local Log = require(script.Parent.Parent.Utils.Log)
local Memberships = require(script.Parent.Memberships)
local State = require(script.Parent.State)
local ZoneShapes = require(script.Parent.ZoneShapes)
local ZoneChanges = require(script.Parent.ZoneChanges)

local queryPoint = LinearBVH.queryPoint
local touches = ZoneChanges.touches
local containsPoint = ZoneShapes.containsPoint
local fireCallback = Callbacks.fire
local setMembership = Memberships.set
local exitMembership = Memberships.exit
local isSubscribed = Memberships.isSubscribed

local staticSlots = State.staticSlots
local dynamicSlots = State.dynamicSlots
local shapeBoundsMin = State.shapeBoundsMin
local shapeBoundsMax = State.shapeBoundsMax
local shapePositions = State.shapePositions
local treeExact = State.treeExact
local zoneIdToZoneObj = State.zoneIdToZoneObj
local zoneSlotIds = State.zoneSlotIds
local zoneAttachedObservers = State.zoneAttachedObservers
local zoneSoleObserver = State.zoneSoleObserver
local autoSyncZones = State.autoSyncZones

local observerPriorityMap = State.observerPriorityMap
local observerTrackingEntities = State.observerTrackingEntities
local observerEnteredCallbacks = State.observerEnteredCallbacks
local observerTransitionedCallbacks = State.observerTransitionedCallbacks
local observerEnabled = State.observerEnabled
local observerSafety = State.observerSafety
local observerPrecisionSq = State.observerPrecisionSq
local observerUpdateRate = State.observerUpdateRate
local observerStaticCount = State.observerStaticCount
local observerDynamicCount = State.observerDynamicCount

local entityToReference = State.entityToReference
local entityData = State.entityData
local entityToObservers = State.entityToObservers
local entityToGroups = State.entityToGroups
local groupToObservers = State.groupToObservers
local dirtyProfiles = State.dirtyProfiles
local dirtyTopology = State.dirtyTopology

local staticTree = State.staticTree
local dynamicTree = State.dynamicTree
local staticChanges = State.staticChanges
local dynamicChanges = State.dynamicChanges

local ctx_hits = table.create(64) :: { number }
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority = table.create(16) :: { [number]: number }
local ctx_candidateIndex = table.create(16) :: { [number]: number }
local ctx_candidateList = table.create(16) :: { [number]: number }
local ctx_linkedObservers: { [number]: boolean }
local ctx_currentMemberships: { [number]: number }

local frameBudget = Config.Scheduler.frameBudget
local autoSyncRate = Config.Scheduler.autoSyncRate
local autoSyncTimer = 0
local autoUpdateConnection: RBXScriptConnection?

local bucketList = State.bucketList
local buckets = State.buckets
local nextBucketIndex = 1 -- Round-robin pointer
local bucketLastProcessedIndex = {} :: { [number]: number }
local BUDGET_CHECK = 32

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_TRANSFORM = Config.Strategy.TRANSFORM
local STRAT_PIVOT = Config.Strategy.PIVOT

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

			-- If the bucket is now empty, remove it and update the bucket list
			if #oldBucket == 0 then
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
				table.sort(bucketList, function(a: number, b: number)
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

local function processObserverHit(observerId: number, zoneId: number)
	if not ctx_linkedObservers[observerId] or observerEnabled[observerId] == false then
		return
	end

	local currentPriority = ctx_candidatePriority[observerId]
	local priority = observerPriorityMap[observerId] or 0

	if not currentPriority then -- First hit
		ctx_cCount += 1
		ctx_candidateList[ctx_cCount] = observerId
		ctx_candidateIndex[observerId] = zoneId
		ctx_candidatePriority[observerId] = priority

		if priority > ctx_highestWin then
			ctx_highestWin = priority
		end
	elseif priority > currentPriority then -- Override previous hits
		ctx_candidateIndex[observerId] = zoneId
		ctx_candidatePriority[observerId] = priority

		if priority > ctx_highestWin then
			ctx_highestWin = priority
		end
	elseif priority == currentPriority and ctx_currentMemberships[observerId] == zoneId then -- Sticky behavior
		ctx_candidateIndex[observerId] = zoneId
	end
end

local function processZoneHit(slot: number)
	local observers = zoneAttachedObservers[slot]
	if not observers then
		return
	end

	local zoneId = zoneSlotIds[slot]
	for _, observerId in observers do
		processObserverHit(observerId, zoneId)
	end
end

local function queryTree(tree: Types.Tree, position: Vector3)
	local hitCount = queryPoint(tree, position, ctx_hits, 0)
	for i = 1, hitCount do
		local slot = ctx_hits[i]
		local observerId = zoneSoleObserver[slot]

		if observerId then
			if ctx_candidatePriority[observerId] ~= nil then
				-- An observer's zones share a priority, so only the current zone can take over
				if ctx_currentMemberships[observerId] ~= zoneSlotIds[slot] then
					continue
				end
			elseif not ctx_linkedObservers[observerId] then
				continue
			end

			if treeExact[slot] or containsPoint(slot, position) then
				processObserverHit(observerId, zoneSlotIds[slot])
			end
		elseif treeExact[slot] or containsPoint(slot, position) then
			processZoneHit(slot)
		end
	end
end

local Scheduler = {}

local function tick(dt: number)
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

			for slot, zone in autoSyncZones do
				local reference = zone.reference
				if reference then
					ZoneShapes.setCFrame(
						slot,
						if reference:IsA('Attachment') then reference.WorldCFrame else reference.CFrame
					)
				end
			end
		end
	end

	Scheduler.rebuildTrees()

	if (os.clock() - start) > frameBudget then
		return
	end

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
			local position
			local strategy = data.strategy
			if strategy == STRAT_POS then
				position = (entity :: BasePart).Position
			elseif strategy == STRAT_WORLD then
				position = (entity :: Attachment).WorldPosition
			elseif strategy == STRAT_CFRAME then
				position = (entity :: BasePart).CFrame.Position
			elseif strategy == STRAT_TRANSFORM then
				position = (entity :: any).Transform.Position
			elseif strategy == STRAT_PRIM then
				local prim = (entity :: Model).PrimaryPart
				position = prim and prim.Position or (entity :: Model):GetPivot().Position
			elseif strategy == STRAT_PIVOT then
				position = (entity :: any):GetPivot().Position
			end

			local needsStatic = data.needsStatic
			local needsDynamic = data.needsDynamic

			local lastPosition = data.lastPosition
			local shouldCheck = data.logicVersion ~= logicVersion

			if not shouldCheck then
				local dx = position.X - lastPosition.X
				local dy = position.Y - lastPosition.Y
				local dz = position.Z - lastPosition.Z

				shouldCheck = (dx * dx + dy * dy + dz * dz) >= data.precisionSq
			end

			-- Standing still, so only zone changes at either position matter
			if not shouldCheck and needsDynamic and data.dynamicVersion ~= dynamicVersion then
				shouldCheck = touches(dynamicChanges, data.dynamicVersion, dynamicVersion, position, lastPosition)
				if not shouldCheck then
					data.dynamicVersion = dynamicVersion
				end
			end

			if not shouldCheck and needsStatic and data.staticVersion ~= staticVersion then
				shouldCheck = touches(staticChanges, data.staticVersion, staticVersion, position, lastPosition)
				if not shouldCheck then
					data.staticVersion = staticVersion
				end
			end

			if shouldCheck then
				data.lastPosition = position
				data.dynamicVersion = dynamicVersion
				data.logicVersion = logicVersion
				data.staticVersion = staticVersion

				ctx_linkedObservers = entityToObservers[entity]
				ctx_currentMemberships = data.activeObserverMemberships

				ctx_cCount = 0
				ctx_highestWin = -math.huge

				if needsDynamic then
					queryTree(dynamicTree, position)
				end

				if needsStatic then
					queryTree(staticTree, position)
				end

				local current = data.activeObserverMemberships

				-- Exits
				for observerId in current do
					local newPri = ctx_candidatePriority[observerId]
					if newPri and newPri >= ctx_highestWin then
						continue
					end

					exitMembership(observerId, entity, data)
				end

				-- Entries & Transitions
				for i = 1, ctx_cCount do
					local observerId = ctx_candidateList[i]
					local priority = ctx_candidatePriority[observerId]
					local zoneIdx = ctx_candidateIndex[observerId]

					ctx_candidatePriority[observerId] = nil
					ctx_candidateIndex[observerId] = nil
					ctx_candidateList[i] = nil

					if not observerTrackingEntities[observerId] then
						continue
					end

					if priority < ctx_highestWin then
						continue
					end

					-- An earlier callback may have removed the entity or destroyed the zone
					local zone = zoneIdToZoneObj[zoneIdx]
					if entityData[entity] ~= data or not zone then
						continue
					end

					-- Or changed the observer, so the entity is checked again next tick
					local attached = zoneAttachedObservers[zone.slot]
					if
						observerEnabled[observerId] == false
						or not attached
						or not table.find(attached, observerId)
						or not isSubscribed(entity, observerId)
					then
						data.logicVersion = -1
						continue
					end

					local currentZoneId = current[observerId]
					if currentZoneId == zoneIdx then
						continue
					end

					setMembership(observerId, entity, data, zoneIdx)

					-- Entry if it was in none of the observer's zones, transition otherwise
					local reference = entityToReference[entity] or entity
					fireCallback(
						if currentZoneId then observerTransitionedCallbacks else observerEnteredCallbacks,
						observerId,
						reference,
						zone,
						entity,
						observerSafety[observerId]
					)
				end
			end

			-- Callbacks may have removed entities, swapping another into this index
			if list[idx] == entity then
				idx += 1
			end
			totalEntities = #list
			if totalEntities == 0 then
				break
			end
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

-- Set while a tick runs. A callback updating again would clobber the tick in progress,
-- so that update is skipped and its work is left to the next tick
local ticking = false

function Scheduler.update(dt: number)
	if ticking then
		return
	end

	ticking = true
	local ok, trace = xpcall(tick, debug.traceback, dt)
	ticking = false
	if not ok then
		error(trace, 0)
	end
end

function Scheduler.setEnabled(enabled: boolean)
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
	if n <= 0 then
		Log.fatal('frameBudget must be greater than 0.', nil)
	end

	frameBudget = n
end

-- Refit if only shapes changed, rebuild if zones were added or removed or the tree degraded
local function updateTree(tree: Types.Tree, members: { [number]: any })
	if tree.membersChanged or not LinearBVH.refit(tree, shapeBoundsMin, shapeBoundsMax) then
		LinearBVH.build(tree, members, shapeBoundsMin, shapeBoundsMax, shapePositions)
		tree.membersChanged = false
	end
	ZoneShapes.markBuilt(members)
end

function Scheduler.rebuildTrees()
	if State.pendingDynamicRebuild then
		updateTree(dynamicTree, dynamicSlots)
		State.pendingDynamicRebuild = false
	end

	if State.pendingStaticRebuild then
		updateTree(staticTree, staticSlots)
		State.pendingStaticRebuild = false
	end

	-- New version for every tree that changed
	if ZoneChanges.commit(dynamicChanges, State.dynamicVersion + 1, (dynamicTree.count + 1) // 2) then
		State.dynamicVersion += 1
	end

	if ZoneChanges.commit(staticChanges, State.staticVersion + 1, (staticTree.count + 1) // 2) then
		State.staticVersion += 1
	end

	-- Released slots are safe to reuse
	local released = State.releasedZoneSlots
	local releasedCount = #released
	if releasedCount > 0 then
		local free = State.freeZoneSlots
		table.move(released, 1, releasedCount, #free + 1, free)
		table.clear(released)
	end
end

Scheduler.setEnabled(Config.Scheduler.enabled)

return Scheduler

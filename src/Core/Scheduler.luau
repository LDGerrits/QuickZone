--!native
--!optimize 2
--!strict

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local Log = require(ReplicatedStorage.QuickZone.Utils.Log)
local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Geometry = require(script.Parent.Parent.Utils.Geometry)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local State = require(script.Parent.State)

local queryPoint = LinearBVH.queryPoint
local queryBox = LinearBVH.queryBox
local isPointInShape = Geometry.isPointInShape
local getObjectBounds = Geometry.getObjectBounds
local isBoxInShape = Geometry.isBoxInShape

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

local entityToReference = State.entityToReference
local entityData = State.entityData
local entityToObservers = State.entityToObservers
local entityToGroups = State.entityToGroups
local groupToObservers = State.groupToObservers
local dirtyProfiles = State.dirtyProfiles
local dirtyTopology = State.dirtyTopology

local staticTree = State.staticTree
local dynamicTree = State.dynamicTree

local ctx_pos: Vector3
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)
local ctx_linkedObservers: { [number]: boolean }
local ctx_currentMemberships: { [number]: number }
local ctx_boxCFrame: CFrame
local ctx_boxHalfSize: Vector3

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
	local hasVolume = false

	-- Find the highest settings across all subscribed observers
	for groupId, _ in groups do
		local group = State.groups[groupId]
		if group and group.hasVolume then
			hasVolume = true
		end

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

	if hasVolume then
		local ref = entityToReference[entity] or entity

		if typeof(ref) == 'Instance' and ref:IsA('Player') then
			-- TODO This needs to be done more intelligently
			data.halfSize = Vector3.new(1, 2.5, 0.5)
			data.pivotOffset = CFrame.new(0, 0.5, 0)
		elseif typeof(entity) == 'Instance' then
			if entity:IsA('BasePart') then
				data.halfSize = entity.Size * 0.5
				data.pivotOffset = nil
			elseif entity:IsA('Model') then
				local boundsCF, boundsSize = entity:GetBoundingBox()
				local pivotCF = entity:GetPivot()
				data.halfSize = boundsSize * 0.5
				data.pivotOffset = pivotCF:ToObjectSpace(boundsCF)
			else
				data.halfSize = nil
				data.pivotOffset = nil
			end
		elseif typeof(entity) == 'table' then
			local entityTable = entity :: Types.EntityTable
			if entityTable.Size then
				data.halfSize = entityTable.Size * 0.5
				data.pivotOffset = nil
			else
				data.halfSize = nil
				data.pivotOffset = nil
			end
		end
	else
		data.halfSize = nil
		data.pivotOffset = nil
	end

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
		if ctx_linkedObservers[observerId] and observerEnabled[observerId] ~= false then
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
	end
end

local function queryPointCallbackStatic(zoneId: number)
	if isPointInShape(ctx_pos, staticCFrames[zoneId], staticHalfSizes[zoneId], staticTypes[zoneId]) then
		processZoneHit(zoneId)
	end
end

local function queryPointCallbackDynamic(zoneId: number)
	if isPointInShape(ctx_pos, dynamicCFrames[zoneId], dynamicHalfSizes[zoneId], dynamicTypes[zoneId]) then
		processZoneHit(zoneId)
	end
end

local function queryBoxCallbackStatic(zoneId: number)
	if
		isBoxInShape(
			ctx_boxCFrame,
			ctx_boxHalfSize,
			staticCFrames[zoneId],
			staticHalfSizes[zoneId],
			staticTypes[zoneId]
		)
	then
		processZoneHit(zoneId)
	end
end

local function queryBoxCallbackDynamic(zoneId: number)
	if
		isBoxInShape(
			ctx_boxCFrame,
			ctx_boxHalfSize,
			dynamicCFrames[zoneId],
			dynamicHalfSizes[zoneId],
			dynamicTypes[zoneId]
		)
	then
		processZoneHit(zoneId)
	end
end

local function fireCallback(
	callbacks: { (Types.Entity, Types.Zone) -> () },
	entity: any,
	zone: Types.Zone,
	safety: boolean
)
	if safety then
		for _, callback in callbacks do
			task.spawn(callback, entity, zone)
		end
	else
		for _, callback in callbacks do
			callback(entity, zone)
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

			local strategy = data.strategy
			local halfSize = data.halfSize

			local position: Vector3
			local cframe: CFrame?

			if halfSize then -- volume
				if strategy == STRAT_POS or strategy == STRAT_CFRAME then
					local rawCF = (entity :: any).CFrame
					cframe = rawCF or CFrame.new((entity :: any).Position)
				elseif strategy == STRAT_WORLD then
					local rawCF = (entity :: any).WorldCFrame
					cframe = rawCF or CFrame.new((entity :: any).WorldPosition)
				elseif strategy == STRAT_TRANSFORM then
					cframe = (entity :: any).Transform
				elseif strategy == STRAT_PRIM then
					local prim = (entity :: any).PrimaryPart
					cframe = prim and prim.CFrame or (entity :: any):GetPivot()
				elseif strategy == STRAT_PIVOT then
					cframe = (entity :: any):GetPivot()
				end

				local offset = data.pivotOffset
				if offset then
					cframe = (cframe :: CFrame) * offset
				end

				position = (cframe :: CFrame).Position
			else -- point
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
			end

			local needsStatic = data.needsStatic
			local needsDynamic = data.needsDynamic

			local shouldCheck = (data.logicVersion ~= logicVersion)
				or (needsDynamic and data.dynamicVersion ~= dynamicVersion)
				or (needsStatic and data.staticVersion ~= staticVersion)

			if not shouldCheck then
				local lastPosition = data.lastPosition
				local dx = position.X - lastPosition.X
				local dy = position.Y - lastPosition.Y
				local dz = position.Z - lastPosition.Z
				if (dx * dx + dy * dy + dz * dz) >= data.precisionSq then
					shouldCheck = true
				end
			end

			if shouldCheck then
				data.lastPosition = position
				data.dynamicVersion = dynamicVersion
				data.logicVersion = logicVersion
				data.staticVersion = staticVersion

				ctx_linkedObservers = entityToObservers[entity]
				ctx_currentMemberships = data.activeObserverMemberships

				ctx_pos = position
				ctx_cCount = 0
				ctx_highestWin = -math.huge

				if halfSize and cframe then -- volume
					ctx_boxCFrame = cframe
					ctx_boxHalfSize = halfSize
					local bMin, bMax = getObjectBounds(cframe, halfSize)

					if needsDynamic then
						queryBox(dynamicTree, bMin, bMax, queryBoxCallbackDynamic)
					end
					if needsStatic then
						queryBox(staticTree, bMin, bMax, queryBoxCallbackStatic)
					end
				else -- point
					if needsDynamic then
						queryPoint(dynamicTree, position, queryPointCallbackDynamic)
					end
					if needsStatic then
						queryPoint(staticTree, position, queryPointCallbackStatic)
					end
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
					local zone = zoneIdToZoneObj[oldZoneId]
					local reference = entityToReference[entity] or entity
					fireCallback(cbs, reference, zone, safety)
				end

				-- Entries & Transitions
				for i = 1, ctx_cCount do
					local observerId = ctx_candidateList[i]
					local priority = ctx_candidatePriority[observerId]
					local zoneIdx = ctx_candidateIndex[observerId]

					ctx_candidatePriority[observerId] = nil
					ctx_candidateIndex[observerId] = nil
					ctx_candidateList[i] = nil

					if priority < ctx_highestWin then
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

						local zone = zoneIdToZoneObj[zoneIdx]
						local reference = entityToReference[entity] or entity
						fireCallback(cbs, reference, zone, safety)
					else -- Transition
						local cbs = observerTransitionedCallbacks[observerId]
						if not cbs then
							continue
						end

						local zone = zoneIdToZoneObj[zoneIdx]
						local reference = entityToReference[entity] or entity
						fireCallback(cbs, reference, zone, safety)
					end
				end
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
	if n <= 0 then
		Log.fatal('frameBudget must be greater than 0.', nil)
	end

	frameBudget = n
end

function Scheduler.rebuildTrees()
	if State.pendingDynamicRebuild then
		LinearBVH.build(dynamicTree, dynamicCFrames, dynamicHalfSizes)
		State.pendingDynamicRebuild = false
		State.dynamicVersion += 1
	end

	if State.pendingStaticRebuild then
		LinearBVH.build(staticTree, staticCFrames, staticHalfSizes)
		State.pendingStaticRebuild = false
		State.staticVersion += 1
	end
end

Scheduler.setAutoUpdate(Config.Scheduler.autoUpdate)

return Scheduler

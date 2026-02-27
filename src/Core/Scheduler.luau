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

local zoneAttachedObservers = State.zoneAttachedObservers
local observerPriorityMap = State.observerPriorityMap
local observerTrackingEntities = State.observerTrackingEntities
local observerEnteredCallbacks = State.observerEnteredCallbacks
local observerExitedCallbacks = State.observerExitedCallbacks
local observerTransitionedCallbacks = State.observerTransitionedCallbacks
local observerEnabled = State.observerEnabled
local observerSafety = State.observerSafety
local zoneIdToZoneObj = State.zoneIdToZoneObj
local bucketList = State.bucketList
local entityData = State.entityData
local entityToObservers = State.entityToObservers
local autoSyncZones = State.autoSyncZones

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes

local ctx_pos: Vector3
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)
local ctx_linkedObservers: { [number]: boolean }
local ctx_currentMemberships: { [number]: number }

local frameBudget = Config.Scheduler.frameBudget
local nextBucketIndex = 1 -- Round-robin pointer
local bucketLastProcessedIndex = {} :: { [number]: number }

local autoUpdateConnection: RBXScriptConnection?
local autoSyncToPartRate = Config.Scheduler.autoSyncToPartRate
local autoSyncToPartTimer = 0

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME

local BUDGET_CHECK = 32
local AUTO_SYNC_TO_PART_PRECISION = 0.1 ^ 2

local function processAutoSyncToPart(dt: number)
	local shouldSync = false

	if autoSyncToPartRate > 0 then
		local syncInterval = 1 / autoSyncToPartRate
		autoSyncToPartTimer += dt
		if autoSyncToPartTimer >= syncInterval then
			autoSyncToPartTimer = 0
			shouldSync = true
		end
	else
		shouldSync = true
	end

	if not shouldSync then
		return
	end

	for id, zone in autoSyncZones do
		local part = zone.part
		if not part then
			continue
		end

		local newCF = part.CFrame
		local oldCF = dynamicCFrames[id]

		if oldCF == newCF then
			continue
		end

		local p1, p2 = oldCF.Position, newCF.Position
		local dx, dy, dz = p2.X - p1.X, p2.Y - p1.Y, p2.Z - p1.Z
		if (dx * dx + dy * dy + dz * dz) > AUTO_SYNC_TO_PART_PRECISION or oldCF.Rotation ~= newCF.Rotation then
			dynamicCFrames[id] = newCF
			State.pendingDynamicRebuild = true
		end
	end
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
	if not callbacks then
		return
	end

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

	processAutoSyncToPart(dt)
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

	local spatialVersion = State.spatialVersion

	-- Round-robin scheduling to prevent starvation
	for _ = 1, numBuckets do
		local rate = bucketList[nextBucketIndex]
		nextBucketIndex = (nextBucketIndex % numBuckets) + 1

		local list = State.buckets[rate]
		local totalEntities = #list
		if totalEntities == 0 then
			continue
		end

		local workQuota = math.ceil(totalEntities * rate * dt)
		if workQuota < 1 then
			workQuota = 1
		end
		if workQuota > totalEntities then
			workQuota = totalEntities
		end

		local processed = 0
		local idx = bucketLastProcessedIndex[rate] or 1
		if idx > totalEntities then
			idx = 1
		end

		local budgetCheckCountdown = BUDGET_CHECK

		while processed < workQuota do
			local entity = list[idx]
			local data = entityData[entity] :: Types.EntityData?

			-- Race condition guard
			if not data then
				idx += 1
				if idx > totalEntities then
					idx = 1
				end
				processed += 1
				continue
			end

			-- Strategy
			local pos
			local strategy = data.strategy
			if strategy == STRAT_POS then
				pos = (entity :: BasePart).Position
			elseif strategy == STRAT_WORLD then
				pos = (entity :: Attachment).WorldPosition
			elseif strategy == STRAT_CFRAME then
				pos = (entity :: BasePart).CFrame.Position
			elseif strategy == STRAT_PRIM and (entity :: Model).PrimaryPart then
				pos = ((entity :: Model).PrimaryPart :: BasePart).Position
			else
				pos = (entity :: any):GetPivot().Position
			end

			-- Threshold
			local shouldCheck = data.lastSpatialVersion ~= spatialVersion

			if not shouldCheck then
				local lp = data.lastPosition
				local dx, dy, dz = pos.X - lp.X, pos.Y - lp.Y, pos.Z - lp.Z
				if (dx * dx + dy * dy + dz * dz) >= data.precisionSq then
					shouldCheck = true
				end
			end

			if shouldCheck then
				data.lastPosition = pos
				data.lastSpatialVersion = spatialVersion

				ctx_linkedObservers = entityToObservers[entity]
				ctx_currentMemberships = data.activeObserverMemberships

				ctx_pos = pos
				ctx_cCount = 0
				ctx_highestWin = -math.huge

				queryPoint(dynamicTree, pos, queryCallbackDynamic)
				queryPoint(staticTree, pos, queryCallbackStatic)

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

					ctx_candidatePriority[observerId] = nil
					ctx_candidateIndex[observerId] = nil
					ctx_candidateList[i] = nil

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

function Scheduler.setFrameBudget(n: number)
	assert(n > 0, '[QuickZone] frameBudget must be greater than 0')

	frameBudget = n
end

function Scheduler.rebuildTrees()
	if State.pendingDynamicRebuild then
		State.dynamicTree = LinearBVH.build(State.dynamicCFrames, State.dynamicHalfSizes)
		State.pendingDynamicRebuild = false
		State.spatialVersion += 1
	end

	if State.pendingStaticRebuild then
		State.staticTree = LinearBVH.build(State.staticCFrames, State.staticHalfSizes)
		State.pendingStaticRebuild = false
		State.spatialVersion += 1
	end
end

function Scheduler.setAutoSyncToPartRate(hz: number)
	if hz <= 0 then
		autoSyncToPartRate = 0
	else
		autoSyncToPartRate = hz
	end
end

Scheduler.setAutoUpdate(Config.Scheduler.autoUpdate)

return Scheduler

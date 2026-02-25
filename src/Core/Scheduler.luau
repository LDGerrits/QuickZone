--!native
--!strict

local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.Parent.State)
local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local queryPoint = LinearBVH.queryPoint
local isPointInZone = Geometry.isPointInZone

local zoneAttachedObservers = State.zoneAttachedObservers
local observerPriorityMap = State.observerPriorityMap
local observerEnteredCallbacks = State.observerEnteredCallbacks
local observerTrackingEntities = State.observerTrackingEntities
local observerExitedCallbacks = State.observerExitedCallbacks
local observerEnabled = State.observerEnabled
local observerSafety = State.observerSafety
local zoneIdToZoneObj = State.zoneIdToZoneObj
local bucketList = State.bucketList
local entityData = State.entityData
local entityToObservers = State.entityToObservers

local ctx_pos: Vector3
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)
local ctx_linkedObservers: { [number]: boolean }

local frameBudget = Config.Scheduler.frameBudget
local nextBucketIndex = 1 -- Round-robin pointer
local bucketLastProcessedIndex = {} :: { [number]: number }

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME

local BUDGET_CHECK = 32

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
			ctx_cCount += 1
			ctx_candidateList[ctx_cCount] = observerId
			ctx_candidateIndex[observerId] = zoneId
			ctx_candidatePriority[observerId] = pri

			if pri > ctx_highestWin then
				ctx_highestWin = pri
			end
		end
	end
end

local function queryCallbackStatic(zoneId: number)
	if isPointInZone(ctx_pos, zoneId, false) then
		processZoneHit(zoneId)
	end
end

local function queryCallbackDynamic(zoneId: number)
	if isPointInZone(ctx_pos, zoneId, true) then
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

RunService.PostSimulation:Connect(function(dt: number)
	debug.profilebegin('QuickZone_Scheduler')
	local start = os.clock()

	if State.pendingDynamicRebuild then
		State.dynamicRootNode = LinearBVH.build(State.dynamicCFrames, State.dynamicHalfSizes)
		State.pendingDynamicRebuild = false
		State.spatialVersion += 1
	end

	if State.pendingStaticRebuild then
		State.staticRootNode = LinearBVH.build(State.staticCFrames, State.staticHalfSizes)
		State.pendingStaticRebuild = false
		State.spatialVersion += 1
	end

	if (os.clock() - start) > frameBudget then
		debug.profileend()
		return
	end

	local staticRoot = State.staticRootNode
	local dynamicRoot = State.dynamicRootNode

	if not staticRoot and not dynamicRoot then
		debug.profileend()
		return
	end

	local numBuckets = #bucketList
	if numBuckets == 0 then
		debug.profileend()
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

				ctx_pos = pos
				ctx_cCount = 0
				ctx_highestWin = -math.huge

				if dynamicRoot then
					queryPoint(dynamicRoot, pos, queryCallbackDynamic)
				end

				if staticRoot then
					queryPoint(staticRoot, pos, queryCallbackStatic)
				end

				local current = data.activeObserverMemberships

				-- Exits
				for observerId, oldZoneId in current do
					local newPri = ctx_candidatePriority[observerId]
					if not newPri or newPri < ctx_highestWin then
						current[observerId] = nil
						if observerTrackingEntities[observerId] then
							observerTrackingEntities[observerId][entity] = nil
						end

						local cbs = observerExitedCallbacks[observerId]
						if cbs then
							local safety = observerSafety[observerId]
							local z = zoneIdToZoneObj[oldZoneId]
							fireCallback(cbs, entity, z, safety)
						end
					end
				end

				-- Entries
				for i = 1, ctx_cCount do
					local observerId = ctx_candidateList[i]
					local pri = ctx_candidatePriority[observerId]
					if pri >= ctx_highestWin and not current[observerId] then
						local zoneIdx = ctx_candidateIndex[observerId]
						current[observerId] = zoneIdx
						observerTrackingEntities[observerId][entity] = true
						local cbs = observerEnteredCallbacks[observerId]
						if cbs then
							local safety = observerSafety[observerId]
							local z = zoneIdToZoneObj[zoneIdx]
							fireCallback(cbs, entity, z, safety)
						end
					end
					ctx_candidatePriority[observerId] = nil
					ctx_candidateIndex[observerId] = nil
					ctx_candidateList[i] = nil
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

	debug.profileend()
end)

local Scheduler = {}

function Scheduler.setFrameBudget(n: number)
	assert(n > 0, '[QuickZone] frameBudget must be greater than 0')

	frameBudget = n
end

return Scheduler

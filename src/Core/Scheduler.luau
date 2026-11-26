--!native
--!optimize 2
--!strict

local RunService = game:GetService('RunService')

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Callbacks = require(script.Parent.Callbacks)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local Log = require(script.Parent.Parent.Utils.Log)
local Links = require(script.Parent.Links)
local Memberships = require(script.Parent.Memberships)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local Routing = require(script.Parent.Routing)
local ZoneChanges = require(script.Parent.ZoneChanges)
local ZoneShapes = require(script.Parent.ZoneShapes)

local queryPoint = LinearBVH.queryPoint
local touches = ZoneChanges.touches
local touchesBox = ZoneChanges.touchesBox
local clearRadiusAt = ZoneShapes.clearRadius
local containsPoint = ZoneShapes.containsPoint
local fireCallback = Callbacks.fire
local moveMembership = Memberships.move
local exitMembership = Memberships.exit
local isSubscribed = Memberships.isSubscribed

local treeExact = ZoneShapes.treeExact
local shapeBoundsMin = ZoneShapes.shapeBoundsMin
local shapeBoundsMax = ZoneShapes.shapeBoundsMax
local shapePositions = ZoneShapes.shapePositions
local shapeFilledHalfSizes = ZoneShapes.shapeFilledHalfSizes
local firstLeaf = LinearBVH.firstLeaf
local zoneIdToZoneObj = Registry.zoneIdToZoneObj
local zoneSlotIds = ZoneShapes.zoneSlotIds
local slotObservers = Links.slotObservers
local slotSoleObserver = Links.slotSoleObserver
local autoSyncZones = Registry.autoSyncZones

local observers = Registry.observers

local entityToReference = References.entityToReference
local dirtyProfiles = Routing.dirtyProfiles

local staticTree = ZoneShapes.staticTree
local recentTree = ZoneShapes.recentTree
local dynamicTree = ZoneShapes.dynamicTree
local staticChanges = ZoneShapes.staticChanges
local dynamicChanges = ZoneShapes.dynamicChanges

local ctx_hits = table.create(64) :: { number }
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority = table.create(16) :: { [number]: number }
local ctx_candidateIndex = table.create(16) :: { [number]: number }
local ctx_candidateList = table.create(16) :: { [number]: number }
local ctx_linkedObservers: { [number]: true }
local ctx_currentMemberships: { [number]: number }
local ctx_checkingRate: number? = nil
local ctx_checkingIndex = 0

local frameBudgetSeconds = Config.Scheduler.frameBudgetSeconds
local autoSyncRate = Config.Scheduler.autoSyncRate
local autoSyncTimer = 0
local autoUpdateConnection: RBXScriptConnection?

local bucketList = Routing.bucketList
local buckets = Routing.buckets
local bucketData = Routing.bucketData
local nextBucketIndex = 1
local bucketLastProcessedIndex = {} :: { [number]: number }
local BUDGET_CHECK = 32
local NOWHERE = Vector3.new(0 / 0, 0 / 0, 0 / 0)

local UNCHECKED_VERSION = -1

-- After a check, an entity that moved less than CLEAR_AFTER_MOVE on every axis since its previous check gets a cube
-- of up to MAX_CLEAR_RADIUS studs around it in which no zone can change its answer. Its checks are skipped while it
-- stays inside, until a zone change reaches the cube.
local MAX_CLEAR_RADIUS = 32
local CLEAR_AFTER_MOVE = 8

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_TRANSFORM = Config.Strategy.TRANSFORM
local STRAT_PIVOT = Config.Strategy.PIVOT

local Scheduler = {}

local function processObserverHit(observerId: number, zoneId: number)
	if not ctx_linkedObservers[observerId] then
		return
	end
	local observer = observers[observerId]
	if not observer or not observer.enabled then
		return
	end

	if ctx_candidatePriority[observerId] == nil then
		local priority = observer.priority
		ctx_cCount += 1
		ctx_candidateList[ctx_cCount] = observerId
		ctx_candidateIndex[observerId] = zoneId
		ctx_candidatePriority[observerId] = priority

		if priority > ctx_highestWin then
			ctx_highestWin = priority
		end
	elseif ctx_currentMemberships[observerId] == zoneId then
		ctx_candidateIndex[observerId] = zoneId
	end
end

local function processZoneHit(slot: number)
	local attached = slotObservers[slot]
	if not attached then
		return
	end

	local zoneId = zoneSlotIds[slot]
	for _, observerId in attached do
		processObserverHit(observerId, zoneId)
	end
end

local function queryTree(tree: Types.Tree, position: Vector3)
	local hitCount = queryPoint(tree, position, ctx_hits, 0)
	for i = 1, hitCount do
		local slot = ctx_hits[i]
		local observerId = slotSoleObserver[slot]

		if observerId then
			if ctx_candidatePriority[observerId] ~= nil then
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

local ctx_soleObserverId = 0

local function isAttachedTo(slot: number, observerId: number): boolean
	local sole = slotSoleObserver[slot]
	if sole then
		return sole == observerId
	end
	local attached = slotObservers[slot]
	return attached ~= nil and table.find(attached, observerId) ~= nil
end

local function acceptsSoleHit(slot: number, position: Vector3): boolean
	return isAttachedTo(slot, ctx_soleObserverId) and (treeExact[slot] or containsPoint(slot, position))
end

-- Whether the zone still holds the position, as a tree query would find it
local function stillHolds(zoneId: number, observerId: number, position: Vector3): boolean
	local zone = zoneIdToZoneObj[zoneId]
	if not zone then
		return false
	end
	local slot = zone.slot
	if zoneSlotIds[slot] ~= zoneId or not isAttachedTo(slot, observerId) then
		return false
	elseif treeExact[slot] then
		-- ZoneShapes keeps a box only where it isn't the position plus and minus the half size
		local min, max = shapeBoundsMin[slot], shapeBoundsMax[slot]
		if not min then
			local center, halfSize = shapePositions[slot], shapeFilledHalfSizes[slot]
			min, max = center - halfSize, center + halfSize
		end
		return vector.max(min, position) == position and vector.min(max, position) == position
	end
	return containsPoint(slot, position)
end

local function dropBucketProgress(rate: number)
	bucketLastProcessedIndex[rate] = nil
end

local function runTick(dt: number)
	local start = os.clock()

	Routing.settle(dropBucketProgress)

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

	ZoneShapes.rebuildTrees()

	local numBuckets = #bucketList
	if numBuckets == 0 then
		return
	end

	if nextBucketIndex > numBuckets then
		nextBucketIndex = 1
	end

	local dynamicVersion = ZoneShapes.dynamicVersion
	local staticVersion = ZoneShapes.staticVersion
	local logicVersion = Routing.logicVersion

	for _ = 1, numBuckets do
		local rate = bucketList[nextBucketIndex]
		nextBucketIndex = (nextBucketIndex % numBuckets) + 1

		local list = buckets[rate]
		local dataList = bucketData[rate]
		local totalEntities = #list
		if totalEntities == 0 then
			continue
		end

		-- At least one, also when an infinite rate and zero dt make the quota NaN
		local rawQuota = math.ceil(totalEntities * rate * dt)
		local workQuota = if rawQuota >= totalEntities then totalEntities elseif rawQuota >= 1 then rawQuota else 1

		local processed = 0
		local idx = bucketLastProcessedIndex[rate] or 1
		if idx > totalEntities then
			idx = 1
		end

		local budgetCheckCountdown = BUDGET_CHECK
		ctx_checkingRate = rate

		while processed < workQuota do
			ctx_checkingIndex = idx
			local entity = list[idx]
			local data = dataList[idx]

			local position
			local strategy = data.strategy
			if strategy == STRAT_POS then
				position = (entity :: BasePart).Position
			elseif strategy == STRAT_WORLD then
				position = (entity :: Attachment).WorldPosition
			elseif strategy == STRAT_CFRAME then
				local cframe = (entity :: BasePart).CFrame
				position = cframe and cframe.Position
			elseif strategy == STRAT_TRANSFORM then
				local transform = (entity :: any).Transform
				position = transform and transform.Position
			elseif strategy == STRAT_PRIM then
				local prim = (entity :: Model).PrimaryPart
				position = prim and prim.Position or (entity :: Model):GetPivot().Position
			elseif strategy == STRAT_PIVOT then
				position = (entity :: any):GetPivot().Position
			end
			if not position then
				position = NOWHERE
			end

			local needsStatic = data.needsStatic
			local needsDynamic = data.needsDynamic

			local lastPosition = data.lastPosition
			local shouldCheck = data.logicVersion ~= logicVersion
			local inClear = false

			if not shouldCheck then
				local clearRadius = data.clearRadius
				if clearRadius > 0 then
					-- False for a NaN position, which then counts as moved below
					local offset = vector.abs(position - data.clearCenter)
					if offset.X < clearRadius and offset.Y < clearRadius and offset.Z < clearRadius then
						inClear = true
					else
						data.clearRadius = 0
					end
				end

				if not inClear then
					local dx = position.X - lastPosition.X
					local dy = position.Y - lastPosition.Y
					local dz = position.Z - lastPosition.Z

					-- A NaN position counts as moved, so the entity leaves its zone instead of keeping it forever
					shouldCheck = not ((dx * dx + dy * dy + dz * dz) < data.precisionSq)
				end
			end

			if not shouldCheck and needsDynamic and data.dynamicVersion ~= dynamicVersion then
				if inClear then
					local center, extent = data.clearCenter, vector.one * data.clearRadius
					shouldCheck = touchesBox(
						dynamicChanges,
						data.dynamicVersion,
						dynamicVersion,
						center - extent,
						center + extent
					)
				else
					shouldCheck = touches(dynamicChanges, data.dynamicVersion, dynamicVersion, position, lastPosition)
				end
				if not shouldCheck then
					data.dynamicVersion = dynamicVersion
				end
			end

			if not shouldCheck and needsStatic and data.staticVersion ~= staticVersion then
				if inClear then
					local center, extent = data.clearCenter, vector.one * data.clearRadius
					shouldCheck =
						touchesBox(staticChanges, data.staticVersion, staticVersion, center - extent, center + extent)
				else
					shouldCheck = touches(staticChanges, data.staticVersion, staticVersion, position, lastPosition)
				end
				if not shouldCheck then
					data.staticVersion = staticVersion
				end
			end

			if shouldCheck and Routing.profilesDirty and dirtyProfiles[entity] then
				data.logicVersion = UNCHECKED_VERSION
				data.clearRadius = 0
				shouldCheck = false
			elseif inClear and not shouldCheck then
				data.lastPosition = position
			end

			if shouldCheck then
				local moved = vector.abs(position - lastPosition)
				data.lastPosition = position
				data.dynamicVersion = dynamicVersion
				data.logicVersion = logicVersion
				data.staticVersion = staticVersion

				local current = data.activeObserverMemberships
				local soleObserverId = data.soleObserver

				if soleObserverId then
					local observer = observers[soleObserverId]
					local currentZoneId = current[soleObserverId]
					local zoneIdx = nil
					if observer and observer.enabled then
						-- The entity keeps its zone while that zone holds it, else takes the first one that does,
						-- dynamic zones first
						if currentZoneId and stillHolds(currentZoneId, soleObserverId, position) then
							zoneIdx = currentZoneId
						else
							ctx_soleObserverId = soleObserverId
							local slot = if needsDynamic then firstLeaf(dynamicTree, position, acceptsSoleHit) else nil
							if not slot and needsStatic then
								slot = firstLeaf(staticTree, position, acceptsSoleHit)
								if not slot and recentTree.count > 0 then
									slot = firstLeaf(recentTree, position, acceptsSoleHit)
								end
							end
							if slot then
								zoneIdx = zoneSlotIds[slot]
							end
						end
					end

					if zoneIdx == nil then
						if currentZoneId then
							exitMembership(soleObserverId, entity, data)
						end
					elseif zoneIdx ~= currentZoneId then
						-- No callback ran since this entity's check began, so the observer is still enabled and
						-- attached to the zone (both checked above), and the entity's links are unchanged
						local zone = zoneIdToZoneObj[zoneIdx]
						if zone then
							local soleObserver = observer :: Types.InternalObserver
							moveMembership(soleObserverId, entity, data, zoneIdx)
							fireCallback(
								if currentZoneId
									then soleObserver.transitionedCallbacks
									else soleObserver.enteredCallbacks,
								soleObserverId,
								References.linked and entityToReference[entity] or entity,
								zone,
								entity,
								soleObserver.safety,
								zoneIdx
							)
						end
					end
				else
					ctx_linkedObservers = data.linkedObservers :: { [number]: true }
					ctx_currentMemberships = current

					ctx_cCount = 0
					ctx_highestWin = -math.huge

					if needsDynamic then
						queryTree(dynamicTree, position)
					end

					if needsStatic then
						queryTree(staticTree, position)
						if recentTree.count > 0 then
							queryTree(recentTree, position)
						end
					end

					for observerId in current do
						local newPri = ctx_candidatePriority[observerId]
						if newPri and newPri >= ctx_highestWin then
							continue
						end

						exitMembership(observerId, entity, data)
					end

					for i = 1, ctx_cCount do
						local observerId = ctx_candidateList[i]
						local priority = ctx_candidatePriority[observerId]
						local zoneIdx = ctx_candidateIndex[observerId]

						ctx_candidatePriority[observerId] = nil
						ctx_candidateIndex[observerId] = nil
						ctx_candidateList[i] = nil

						local observer = observers[observerId]
						if not observer then
							continue
						end

						if priority < ctx_highestWin then
							continue
						end

						local currentZoneId = current[observerId]
						if currentZoneId == zoneIdx then
							continue
						end

						local zone = zoneIdToZoneObj[zoneIdx]
						if data.dropped or not zone then
							continue
						end

						local attached = slotObservers[zone.slot]
						if
							not observer.enabled
							or not attached
							or not table.find(attached, observerId)
							or (
								Routing.profilesDirty
								and dirtyProfiles[entity]
								and not isSubscribed(entity, observerId)
							)
						then
							data.logicVersion = UNCHECKED_VERSION
							continue
						end

						moveMembership(observerId, entity, data, zoneIdx)

						local reference = entityToReference[entity] or entity
						fireCallback(
							if currentZoneId then observer.transitionedCallbacks else observer.enteredCallbacks,
							observerId,
							reference,
							zone,
							entity,
							observer.safety,
							zoneIdx
						)
					end
				end
				if Routing.profilesDirty and dirtyProfiles[entity] then
					data.logicVersion = UNCHECKED_VERSION
					data.clearRadius = 0
				elseif
					moved.X < CLEAR_AFTER_MOVE
					and moved.Y < CLEAR_AFTER_MOVE
					and moved.Z < CLEAR_AFTER_MOVE
					-- When every dynamic zone moves, the next tick undoes any clear cube near one
					and not (needsDynamic and ZoneShapes.dynamicChurn)
				then
					data.clearRadius = clearRadiusAt(position, MAX_CLEAR_RADIUS, needsStatic, needsDynamic)
					data.clearCenter = position
				else
					data.clearRadius = 0
				end
			end

			-- A callback that removed the entity swapped the bucket's last entity into idx
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

			budgetCheckCountdown -= 1
			if budgetCheckCountdown == 0 then
				budgetCheckCountdown = BUDGET_CHECK
				if (os.clock() - start) > frameBudgetSeconds then
					break
				end
			end
		end

		bucketLastProcessedIndex[rate] = idx
		ctx_checkingRate = nil

		if (os.clock() - start) > frameBudgetSeconds then
			break
		end
	end
end

local function recoverFromError()
	ctx_cCount = 0
	table.clear(ctx_candidateList)
	table.clear(ctx_candidatePriority)
	table.clear(ctx_candidateIndex)

	if ctx_checkingRate then
		bucketLastProcessedIndex[ctx_checkingRate] = ctx_checkingIndex + 1
		ctx_checkingRate = nil
	end
end

local tickThread: thread? = nil
local tickCallbackDepth = 0
local warnedYield = false

function Scheduler.update(dt: number?)
	-- A tick whose thread was killed, by a script timeout or task.cancel, never comes back to clear tickThread
	if tickThread and coroutine.status(tickThread) == 'dead' then
		tickThread = nil
		warnedYield = false
		recoverFromError()
		Callbacks.restoreDepth(tickCallbackDepth)
	end

	if tickThread then
		if not warnedYield and coroutine.status(tickThread) == 'suspended' then
			warnedYield = true
			Log.warn(
				'An unsafe callback (safety = false) yielded, so QuickZone waits for it to resume before it '
					.. 'updates again. Unsafe callbacks must not yield.',
				nil
			)
		end
		return
	end

	local step = if type(dt) == 'number' and dt >= 0 then dt else 0

	tickThread = coroutine.running()
	tickCallbackDepth = Callbacks.depth()
	-- Cast, as xpcall's type gives the handler's result no place in its returns
	local ok, trace = xpcall(runTick :: any, debug.traceback :: any, step)
	tickThread = nil
	warnedYield = false
	if not ok then
		recoverFromError()
		error(trace, 0)
	end
end

function Scheduler.setEnabled(enabled: boolean)
	if enabled and not autoUpdateConnection then
		autoUpdateConnection = RunService.PostSimulation:Connect(Scheduler.update)
	elseif not enabled and autoUpdateConnection then
		autoUpdateConnection:Disconnect()
		autoUpdateConnection = nil
	end
end

function Scheduler.checkAutoSyncRate(hz: any)
	if type(hz) ~= 'number' or hz ~= hz then
		Log.fatal('autoSyncRate must be a number, got %s. Use 0 to stop auto-syncing.', nil, tostring(hz))
	end
end

function Scheduler.setAutoSyncRate(hz: number)
	Scheduler.checkAutoSyncRate(hz)
	autoSyncRate = if hz > 0 then hz else 0
end

function Scheduler.checkFrameBudget(n: any)
	if type(n) ~= 'number' or not (n > 0) then
		Log.fatal('frameBudget must be greater than 0.', nil)
	end
end

function Scheduler.setFrameBudget(n: number)
	Scheduler.checkFrameBudget(n)
	frameBudgetSeconds = n
end

Scheduler.setEnabled(Config.Scheduler.enabled)

return Scheduler

--!native
--!optimize 2
--!strict

local RunService = game:GetService('RunService')

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Callbacks = require(script.Parent.Callbacks)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local Log = require(script.Parent.Parent.Utils.Log)
local Entities = require(script.Parent.Entities)
local Links = require(script.Parent.Links)
local Memberships = require(script.Parent.Memberships)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local Routing = require(script.Parent.Routing)
local ZoneChanges = require(script.Parent.ZoneChanges)
local ZoneShapes = require(script.Parent.ZoneShapes)

local queryPoint = LinearBVH.queryPoint
local touches = ZoneChanges.touches
local containsPoint = ZoneShapes.containsPoint
local fireCallback = Callbacks.fire
local moveMembership = Memberships.move
local exitMembership = Memberships.exit
local isSubscribed = Memberships.isSubscribed

local treeExact = ZoneShapes.treeExact
local zoneIdToZoneObj = Registry.zoneIdToZoneObj
local zoneSlotIds = ZoneShapes.zoneSlotIds
local slotObservers = Links.slotObservers
local slotSoleObserver = Links.slotSoleObserver
local autoSyncZones = Registry.autoSyncZones

local observerPriorityMap = Registry.observerPriorityMap
local observerTrackingEntities = Memberships.observerTrackingEntities
local observerEnteredCallbacks = Callbacks.observerEnteredCallbacks
local observerTransitionedCallbacks = Callbacks.observerTransitionedCallbacks
local observerEnabled = Registry.observerEnabled
local observerSafety = Registry.observerSafety

local entityToReference = References.entityToReference
local entityData = Entities.entityData
local entityToObservers = Routing.entityToObservers
local dirtyProfiles = Routing.dirtyProfiles

local staticTree = ZoneShapes.staticTree
local dynamicTree = ZoneShapes.dynamicTree
local staticChanges = ZoneShapes.staticChanges
local dynamicChanges = ZoneShapes.dynamicChanges

local ctx_hits = table.create(64) :: { number }
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority = table.create(16) :: { [number]: number }
local ctx_candidateIndex = table.create(16) :: { [number]: number }
local ctx_candidateList = table.create(16) :: { [number]: number }
local ctx_linkedObservers: { [number]: boolean }
local ctx_currentMemberships: { [number]: number }
local ctx_checkingRate: number? = nil
local ctx_checkingIndex = 0

local frameBudget = Config.Scheduler.frameBudget
local autoSyncRate = Config.Scheduler.autoSyncRate
local autoSyncTimer = 0
local autoUpdateConnection: RBXScriptConnection?

local bucketList = Routing.bucketList
local buckets = Routing.buckets
local nextBucketIndex = 1
local bucketLastProcessedIndex = {} :: { [number]: number }
local BUDGET_CHECK = 32
local NOWHERE = Vector3.new(0 / 0, 0 / 0, 0 / 0)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_TRANSFORM = Config.Strategy.TRANSFORM
local STRAT_PIVOT = Config.Strategy.PIVOT

local Scheduler = {}

local function processObserverHit(observerId: number, zoneId: number)
	if not ctx_linkedObservers[observerId] or observerEnabled[observerId] == false then
		return
	end

	if ctx_candidatePriority[observerId] == nil then
		local priority = observerPriorityMap[observerId] or 0
		ctx_cCount += 1
		ctx_candidateList[ctx_cCount] = observerId
		ctx_candidateIndex[observerId] = zoneId
		ctx_candidatePriority[observerId] = priority

		if priority > ctx_highestWin then
			ctx_highestWin = priority
		end
	elseif ctx_currentMemberships[observerId] == zoneId then
		-- An observer's zones share its priority, so only the current zone takes over
		ctx_candidateIndex[observerId] = zoneId
	end
end

local function processZoneHit(slot: number)
	local observers = slotObservers[slot]
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

	-- No early return on budget, or entities would never be checked while zones keep moving
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
			local data = entityData[entity] :: Types.EntityData

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
			-- A table entity without a position is nowhere, rather than an error that stops the tick
			if not position then
				position = NOWHERE
			end

			local needsStatic = data.needsStatic
			local needsDynamic = data.needsDynamic

			local lastPosition = data.lastPosition
			local shouldCheck = data.logicVersion ~= logicVersion

			if not shouldCheck then
				local dx = position.X - lastPosition.X
				local dy = position.Y - lastPosition.Y
				local dz = position.Z - lastPosition.Z

				-- A NaN position counts as moved, so the entity leaves its zone instead of keeping it forever
				shouldCheck = not ((dx * dx + dy * dy + dz * dz) < data.precisionSq)
			end

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

			-- Groups changed by a callback this tick apply next tick; checked now, a lost observer could still win
			if shouldCheck and dirtyProfiles[entity] then
				data.logicVersion = -1
				shouldCheck = false
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

					if not observerTrackingEntities[observerId] then
						continue
					end

					if priority < ctx_highestWin then
						continue
					end

					local currentZoneId = current[observerId]
					if currentZoneId == zoneIdx then
						continue
					end

					-- An earlier callback may have removed the entity or destroyed the zone
					local zone = zoneIdToZoneObj[zoneIdx]
					if entityData[entity] ~= data or not zone then
						continue
					end

					-- Or changed the observer, so recheck next tick. A clean profile means it is still subscribed
					local attached = slotObservers[zone.slot]
					if
						observerEnabled[observerId] == false
						or not attached
						or not table.find(attached, observerId)
						or (dirtyProfiles[entity] and not isSubscribed(entity, observerId))
					then
						data.logicVersion = -1
						continue
					end

					moveMembership(observerId, entity, data, zoneIdx)

					local reference = entityToReference[entity] or entity
					fireCallback(
						if currentZoneId then observerTransitionedCallbacks else observerEnteredCallbacks,
						observerId,
						reference,
						zone,
						entity,
						observerSafety[observerId],
						zoneIdx
					)
				end

				-- A callback changed its groups, so recheck next tick even when standing still
				if dirtyProfiles[entity] then
					data.logicVersion = -1
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

			budgetCheckCountdown -= 1
			if budgetCheckCountdown == 0 then
				budgetCheckCountdown = BUDGET_CHECK
				if (os.clock() - start) > frameBudget then
					break
				end
			end
		end

		bucketLastProcessedIndex[rate] = idx
		ctx_checkingRate = nil

		if (os.clock() - start) > frameBudget then
			break
		end
	end
end

-- Leftover candidates would freeze their observers, and every tick would stop at the same entity
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

-- Set while a tick runs, so an update from a callback is skipped instead of clobbering it.
-- Suspended means an unsafe callback yielded
local tickThread: thread? = nil
local warnedYield = false

function Scheduler.update(dt: number?)
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

	-- A missing, NaN or negative time step would stop auto-syncing for good
	local step = if type(dt) == 'number' and dt >= 0 then dt else 0

	tickThread = coroutine.running()
	local ok, trace = xpcall(runTick, debug.traceback, step)
	tickThread = nil
	warnedYield = false
	if not ok then
		recoverFromError()
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
	frameBudget = n
end

Scheduler.setEnabled(Config.Scheduler.enabled)

return Scheduler

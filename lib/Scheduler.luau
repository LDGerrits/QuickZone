--!native
--!strict

local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.State)
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local objects = State.Objects
local zoneBoundGroups = State.ZoneBoundGroups
local groupPriorityMap = State.GroupPriorityMap
local itemCustomData = State.ItemCustomData
local groupEnteredCallbacks = State.GroupEnteredCallbacks
local groupTrackingItems = State.GroupTrackingItems
local groupExitedCallbacks = State.GroupExitedCallbacks
local zoneIdToZoneObj = State.ZoneIdToZoneObj

local ctx_pos: Vector3
local ctx_collectionId: number
local ctx_cCount: number = 0
local ctx_highestWin: number
local ctx_candidatePriority: { [number]: number } = table.create(16)
local ctx_candidateIndex: { [number]: number } = table.create(16)
local ctx_candidateList: { [number]: number } = table.create(16)

local frameBudget = Config.Scheduler.FrameBudget

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME

local function fireCallback(callbacks, item, zone, customData, safeMode)
	if not callbacks then
		return
	end

	if safeMode then
		for _, cb in callbacks do
			task.spawn(cb, item, zone, customData)
		end
	else
		for _, cb in callbacks do
			cb(item, zone, customData)
		end
	end
end

local function queryCallback(zoneId: number)
	if not Geometry.IsPointInShape(ctx_pos, objects[zoneId]) then
		return
	end

	local groups = zoneBoundGroups[zoneId]
	if not groups then
		return
	end

	local linkedGroups = State.CollectionToGroups[ctx_collectionId]
	if not linkedGroups then
		return
	end

	local isRelevant = false
	for _, gId in groups do
		-- Is this group even interested in this collection?
		if linkedGroups[gId] then
			-- Do we already have a better candidate?
			if not ctx_candidatePriority[gId] then
				isRelevant = true
				break
			end
		end
	end
	if not isRelevant then
		return
	end

	for _, gId in groups do
		if linkedGroups[gId] then
			local pri = groupPriorityMap[gId] or 0
			ctx_cCount += 1
			ctx_candidateList[ctx_cCount] = gId
			ctx_candidateIndex[gId] = zoneId
			ctx_candidatePriority[gId] = pri
			if pri > ctx_highestWin then
				ctx_highestWin = pri
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	if State.PendingRebuild then
		debug.profilebegin('QuickBounds_Build')
		State.RootNode = LinearBVH.Build(objects)
		State.PendingRebuild = false
		debug.profileend()
		State.IsDirty = true
	end

	if not State.RootNode then
		return
	end

	debug.profilebegin('QuickBounds_Step')
	local start = os.clock()
	local forceRefresh = State.IsDirty
	State.IsDirty = false

	-- Each collection is processed one-by-one
	for _, col in pairs(State.Collections) do
		local list = col._items
		local totalItems = #list
		if totalItems == 0 then
			continue
		end

		local config = col._config
		local rate = config.UpdateRate or 20
		local precSq = config.PrecisionSq or 0.01
		local safeMode = config.SafetyMode

		local workQuota = math.ceil(totalItems * rate * dt)
		if workQuota < 1 then
			workQuota = 1
		end
		if workQuota > totalItems then
			workQuota = totalItems
		end

		local processed = 0
		local idx = col._lastProcessedIndex
		if idx > totalItems then
			idx = 1
		end

		ctx_collectionId = col.Id

		while processed < workQuota do
			local item = list[idx]
			local d = col._itemData[item] :: Types._itemData?

			-- Race condition guard
			if not d then
				idx += 1
				if idx > totalItems then
					idx = 1
				end
				processed += 1
				continue
			end

			-- Strategy
			local pos
			local strategy = d.strategy
			if strategy == STRAT_POS then
				pos = (item :: BasePart).Position
			elseif strategy == STRAT_WORLD then
				pos = (item :: Attachment).WorldPosition
			elseif strategy == STRAT_CFRAME then
				pos = (item :: BasePart).CFrame.Position
			elseif strategy == STRAT_PRIM and (item :: Model).PrimaryPart then
				pos = ((item :: Model).PrimaryPart :: BasePart).Position
			else
				pos = (item :: any):GetPivot().Position
			end

			-- Threshold
			local shouldCheck = forceRefresh or d.IsDirty
			if not shouldCheck then
				local lp = d.lastPosition
				local dx, dy, dz = pos.X - lp.X, pos.Y - lp.Y, pos.Z - lp.Z
				if (dx * dx + dy * dy + dz * dz) >= precSq then
					shouldCheck = true
				end
			end

			if shouldCheck then
				d.lastPosition = pos
				d.IsDirty = false

				ctx_pos = pos
				ctx_cCount = 0
				ctx_highestWin = -math.huge

				LinearBVH.QueryPoint(State.RootNode, pos, queryCallback)

				local current = d.ActiveGroupMemberships

				-- Exits
				for gId, oldZoneIdx in pairs(current) do
					local newPri = ctx_candidatePriority[gId]
					if not newPri or newPri < ctx_highestWin then
						current[gId] = nil
						if groupTrackingItems[gId] then
							groupTrackingItems[gId][item] = nil
						end

						local cbs = groupExitedCallbacks[gId]
						if cbs then
							local z = zoneIdToZoneObj[oldZoneIdx]
							local cd = itemCustomData[item] and itemCustomData[item][gId]
							fireCallback(cbs, item, z, cd, safeMode)
						end
					end
				end

				-- Entries
				for i = 1, ctx_cCount do
					local gId = ctx_candidateList[i]
					local pri = ctx_candidatePriority[gId]
					if pri >= ctx_highestWin and not current[gId] then
						local newZoneIdx = ctx_candidateIndex[gId]
						current[gId] = newZoneIdx
						groupTrackingItems[gId][item] = true
						local cbs = groupEnteredCallbacks[gId]
						if cbs then
							local z = zoneIdToZoneObj[newZoneIdx]
							local cd = itemCustomData[item] and itemCustomData[item][gId]
							fireCallback(cbs, item, z, cd, safeMode)
						end
					end
					ctx_candidatePriority[gId] = nil
					ctx_candidateIndex[gId] = nil
					ctx_candidateList[i] = nil
				end
			end

			idx += 1
			if idx > totalItems then
				idx = 1
			end
			processed += 1

			-- Global budget check
			if processed % 42 == 0 and (os.clock() - start) > frameBudget then
				break
			end
		end

		col._lastProcessedIndex = idx

		if (os.clock() - start) > frameBudget then
			break
		end
	end

	debug.profileend()
end)

local Scheduler = {}

function Scheduler.SetFrameBudget(n: number)
	frameBudget = n
end

return Scheduler

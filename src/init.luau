--!strict

local RunService = game:GetService('RunService')

local Types = require(script.Types)
local Config = require(script.Config)
local Scheduler = require(script.Core.Scheduler)
local State = require(script.Core.State)
local Geometry = require(script.Utils.Geometry)
local LinearBVH = require(script.Utils.LinearBVH)

local queryPoint = LinearBVH.queryPoint
local isPointInShape = Geometry.isPointInShape

local zoneIdToZoneObj = State.zoneIdToZoneObj
local zoneAttachedObservers = State.zoneAttachedObservers
local observerIdToObserverObj = State.observerIdToObserverObj

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes

local foundIdsCache = {}

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?
local debugVisuals = {} :: { [number]: BoxHandleAdornment }

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Zones = Types.Zones
export type Observer = Types.Observer
export type Group = Types.Group
export type Entity = Types.Entity

--[=[
	QuickZone is a high-performance spatial partitioning library for Roblox. 

	@class QuickZone
]=]
local QuickZone = {
	Zone = require(script.Classes.Zone) :: Types.ZoneClass,
	Observer = require(script.Classes.Observer) :: Types.ObserverClass,
	Group = require(script.Classes.Group) :: Types.GroupClass,
}

--[=[ 
    Enables or disables automatic updating. If false, you must call `QuickZone:update(dt)` manually.

    @method setAutoUpdate
    @within QuickZone
    @param enabled boolean
    @return QuickZone
]=]
function QuickZone:setAutoUpdate(enabled: boolean): QuickZone
	Scheduler.setAutoUpdate(enabled)
	return QuickZone
end

--[=[ 
    Manually processes the spatial queries and trigger callbacks.
    This is only necessary if `setAutoUpdate` is set to false.

    @method update
    @within QuickZone
    @param dt number -- Delta time
    @return QuickZone
]=]
function QuickZone:update(dt: number): QuickZone
	Scheduler.update(dt)
	return QuickZone
end

--[=[ 
    Instantly forces the internal spatial trees to rebuild if any zones have been modified.
    
    The engine automatically calls this during `QuickZone:update(dt)`.

    @method rebuildTrees
    @within QuickZone
    @return QuickZone
]=]
function QuickZone:rebuildTrees(): QuickZone
	Scheduler.rebuildTrees()
	return self
end

--[=[ 
    Sets how many times per second the engine should automatically poll auto-synced parts.
    Lowering this (e.g., to 20 or 30) improves performance for games with 
    hundreds of moving zones. Set to 0 to poll every frame.

    @method setAutoSyncToPartRate
    @within QuickZone
    @param hz number
    @return QuickZone
]=]
function QuickZone:setAutoSyncToPartRate(hz: number): QuickZone
	Scheduler.setAutoSyncToPartRate(hz)
	return self
end

--[=[ 
	Sets the global execution budget for the Scheduler per frame in milliseconds.
	
	The Scheduler will 'dispatch' entity steps until this threshold is reached, 
	at which point it yields until the next frame to prevent render stutter.
	
	Defaults to 1ms.

	```lua
	-- Allow QuickZone to use up to 0.5ms of frame time
	QuickZone:setFrameBudget(0.5)
	```

	@method setFrameBudget
	@within QuickZone
	@param ms number -- Time in milliseconds
	@return QuickZone
]=]
function QuickZone:setFrameBudget(ms: number): QuickZone
	local s = ms / 1000
	Scheduler.setFrameBudget(s)
	return QuickZone
end

--[=[ 
	Returns an array of all Observers currently existing in the system.

	@method getObservers
	@within QuickZone
	@return { Observer }
]=]
function QuickZone:getObservers(): { Types.Observer }
	local result = {}
	for _, observer in State.observerIdToObserverObj do
		table.insert(result, observer)
	end
	return result
end

--[=[ 
	Returns an array of all Groups (including PlayerGroups) currently 
	registered in the system.

	@method getGroups
	@within QuickZone
	@return { Group }
]=]
function QuickZone:getGroups(): { Types.Group }
	local result = {}
	for _, group in State.groups do
		table.insert(result, group)
	end
	return result
end

--[=[ 
	Returns an array containing every Zone currently registered in the system.
	This includes both static and dynamic zones.

	@method getZones
	@within QuickZone
	@return { Zone }
]=]
function QuickZone:getZones(): { Types.Zone }
	local result = {}
	for _, zone in State.zoneIdToZoneObj do
		table.insert(result, zone)
	end
	return result
end

--[=[ 
	Returns a flattened array of every Entity (Parts, Models, etc.) currently 
	being tracked across all Groups.

	@method getEntities
	@within QuickZone
	@return { Entity }
]=]
function QuickZone:getEntities(): { Types.Entity }
	local result = {}
	for _, group in State.groups do
		local count = #group.entities
		if count > 0 then
			local currentSize = #result
			table.move(group.entities, 1, count, currentSize + 1, result)
		end
	end
	return result
end

--[=[ 
	Returns the Player associated with the entity, if it exists.

	@method getPlayerOfEntity
	@within QuickZone
	@param entity Entity
	@return Player?
]=]
function QuickZone:getPlayerOfEntity(entity: Types.Entity): Player?
	return State.entityToPlayer[entity]
end

--[=[ 
	Performs a spatial query to find all Zones containing the given point.

	@method getZonesAtPoint
	@within QuickZone
	@param position Vector3 -- The world position to check.
	@return { Zone }
]=]
function QuickZone:getZonesAtPoint(position: Vector3): { Zone }
	local results = {}

	queryPoint(State.dynamicTree, position, function(zoneId)
		if isPointInShape(position, dynamicCFrames[zoneId], dynamicHalfSizes[zoneId], dynamicTypes[zoneId]) then
			local zone = zoneIdToZoneObj[zoneId]
			if zone then
				table.insert(results, zone)
			end
		end
	end)

	queryPoint(State.staticTree, position, function(zoneId)
		if isPointInShape(position, staticCFrames[zoneId], staticHalfSizes[zoneId], staticTypes[zoneId]) then
			local zone = zoneIdToZoneObj[zoneId]
			if zone then
				table.insert(results, zone)
			end
		end
	end)

	return results
end

--[=[
	Performs a spatial query to find all observers containing the given point.

	@method getObserversAtPoint
	@within QuickZone
	@param position Vector3 -- The world position to check.
	@return { Observer }
]=]
function QuickZone:getObserversAtPoint(position: Vector3): { Observer }
	table.clear(foundIdsCache)
	local results = {}

	local function processValidZone(zoneId: number)
		local observers = zoneAttachedObservers[zoneId]
		if not observers then
			return
		end

		for _, id in observers do
			if foundIdsCache[id] then
				continue
			end
			foundIdsCache[id] = true

			local observer = observerIdToObserverObj[id]
			if observer then
				table.insert(results, observer)
			end
		end
	end

	queryPoint(State.dynamicTree, position, function(zoneId)
		if isPointInShape(position, dynamicCFrames[zoneId], dynamicHalfSizes[zoneId], dynamicTypes[zoneId]) then
			processValidZone(zoneId)
		end
	end)

	queryPoint(State.staticTree, position, function(zoneId)
		if isPointInShape(position, staticCFrames[zoneId], staticHalfSizes[zoneId], staticTypes[zoneId]) then
			processValidZone(zoneId)
		end
	end)

	return results
end

--[=[ 
	Returns an array of all Groups that the specified entity is currently in.

	@method getGroupsOfEntity
	@within QuickZone
	@param entity Entity -- The Part, Model, or Table entity.
	@return { Group }
]=]
function QuickZone:getGroupsOfEntity(entity: Types.Entity): { Types.Group }
	local groupIds: { [number]: boolean } = State.entityToGroups[entity]
	if not groupIds then
		return {}
	end

	local results = {}
	for groupId, _ in groupIds do
		local group = State.groups[groupId]
		if group then
			table.insert(results, group)
		end
	end
	return results
end

--[=[ 
	Returns an array of all Groups that the specified player is currently in.

	@method getGroupsOfPlayer
	@within QuickZone
	@param player Player
	@return { Group }
]=]
function QuickZone:getGroupsOfPlayer(player: Player): { Types.Group }
	local character = player.Character
	if not character then
		return {}
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return {}
	end

	return self:getGroupsOfEntity(hrp)
end

--[=[ 
	Returns an array of all Observers currently tracking the given entity.

	@method getObserversOfEntity
	@within QuickZone
	@param entity Entity
	@return { Observer }
]=]
function QuickZone:getObserversOfEntity(entity: Types.Entity): { Types.Observer }
	local activeObservers = State.entityToObservers[entity]
	if not activeObservers then
		return {}
	end

	local results = {}
	for observerId, _ in activeObservers do
		local observer = State.observerIdToObserverObj[observerId]
		if observer then
			table.insert(results, observer)
		end
	end
	return results
end

--[=[ 
	Returns an array of all Observers currently tracking the given player.

	@method getObserversOfPlayer
	@within QuickZone
	@param player Player
	@return { Observer }
]=]
function QuickZone:getObserversOfPlayer(player: Player): { Types.Observer }
	local character = player.Character
	if not character then
		return {}
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return {}
	end

	return self:getObserversOfEntity(hrp)
end

--[=[ 
	Returns an array of all Zones the given entity is actively inside, 
	based on its observer memberships.

	@method getZonesOfEntity
	@within QuickZone
	@param entity Entity
	@return { Zone }
]=]
function QuickZone:getZonesOfEntity(entity: Types.Entity): { Types.Zone }
	local data = State.entityData[entity]
	if not data or not data.activeObserverMemberships then
		return {}
	end

	local results = {}
	local seenZones = {} -- In case multiple observers track the entity in the same zone

	for _, zoneId in data.activeObserverMemberships do
		if seenZones[zoneId] then
			continue
		end
		seenZones[zoneId] = true

		local zone = State.zoneIdToZoneObj[zoneId]
		if zone then
			table.insert(results, zone)
		end
	end

	return results
end

--[=[ 
	Returns an array of all Zones the given player is actively inside.

	@method getZonesOfPlayer
	@within QuickZone
	@param player Player
	@return { Zone }
]=]
function QuickZone:getZonesOfPlayer(player: Player): { Types.Zone }
	local character = player.Character
	if not character then
		return {}
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return {}
	end

	return self:getZonesOfEntity(hrp)
end

--[=[ 
	Enables or disables visual rendering of all registered Zones.
	Static and Dynamic zones are colored differently based on their active status.

	@tag Debug
	@method visualize
	@within QuickZone
	@param enabled boolean -- Whether to show the debug visuals.
	@return QuickZone
]=]
function QuickZone:visualize(enabled: boolean): QuickZone
	if debugConnection then
		debugConnection:Disconnect()
		debugConnection = nil
	end
	if debugFolder then
		debugFolder:Destroy()
		debugFolder = nil
	end
	table.clear(debugVisuals)

	if not enabled then
		return self
	end

	local newDebugFolder = Instance.new('Folder')
	newDebugFolder.Name = 'QuickZone_Debug_Visuals'
	newDebugFolder.Parent = workspace
	debugFolder = newDebugFolder

	local function getOrCreateVisual(id: number): BoxHandleAdornment
		local box = debugVisuals[id]
		if not box then
			local newbox = Instance.new('BoxHandleAdornment')
			newbox.Name = 'Zone_' .. id
			newbox.Adornee = workspace.Terrain
			newbox.Transparency = Config.Debug.transparency
			newbox.AlwaysOnTop = true
			newbox.ZIndex = 1
			newbox.Parent = debugFolder
			debugVisuals[id] = newbox
			box = newbox
		end
		return box
	end

	local loopEvent: RBXScriptSignal<number> = RunService:IsClient() and RunService.PreRender or RunService.Heartbeat

	debugConnection = loopEvent:Connect(function()
		if not debugFolder then
			return
		end

		-- Draw static zones
		for id, cframe in State.staticCFrames do
			local box = getOrCreateVisual(id)
			local halfSize = State.staticHalfSizes[id]

			local observers = State.zoneAttachedObservers[id]
			local isActive = observers and next(observers) ~= nil
			local color = isActive and Config.Debug.staticActive or Config.Debug.staticInactive

			box.Size = halfSize * 2
			box.CFrame = cframe
			box.Color3 = color
		end

		-- Draw dynamic zones
		for id, cframe in State.dynamicCFrames do
			local box = getOrCreateVisual(id)
			local halfSize = State.dynamicHalfSizes[id]

			local observers = State.zoneAttachedObservers[id]
			local isActive = observers and next(observers) ~= nil
			local color = isActive and Config.Debug.dynamicActive or Config.Debug.dynamicInactive

			box.Size = halfSize * 2
			box.CFrame = cframe
			box.Color3 = color
		end

		-- Destroy removed zones
		for id, box in debugVisuals do
			if not State.staticCFrames[id] and not State.dynamicCFrames[id] then
				box:Destroy()
				debugVisuals[id] = nil
			end
		end
	end)

	return self
end

-- --[=[
--     Returns an iterator that yields every Zone intersecting the given point.
--     Ideal for zero-allocation ECS queries. Safe to `break` out of early.
-- ]=]
-- function QuickZone:iterZonesAtPoint(point: Vector3)
-- 	-- Grab local references to avoid indexing `State` inside the tight loop
-- 	local dynamicTree = State.dynamicTree
-- 	local staticTree = State.staticTree

-- 	local dynNodes = dynamicTree.nodes
-- 	local dynCount = dynamicTree.count or 0

-- 	local statNodes = staticTree.nodes
-- 	local statCount = staticTree.count or 0

-- 	local px, py, pz = point.X, point.Y, point.Z

-- 	local index = 1
-- 	local checkingDynamic = true

-- 	-- This closure acts as our state machine
-- 	return function(): Types.Zone?
-- 		if checkingDynamic then
-- 			while index <= dynCount do
-- 				local node = dynNodes[index]
-- 				local min, max = node.min, node.max

-- 				if px >= min.X and px <= max.X and py >= min.Y and py <= max.Y and pz >= min.Z and pz <= max.Z then
-- 					if node.id > 0 then
-- 						local hitId = node.id
-- 						index += 1
-- 						-- Yield the actual Zone object!
-- 						return zoneIdToZoneObj[hitId]
-- 					else
-- 						index += 1
-- 					end
-- 				else
-- 					index = node.skipIndex
-- 				end
-- 			end

-- 			-- Dynamic tree finished! Swap to static tree for the next iteration.
-- 			checkingDynamic = false
-- 			index = 1
-- 		end

-- 		if not checkingDynamic then
-- 			while index <= statCount do
-- 				local node = statNodes[index]
-- 				local min, max = node.min, node.max

-- 				if px >= min.X and px <= max.X and py >= min.Y and py <= max.Y and pz >= min.Z and pz <= max.Z then
-- 					if node.id > 0 then
-- 						local hitId = node.id
-- 						index += 1
-- 						return zoneIdToZoneObj[hitId]
-- 					else
-- 						index += 1
-- 					end
-- 				else
-- 					index = node.skipIndex
-- 				end
-- 			end
-- 		end

-- 		return nil -- Both trees exhausted
-- 	end
-- end

return QuickZone

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

local zoneAttachedObservers = State.zoneAttachedObservers
local zoneIdToZoneObj = State.zoneIdToZoneObj
local entityData = State.entityData
local observerIdToObserverObj = State.observerIdToObserverObj
local groups = State.groups
local entityToPlayer = State.entityToPlayer
local entityToGroups = State.entityToGroups

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes
local dynamicTree = State.dynamicTree
local staticTree = State.staticTree

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?
local debugVisuals = {} :: { [number]: BoxHandleAdornment }

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Zones = Types.Zones
export type Observer<T> = Types.Observer<T>
export type Group<T> = Types.Group<T>
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
	Configure the QuickZone settings. 

	```lua
	QuickZone:configure({
		enabled = true,
		autoSyncRate = 10,
		frameBudget = 0.5,
	})
	```

	@method configure
	@within QuickZone
	@param config { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }
	@return QuickZone
]=]
function QuickZone:configure(config: { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }): QuickZone
	if config.enabled ~= nil then
		self:setEnabled(config.enabled)
	end

	if config.autoSyncRate ~= nil then
		self:setAutoSyncRate(config.autoSyncRate)
	end

	if config.frameBudget ~= nil then
		self:setFrameBudget(config.frameBudget)
	end

	return self
end

--[=[ 
	Enables or disables automatic updating. If false, you must call `QuickZone:update(dt)` manually.

	@method setEnabled
	@within QuickZone
	@param enabled boolean
	@return QuickZone
]=]
function QuickZone:setEnabled(enabled: boolean): QuickZone
	Scheduler.setAutoUpdate(enabled)
	return QuickZone
end

--[=[ 
	Manually processes the spatial queries and trigger callbacks.
	This is only necessary if you disabled automatic updating.

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
	Sets the automatic sync rate for zones with references. 
	This controls how often QuickZone checks the reference's position and updates the zone accordingly.

	@method setAutoSyncRate
	@within QuickZone
	@param hz number -- Sync frequency in Hz. Set to 0 to disable auto-syncing.
	@return QuickZone	
]=]
function QuickZone:setAutoSyncRate(hz: number): QuickZone
	Scheduler.setAutoSyncRate(hz)
	return QuickZone
end

--[=[ 
	Instantly forces the internal trees to rebuild if any zones have been modified.

	This is only necessary if you have made manual changes to zones or references
	and want to ensure the changes take effect immediately. 
	Otherwise, the Scheduler will automatically rebuild the trees on the next update step.

	@method rebuild
	@within QuickZone
	@return QuickZone
]=]
function QuickZone:rebuild(): QuickZone
	Scheduler.rebuildTrees()
	return self
end

--[=[ 
	Set a reference to an entity. If set, the callbacks will now pass the reference instead of the entity.
	
	```lua
	QuickZone:setReference(id, transformComponent)

	local entityGroup = QuickZone.Group.new({Entities = { entityId }})
	local observer = QuickZone.Observer.new({Groups = {entityGroup}})

	observer:onEnter(function(player, zone)
		print(player.Name .. " entered!")
	end)
	```

	@method setReference
	@within QuickZone
	@param reference any
	@param entity Entity
	@return QuickZone
]=]
function QuickZone:setReference(reference: any, entity: Entity?): QuickZone
	if entity == nil then
		local oldEntity = State.referenceToEntity[reference]
		if oldEntity then
			State.entityToReference[oldEntity] = nil
		end
		State.referenceToEntity[reference] = nil
		return self
	end

	if reference == nil then
		local oldReference = State.entityToReference[entity]
		if oldReference then
			State.referenceToEntity[oldReference] = nil
		end
		State.entityToReference[reference] = nil
		return self
	end

	State.entityToReference[entity] = reference
	State.referenceToEntity[reference] = entity

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
	Instantly and safely removes the entity from the QuickZone engine. 
	It will be removed from all Groups, resolving any active Observers 
	and firing their `onExit` events.

	@method removeEntity
	@within QuickZone
	@param entity Entity
	@return QuickZone
]=]
function QuickZone:removeEntity(entity: Types.Entity): QuickZone
	local groupIds = entityToGroups[entity]
	if not groupIds then
		return self
	end

	local idsToRemove = {}
	for groupId in groupIds do
		table.insert(idsToRemove, groupId)
	end

	for _, groupId in idsToRemove do
		local group = groups[groupId]
		if group then
			group:remove(entity)
		end
	end

	return self
end

--[=[
	Safely removes a player's character from the QuickZone engine.

	@method removePlayer
	@within QuickZone
	@param player Player
	@return QuickZone
]=]
function QuickZone:removePlayer(player: Player): QuickZone
	local character = player.Character
	if not character then
		return self
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return self
	end

	return self:removeEntity(hrp)
end

--[=[ 
	Returns an array of all Observers currently existing.

	@method getObservers
	@within QuickZone
	@return { Observer }
]=]
function QuickZone:getObservers(): { Types.BaseObserver }
	local result = {}
	for _, observer in observerIdToObserverObj do
		table.insert(result, observer)
	end
	return (result :: any) :: { Types.BaseObserver }
end

--[=[ 
	Returns an array of all Groups (including PlayerGroups) currently 
	registered.

	@method getGroups
	@within QuickZone
	@return { Group }
]=]
function QuickZone:getGroups(): { Types.Group }
	local result = {}
	for _, group in groups do
		table.insert(result, group)
	end
	return result
end

--[=[ 
	Returns an array containing every Zone currently registered.
	This includes both static and dynamic zones.

	@method getZones
	@within QuickZone
	@return { Zone }
]=]
function QuickZone:getZones(): { Types.Zone }
	local result = {}
	for _, zone in zoneIdToZoneObj do
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
	local count = 0

	for entity in entityData do
		count += 1
		result[count] = entity
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
	return entityToPlayer[entity]
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
	local count = 0

	queryPoint(dynamicTree, position, function(zoneId)
		if isPointInShape(position, dynamicCFrames[zoneId], dynamicHalfSizes[zoneId], dynamicTypes[zoneId]) then
			local zone = zoneIdToZoneObj[zoneId]
			if zone then
				count += 1
				results[count] = zone
			end
		end
	end)

	queryPoint(staticTree, position, function(zoneId)
		if isPointInShape(position, staticCFrames[zoneId], staticHalfSizes[zoneId], staticTypes[zoneId]) then
			local zone = zoneIdToZoneObj[zoneId]
			if zone then
				count += 1
				results[count] = zone
			end
		end
	end)

	return results
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
	local data = entityData[entity]
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

		local zone = zoneIdToZoneObj[zoneId]
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
	Returns an array of all Groups that the specified entity is currently in.

	@method getGroupsOfEntity
	@within QuickZone
	@param entity Entity
	@return { Group }
]=]
function QuickZone:getGroupsOfEntity(entity: Types.Entity): { Types.Group }
	local groupIds = entityToGroups[entity]
	if not groupIds then
		return {}
	end

	local results = {}
	local count = 0

	for groupId in groupIds do
		local group = groups[groupId]
		if group then
			count += 1
			results[count] = group
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
	Returns a zero-allocation iterator for all Groups.

	@method iterGroups
	@within QuickZone
	@return () -> Group?
]=]
function QuickZone:iterGroups(): () -> Types.Group?
	local groupId = nil
	return function(): Types.Group?
		groupId = next(groups, groupId)
		return groupId and groups[groupId] or nil
	end
end

--[=[
	Returns a zero-allocation iterator for all Zones.

	@method iterZones
	@within QuickZone
	@return () -> Zone?
]=]
function QuickZone:iterZones(): () -> Types.Zone?
	local zoneId = nil

	return function(): Types.Zone?
		zoneId = next(zoneIdToZoneObj, zoneId)
		return zoneId and zoneIdToZoneObj[zoneId] or nil
	end
end

--[=[
	Returns a zero-allocation iterator for all entities.

	@method iterEntities
	@within QuickZone
	@return () -> Entity?
]=]
function QuickZone:iterEntities(): () -> Types.Entity?
	local entity = nil

	return function(): Types.Entity?
		entity = next(entityData, entity)
		return entity
	end
end

--[=[
	Returns a zero-allocation iterator for all Observers.

	@method iterObservers
	@within QuickZone
	@return () -> Observer?
]=]
function QuickZone:iterObservers(): () -> Types.BaseObserver?
	local observerId = nil

	return function(): Types.BaseObserver?
		observerId = next(observerIdToObserverObj, observerId)
		return observerId and observerIdToObserverObj[observerId] or nil
	end
end

--[=[ 
	Returns a zero-allocation iterator for all Groups that the specified entity is currently in.

	@method iterGroupsOfEntity
	@within QuickZone
	@param entity Entity
	@return () -> Group?
]=]
function QuickZone:iterGroupsOfEntity(entity: Types.Entity): () -> Types.Group?
	local groupIds = entityToGroups[entity]
	if not groupIds then
		return function()
			return nil
		end
	end

	local groupId = nil
	return function(): Types.Group?
		groupId = next(groupIds, groupId)
		return groupId and groups[groupId] or nil
	end
end

--[=[ 
	Returns a zero-allocation iterator for all Groups that the specified player is currently in.

	@method iterGroupsOfPlayer
	@within QuickZone
	@param player Player
	@return () -> Group?
]=]
function QuickZone:iterGroupsOfPlayer(player: Player): () -> Types.Group?
	local character = player.Character
	if not character then
		return function()
			return nil
		end
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return function()
			return nil
		end
	end

	return self:iterGroupsOfEntity(hrp)
end

--[=[ 
	Returns an iterator for all unique Zones the given entity is actively inside.

	@method iterZonesOfEntity
	@within QuickZone
	@param entity Entity
	@return () -> Zone?
]=]
function QuickZone:iterZonesOfEntity(entity: Types.Entity): () -> Types.Zone?
	local data = entityData[entity]
	if not data or not data.activeObserverMemberships then
		return function()
			return nil
		end
	end

	local memberships = data.activeObserverMemberships
	local seenZones = {}
	local observerId = nil

	return function(): Types.Zone?
		while true do
			observerId = next(memberships, observerId)
			if not observerId then
				return nil
			end

			local zoneId = memberships[observerId]
			if seenZones[zoneId] then
				continue
			end

			seenZones[zoneId] = true
			local zone = zoneIdToZoneObj[zoneId]

			if zone then
				return zone
			end
		end
	end
end

--[=[ 
	Returns an iterator for all unique Zones the given player is actively inside.

	@method iterZonesOfPlayer
	@within QuickZone
	@param player Player
	@return () -> Zone?
]=]
function QuickZone:iterZonesOfPlayer(player: Player): () -> Types.Zone?
	local character = player.Character
	if not character then
		return function()
			return nil
		end
	end

	local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart?
	if not hrp then
		return function()
			return nil
		end
	end

	return self:iterZonesOfEntity(hrp)
end

--[=[
	Returns an iterator that returns every Zone intersecting the given point.
	Ideal for zero-allocation ECS queries. Safe to `break` out of early.

	@method iterZonesAtPoint
	@within QuickZone
	@param point Vector3
	@return () -> Zone?
]=]
function QuickZone:iterZonesAtPoint(point: Vector3): () -> Types.Zone?
	local dynamicNodes = dynamicTree.nodes
	local dynamicCount = dynamicTree.count or 0

	local staticNodes = staticTree.nodes
	local staticCount = staticTree.count or 0

	local px, py, pz = point.X, point.Y, point.Z

	local index = 1
	local checkingDynamic = true

	return function(): Types.Zone?
		if checkingDynamic then
			while index <= dynamicCount do
				local node = dynamicNodes[index]
				local min, max = node.min, node.max

				if px < min.X or px > max.X or py < min.Y or py > max.Y or pz < min.Z or pz > max.Z then
					index = node.skipIndex
					continue
				end

				index += 1
				local hitId = node.id

				if
					hitId > 0
					and isPointInShape(point, dynamicCFrames[hitId], dynamicHalfSizes[hitId], dynamicTypes[hitId])
				then
					return zoneIdToZoneObj[hitId]
				end
			end

			checkingDynamic = false
			index = 1
		end

		if not checkingDynamic then
			while index <= staticCount do
				local node = staticNodes[index]
				local min, max = node.min, node.max

				if px < min.X or px > max.X or py < min.Y or py > max.Y or pz < min.Z or pz > max.Z then
					index = node.skipIndex
					continue
				end

				index += 1
				local hitId = node.id

				if
					hitId > 0
					and isPointInShape(point, staticCFrames[hitId], staticHalfSizes[hitId], staticTypes[hitId])
				then
					return zoneIdToZoneObj[hitId]
				end
			end
		end

		return nil
	end
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
		for id, cframe in staticCFrames do
			local box = getOrCreateVisual(id)
			local halfSize = staticHalfSizes[id]

			local observers = zoneAttachedObservers[id]
			local isActive = observers and next(observers) ~= nil
			local color = isActive and Config.Debug.staticActive or Config.Debug.staticInactive

			box.Size = halfSize * 2
			box.CFrame = cframe
			box.Color3 = color
		end

		-- Draw dynamic zones
		for id, cframe in dynamicCFrames do
			local box = getOrCreateVisual(id)
			local halfSize = dynamicHalfSizes[id]

			local observers = zoneAttachedObservers[id]
			local isActive = observers and next(observers) ~= nil
			local color = isActive and Config.Debug.dynamicActive or Config.Debug.dynamicInactive

			box.Size = halfSize * 2
			box.CFrame = cframe
			box.Color3 = color
		end

		-- Destroy removed zones
		for id, box in debugVisuals do
			if not staticCFrames[id] and not dynamicCFrames[id] then
				box:Destroy()
				debugVisuals[id] = nil
			end
		end
	end)

	return self
end

return QuickZone

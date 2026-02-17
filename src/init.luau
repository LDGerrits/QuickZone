--!strict

local RunService = game:GetService('RunService')

local Geometry = require(script.Core.Geometry)
local LinearBVH = require(script.Core.LinearBVH)
local Types = require(script.Types)
local State = require(script.State)
local Config = require(script.Config)
local Scheduler = require(script.Core.Scheduler)

local zoneAttachedObservers = State.zoneAttachedObservers
local observerIdToObserverObj = State.observerIdToObserverObj

local foundIdsCache = {}

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?
local debugVisuals = {} :: { [number]: BoxHandleAdornment }

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Observer = Types.Observer
export type Group = Types.Group
export type Entity = Types.Entity

--[=[
	QuickZone is a high-performance spatial partitioning library for Roblox. 

	@class QuickZone
]=]
local QuickZone = {
	Zone = require(script.Classes.Zone) :: Zone,
	Observer = require(script.Classes.Observer) :: Observer,
	Group = require(script.Classes.Group) :: Group,
}

--[=[ 
	Sets the global execution budget for the Scheduler per frame in milliseconds.
	
	The Scheduler will 'dispatch' entity updates until this threshold is reached, 
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
	Performs a spatial query to find all Zones containing the given point.

	@method getZonesAtPoint
	@within QuickZone
	@param position Vector3 -- The world position to check.
	@return { Zone }
]=]
function QuickZone:getZonesAtPoint(position: Vector3): { Zone }
	local results = {}

	local function checkZone(zoneId: number, isDynamic: boolean)
		if Geometry.isPointInZone(position, zoneId, isDynamic) then
			local zone = State.zoneIdToZoneObj[zoneId]
			if zone then
				table.insert(results, zone)
			end
		end
	end

	if State.dynamicRootNode then
		LinearBVH.queryPoint(State.dynamicRootNode, position, function(zoneId)
			checkZone(zoneId, true)
		end)
	end

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			checkZone(zoneId, false)
		end)
	end

	return results
end

--[=[ 
	Finds all Observers whose assigned Zones contain the given point.

	@method getObserversAtPoint
	@within QuickZone
	@param position Vector3 -- The world position to check.
	@return { Observer }
]=]
function QuickZone:getObserversAtPoint(position: Vector3): { Observer }
	table.clear(foundIdsCache)
	local results = {}

	local function checkZone(zoneId: number, isDynamic: boolean)
		if not Geometry.isPointInZone(position, zoneId, isDynamic) then
			return
		end

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

	if State.dynamicRootNode then
		LinearBVH.queryPoint(State.dynamicRootNode, position, function(zoneId)
			checkZone(zoneId, true)
		end)
	end

	if State.staticRootNode then
		LinearBVH.queryPoint(State.staticRootNode, position, function(zoneId)
			checkZone(zoneId, false)
		end)
	end

	return results
end

--[=[ 
	Returns the Group that the specified entity currently belongs to.

	@method getGroupOfEntity
	@within QuickZone
	@param entity Entity -- The Part, Model, or Table entity.
	@return Group?
]=]
function QuickZone:getGroupOfEntity(entity: Types.Entity): Types.Group?
	local groupId = State.entityToGroup[entity]
	if groupId then
		return State.groups[groupId]
	end
	return nil
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

	local function updateVisual(id: number, cframe: CFrame, halfSize: Vector3, color: Color3)
		local box = debugVisuals[id]

		if not box then
			local newBox = Instance.new('BoxHandleAdornment')
			newBox.Name = 'Zone_' .. id
			newBox.Adornee = workspace.Terrain
			newBox.Transparency = Config.Debug.transparency
			newBox.AlwaysOnTop = true
			newBox.ZIndex = 1
			newBox.Parent = debugFolder
			debugVisuals[id] = newBox
			box = newBox
		end

		box.Size = halfSize * 2
		box.CFrame = cframe
		box.Color3 = color
	end

	debugConnection = RunService.PreRender:Connect(function()
		if not debugFolder then
			return
		end

		-- Draw static and dynamic zones
		for id, cframe in State.staticCFrames do
			if not debugVisuals[id] then
				local halfSize = State.staticHalfSizes[id]
				local isActive = State.zoneAttachedObservers[id] ~= nil
				local color = isActive and Config.Debug.staticActive or Config.Debug.staticInactive
				updateVisual(id, cframe, halfSize, color)
			end
		end
		for id, cframe in State.dynamicCFrames do
			if not debugVisuals[id] then
				local halfSize = State.dynamicHalfSizes[id]
				local isActive = State.zoneAttachedObservers[id] ~= nil
				local color = isActive and Config.Debug.dynamicActive or Config.Debug.dynamicInactive
				updateVisual(id, cframe, halfSize, color)
			end
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

return QuickZone

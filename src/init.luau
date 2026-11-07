--!strict
--v1.6.0 • LDGerrits
--[=[
	@class QuickZone

	A high-performance, physics-free spatial query library for Roblox. Maintain 60 FPS with 1M+ zones.
]=]

local RunService = game:GetService('RunService')

local Types = require(script.Types)
local Config = require(script.Config)
local Entities = require(script.Core.Entities)
local Links = require(script.Core.Links)
local PlayerTracker = require(script.Core.PlayerTracker)
local References = require(script.Core.References)
local Registry = require(script.Core.Registry)
local Scheduler = require(script.Core.Scheduler)
local ZoneShapes = require(script.Core.ZoneShapes)
local Log = require(script.Utils.Log)
local WorldQueries = require(script.Classes.WorldQueries)

local isPlayer = References.isPlayer

local entityOf = References.entityOf

local zoneAttachedObservers = Links.zoneAttachedObservers
local zoneSlotToZoneObj = Registry.zoneSlotToZoneObj
local groups = Registry.groups
local entityToGroups = Entities.entityToGroups
local entityToReference = References.entityToReference

local shapeCFrames = ZoneShapes.shapeCFrames
local shapeExtents = ZoneShapes.shapeExtents
local dynamicSlots = ZoneShapes.dynamicSlots

local debugConnection: RBXScriptConnection?
local debugFolder: Folder?

type DebugVisual = {
	adornment: any,
	shape: Types.ShapeType,
	zone: Types.Zone,
}

local debugVisuals = {} :: { [number]: DebugVisual }

export type QuickZone = Types.QuickZone
export type Zone = Types.Zone
export type Zones = Types.Zones
export type Observer<T> = Types.Observer<T>
export type Group<T> = Types.Group<T>
export type Entity = Types.Entity
export type PartsConfig = Types.PartsConfig

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

	@tag Chainable
	@method configure
	@within QuickZone
	@param config { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }
	@return QuickZone
]=]
function QuickZone:configure(config: { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }): QuickZone
	if type(config) ~= 'table' then
		Log.fatal('configure expects a config table, got %s.', nil, typeof(config))
	end
	-- Checked first, so a bad value doesn't leave the settings before it applied
	if config.autoSyncRate ~= nil then
		Scheduler.checkAutoSyncRate(config.autoSyncRate)
	end
	if config.frameBudget ~= nil then
		local ms = config.frameBudget
		Scheduler.checkFrameBudget(if type(ms) == 'number' then ms / 1000 else ms)
	end

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

	@tag Chainable
	@method setEnabled
	@within QuickZone
	@param enabled boolean
	@return QuickZone
]=]
function QuickZone:setEnabled(enabled: boolean): QuickZone
	Scheduler.setEnabled(not not enabled)
	return self
end

--[=[ 
	Manually processes the spatial queries and trigger callbacks.
	This is only necessary if you disabled automatic updating.

	Called from inside a callback, while an update is running, it does nothing: its work is done by the next update.

	@tag Chainable
	@method update
	@within QuickZone
	@param dt number? -- Delta time, 0 when left out
	@return QuickZone
]=]
function QuickZone:update(dt: number?): QuickZone
	Scheduler.update(dt)
	return self
end

--[=[ 
	Sets the automatic sync rate for zones with references. 
	This controls how often QuickZone checks the reference's position and updates the zone accordingly.

	@tag Chainable
	@method setAutoSyncRate
	@within QuickZone
	@param hz number -- Sync frequency in Hz. Set to 0 to disable auto-syncing.
	@return QuickZone	
]=]
function QuickZone:setAutoSyncRate(hz: number): QuickZone
	Scheduler.setAutoSyncRate(hz)
	return self
end

--[=[ 
	Instantly forces the internal trees to rebuild if any zones have been modified.

	This is only necessary if you have made manual changes to zones or references
	and want to ensure the changes take effect immediately. 
	Otherwise, the Scheduler will automatically rebuild the trees on the next update step.

	@tag Chainable
	@method rebuild
	@within QuickZone
	@return QuickZone
]=]
function QuickZone:rebuild(): QuickZone
	ZoneShapes.rebuildTrees()
	return self
end

--[=[ 
	Set a reference to an entity. If set, the callbacks will now pass the reference instead of the entity.
	
	```lua
	QuickZone:setReference(transformComponent, numberId)

	local entityGroup = QuickZone.Group.new({ entities = { transformComponent } })
	local observer = QuickZone.Observer.new({ groups = { entityGroup } })

	observer:onEnter(function(numberId, zone)
		print(tostring(numberId) .. " entered!")
	end)
	```

	:::info Lifetime
	The reference is forgotten once the entity leaves its last group, so set it again when you add the entity back.
	The `HumanoidRootPart` of a player QuickZone tracks keeps the player as its reference; setting another one is ignored.
	:::

	@tag Chainable
	@method setReference
	@within QuickZone
	@param entity Entity
	@param reference any?
	@return QuickZone
]=]
function QuickZone:setReference(entity: Entity, reference: any?): QuickZone
	local oldReference = entityToReference[entity]

	-- The player tracker links a player's part and sets the link again on every respawn
	if isPlayer(oldReference) then
		if reference ~= oldReference then
			Log.warn("Cannot change the reference of a player's HumanoidRootPart. Ignoring request.", nil)
		end
		return self
	end
	if isPlayer(reference) then
		return self
	end

	References.link(entity, reference)

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

	@tag Chainable
	@method setFrameBudget
	@within QuickZone
	@param ms number -- Time in milliseconds
	@return QuickZone
]=]
function QuickZone:setFrameBudget(ms: number): QuickZone
	Scheduler.setFrameBudget(if type(ms) == 'number' then ms / 1000 else ms)
	return self
end

--[=[
	Instantly and safely removes the entity from QuickZone. 
	It will be removed from all Groups, resolving any active Observers 
	and firing their `onExit` events. Managed groups (`Group.players`, `Group.fromTag`) keep it,
	and warn once, as they decide their own members.

	Accepts a Player, an entity, or the reference an entity was given with `setReference`.

	@tag Chainable
	@method removeEntity
	@within QuickZone
	@param entity any
	@return QuickZone
]=]
function QuickZone:removeEntity(entity: any): QuickZone
	-- Groups already asked, so a managed group warns once
	local asked = {} :: { [any]: true }

	-- A player leaves the groups it was added to, also while it has no character
	if isPlayer(entity) then
		for _, group in PlayerTracker.groupsOf(entity) do
			asked[group] = true
			group:remove(entity)
		end
	end

	entity = entityOf(entity)

	local groupIds = entityToGroups[entity]
	if not groupIds then
		return self
	end

	local idsToRemove = {}
	for groupId in groupIds do
		table.insert(idsToRemove, groupId)
	end

	-- A player's character part goes by its player, so the player is removed rather than only this
	-- character. Other entities go by themselves, as entities may share a reference
	local reference = entityToReference[entity]
	local target = if isPlayer(reference) then reference else entity
	for _, groupId in idsToRemove do
		local group = groups[groupId]
		if group and not asked[group] then
			group:remove(target)
		end
	end

	return self
end

--[=[ 
	Enables or disables visual rendering of all registered Zones.
	Static and Dynamic zones are colored differently based on their active status.

	@tag Chainable
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

	-- Keyed by slot, which a new zone may take over
	local function getOrCreateVisual(slot: number): DebugVisual
		local visual = debugVisuals[slot]
		local zone = zoneSlotToZoneObj[slot]
		local shape = zone:getShape()

		if visual and (visual.shape ~= shape or visual.zone ~= zone) then
			visual.adornment:Destroy()
			debugVisuals[slot] = nil
			visual = nil
		end

		if not visual then
			local adornment: any
			if shape == 'Ball' then
				adornment = Instance.new('SphereHandleAdornment')
			elseif shape == 'Cylinder' then
				adornment = Instance.new('CylinderHandleAdornment')
			else
				adornment = Instance.new('BoxHandleAdornment')
			end
			adornment.Name = 'Zone_' .. zone:getId()
			adornment.Adornee = workspace.Terrain
			adornment.Transparency = Config.Debug.transparency
			adornment.AlwaysOnTop = true
			adornment.ZIndex = 1
			adornment.Parent = debugFolder
			visual = {
				adornment = adornment,
				shape = shape,
				zone = zone,
			}
			debugVisuals[slot] = visual
		end
		return visual
	end

	local loopEvent: RBXScriptSignal<number> = RunService:IsClient() and RunService.PreRender or RunService.Heartbeat

	debugConnection = loopEvent:Connect(function()
		if not debugFolder then
			return
		end

		for slot, cframe in shapeCFrames do
			local visual = getOrCreateVisual(slot)
			local box = visual.adornment
			-- What the shape fills, so a Ball or Cylinder is drawn at the size it detects
			local halfSize = shapeExtents[slot]
			local size = halfSize * 2

			local observers = zoneAttachedObservers[slot]
			-- Links drops a slot's list once it empties
			local isActive = observers ~= nil
			local color
			if dynamicSlots[slot] then
				color = isActive and Config.Debug.dynamicActive or Config.Debug.dynamicInactive
			else
				color = isActive and Config.Debug.staticActive or Config.Debug.staticInactive
			end

			if visual.shape == 'Ball' then
				box.Radius = halfSize.X
				box.CFrame = cframe
			elseif visual.shape == 'Cylinder' then
				box.Radius = halfSize.Y
				box.Height = size.X
				box.CFrame = cframe * CFrame.Angles(0, math.rad(90), 0)
			else
				box.Size = size
				box.CFrame = cframe
			end
			box.Color3 = color
		end

		-- Destroy removed zones
		for id, box in debugVisuals do
			if not shapeCFrames[id] then
				box.adornment:Destroy()
				debugVisuals[id] = nil
			end
		end
	end)

	return self
end

-- Its queries are kept in their own file
for name, method in WorldQueries do
	(QuickZone :: any)[name] = method
end

return QuickZone

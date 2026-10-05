--!strict
--[=[
	@class Zone
	
	Zones define physical areas in world space. They can be static or dynamic 
	and support shapes like Blocks, Balls, and Cylinders, as well as the collision
	geometry of MeshParts and Unions.
	
	Zones themselves are 'passive', meaning they must be attached to an Observer before any detection occurs.

	:::caution Performance
	If a zone moves (e.g., attached to a moving platform) or changes size, 
	you should make the zone dynamic by setting `isDynamic` to `true`. 

	Static zones are optimized into a large, pre-calculated tree. Updating a 
	static zone forces a full recalculation of that tree, which is expensive. 
	Dynamic zones are handled separately and are much cheaper to update.
	:::
]=]

local CollectionService = game:GetService('CollectionService')

local State = require(script.Parent.Parent.Core.State)
local ZoneShapes = require(script.Parent.Parent.Core.ZoneShapes)
local Types = require(script.Parent.Parent.Types)
local Geometry = require(script.Parent.Parent.Utils.Geometry)
local Log = require(script.Parent.Parent.Utils.Log)
local Zones = require(script.Parent.Zones)

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes
local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes
local staticMeshes = State.staticMeshes
local dynamicMeshes = State.dynamicMeshes

local BLOCK_SHAPE_VALUE = Enum.PartType.Block.Value
local MESH_SHAPE_VALUE = Geometry.MESH_SHAPE_VALUE

local SHAPE_MAP = {
	Block = Enum.PartType.Block.Value,
	Cylinder = Enum.PartType.Cylinder.Value,
	Ball = Enum.PartType.Ball.Value,
	Wedge = Enum.PartType.Wedge.Value,
	CornerWedge = Enum.PartType.CornerWedge.Value,
	Mesh = MESH_SHAPE_VALUE,
}

local function getShapeEnumValue(part: BasePart): number
	if part:IsA('Part') then
		return part.Shape.Value
	end

	if part:IsA('MeshPart') or part:IsA('PartOperation') then
		return MESH_SHAPE_VALUE
	end

	if part:IsA('WedgePart') then
		return Enum.PartType.Wedge.Value
	end

	if part:IsA('CornerWedgePart') then
		return Enum.PartType.CornerWedge.Value
	end

	return Enum.PartType.Block.Value
end

local function asQueryablePart(reference: (BasePart | Attachment | Bone)?): BasePart?
	if reference and reference:IsA('BasePart') then
		return reference
	end
	return nil
end

local function applyShapeType(slot: number, isDynamic: boolean, shapeType: number, part: BasePart?)
	if shapeType == MESH_SHAPE_VALUE and not part then
		Log.warn(
			"Shape 'Mesh' requires a BasePart reference. Defaulting Zone %d to Block.",
			nil,
			State.zoneSlotIds[slot]
		)
		shapeType = BLOCK_SHAPE_VALUE
	end

	local meshPart = if shapeType == MESH_SHAPE_VALUE then part else nil

	if isDynamic then
		dynamicTypes[slot] = shapeType
		dynamicMeshes[slot] = meshPart
	else
		staticTypes[slot] = shapeType
		staticMeshes[slot] = meshPart
	end
end

local function clearAutoSync(zone: Types.InternalZone)
	State.autoSyncZones[zone.slot] = nil
	if zone.syncConnections then
		for _, conn in zone.syncConnections do
			conn:Disconnect()
		end
		zone.syncConnections = nil
	end
end

local function setupAutoSync(zone: Types.InternalZone, reference: BasePart | Attachment | Bone)
	State.autoSyncZones[zone.slot] = zone

	local connections = zone.syncConnections or {}

	if reference:IsA('BasePart') then
		table.insert(
			connections,
			reference:GetPropertyChangedSignal('Size'):Connect(function()
				local newHalfSize = reference.ExtentsSize * 0.5
				if dynamicHalfSizes[zone.slot] ~= newHalfSize then
					dynamicHalfSizes[zone.slot] = newHalfSize
					ZoneShapes.refresh(zone.slot)
					State.pendingDynamicRebuild = true
				end
			end)
		)
	end

	if reference:IsA('Part') then
		table.insert(
			connections,
			reference:GetPropertyChangedSignal('Shape'):Connect(function()
				local newShape = reference.Shape.Value
				if dynamicTypes[zone.slot] ~= newShape then
					dynamicTypes[zone.slot] = newShape
					ZoneShapes.refresh(zone.slot)
					State.pendingDynamicRebuild = true
				end
			end)
		)
	end

	zone.syncConnections = connections
	zone:sync()
end

local function updateObserverZoneCount(observerId: number, isDynamic: boolean, delta: number)
	local dict = isDynamic and State.observerDynamicCount or State.observerStaticCount
	local current = dict[observerId] or 0
	local newCount = current + delta
	dict[observerId] = newCount

	-- Only flag entities dirty if the observer's topology fundamentally changed
	if (current == 0 and newCount == 1) or (current == 1 and newCount == 0) then
		-- Only force a global logic override when an observer loses its last zone
		if current == 1 and newCount == 0 then
			State.logicVersion += 1
		end

		for groupId, observers in State.groupToObservers do
			if not observers[observerId] then
				continue
			end

			local group = State.groups[groupId]
			if not group then
				continue
			end

			for _, entity in group.entities do
				State.dirtyTopology[entity] = true
			end
		end
	end
end

-- Fires the observer's exits for its entities in the zone
local function exitEntities(zone: Types.InternalZone, observerId: number)
	local trackedEntities = State.observerTrackingEntities[observerId]
	if not trackedEntities then
		return
	end

	local id = zone.id
	for entity, zoneId in trackedEntities do
		if zoneId ~= id then
			continue
		end

		local data = State.entityData[entity]
		if not data or data.activeObserverMemberships[observerId] ~= id then
			continue
		end

		data.activeObserverMemberships[observerId] = nil
		trackedEntities[entity] = nil

		local cbs = State.observerExitedCallbacks[observerId]
		if not cbs then
			continue
		end

		local safety = State.observerSafety[observerId]
		local ref = State.entityToReference[entity] or entity
		for _, fn in cbs do
			if safety then
				task.spawn(fn, ref, zone, entity)
			else
				fn(ref, zone, entity)
			end
		end
	end
end

local Zone = {}
Zone.__index = Zone

local function newZoneInternal(
	cframe: CFrame,
	size: Vector3,
	shapeType: number,
	reference: (BasePart | Attachment | Bone)?,
	isDynamic: boolean,
	metadata: any?,
	autoSync: boolean
): Types.Zone
	local id = State.nextZoneId
	State.nextZoneId += 1

	-- Keyed by slot, which is reused, so the tables stay arrays
	local slot = table.remove(State.freeZoneSlots)
	if not slot then
		slot = State.zoneSlotCount + 1
		State.zoneSlotCount = slot
	end
	State.zoneSlotIds[slot] = id

	local halfSize = size * 0.5
	if isDynamic then
		State.dynamicCFrames[slot] = cframe
		State.dynamicHalfSizes[slot] = halfSize
		State.pendingDynamicRebuild = true
		State.dynamicTree.membersChanged = true
	else
		State.staticCFrames[slot] = cframe
		State.staticHalfSizes[slot] = halfSize
		State.pendingStaticRebuild = true
		State.staticTree.membersChanged = true
	end

	applyShapeType(slot, isDynamic, shapeType, asQueryablePart(reference))
	ZoneShapes.refresh(slot)

	local self: Types.InternalZone = setmetatable({
		id = id,
		slot = slot,
		reference = reference,
		dynamic = isDynamic,
		metadata = metadata,
		autoSync = false,
	}, Zone) :: any
	State.zoneIdToZoneObj[id] = self
	State.zoneSlotToZoneObj[slot] = self

	if autoSync then
		self:setAutoSync(true)
	end

	return self
end

--[=[ 
	Creates a Zone object.

	```lua
	local zone = QuickZone.Zone.new({
		cframe = CFrame.new(0, 10, 0),
		size = Vector3.new(10, 10, 10),
		shape = 'Block',
		isDynamic = false,
		metadata = { Name = "Lobby" }
	})
	```

	:::caution Dynamic Zones
	If a zone moves, set `isDynamic` to `true` for maximum performance. 
	:::

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Constructor
	@tag Chainable
	@param config { cframe: CFrame, size: Vector3, shape: Types.ShapeType?, reference: (BasePart | Attachment | Bone)?, isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zone
]=]
function Zone.new(config: {
	cframe: CFrame,
	size: Vector3,
	shape: Types.ShapeType?,
	reference: (BasePart | Attachment | Bone)?,
	isDynamic: boolean?,
	metadata: any?,
	autoSync: boolean?,
}): Types.Zone
	local shapeType = Enum.PartType.Block.Value

	if config.shape then
		local mapped = SHAPE_MAP[config.shape]
		if mapped then
			shapeType = mapped
		else
			Log.warn("Invalid shape '%s'. Defaulting to Block.", nil, tostring(config.shape))
		end
	end

	return newZoneInternal(
		config.cframe,
		config.size,
		shapeType,
		config.reference,
		config.isDynamic or false,
		config.metadata,
		config.autoSync or false
	)
end

--[=[ 
	Creates a Zone automatically based on the Part's properties.
	Supported shapes: Block, Ball (Spheres), Cylinder, Wedge, and CornerWedge.

	MeshParts and solid modelled parts (unions, intersections and negates) get the
	`Mesh` shape, which resolves containment against the part's collision geometry.

	```lua
	local part = workspace.ZonePart
	local zone = QuickZone.Zone.fromPart(part)
	```

	:::caution Dynamic Zones
	If a zone moves, set `isDynamic` to `true` for maximum performance. 
	:::

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Constructor
	@tag Chainable
	@param part BasePart -- The part to derive the zone from.
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zone
]=]
function Zone.fromPart(
	part: BasePart,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zone
	local shapeId = getShapeEnumValue(part)

	local isDynamic = config and config.isDynamic or false
	local metadata = config and config.metadata
	local autoSync = config and config.autoSync or false

	return newZoneInternal(part.CFrame, part.ExtentsSize, shapeId, part, isDynamic, metadata, autoSync)
end

--[=[
	Creates and manages a collection of Zones from a static array of BaseParts.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parts { BasePart }
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromParts(
	parts: { BasePart },
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	for _, part in parts do
		if part:IsA('BasePart') then
			local newZone = Zone.fromPart(part, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
				autoSync = autoSync,
			})
			zones:add(newZone)
		end
	end

	return zones
end

--[=[
	Dynamically creates and manages a Zones object from all BaseParts that are 
	direct children of the given Instance. Automatically updates as children are added/removed.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parent Instance
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromChildren(
	parent: Instance,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	local instanceToZone = {} :: { [Instance]: Types.Zone }

	local function onAdded(child: Instance)
		if child:IsA('BasePart') and not instanceToZone[child] then
			local newZone = Zone.fromPart(child, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
			})
			instanceToZone[child] = newZone
			zones:add(newZone)
		end
	end

	local function onRemoved(child: Instance)
		local oldZone = instanceToZone[child]
		if oldZone then
			instanceToZone[child] = nil
			oldZone:destroy()
		end
	end

	local addedConn = parent.ChildAdded:Connect(onAdded)
	local removedConn = parent.ChildRemoved:Connect(onRemoved)
	for _, child in parent:GetChildren() do
		onAdded(child)
	end

	zones:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for child, _ in instanceToZone do
			onRemoved(child)
		end
		table.clear(instanceToZone)
	end)

	return zones
end

--[=[
	Dynamically creates and manages a Zones object from all BaseParts contained 
	anywhere within the given Instance. Automatically updates as descendants are added/removed.
	
	```lua
	local mapZones = QuickZone.Zone.fromDescendants(workspace.HazardFolder)
	```
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param parent Instance -- The container (Model, Folder, etc.) to search through.
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromDescendants(
	parent: Instance,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	local instanceToZone = {} :: { [Instance]: Types.Zone }

	local function onAdded(descendant: Instance)
		if descendant:IsA('BasePart') and not instanceToZone[descendant] then
			local newZone = Zone.fromPart(descendant, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
			})
			instanceToZone[descendant] = newZone
			zones:add(newZone)
		end
	end

	local function onRemoved(descendant: Instance)
		local oldZone = instanceToZone[descendant]
		if oldZone then
			instanceToZone[descendant] = nil
			oldZone:destroy()
		end
	end

	local addedConn = parent.DescendantAdded:Connect(onAdded)
	local removedConn = parent.DescendantRemoving:Connect(onRemoved)
	for _, descendant in parent:GetDescendants() do
		onAdded(descendant)
	end

	zones:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for descendant, _ in instanceToZone do
			onRemoved(descendant)
		end
		table.clear(instanceToZone)
	end)

	return zones
end

--[=[
	Dynamically creates and manages Zones for all BaseParts with a specific CollectionService tag.
	If the tag is applied to a container (e.g., a Model or a Folder), it will create zones for all BasePart descendants.
	
	@tag Constructor
	@tag Chainable
	@within Zone
	@param tag string
	@param config { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	@return Zones
]=]
function Zone.fromTag(
	tag: string,
	config: {
		isDynamic: boolean?,
		metadata: any?,
		autoSync: boolean?,
	}?
): Types.Zones
	local isDynamic = if config and config.isDynamic ~= nil then config.isDynamic else false
	local metadata = if config and config.metadata ~= nil then config.metadata else nil
	local autoSync = if config and config.autoSync ~= nil then config.autoSync else false

	local zones = Zones.new({
		isDynamic = isDynamic,
		metadata = metadata,
		autoSync = autoSync,
	}) :: Types.InternalZones

	local watchingAncestry = {} :: { [Instance]: RBXScriptConnection }
	local containerConnections = {} :: { [Instance]: { RBXScriptConnection } }
	local partDestroyingConnections = {} :: { [BasePart]: RBXScriptConnection }
	local instanceToZone = {} :: { [BasePart]: Types.Zone }
	local partRefCount = {} :: { [BasePart]: number }

	local function removePart(part: BasePart)
		local count = (partRefCount[part] or 0) - 1

		if count <= 0 then -- No more active tags claim this part, so safe to destroy
			partRefCount[part] = nil
			local deadZone = instanceToZone[part]
			if deadZone then
				instanceToZone[part] = nil
				deadZone:destroy()
			end
			local destroyingConn = partDestroyingConnections[part]
			if destroyingConn then
				destroyingConn:Disconnect()
				partDestroyingConnections[part] = nil
			end
		else
			partRefCount[part] = count
		end
	end

	local function addPart(part: BasePart)
		local count = (partRefCount[part] or 0) + 1
		partRefCount[part] = count

		-- Only create the zone if this is the first time
		if count == 1 then
			local newZone = Zone.fromPart(part, {
				isDynamic = isDynamic,
				metadata = zones.metadata,
				autoSync = autoSync,
			})
			instanceToZone[part] = newZone
			zones:add(newZone)

			if partDestroyingConnections[part] == nil then
				partDestroyingConnections[part] = part.Destroying:Connect(function()
					partRefCount[part] = 1
					removePart(part)
				end)
			end
		end
	end

	local function processTaggedInstance(instance: Instance)
		local inWorkspace = instance:IsDescendantOf(workspace)
		if inWorkspace then
			if instance:IsA('BasePart') then
				addPart(instance)
			else
				if not containerConnections[instance] then
					local addedConn = instance.DescendantAdded:Connect(function(descendant)
						if descendant:IsA('BasePart') then
							addPart(descendant)
						end
					end)
					local removedConn = instance.DescendantRemoving:Connect(function(descendant)
						if descendant:IsA('BasePart') then
							removePart(descendant)
						end
					end)
					containerConnections[instance] = { addedConn, removedConn }

					for _, descendant in instance:GetDescendants() do
						if descendant:IsA('BasePart') then
							addPart(descendant)
						end
					end
				end
			end
		else
			if instance:IsA('BasePart') then
				removePart(instance)
			else
				local conns = containerConnections[instance]
				if conns then
					conns[1]:Disconnect()
					conns[2]:Disconnect()
					containerConnections[instance] = nil
				end
				for _, descendant in instance:GetDescendants() do
					if descendant:IsA('BasePart') then
						removePart(descendant)
					end
				end
			end
		end
	end

	local function startWatching(instance: Instance)
		if watchingAncestry[instance] then
			return
		end
		watchingAncestry[instance] = instance.AncestryChanged:Connect(function()
			processTaggedInstance(instance)
		end)
		processTaggedInstance(instance)
	end

	local function stopWatching(instance: Instance)
		local conn = watchingAncestry[instance]
		if conn then
			conn:Disconnect()
			watchingAncestry[instance] = nil
		end

		if instance:IsA('BasePart') then
			removePart(instance)
		else
			local conns = containerConnections[instance]
			if conns then
				conns[1]:Disconnect()
				conns[2]:Disconnect()
				containerConnections[instance] = nil
			end
			for _, descendant in instance:GetDescendants() do
				if descendant:IsA('BasePart') then
					removePart(descendant)
				end
			end
		end
	end

	local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(startWatching)
	local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(stopWatching)
	for _, instance in CollectionService:GetTagged(tag) do
		startWatching(instance)
	end

	zones:onDestroy(function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		for inst in watchingAncestry do
			stopWatching(inst)
		end
		for _, conn in partDestroyingConnections do
			conn:Disconnect()
		end
		table.clear(watchingAncestry)
		table.clear(containerConnections)
		table.clear(partDestroyingConnections)
		table.clear(instanceToZone)
		table.clear(partRefCount)
	end)

	return zones
end

-- private
function Zone.attach(self: Types.InternalZone, observer: Types.InternalObserver): Types.Zone
	if self.destroyed then
		return self
	end

	local attached = State.zoneAttachedObservers[self.slot] or {}
	State.zoneAttachedObservers[self.slot] = attached

	if not table.find(attached, observer.id) then
		table.insert(attached, observer.id)
		State.zoneSoleObserver[self.slot] = if #attached == 1 then attached[1] else nil
		updateObserverZoneCount(observer.id, self.dynamic, 1)
		ZoneShapes.touch(self.slot, self.dynamic)

		if self.detachedObservers then
			self.detachedObservers[observer.id] = nil
		end
	end

	return self
end

-- private
function Zone.detach(self: Types.InternalZone, observer: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.slot]
	if not attached then
		return self
	end

	local idx = table.find(attached, observer.id)
	if idx then
		local lastIdx = #attached
		if idx ~= lastIdx then
			attached[idx] = attached[lastIdx]
		end
		attached[lastIdx] = nil
		State.zoneSoleObserver[self.slot] = if #attached == 1 then attached[1] else nil
		updateObserverZoneCount(observer.id, self.dynamic, -1)
		ZoneShapes.touch(self.slot, self.dynamic)

		-- Its entities leave on the next tick, unless the zone is destroyed first
		local detached = self.detachedObservers or {}
		detached[observer.id] = true
		self.detachedObservers = detached
	end

	if #attached == 0 then
		State.zoneAttachedObservers[self.slot] = nil
	end

	return self
end

--[=[ 
	Enables or disables automatic polling and syncing to the tracked BasePart.
	If the zone is currently static, it will automatically be set to dynamic.

	@tag Chainable
	@method setAutoSync
	@within Zone
	@param autoSync boolean
	@return Zone
]=]
function Zone.setAutoSync(self: Types.InternalZone, autoSync: boolean): Types.Zone
	if self.autoSync == autoSync then
		return self
	end

	self.autoSync = autoSync
	if autoSync then
		if not self.dynamic then
			self:setDynamic(true)
		end

		if self.reference then
			setupAutoSync(self, self.reference)
		else
			Log.warn('Cannot autoSync Zone %d without a tracked reference.', nil, self.id)
		end
	else
		clearAutoSync(self)
	end

	return self
end

--[=[ 
	Updates the tracked reference for this zone. If `autoSync` is enabled, 
	the zone will immediately start syncing to the new reference.

	@tag Chainable
	@method setReference
	@within Zone
	@param reference (BasePart | Attachment | Bone)?
	@return Zone
]=]
function Zone.setReference(self: Types.InternalZone, reference: (BasePart | Attachment | Bone)?): Types.Zone
	self.reference = reference

	local currentShape = if self.dynamic then dynamicTypes[self.slot] else staticTypes[self.slot]
	if currentShape == MESH_SHAPE_VALUE then
		-- Mesh zones query the part directly, so the new reference has to take over.
		-- Without a queryable part the zone falls back to its bounding box.
		applyShapeType(self.slot, self.dynamic, MESH_SHAPE_VALUE, asQueryablePart(reference))
		ZoneShapes.refresh(self.slot)
	end

	if self.autoSync then
		clearAutoSync(self)
		if reference then
			setupAutoSync(self, reference)
		end
	end

	return self
end

--[=[ 
	Update the zone to the reference. For a part-based zone, this will sync the zone's 
	CFrame, Size and Shape to match the reference's. For attachment/bone-based zones, 
	only the WorldCFrame is synced.

	:::info Rebuild
	This method flags the zone for an update. The actual tree rebuild is batched and occurs once per frame.
	* Static Zones: Expensive. Forces a rebuild of the main static tree.
	* Dynamic Zones: Cheap. Forces a rebuild of the smaller dynamic tree.
	:::

	@tag Chainable
	@method sync
	@within Zone
	@return Zone
]=]
function Zone.sync(self: Types.InternalZone): Types.Zone
	local reference = self.reference
	if not reference then
		Log.warn('Zone:sync failed for Zone %d. No reference found.', nil, self.id)
		return self
	end

	local slot = self.slot

	if reference:IsA('BasePart') then
		local newCFrame = reference.CFrame
		local newHalfSize = reference.ExtentsSize * 0.5
		local newShape = getShapeEnumValue(reference)

		if self.dynamic then
			local needsUpdate = false

			if dynamicCFrames[slot] ~= newCFrame then
				dynamicCFrames[slot] = newCFrame
				needsUpdate = true
			end

			if dynamicHalfSizes[slot] ~= newHalfSize then
				dynamicHalfSizes[slot] = newHalfSize
				needsUpdate = true
			end

			if
				dynamicTypes[slot] ~= newShape or (newShape == MESH_SHAPE_VALUE and dynamicMeshes[slot] ~= reference)
			then
				applyShapeType(slot, true, newShape, reference)
				needsUpdate = true
			end

			if needsUpdate then
				ZoneShapes.refresh(slot)
				State.pendingDynamicRebuild = true
			end
		else
			local needsUpdate = false

			if staticCFrames[slot] ~= newCFrame then
				staticCFrames[slot] = newCFrame
				needsUpdate = true
			end

			if staticHalfSizes[slot] ~= newHalfSize then
				staticHalfSizes[slot] = newHalfSize
				needsUpdate = true
			end

			if staticTypes[slot] ~= newShape or (newShape == MESH_SHAPE_VALUE and staticMeshes[slot] ~= reference) then
				applyShapeType(slot, false, newShape, reference)
				needsUpdate = true
			end

			if needsUpdate then
				ZoneShapes.refresh(slot)
				State.pendingStaticRebuild = true
			end
		end

		return self
	end

	if reference:IsA('Attachment') or reference:IsA('Bone') then
		local newCFrame = reference.WorldCFrame
		if self.dynamic then
			if dynamicCFrames[slot] == newCFrame then
				return self
			end

			dynamicCFrames[slot] = newCFrame
			ZoneShapes.refresh(slot)
			State.pendingDynamicRebuild = true
		else
			if staticCFrames[slot] == newCFrame then
				return self
			end

			staticCFrames[slot] = newCFrame
			ZoneShapes.refresh(slot)
			State.pendingStaticRebuild = true
		end

		return self
	end

	return self
end

--[=[ 
	Promotes or demotes a zone between the Static and Dynamic trees.
	
	:::info Performance
	Changing a zone's dynamic state forces both the static and dynamic trees to rebuild. 
	Use this sparingly (e.g., when a static bridge breaks and becomes dynamic).
	:::

	@tag Chainable
	@method setDynamic
	@within Zone
	@param isDynamic boolean
	@return Zone
]=]
function Zone.setDynamic(self: Types.InternalZone, isDynamic: boolean): Types.Zone
	if self.dynamic == isDynamic then
		return self
	end

	local slot = self.slot
	self.dynamic = isDynamic

	local attached = State.zoneAttachedObservers[slot]
	if attached then
		for _, obsId in attached do
			updateObserverZoneCount(obsId, not isDynamic, -1)
			updateObserverZoneCount(obsId, isDynamic, 1)
		end
	end

	if isDynamic then
		dynamicCFrames[slot] = staticCFrames[slot]
		dynamicHalfSizes[slot] = staticHalfSizes[slot]
		dynamicTypes[slot] = staticTypes[slot]
		dynamicMeshes[slot] = staticMeshes[slot]

		staticCFrames[slot] = nil
		staticHalfSizes[slot] = nil
		staticTypes[slot] = nil
		staticMeshes[slot] = nil
	else
		if self.autoSync then
			self:setAutoSync(false)
		end

		staticCFrames[slot] = dynamicCFrames[slot]
		staticHalfSizes[slot] = dynamicHalfSizes[slot]
		staticTypes[slot] = dynamicTypes[slot]
		staticMeshes[slot] = dynamicMeshes[slot]

		dynamicCFrames[slot] = nil
		dynamicHalfSizes[slot] = nil
		dynamicTypes[slot] = nil
		dynamicMeshes[slot] = nil
	end

	State.pendingStaticRebuild = true
	State.pendingDynamicRebuild = true
	State.staticTree.membersChanged = true
	State.dynamicTree.membersChanged = true

	return self
end

--[=[ 
	Updates the Zone's CFrame.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Chainable
	@method setCFrame
	@within Zone
	@param cf CFrame
	@return Zone
]=]
function Zone.setCFrame(self: Types.InternalZone, cf: CFrame): Types.Zone
	if self.dynamic then
		dynamicCFrames[self.slot] = cf
		State.pendingDynamicRebuild = true
	else
		staticCFrames[self.slot] = cf
		State.pendingStaticRebuild = true
	end
	ZoneShapes.refresh(self.slot)
	return self
end

--[=[ 
	Updates the Zone's Position while preserving its current Rotation.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::

	@tag Chainable
	@method setPosition
	@within Zone
	@param pos Vector3
	@return Zone
]=]
function Zone.setPosition(self: Types.InternalZone, pos: Vector3): Types.Zone
	local currentCF = self.dynamic and dynamicCFrames[self.slot] or staticCFrames[self.slot]
	local newCF = currentCF.Rotation + pos
	return self:setCFrame(newCF)
end

--[=[ 
	Updates the Zone's Size.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::
	
	@tag Chainable
	@method setSize
	@within Zone
	@param size Vector3
	@return Zone
]=]
function Zone.setSize(self: Types.InternalZone, size: Vector3): Types.Zone
	local halfSize = size * 0.5

	if self.dynamic then
		dynamicHalfSizes[self.slot] = halfSize
		State.pendingDynamicRebuild = true
	else
		staticHalfSizes[self.slot] = halfSize
		State.pendingStaticRebuild = true
	end
	ZoneShapes.refresh(self.slot)
	return self
end

--[=[ 
	Updates the Zone's geometric shape.
	
	@tag Chainable
	@method setShape
	@within Zone
	@param shape ShapeType
	@return Zone
]=]
function Zone.setShape(self: Types.InternalZone, shape: Types.ShapeType): Types.Zone
	local shapeType = Enum.PartType.Block.Value

	local mapped = SHAPE_MAP[shape]
	if mapped then
		shapeType = mapped
	else
		Log.warn("Invalid shape '%s'. Defaulting to Block.", nil, tostring(shape))
	end

	applyShapeType(self.slot, self.dynamic, shapeType, asQueryablePart(self.reference))
	ZoneShapes.refresh(self.slot)

	if self.dynamic then
		State.pendingDynamicRebuild = true
	else
		State.pendingStaticRebuild = true
	end

	return self
end

--[=[ 
	Set the metadata of the zone.

	@tag Chainable
	@method setMetadata
	@within Zone
	@param metadata any?
	@return Zone
]=]
function Zone.setMetadata(self: Types.InternalZone, metadata: any?): Types.Zone
	self.metadata = metadata
	return self
end

--[=[ 
	Returns the metadata of the zone.
	
	@method getMetadata
	@within Zone
	@return any?
]=]
function Zone.getMetadata(self: Types.InternalZone): any?
	return self.metadata
end

--[=[ 
	Returns the unique internal ID of the zone.

	@method getId
	@within Zone
	@return number
]=]
function Zone.getId(self: Types.InternalZone): number
	return self.id
end

--[=[
	Returns the reference associated with this zone, if any.

	@method getReference
	@within Zone
	@return (BasePart | Attachment | Bone)?
]=]
function Zone.getReference(self: Types.InternalZone): (BasePart | Attachment | Bone)?
	return self.reference
end

--[=[
	Returns the current position of the zone.

	@method getPosition
	@within Zone
	@return Vector3
]=]
function Zone.getPosition(self: Types.InternalZone): Vector3
	local cf = self.dynamic and dynamicCFrames[self.slot] or staticCFrames[self.slot]
	return cf.Position
end

--[=[
	Returns the current CFrame of the zone.

	@method getCFrame
	@within Zone
	@return CFrame
]=]
function Zone.getCFrame(self: Types.InternalZone): CFrame
	return self.dynamic and dynamicCFrames[self.slot] or staticCFrames[self.slot]
end

--[=[
	Returns the full size of the zone.

	@method getSize
	@within Zone
	@return Vector3
]=]
function Zone.getSize(self: Types.InternalZone): Vector3
	local halfSize = self.dynamic and dynamicHalfSizes[self.slot] or staticHalfSizes[self.slot]
	return halfSize * 2
end

--[=[ 
	Returns the geometric shape type of the zone.

	@method getShape
	@within Zone
	@return ShapeType
]=]
function Zone.getShape(self: Types.InternalZone): Types.ShapeType
	local shapeType = self.dynamic and dynamicTypes[self.slot] or staticTypes[self.slot]
	if shapeType == Enum.PartType.Block.Value then
		return 'Block'
	elseif shapeType == Enum.PartType.Ball.Value then
		return 'Ball'
	elseif shapeType == Enum.PartType.Cylinder.Value then
		return 'Cylinder'
	elseif shapeType == Enum.PartType.Wedge.Value then
		return 'Wedge'
	elseif shapeType == Enum.PartType.CornerWedge.Value then
		return 'CornerWedge'
	elseif shapeType == MESH_SHAPE_VALUE then
		return 'Mesh'
	end
	return 'Block'
end

--[=[ 
	Checks if a point is inside this specific zone.

	@method isPointInside
	@within Zone
	@param point Vector3
	@return boolean
]=]
function Zone.isPointInside(self: Types.InternalZone, point: Vector3): boolean
	return ZoneShapes.containsPoint(self.slot, point)
end

--[=[ 
	Returns whether the zone is currently registered as a dynamic object.
	
	@method isDynamic
	@within Zone
	@return boolean
]=]
function Zone.isDynamic(self: Types.InternalZone): boolean
	return self.dynamic
end

--[=[ 
	Fires when `destroy()` is called on the zone

	```lua
	local disconnect = myZone:onDestroy(function()
		print('Zone was destroyed!')
	end)
	```

	@tag Event
	@method onDestroy
	@within Zone
	@param callback () -> ()
	@return () -> () -- Disconnect function
]=]
function Zone.onDestroy(self: Types.InternalZone, callback: () -> ()): () -> ()
	if not self.onDestroyCallbacks then
		self.onDestroyCallbacks = {}
	end

	table.insert(self.onDestroyCallbacks :: any, callback)

	return function()
		local idx = table.find(self.onDestroyCallbacks :: any, callback)
		if idx then
			table.remove(self.onDestroyCallbacks :: any, idx)
		end
	end
end

--[=[ 
	Cleans up the zone, removes it from the LBVH tree, and detaches all observers.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::
	
	@tag Destructor
	@method destroy
	@within Zone
]=]
function Zone.destroy(self: Types.InternalZone): ()
	-- A callback below may destroy the zone again, which would release its slot twice
	if self.destroyed then
		return
	end
	self.destroyed = true

	clearAutoSync(self)

	local id = self.id
	local slot = self.slot

	-- Detach before any callback runs, so a callback detaching again is a no-op
	local attachedObservers = State.zoneAttachedObservers[slot]
	State.zoneAttachedObservers[slot] = nil
	State.zoneSoleObserver[slot] = nil

	-- Exit while the zone object is still alive, so callbacks get it
	if attachedObservers then
		for _, observerId in attachedObservers do
			updateObserverZoneCount(observerId, self.dynamic, -1)
		end
		for _, observerId in attachedObservers do
			exitEntities(self, observerId)
		end
	end

	-- Observers detached since the last tick still have entities here
	local detachedObservers = self.detachedObservers
	if detachedObservers then
		self.detachedObservers = nil
		for observerId in detachedObservers do
			exitEntities(self, observerId)
		end
	end

	if self.onDestroyCallbacks then
		-- The table must be cloned to avoid iterator shifts
		local onDestroyCallbacks = table.clone(self.onDestroyCallbacks)
		for _, callback in onDestroyCallbacks do
			task.spawn(callback)
		end
		table.clear(self.onDestroyCallbacks)
	end

	State.zoneIdToZoneObj[id] = nil
	State.zoneSlotToZoneObj[slot] = nil
	State.zoneSlotIds[slot] = nil

	if self.dynamic then
		dynamicCFrames[slot] = nil
		dynamicHalfSizes[slot] = nil
		dynamicTypes[slot] = nil
		dynamicMeshes[slot] = nil
		State.pendingDynamicRebuild = true
		State.dynamicTree.membersChanged = true
	else
		staticCFrames[slot] = nil
		staticHalfSizes[slot] = nil
		staticTypes[slot] = nil
		staticMeshes[slot] = nil
		State.pendingStaticRebuild = true
		State.staticTree.membersChanged = true
	end
	ZoneShapes.remove(slot, self.dynamic)

	-- Reusable after the next rebuild
	table.insert(State.releasedZoneSlots, slot)

	setmetatable(self :: any, nil)
end

return Zone

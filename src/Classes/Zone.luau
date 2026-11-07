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

local Registry = require(script.Parent.Parent.Core.Registry)
local Wiring = require(script.Parent.Parent.Core.Wiring)
local ZoneShapes = require(script.Parent.Parent.Core.ZoneShapes)
local Types = require(script.Parent.Parent.Types)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Geometry = require(script.Parent.Parent.Utils.Geometry)
local Log = require(script.Parent.Parent.Utils.Log)
local ZoneContainers = require(script.Parent.ZoneContainers)

local shapeCFrames = ZoneShapes.shapeCFrames
local shapeHalfSizes = ZoneShapes.shapeHalfSizes
local shapeTypes = ZoneShapes.shapeTypes

local BLOCK_SHAPE_VALUE = Geometry.BLOCK_SHAPE_VALUE
local MESH_SHAPE_VALUE = Geometry.MESH_SHAPE_VALUE
local WEDGE_SHAPE_VALUE = Geometry.WEDGE_SHAPE_VALUE
local CORNER_WEDGE_SHAPE_VALUE = Geometry.CORNER_WEDGE_SHAPE_VALUE

local SHAPE_MAP: { [string]: number } = {
	Block = BLOCK_SHAPE_VALUE,
	Cylinder = Geometry.CYLINDER_SHAPE_VALUE,
	Ball = Geometry.BALL_SHAPE_VALUE,
	Wedge = WEDGE_SHAPE_VALUE,
	CornerWedge = CORNER_WEDGE_SHAPE_VALUE,
	Mesh = MESH_SHAPE_VALUE,
}
local SHAPE_NAMES = {} :: { [number]: Types.ShapeType }
for name, value in SHAPE_MAP do
	SHAPE_NAMES[value] = name :: any
end

-- The shape type of a shape name, Block for one that isn't
local function shapeValueOf(shape: any): number
	local mapped = SHAPE_MAP[shape]
	if not mapped then
		Log.warn("Invalid shape '%s'. Defaulting to Block.", nil, tostring(shape))
	end
	return mapped or BLOCK_SHAPE_VALUE
end

local function getShapeEnumValue(part: BasePart): number
	if part:IsA('Part') then
		return part.Shape.Value
	end

	if part:IsA('MeshPart') or part:IsA('PartOperation') then
		return MESH_SHAPE_VALUE
	end

	if part:IsA('WedgePart') then
		return WEDGE_SHAPE_VALUE
	end

	if part:IsA('CornerWedgePart') then
		return CORNER_WEDGE_SHAPE_VALUE
	end

	return BLOCK_SHAPE_VALUE
end

local function asQueryablePart(reference: (BasePart | Attachment | Bone)?): BasePart?
	if typeof(reference) == 'Instance' and reference:IsA('BasePart') then
		return reference
	end
	return nil
end

-- The shape type and the part it queries. Mesh zones need a part, and fall back to Block without one
local function resolveShape(zoneId: number, shapeType: number, part: BasePart?): (number, BasePart?)
	if shapeType ~= MESH_SHAPE_VALUE then
		return shapeType, nil
	end

	if not part then
		Log.warn("Shape 'Mesh' requires a BasePart reference. Defaulting Zone %d to Block.", nil, zoneId)
		return BLOCK_SHAPE_VALUE, nil
	end

	return shapeType, part
end

-- Sets the shape asked for. It is kept, so a Mesh zone that fell back to Block is Mesh again once it has a part
local function applyShape(zone: Types.InternalZone, shapeType: number)
	zone.requestedShapeType = shapeType
	ZoneShapes.setShape(zone.slot, resolveShape(zone.id, shapeType, asQueryablePart(zone.reference)))
end

local function clearAutoSync(zone: Types.InternalZone)
	Registry.autoSyncZones[zone.slot] = nil
	if zone.syncConnections then
		for _, conn in zone.syncConnections do
			conn:Disconnect()
		end
		zone.syncConnections = nil
	end
end

local function setupAutoSync(zone: Types.InternalZone, reference: BasePart | Attachment | Bone)
	-- A callback during destroy must not start syncing the zone again
	if Destroyed.isDestroyed(zone) then
		return
	end

	-- Each tick reads its CFrame, so anything else would make every tick error
	if typeof(reference) ~= 'Instance' or not (reference:IsA('BasePart') or reference:IsA('Attachment')) then
		Log.warn(
			'Cannot autoSync Zone %d to %s. Use a BasePart, Attachment or Bone.',
			nil,
			zone.id,
			if typeof(reference) == 'Instance' then reference.ClassName else typeof(reference)
		)
		return
	end

	Registry.autoSyncZones[zone.slot] = zone

	local connections = zone.syncConnections or {}

	if reference:IsA('BasePart') then
		table.insert(
			connections,
			reference:GetPropertyChangedSignal('Size'):Connect(function()
				ZoneShapes.setHalfSize(zone.slot, reference.ExtentsSize * 0.5)
			end)
		)
	end

	if reference:IsA('Part') then
		table.insert(
			connections,
			reference:GetPropertyChangedSignal('Shape'):Connect(function()
				applyShape(zone, reference.Shape.Value)
			end)
		)
	end

	zone.syncConnections = connections
	zone:sync()
end

-- Checked before a setter writes, as a bad value stored in the zone would break every later write
local function checkCFrame(cframe: any)
	if typeof(cframe) ~= 'CFrame' then
		Log.fatal('Zone cframe must be a CFrame, got %s.', nil, typeof(cframe))
	end
end

local function checkSize(size: any)
	if typeof(size) ~= 'Vector3' then
		Log.fatal('Zone size must be a Vector3, got %s.', nil, typeof(size))
	end
end

local function checkReference(reference: any)
	if reference ~= nil and typeof(reference) ~= 'Instance' then
		Log.fatal('Zone reference must be a BasePart, Attachment or Bone, got %s.', nil, typeof(reference))
	end
end

local Zone = {}
Zone.__index = Zone

type PartsConfig = Types.PartsConfig

local function newZoneInternal(
	cframe: CFrame,
	size: Vector3,
	shapeType: number,
	reference: (BasePart | Attachment | Bone)?,
	isDynamic: boolean,
	metadata: any?,
	autoSync: boolean
): Types.Zone
	-- Checked before anything is registered, so a bad config can't leave a broken slot in the tree
	checkCFrame(cframe)
	checkSize(size)
	checkReference(reference)

	local id = Registry.nextZoneId
	Registry.nextZoneId += 1

	local slot = ZoneShapes.allocateSlot(id)

	local resolvedType, part = resolveShape(id, shapeType, asQueryablePart(reference))
	ZoneShapes.add(slot, isDynamic, cframe, size * 0.5, resolvedType, part)

	local self: Types.InternalZone = setmetatable({
		id = id,
		phase = 'alive',
		slot = slot,
		requestedShapeType = shapeType,
		reference = reference,
		metadata = metadata,
		autoSync = false,
	}, Zone) :: any
	Registry.zoneIdToZoneObj[id] = self
	Registry.zoneSlotToZoneObj[slot] = self

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
	@param config { cframe: CFrame, size: Vector3, shape: Types.ShapeType?, reference: (BasePart | Attachment | Bone)?, isDynamic: boolean?, metadata: any?, autoSync: boolean? }
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
	if type(config) ~= 'table' then
		Log.fatal('Zone.new expects a config table, got %s.', nil, typeof(config))
	end

	return newZoneInternal(
		config.cframe,
		config.size,
		if config.shape then shapeValueOf(config.shape) else BLOCK_SHAPE_VALUE,
		config.reference,
		not not config.isDynamic,
		config.metadata,
		not not config.autoSync
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
function Zone.fromPart(part: BasePart, config: PartsConfig?): Types.Zone
	if typeof(part) ~= 'Instance' or not part:IsA('BasePart') then
		Log.fatal('Zone.fromPart expects a BasePart, got %s.', nil, tostring(part))
	end

	local shapeId = getShapeEnumValue(part)

	local isDynamic = config ~= nil and not not config.isDynamic
	local metadata = config and config.metadata
	local autoSync = config ~= nil and not not config.autoSync

	return newZoneInternal(part.CFrame, part.ExtentsSize, shapeId, part, isDynamic, metadata, autoSync)
end

-- Kept for scripts that attach from the zone. Observer:attach is the way to do it
function Zone.attach(self: Types.InternalZone, observer: any): Types.Zone
	if not Destroyed.isDead(observer) then
		observer:attach(self)
	end
	return self
end

-- Kept for scripts that detach from the zone. Observer:detach is the way to do it
function Zone.detach(self: Types.InternalZone, observer: any): Types.Zone
	if not Destroyed.isDead(observer) then
		observer:detach(self)
	end
	return self
end

--[=[ 
	Enables or disables automatic polling and syncing to the tracked BasePart.
	If the zone is currently static, it will automatically be set to dynamic.
	A zone without a reference warns and starts syncing once `setReference` gives it one.

	@tag Chainable
	@method setAutoSync
	@within Zone
	@param autoSync boolean
	@return Zone
]=]
function Zone.setAutoSync(self: Types.InternalZone, autoSync: boolean): Types.Zone
	autoSync = not not autoSync
	if self.autoSync == autoSync then
		return self
	end

	self.autoSync = autoSync
	if autoSync then
		if not ZoneShapes.isDynamic(self.slot) then
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
	checkReference(reference)
	self.reference = reference

	if self.requestedShapeType == MESH_SHAPE_VALUE then
		-- Mesh zones query the part directly, so the new reference has to take over.
		-- Without a queryable part the zone falls back to its bounding box.
		applyShape(self, MESH_SHAPE_VALUE)
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

	if reference:IsA('BasePart') then
		self.requestedShapeType = getShapeEnumValue(reference)
		local shapeType, part = resolveShape(self.id, self.requestedShapeType, reference)
		ZoneShapes.set(self.slot, reference.CFrame, reference.ExtentsSize * 0.5, shapeType, part)
	elseif reference:IsA('Attachment') or reference:IsA('Bone') then
		ZoneShapes.setCFrame(self.slot, reference.WorldCFrame)
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
	-- A boolean, as the observers' zone counts below assume the zone really changes tree
	isDynamic = not not isDynamic
	if not Wiring.setZoneDynamic(self.slot, isDynamic) then
		return self
	end

	if not isDynamic and self.autoSync then
		self:setAutoSync(false)
	end

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
	checkCFrame(cf)
	ZoneShapes.setCFrame(self.slot, cf)
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
	if typeof(pos) ~= 'Vector3' then
		Log.fatal('Zone position must be a Vector3, got %s.', nil, typeof(pos))
	end
	return self:setCFrame(shapeCFrames[self.slot].Rotation + pos)
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
	checkSize(size)
	ZoneShapes.setHalfSize(self.slot, size * 0.5)
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
	applyShape(self, shapeValueOf(shape))
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
	return shapeCFrames[self.slot].Position
end

--[=[
	Returns the current CFrame of the zone.

	@method getCFrame
	@within Zone
	@return CFrame
]=]
function Zone.getCFrame(self: Types.InternalZone): CFrame
	return shapeCFrames[self.slot]
end

--[=[
	Returns the full size of the zone.

	@method getSize
	@within Zone
	@return Vector3
]=]
function Zone.getSize(self: Types.InternalZone): Vector3
	return shapeHalfSizes[self.slot] * 2
end

--[=[ 
	Returns the geometric shape type of the zone.

	@method getShape
	@within Zone
	@return ShapeType
]=]
function Zone.getShape(self: Types.InternalZone): Types.ShapeType
	return SHAPE_NAMES[shapeTypes[self.slot]] or 'Block'
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
	return ZoneShapes.isDynamic(self.slot)
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
	return Destroyed.connect(self, callback)
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
	if not Destroyed.begin(self) then
		return
	end

	clearAutoSync(self)
	self.autoSync = false

	local id = self.id
	local slot = self.slot

	Wiring.unwireZone(slot, id)

	Destroyed.fireCallbacks(self.onDestroyCallbacks)

	Registry.zoneIdToZoneObj[id] = nil
	Registry.zoneSlotToZoneObj[slot] = nil
	ZoneShapes.remove(slot)

	Destroyed.finish(self)
end

-- The constructors that keep a Zones in step with a set of parts are kept in their own file
ZoneContainers.setZone(Zone)
Zone.fromParts = ZoneContainers.fromParts
Zone.fromChildren = ZoneContainers.fromChildren
Zone.fromDescendants = ZoneContainers.fromDescendants
Zone.fromTag = ZoneContainers.fromTag

return Zone

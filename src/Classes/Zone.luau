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
local SyncMode = require(script.Parent.Parent.Utils.SyncMode)
local ZoneContainers = require(script.Parent.ZoneContainers)

local shapePositions = ZoneShapes.shapePositions
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

local function setMeshRequested(zone: Types.InternalZone, shapeType: number)
	local requested = shapeType == MESH_SHAPE_VALUE
	if requested ~= (zone.meshRequested == true) then
		zone.meshRequested = if requested then true else nil
	end
end

local function applyShape(zone: Types.InternalZone, shapeType: number)
	setMeshRequested(zone, shapeType)
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
	if Destroyed.isDestroyed(zone) then
		return
	end

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

local function followReference(zone: Types.InternalZone)
	clearAutoSync(zone)
	if zone.autoSync and zone.reference then
		setupAutoSync(zone, zone.reference)
	end
end

local function syncModeOf(zone: Types.InternalZone): Types.SyncMode
	return SyncMode.of(ZoneShapes.isDynamic(zone.slot), zone.autoSync == true)
end

local function setSyncMode(zone: Types.InternalZone, mode: Types.SyncMode)
	local autoSync = mode == 'synced'
	local syncChanged = (zone.autoSync == true) ~= autoSync
	if syncChanged then
		zone.autoSync = if autoSync then true else nil
	end
	Wiring.setZoneDynamic(zone.slot, mode ~= 'static')
	if syncChanged then
		followReference(zone)
	end
end

local function checkType(field: string, expected: string, value: any)
	if typeof(value) ~= expected then
		Log.fatal('Zone %s must be a %s, got %s.', nil, field, expected, typeof(value))
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
	checkType('cframe', 'CFrame', cframe)
	checkType('size', 'Vector3', size)
	checkReference(reference)

	local id = Registry.nextZoneId
	Registry.nextZoneId += 1

	local resolvedType, part = resolveShape(id, shapeType, asQueryablePart(reference))

	-- Only the fields every zone needs, so the table gets 2 slots. Writing even nil to a missing field adds a slot, so
	-- the others are set only when they hold something, and phase stays out until the zone is destroyed.
	local self: Types.InternalZone = setmetatable({
		id = id,
		slot = 0,
	}, Zone) :: any
	if shapeType == MESH_SHAPE_VALUE then
		self.meshRequested = true
	end
	if reference ~= nil then
		self.reference = reference
	end
	if metadata ~= nil then
		self.metadata = metadata
	end
	Wiring.addZone(self, isDynamic, cframe, size * 0.5, resolvedType, part)

	if autoSync then
		setSyncMode(self, 'synced')
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

function Zone.attach(self: Types.InternalZone, observer: any): Types.Zone
	if not Destroyed.isDead(observer) then
		observer:attach(self)
	end
	return self
end

function Zone.detach(self: Types.InternalZone, observer: any): Types.Zone
	if not Destroyed.isDead(observer) then
		observer:detach(self)
	end
	return self
end

--[=[ 
	Enables or disables automatic polling and syncing to the tracked BasePart.
	If the zone is currently static, it will automatically be set to dynamic.
	A zone without a reference starts syncing once `setReference` gives it one.

	@tag Chainable
	@method setAutoSync
	@within Zone
	@param autoSync boolean
	@return Zone
]=]
function Zone.setAutoSync(self: Types.InternalZone, autoSync: boolean): Types.Zone
	setSyncMode(self, SyncMode.withAutoSync(syncModeOf(self), autoSync))
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

	if self.meshRequested then
		applyShape(self, MESH_SHAPE_VALUE)
	end

	followReference(self)

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
		return self
	end

	if reference:IsA('BasePart') then
		local requested = getShapeEnumValue(reference)
		setMeshRequested(self, requested)
		local shapeType, part = resolveShape(self.id, requested, reference)
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
	setSyncMode(self, SyncMode.withDynamic(syncModeOf(self), isDynamic))
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
	if typeof(cf) ~= 'CFrame' then
		checkType('cframe', 'CFrame', cf)
	end
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
	checkType('position', 'Vector3', pos)
	return self:setCFrame(ZoneShapes.cframeOf(self.slot).Rotation + pos)
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
	checkType('size', 'Vector3', size)
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
	return shapePositions[self.slot]
end

--[=[
	Returns the current CFrame of the zone.

	@method getCFrame
	@within Zone
	@return CFrame
]=]
function Zone.getCFrame(self: Types.InternalZone): CFrame
	return ZoneShapes.cframeOf(self.slot)
end

--[=[
	Returns the full size of the zone.

	@method getSize
	@within Zone
	@return Vector3
]=]
function Zone.getSize(self: Types.InternalZone): Vector3
	return ZoneShapes.rawHalfSizeOf(self.slot) * 2
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
Zone.onDestroy = Destroyed.connect

--[=[ 
	Cleans up the zone, removes it from the LBVH tree, and detaches all observers.
	Destroying it again does nothing. Its other methods raise an error once it is destroyed.

	:::caution Rebuild Request
	Requests a rebuild of corresponding tree (batched per frame).
	:::
	
	@tag Destructor
	@method destroy
	@within Zone
]=]
function Zone.destroy(self: Types.InternalZone): ()
	if not Destroyed.begin(self) then
		return
	end

	self:setAutoSync(false)

	Wiring.removeZone(self)

	Destroyed.finish(self)
end

ZoneContainers.useFromPart(Zone.fromPart)
Zone.fromParts = ZoneContainers.fromParts
Zone.fromChildren = ZoneContainers.fromChildren
Zone.fromDescendants = ZoneContainers.fromDescendants
Zone.fromTag = ZoneContainers.fromTag

return Zone

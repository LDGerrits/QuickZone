--!strict

local Geometry = require(script.Parent.Parent.Core.Geometry)
local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes

local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes

local SHAPE_MAP = {
	Block = Enum.PartType.Block.Value,
	Cylinder = Enum.PartType.Cylinder.Value,
	Ball = Enum.PartType.Ball.Value,
	Wedge = Enum.PartType.Wedge.Value,
	CornerWedge = Enum.PartType.CornerWedge.Value,
}

local function getShapeEnumValue(part: BasePart): number
	if part:IsA('Part') then
		return part.Shape.Value
	end

	if part:IsA('WedgePart') then
		return Enum.PartType.Wedge.Value
	end

	if part:IsA('CornerWedgePart') then
		return Enum.PartType.CornerWedge.Value
	end

	-- Fallback for Meshes, Unions, CornerWedges, Trusses
	return Enum.PartType.Block.Value
end

--[=[ 
	Zones define physical areas in world space. They can be static or dynamic 
	and support shapes like Blocks, Balls, and Cylinders.
	
	Zones themselves are 'passive', meaning they must be attached to an Observer before any detection occurs.

	@class Zone
]=]
local Zone = {}
Zone.__index = Zone

local function newZoneInternal(
	cframe: CFrame,
	size: Vector3,
	shapeType: number,
	part: BasePart?,
	isDynamic: boolean,
	metadata: any?
): Types.Zone
	local id = State.nextZoneId
	State.nextZoneId += 1

	local halfSize = size * 0.5
	if isDynamic then
		State.dynamicCFrames[id] = cframe
		State.dynamicHalfSizes[id] = halfSize
		State.dynamicTypes[id] = shapeType
		State.pendingDynamicRebuild = true
	else
		State.staticCFrames[id] = cframe
		State.staticHalfSizes[id] = halfSize
		State.staticTypes[id] = shapeType
		State.pendingStaticRebuild = true
	end

	local self = setmetatable({
		id = id,
		part = part,
		dynamic = isDynamic,
		metadata = metadata,
	}, Zone)

	State.zoneIdToZoneObj[id] = self :: any
	return self :: any
end

--[=[ 
	Creates a Zone object.

	```lua
	local zone = QuickZone.Zone({
		cframe = CFrame.new(0, 10, 0),
		size = Vector3.new(10, 10, 10),
		shape = 'Block',
		metadata = { Name = "Lobby" }
	})
	```

	:::caution Performance
	If this zone moves (e.g., attached to a moving platform) or changes size, 
	you **must** set `isDynamic` to `true`. 

	Static zones are optimized into a large, pre-calculated tree. Updating a 
	static zone forces a full recalculation of that tree, which is expensive. 
	Dynamic zones are handled separately and are much cheaper to update.
	:::

	@tag Constructor
	@param config ZoneConfig
	@return Zone
]=]
function Zone.new(config: Types.ZoneConfig): Types.Zone
	local shapeType = Enum.PartType.Block.Value

	if config.shape then
		local mapped = SHAPE_MAP[config.shape]
		if mapped then
			shapeType = mapped
		else
			warn(`[QuickZone] Invalid shape '{config.shape}'. Defaulting to Block.`)
		end
	end

	return newZoneInternal(
		config.cframe,
		config.size,
		shapeType,
		config.part,
		config.isDynamic or false,
		config.metadata
	)
end

--[=[ 
	Creates a Zone automatically based on a Part's properties.
	Supported shapes: Block, Ball (Spheres), Cylinder, and Wedge.

	@tag Constructor
	@param part BasePart -- The part to derive the zone from.
	@param config { isDynamic: boolean?, metadata: any? }?
	@return Zone
]=]
function Zone.fromPart(part: BasePart, config: { isDynamic: boolean?, metadata: any? }?): Types.Zone
	local shapeId = Enum.PartType.Block.Value
	if part:IsA('Part') then
		shapeId = part.Shape.Value
	elseif part:IsA('WedgePart') then
		shapeId = Enum.PartType.Wedge.Value
	elseif part:IsA('CornerWedgePart') then
		shapeId = Enum.PartType.CornerWedge.Value
	end

	local isDynamic = config and config.isDynamic or false
	local metadata = config and config.metadata

	return newZoneInternal(part.CFrame, part.Size, shapeId, part, isDynamic, metadata)
end

--[=[ 
	Create a list of zones corresponding to the list of `BaseParts`.
	Each zone corresponds to a `BasePart` and shares the same properties.

	@tag Constructor
	@param part { BasePart } -- The parts to derive the zones from.
	@param config { isDynamic: boolean?, metadata: any? }? -- Optional config shared across all zones
	@return { Zone }
]=]
function Zone.fromParts(parts: { BasePart }, config: { isDynamic: boolean?, metadata: any? }?): { Types.Zone }
	local zones = table.create(#parts)
	local isDynamic = config and config.isDynamic or false
	local metadata = config and config.metadata

	for i, part in parts do
		local shapeId = Enum.PartType.Block.Value
		if part:IsA('Part') then
			shapeId = part.Shape.Value
		elseif part:IsA('WedgePart') then
			shapeId = Enum.PartType.Wedge.Value
		elseif part:IsA('CornerWedgePart') then
			shapeId = Enum.PartType.CornerWedge.Value
		end

		zones[i] = newZoneInternal(part.CFrame, part.Size, shapeId, part, isDynamic, metadata)
	end

	return zones
end

--[=[ 
	Attaches an Observer to this zone. The observer will begin 
	monitoring this area for entity overlaps.

	```lua
	-- You are also able to chain calls
	zone:attach(damageObserver)
		:attach(visualObserver)
		:attach(soundObserver)
	```

	@method attach
	@within Zone
	@param observer Observer -- The observer to link.
	@return Zone
]=]
function Zone.attach(self: Types.InternalZone, observer: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id] or {}
	State.zoneAttachedObservers[self.id] = attached

	if not table.find(attached, observer.id) then
		table.insert(attached, observer.id)
	end

	State.isDirty = true
	return self
end

--[=[ 
	Detaches observer from this zone.

	@method detach
	@within Zone
	@param observer Observer -- The observer to unlink.
	@return Zone
]=]
function Zone.detach(self: Types.InternalZone, observer: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id]
	if not attached then
		return self
	end

	local idx = table.find(attached, observer.id)
	while idx do
		table.remove(attached, idx)
		idx = table.find(attached, observer.id)
	end

	if #attached == 0 then
		State.zoneAttachedObservers[self.id] = nil
	end
	State.isDirty = true

	return self
end

--[=[ 
	Update the zone to the part's current CFrame, Size and Shape.

	@method syncToPart
	@within Zone
	@return Zone
]=]
function Zone.syncToPart(self: Types.InternalZone): Types.Zone
	local part = self.part
	if not part then
		warn('[QuickZone] Zone:syncToPart failed. No reference part found.')
		return self
	end

	local id = self.id
	local newCFrame = part.CFrame
	local halfSize = part.Size * 0.5
	local shapeType = getShapeEnumValue(part)

	if self.dynamic then
		if dynamicCFrames[id] == newCFrame and dynamicHalfSizes[id] == halfSize and dynamicTypes[id] == shapeType then
			return self
		end

		dynamicCFrames[id] = newCFrame
		dynamicHalfSizes[id] = halfSize
		dynamicTypes[id] = shapeType
		State.pendingDynamicRebuild = true
	else
		if staticCFrames[id] == newCFrame and staticHalfSizes[id] == halfSize and staticTypes[id] == shapeType then
			return self
		end

		staticCFrames[id] = newCFrame
		staticHalfSizes[id] = halfSize
		staticTypes[id] = shapeType
		State.pendingStaticRebuild = true
	end

	return self
end

--[=[ 
	Updates the Zone's CFrame.

	@method setCFrame
	@within Zone
	@param cf CFrame
	@return Zone
]=]
function Zone.setCFrame(self: Types.InternalZone, cf: CFrame): Types.Zone
	if self.dynamic then
		dynamicCFrames[self.id] = cf
		State.pendingDynamicRebuild = true
	else
		staticCFrames[self.id] = cf
		State.pendingStaticRebuild = true
	end
	return self
end

--[=[ 
	Updates the Zone's Position while preserving its current Rotation.

	@method setPosition
	@within Zone
	@param pos Vector3
	@return Zone
]=]
function Zone.setPosition(self: Types.InternalZone, pos: Vector3): Types.Zone
	local currentCF = self.dynamic and dynamicCFrames[self.id] or staticCFrames[self.id]
	local newCF = currentCF.Rotation + pos
	return self:setCFrame(newCF)
end

--[=[ 
	Updates the Zone's Size.

	@method setSize
	@within Zone
	@param size Vector3
	@return Zone
]=]
function Zone.setSize(self: Types.InternalZone, size: Vector3): Types.Zone
	local halfSize = size * 0.5

	if self.dynamic then
		dynamicHalfSizes[self.id] = halfSize
		State.pendingDynamicRebuild = true
	else
		staticHalfSizes[self.id] = halfSize
		State.pendingStaticRebuild = true
	end
	return self
end

--[=[ 
	Updates the Zone's geometric shape.
	
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
		warn(`[QuickZone] Invalid shape '{shape}'. Defaulting to Block.`)
	end

	if self.dynamic then
		dynamicTypes[self.id] = shapeType
	else
		staticTypes[self.id] = shapeType
	end

	-- Changing the shape doesn't need a rebuild.
	State.isDirty = true
	return self
end

--[=[ 
	Set the metadata of the zone.

	@method setMetadata
	@within Zone
	@return number
]=]
function Zone.setMetadata(self: Types.InternalZone, metadata: any?): Types.Zone
	self.metadata = metadata
	return self
end

--[=[ 
	Returns the metadata of the zone.
	
	@method getMetadata
	@within Zone
	@return number
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
	Returns the BasePart associated with this zone, if any.

	@method getPart
	@within Zone
	@return BasePart?
]=]
function Zone.getPart(self: Types.InternalZone): BasePart?
	return self.part
end

--[=[
	Returns the current position of the zone.

	@method getPosition
	@within Zone
	@return CFrame
]=]
function Zone.getPosition(self: Types.InternalZone): Vector3
	local cf = self.dynamic and dynamicCFrames[self.id] or staticCFrames[self.id]
	return cf.Position
end

--[=[
	Returns the current CFrame of the zone.

	@method getCFrame
	@within Zone
	@return CFrame
]=]
function Zone.getCFrame(self: Types.InternalZone): CFrame
	return self.dynamic and dynamicCFrames[self.id] or staticCFrames[self.id]
end

--[=[
	Returns the full size of the zone.

	@method getSize
	@within Zone
	@return Vector3
]=]
function Zone.getSize(self: Types.InternalZone): Vector3
	local halfSize = self.dynamic and dynamicHalfSizes[self.id] or staticHalfSizes[self.id]
	return halfSize * 2
end

--[=[ 
	Returns the geometric shape type of the zone.

	@method getShape
	@within Zone
	@return ShapeType
]=]
function Zone.getShape(self: Types.InternalZone): Types.ShapeType
	local shapeType = self.dynamic and dynamicTypes[self.id] or staticTypes[self.id]
	if shapeType == Enum.PartType.Block.Value then
		return 'Block'
	elseif shapeType == Enum.PartType.Ball.Value then
		return 'Ball'
	elseif shapeType == Enum.PartType.Cylinder.Value then
		return 'Cylinder'
	elseif shapeType == Enum.PartType.Wedge.Value then
		return 'Wedge'
	end
	return 'Block'
end

--[=[ 
	Returns a list of all Observers currently attached to this zone.
	
	@method getObservers
	@within Zone
	@return { Observer }
]=]
function Zone.getObservers(self: Types.InternalZone): { Types.Observer }
	local attached = State.zoneAttachedObservers[self.id]
	if not attached then
		return {}
	end

	local result = {}
	for _, id in attached do
		local observer = State.observerIdToObserverObj[id]
		if observer then
			table.insert(result, observer)
		end
	end
	return result
end

--[=[ 
	Checks if a point is inside this specific zone.

	@method isPointInside
	@within Zone
	@param point Vector3
	@return boolean
]=]
function Zone.isPointInside(self: Types.InternalZone, point: Vector3): boolean
	return Geometry.isPointInZone(point, self.id, self.dynamic)
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
	Cleans up the zone, removes it from the LBVH tree, and detaches all observers.
	
	@tag Destructor
	@method destroy
	@within Zone
]=]
function Zone.destroy(self: Types.InternalZone): ()
	State.zoneAttachedObservers[self.id] = nil
	State.zoneIdToZoneObj[self.id] = nil

	if self.dynamic then
		dynamicCFrames[self.id] = nil
		dynamicHalfSizes[self.id] = nil
		dynamicTypes[self.id] = nil
		State.pendingDynamicRebuild = true
	else
		staticCFrames[self.id] = nil
		staticHalfSizes[self.id] = nil
		staticTypes[self.id] = nil
		State.pendingStaticRebuild = true
	end

	setmetatable(self :: any, nil)
end

return Zone

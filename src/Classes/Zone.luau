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

local function getShapeEnumValue(part: BasePart): number
	if part:IsA('Part') then
		return part.Shape.Value
	end

	if part:IsA('WedgePart') then
		return Enum.PartType.Wedge.Value
	end

	-- if part:IsA('CornerWedgePart') then
	-- 	return Enum.PartType.CornerWedge.Value
	-- end

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

function Zone.new(
	cframe: CFrame,
	size: Vector3,
	shapeType: number,
	associatedPart: BasePart?,
	isDynamic: boolean?,
	metadata: any?
): Types.Zone
	local id = State.nextZoneId
	State.nextZoneId += 1

	local halfSize = size / 2

	if isDynamic then
		dynamicCFrames[id] = cframe
		dynamicHalfSizes[id] = halfSize
		dynamicTypes[id] = shapeType
		State.pendingDynamicRebuild = true
	else
		staticCFrames[id] = cframe
		staticHalfSizes[id] = halfSize
		staticTypes[id] = shapeType
		State.pendingStaticRebuild = true
	end

	local self: Types.InternalZone =
		setmetatable({ id = id, part = associatedPart, dynamic = isDynamic or false, metadata = metadata }, Zone) :: any
	State.zoneIdToZoneObj[id] = self

	return self
end

--[=[ 
	Attaches one or more Observers to this zone. The observers will begin 
	monitoring this area for entity overlaps.

	```lua
	zone:attach(myObserver)
	```

	@method attach
	@within Zone
	@param ... Observer -- The observers to link.
	@return Zone
]=]
function Zone.attach(self: Types.InternalZone, ...: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id] or {}
	State.zoneAttachedObservers[self.id] = attached
	for _, observer in { ... } do
		if not table.find(attached, observer.id) then
			table.insert(attached, observer.id)
		end
	end
	State.isDirty = true
	return self
end

--[=[ 
	Detaches observers from this zone.

	@method detach
	@within Zone
	@param ... Observer -- The observers to unlink.
	@return Zone
]=]
function Zone.detach(self: Types.InternalZone, ...: Types.InternalObserver): Types.Zone
	local attached = State.zoneAttachedObservers[self.id]
	if not attached then
		return self
	end

	for _, observer in { ... } do
		local idx = table.find(attached, observer.id)
		while idx do
			table.remove(attached, idx)
			idx = table.find(attached, observer.id)
		end
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
	local shapeType
	if shape == 'Block' then
		shapeType = Enum.PartType.Block.Value
	elseif shape == 'Cylinder' then
		shapeType = Enum.PartType.Cylinder.Value
	elseif shape == 'Ball' then
		shapeType = Enum.PartType.Ball.Value
	elseif shape == 'Wedge' then
		shapeType = Enum.PartType.Wedge.Value
	else
		shapeType = Enum.PartType.Block.Value
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

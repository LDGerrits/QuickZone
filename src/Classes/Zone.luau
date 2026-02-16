--!strict

local Geometry = require(script.Parent.Parent.Core.Geometry)
local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

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
	Updates the zone's position and size.

	```lua
	-- Manual update
	zone:update(CFrame.new(0, 20, 0), Vector3.new(5, 5, 5))

	-- Sync with associated part
	zone:update()
	```

	:::info Auto-Sync
	If the zone was created with an `associatedPart`, calling `update()` 
	without arguments will automatically sync the zone to that part's current 
	CFrame and Size.
	:::

	@method update
	@within Zone
	@param newCFrame CFrame? -- Optional new position/rotation.
	@param newSize Vector3? -- Optional new dimensions.
	@return Zone
]=]
function Zone.update(self: Types.InternalZone, newCFrame: CFrame?, newSize: Vector3?): Types.Zone
	-- If no arguments, use reference part if possible
	if not newCFrame and self.part then
		newCFrame = self.part.CFrame
		newSize = self.part.Size
	end

	if not newCFrame or not newSize then
		warn('[QuickZone] Zone:update failed. No Part given and no CFrame provided.')
		return self
	end

	local halfSize = newSize / 2

	if self.dynamic then
		State.dynamicCFrames[self.id] = newCFrame
		State.dynamicHalfSizes[self.id] = halfSize
		State.pendingDynamicRebuild = true
	else
		State.staticCFrames[self.id] = newCFrame
		State.staticHalfSizes[self.id] = halfSize
		State.pendingStaticRebuild = true
	end

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

	@method getPositioin
	@within Zone
	@return CFrame
]=]
function Zone.getPosition(self: Types.InternalZone): Vector3
	local cf = self.dynamic and State.dynamicCFrames[self.id] or State.staticCFrames[self.id]
	return cf.Position
end

--[=[
	Returns the current CFrame of the zone.

	@method getCFrame
	@within Zone
	@return CFrame
]=]
function Zone.getCFrame(self: Types.InternalZone): CFrame
	return self.dynamic and State.dynamicCFrames[self.id] or State.staticCFrames[self.id]
end

--[=[
	Returns the full size of the zone.

	@method getSize
	@within Zone
	@return Vector3
]=]
function Zone.getSize(self: Types.InternalZone): Vector3
	local halfSize = self.dynamic and State.dynamicHalfSizes[self.id] or State.staticHalfSizes[self.id]
	return halfSize * 2
end

--[=[ 
	Returns the geometric shape type of the zone.

	@method getShape
	@within Zone
	@return ShapeType
]=]
function Zone.getShape(self: Types.InternalZone): Types.ShapeType
	local shapeType = self.dynamic and State.dynamicTypes[self.id] or State.staticTypes[self.id]
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
		State.dynamicCFrames[self.id] = nil
		State.dynamicHalfSizes[self.id] = nil
		State.dynamicTypes[self.id] = nil
		State.pendingDynamicRebuild = true
	else
		State.staticCFrames[self.id] = nil
		State.staticHalfSizes[self.id] = nil
		State.staticTypes[self.id] = nil
		State.pendingStaticRebuild = true
	end

	setmetatable(self :: any, nil)
end

return Zone

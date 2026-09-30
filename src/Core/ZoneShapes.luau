--!native
--!optimize 2
--!strict

-- Caches every zone's world-space shape so queries and rebuilds never read a CFrame

local Geometry = require(script.Parent.Parent.Utils.Geometry)
local State = require(script.Parent.State)

local BLOCK_SHAPE_VALUE = Enum.PartType.Block.Value

local getBounds = Geometry.getBounds
local isPointInShape = Geometry.isPointInShape

local shapeTypes = State.shapeTypes
local shapeHalfSizes = State.shapeHalfSizes
local shapeParts = State.shapeParts
local shapePositions = State.shapePositions
local shapeRights = State.shapeRights
local shapeUps = State.shapeUps
local shapeBacks = State.shapeBacks
local shapeBoundsMin = State.shapeBoundsMin
local shapeBoundsMax = State.shapeBoundsMax
local shapeAxisAligned = State.shapeAxisAligned
local treeExact = State.treeExact

local function isAxis(direction: Vector3): boolean
	local magnitude = vector.abs(direction)
	return magnitude == Vector3.xAxis or magnitude == Vector3.yAxis or magnitude == Vector3.zAxis
end

local ZoneShapes = {}

-- Call after the CFrame, size, shape or mesh changes
function ZoneShapes.refresh(id: number, isDynamic: boolean)
	local cframe, halfSize, shapeType, part
	if isDynamic then
		cframe, halfSize, shapeType, part =
			State.dynamicCFrames[id], State.dynamicHalfSizes[id], State.dynamicTypes[id], State.dynamicMeshes[id]
	else
		cframe, halfSize, shapeType, part =
			State.staticCFrames[id], State.staticHalfSizes[id], State.staticTypes[id], State.staticMeshes[id]
	end

	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cframe:GetComponents()
	local position = Vector3.new(x, y, z)
	local right = Vector3.new(r00, r10, r20)
	local up = Vector3.new(r01, r11, r21)
	local back = Vector3.new(r02, r12, r22)
	local boundsMin, boundsMax = getBounds(position, right, up, back, halfSize)

	shapeTypes[id] = shapeType
	shapeHalfSizes[id] = halfSize
	shapeParts[id] = part
	shapePositions[id] = position
	shapeRights[id] = right
	shapeUps[id] = up
	shapeBacks[id] = back
	shapeBoundsMin[id] = boundsMin
	shapeBoundsMax[id] = boundsMax
	-- Unrotated blocks are exactly their bounds
	shapeAxisAligned[id] = shapeType == BLOCK_SHAPE_VALUE and isAxis(right) and isAxis(up) and isAxis(back)

	-- Leaf is stale until the next rebuild
	treeExact[id] = nil
end

function ZoneShapes.remove(id: number)
	shapeTypes[id] = nil
	shapeHalfSizes[id] = nil
	shapeParts[id] = nil
	shapePositions[id] = nil
	shapeRights[id] = nil
	shapeUps[id] = nil
	shapeBacks[id] = nil
	shapeBoundsMin[id] = nil
	shapeBoundsMax[id] = nil
	shapeAxisAligned[id] = nil
	treeExact[id] = nil
end

-- Called after a tree is rebuilt
function ZoneShapes.markBuilt(ids: { [number]: any })
	for id in ids do
		treeExact[id] = shapeAxisAligned[id]
	end
end

function ZoneShapes.containsPoint(id: number, point: Vector3): boolean
	local shapeType = shapeTypes[id]
	if not shapeType then
		return false
	end

	return isPointInShape(
		point,
		shapePositions[id],
		shapeRights[id],
		shapeUps[id],
		shapeBacks[id],
		shapeHalfSizes[id],
		shapeType,
		shapeParts[id]
	)
end

-- Skips the shape check for exact leaves
function ZoneShapes.leafContainsPoint(id: number, point: Vector3): boolean
	return treeExact[id] == true or ZoneShapes.containsPoint(id, point)
end

return ZoneShapes

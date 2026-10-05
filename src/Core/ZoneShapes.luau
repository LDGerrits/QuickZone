--!native
--!optimize 2
--!strict

-- Caches every zone's world-space shape so queries and rebuilds never read a CFrame

local Geometry = require(script.Parent.Parent.Utils.Geometry)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local ZoneChanges = require(script.Parent.ZoneChanges)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

local BLOCK_SHAPE_VALUE = Enum.PartType.Block.Value

local getBounds = Geometry.getBounds
local queryPoint = LinearBVH.queryPoint
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
local dynamicCFrames = State.dynamicCFrames
local dynamicTree = State.dynamicTree
local staticTree = State.staticTree
local staticChanges = State.staticChanges
local dynamicChanges = State.dynamicChanges

local function isAxis(direction: Vector3): boolean
	local magnitude = vector.abs(direction)
	return magnitude == Vector3.xAxis or magnitude == Vector3.yAxis or magnitude == Vector3.zAxis
end

local ZoneShapes = {}

local function changesOf(isDynamic: boolean): Types.ZoneChanges
	return if isDynamic then dynamicChanges else staticChanges
end

-- Call after the CFrame, size, shape or mesh changes
function ZoneShapes.refresh(id: number)
	local isDynamic = dynamicCFrames[id] ~= nil
	local cframe, halfSize, shapeType, part
	if isDynamic then
		cframe, halfSize, shapeType, part =
			dynamicCFrames[id], State.dynamicHalfSizes[id], State.dynamicTypes[id], State.dynamicMeshes[id]
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

	-- Entities in the old or new box may be affected
	local changes = changesOf(isDynamic)
	if not changes.all then
		local oldMin = shapeBoundsMin[id]
		if oldMin then
			ZoneChanges.add(changes, oldMin, shapeBoundsMax[id])
		end
		ZoneChanges.add(changes, boundsMin, boundsMax)
	end

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

-- For changes that don't alter the shape, like attaching
function ZoneShapes.touch(id: number, isDynamic: boolean)
	local min = shapeBoundsMin[id]
	if min then
		ZoneChanges.add(changesOf(isDynamic), min, shapeBoundsMax[id])
	end
end

function ZoneShapes.remove(id: number, wasDynamic: boolean)
	local min = shapeBoundsMin[id]
	if min then
		ZoneChanges.add(changesOf(wasDynamic), min, shapeBoundsMax[id])
	end

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

-- Writes the ids of dynamic, then static, leaves containing the point to hits, returns the count.
-- Check each with leafContainsPoint before the trees change
function ZoneShapes.leavesAtPoint(point: Vector3, hits: { number }): number
	local hitCount = queryPoint(dynamicTree, point, hits, 0)
	return queryPoint(staticTree, point, hits, hitCount)
end

return ZoneShapes

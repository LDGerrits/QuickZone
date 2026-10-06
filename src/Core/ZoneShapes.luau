--!native
--!optimize 2
--!strict

-- Owns every zone's geometry. Writes go through here, which keeps the world-space shape used by
-- queries and rebuilds, the change log and the tree rebuild flags in step with it

local Geometry = require(script.Parent.Parent.Utils.Geometry)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local ZoneChanges = require(script.Parent.ZoneChanges)
local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

local BLOCK_SHAPE_VALUE = Enum.PartType.Block.Value
local BALL_SHAPE_VALUE = Enum.PartType.Ball.Value
local CYLINDER_SHAPE_VALUE = Enum.PartType.Cylinder.Value

local getBounds = Geometry.getBounds
local queryPoint = LinearBVH.queryPoint
local isPointInShape = Geometry.isPointInShape

local shapeCFrames = State.shapeCFrames
local shapeHalfSizes = State.shapeHalfSizes
local shapeTypes = State.shapeTypes
local shapeParts = State.shapeParts
local shapePositions = State.shapePositions
local shapeRights = State.shapeRights
local shapeUps = State.shapeUps
local shapeBacks = State.shapeBacks
local shapeBoundsMin = State.shapeBoundsMin
local shapeBoundsMax = State.shapeBoundsMax
local shapeAxisAligned = State.shapeAxisAligned
local treeExact = State.treeExact
local staticSlots = State.staticSlots
local dynamicSlots = State.dynamicSlots
local dynamicTree = State.dynamicTree
local staticTree = State.staticTree
local staticChanges = State.staticChanges
local dynamicChanges = State.dynamicChanges

local function isAxis(direction: Vector3): boolean
	local magnitude = vector.abs(direction)
	return magnitude == Vector3.xAxis or magnitude == Vector3.yAxis or magnitude == Vector3.zAxis
end

-- Half size of a box around the shape. Balls take their radius from X, cylinders from Y,
-- so uneven sizes reach past the zone's own box
local function getShapeExtents(shapeType: number, halfSize: Vector3): Vector3
	if shapeType == BALL_SHAPE_VALUE then
		return Vector3.one * halfSize.X
	elseif shapeType == CYLINDER_SHAPE_VALUE then
		return Vector3.new(halfSize.X, halfSize.Y, halfSize.Y)
	end
	return halfSize
end

local function changesOf(isDynamic: boolean): Types.ZoneChanges
	return if isDynamic then dynamicChanges else staticChanges
end

local function markPending(isDynamic: boolean)
	if isDynamic then
		State.pendingDynamicRebuild = true
	else
		State.pendingStaticRebuild = true
	end
end

-- Zones were added to or removed from the tree, so it must be rebuilt rather than refit
local function markMembersChanged(isDynamic: boolean)
	markPending(isDynamic)
	if isDynamic then
		dynamicTree.membersChanged = true
	else
		staticTree.membersChanged = true
	end
end

-- Recomputes the world-space shape from the geometry
local function refresh(slot: number)
	local isDynamic = dynamicSlots[slot] == true
	local halfSize = shapeHalfSizes[slot]
	local shapeType = shapeTypes[slot]

	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = shapeCFrames[slot]:GetComponents()
	local position = Vector3.new(x, y, z)
	local right = Vector3.new(r00, r10, r20)
	local up = Vector3.new(r01, r11, r21)
	local back = Vector3.new(r02, r12, r22)
	local boundsMin, boundsMax = getBounds(position, right, up, back, getShapeExtents(shapeType, halfSize))

	-- Entities in the old or new box may be affected
	local changes = changesOf(isDynamic)
	if not changes.all then
		local oldMin = shapeBoundsMin[slot]
		if oldMin then
			ZoneChanges.add(changes, oldMin, shapeBoundsMax[slot])
		end
		ZoneChanges.add(changes, boundsMin, boundsMax)
	end

	shapePositions[slot] = position
	shapeRights[slot] = right
	shapeUps[slot] = up
	shapeBacks[slot] = back
	shapeBoundsMin[slot] = boundsMin
	shapeBoundsMax[slot] = boundsMax
	-- Unrotated blocks are exactly their bounds
	shapeAxisAligned[slot] = shapeType == BLOCK_SHAPE_VALUE and isAxis(right) and isAxis(up) and isAxis(back)

	-- Leaf is stale until the next rebuild
	treeExact[slot] = nil

	markPending(isDynamic)
end

local ZoneShapes = {}

-- Adds a zone to the static or dynamic tree. part is the part a Mesh zone queries
function ZoneShapes.add(
	slot: number,
	isDynamic: boolean,
	cframe: CFrame,
	halfSize: Vector3,
	shapeType: number,
	part: BasePart?
)
	if isDynamic then
		dynamicSlots[slot] = true
	else
		staticSlots[slot] = true
	end
	markMembersChanged(isDynamic)

	shapeCFrames[slot] = cframe
	shapeHalfSizes[slot] = halfSize
	shapeTypes[slot] = shapeType
	shapeParts[slot] = part
	refresh(slot)
end

-- Sets the whole geometry
function ZoneShapes.set(slot: number, cframe: CFrame, halfSize: Vector3, shapeType: number, part: BasePart?)
	-- Ignore writes for removed zones, like a late property signal
	if not shapeCFrames[slot] then
		return
	end

	if
		shapeCFrames[slot] == cframe
		and shapeHalfSizes[slot] == halfSize
		and shapeTypes[slot] == shapeType
		and shapeParts[slot] == part
	then
		return
	end

	shapeCFrames[slot] = cframe
	shapeHalfSizes[slot] = halfSize
	shapeTypes[slot] = shapeType
	shapeParts[slot] = part
	refresh(slot)
end

function ZoneShapes.setCFrame(slot: number, cframe: CFrame)
	ZoneShapes.set(slot, cframe, shapeHalfSizes[slot], shapeTypes[slot], shapeParts[slot])
end

function ZoneShapes.setHalfSize(slot: number, halfSize: Vector3)
	ZoneShapes.set(slot, shapeCFrames[slot], halfSize, shapeTypes[slot], shapeParts[slot])
end

function ZoneShapes.setShape(slot: number, shapeType: number, part: BasePart?)
	ZoneShapes.set(slot, shapeCFrames[slot], shapeHalfSizes[slot], shapeType, part)
end

function ZoneShapes.isDynamic(slot: number): boolean
	return dynamicSlots[slot] == true
end

-- Moves a zone between the static and dynamic trees. Its shape stays, so no zone change is recorded
function ZoneShapes.setDynamic(slot: number, isDynamic: boolean)
	if (dynamicSlots[slot] == true) == isDynamic then
		return
	end

	if isDynamic then
		staticSlots[slot] = nil
		dynamicSlots[slot] = true
	else
		dynamicSlots[slot] = nil
		staticSlots[slot] = true
	end
	markMembersChanged(true)
	markMembersChanged(false)
end

-- For changes that don't alter the shape, like attaching
function ZoneShapes.touch(slot: number)
	local min = shapeBoundsMin[slot]
	if min then
		ZoneChanges.add(changesOf(dynamicSlots[slot] == true), min, shapeBoundsMax[slot])
	end
end

function ZoneShapes.remove(slot: number)
	local isDynamic = dynamicSlots[slot] == true
	ZoneShapes.touch(slot)

	staticSlots[slot] = nil
	dynamicSlots[slot] = nil
	markMembersChanged(isDynamic)

	shapeCFrames[slot] = nil
	shapeHalfSizes[slot] = nil
	shapeTypes[slot] = nil
	shapeParts[slot] = nil
	shapePositions[slot] = nil
	shapeRights[slot] = nil
	shapeUps[slot] = nil
	shapeBacks[slot] = nil
	shapeBoundsMin[slot] = nil
	shapeBoundsMax[slot] = nil
	shapeAxisAligned[slot] = nil
	treeExact[slot] = nil
end

-- Called after a tree is rebuilt
function ZoneShapes.markBuilt(slots: { [number]: any })
	for slot in slots do
		treeExact[slot] = shapeAxisAligned[slot]
	end
end

function ZoneShapes.containsPoint(slot: number, point: Vector3): boolean
	local shapeType = shapeTypes[slot]
	if not shapeType then
		return false
	end

	return isPointInShape(
		point,
		shapePositions[slot],
		shapeRights[slot],
		shapeUps[slot],
		shapeBacks[slot],
		shapeHalfSizes[slot],
		shapeType,
		shapeParts[slot]
	)
end

-- Skips the shape check for exact leaves
function ZoneShapes.leafContainsPoint(slot: number, point: Vector3): boolean
	return treeExact[slot] == true or ZoneShapes.containsPoint(slot, point)
end

-- Writes the ids of dynamic, then static, leaves containing the point to hits, returns the count.
-- Check each with leafContainsPoint before the trees change
function ZoneShapes.leavesAtPoint(point: Vector3, hits: { number }): number
	local hitCount = queryPoint(dynamicTree, point, hits, 0)
	return queryPoint(staticTree, point, hits, hitCount)
end

return ZoneShapes

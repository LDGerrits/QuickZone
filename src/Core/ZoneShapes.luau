--!native
--!optimize 2
--!strict

local Geometry = require(script.Parent.Parent.Utils.Geometry)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local ZoneChanges = require(script.Parent.ZoneChanges)
local Types = require(script.Parent.Parent.Types)

local BLOCK_SHAPE_VALUE = Geometry.BLOCK_SHAPE_VALUE
local BALL_SHAPE_VALUE = Geometry.BALL_SHAPE_VALUE
local CYLINDER_SHAPE_VALUE = Geometry.CYLINDER_SHAPE_VALUE
local EMPTY_MIN = Vector3.one * math.huge
local EMPTY_MAX = -EMPTY_MIN

local getBounds = Geometry.getBounds
local queryPoint = LinearBVH.queryPoint
local clearRadius = LinearBVH.clearRadius
local isPointInShape = Geometry.isPointInShape

local INV_SQRT3 = 1 / math.sqrt(3)
-- Kept off every clear radius, so float rounding at a zone's face can't put a point on the wrong side
local CLEAR_MARGIN = 1e-3

local ZoneShapes = {}

ZoneShapes.zoneSlotCount = 0
ZoneShapes.freeZoneSlots = {} :: { number }
ZoneShapes.zoneSlotIds = {} :: { [number]: number }
ZoneShapes.staticSlots = {} :: { [number]: true }
ZoneShapes.dynamicSlots = {} :: { [number]: true }
ZoneShapes.shapeCFrames = {} :: { [number]: CFrame }
ZoneShapes.shapeHalfSizes = {} :: { [number]: Vector3 }
ZoneShapes.shapeFilledHalfSizes = {} :: { [number]: Vector3 }
ZoneShapes.shapeTypes = {} :: { [number]: number }
ZoneShapes.shapeParts = {} :: { [number]: BasePart? }
ZoneShapes.shapePositions = {} :: { [number]: Vector3 }
ZoneShapes.shapeRights = {} :: { [number]: Vector3 }
ZoneShapes.shapeUps = {} :: { [number]: Vector3 }
ZoneShapes.shapeBacks = {} :: { [number]: Vector3 }
ZoneShapes.shapeBoundsMin = {} :: { [number]: Vector3 }
ZoneShapes.shapeBoundsMax = {} :: { [number]: Vector3 }
ZoneShapes.shapeAxisAligned = {} :: { [number]: boolean }
ZoneShapes.treeExact = {} :: { [number]: boolean }
ZoneShapes.staleSlots = {} :: { [number]: true }
ZoneShapes.staticChanges = ZoneChanges.new()
ZoneShapes.dynamicChanges = ZoneChanges.new()
ZoneShapes.staticTree = LinearBVH.new()
ZoneShapes.dynamicTree = LinearBVH.new()
ZoneShapes.staticVersion = 0
ZoneShapes.dynamicVersion = 0

local shapeCFrames = ZoneShapes.shapeCFrames
local shapeHalfSizes = ZoneShapes.shapeHalfSizes
local shapeFilledHalfSizes = ZoneShapes.shapeFilledHalfSizes
local shapeTypes = ZoneShapes.shapeTypes
local shapeParts = ZoneShapes.shapeParts
local shapePositions = ZoneShapes.shapePositions
local shapeRights = ZoneShapes.shapeRights
local shapeUps = ZoneShapes.shapeUps
local shapeBacks = ZoneShapes.shapeBacks
local shapeBoundsMin = ZoneShapes.shapeBoundsMin
local shapeBoundsMax = ZoneShapes.shapeBoundsMax
local shapeAxisAligned = ZoneShapes.shapeAxisAligned
local treeExact = ZoneShapes.treeExact
local staleSlots = ZoneShapes.staleSlots
local staticSlots = ZoneShapes.staticSlots
local dynamicSlots = ZoneShapes.dynamicSlots
local dynamicTree = ZoneShapes.dynamicTree
local staticTree = ZoneShapes.staticTree
local staticChanges = ZoneShapes.staticChanges
local dynamicChanges = ZoneShapes.dynamicChanges

-- Whether staleSlots may hold a slot. next() on a large emptied table scans every free node, so hot paths read this.
local hasStale = false

local function isAxis(direction: Vector3): boolean
	local magnitude = vector.abs(direction)
	return magnitude == Vector3.xAxis or magnitude == Vector3.yAxis or magnitude == Vector3.zAxis
end

local function changesOf(isDynamic: boolean): Types.ZoneChanges
	return if isDynamic then dynamicChanges else staticChanges
end

local function treeOf(isDynamic: boolean): Types.Tree
	return if isDynamic then dynamicTree else staticTree
end

local function markMembersChanged(isDynamic: boolean)
	local tree = treeOf(isDynamic)
	tree.pending = true
	tree.membersChanged = true
end

local function extentsOf(halfSize: Vector3, shapeType: number): Vector3
	local extents = vector.max(halfSize, Vector3.zero)
	if shapeType == BALL_SHAPE_VALUE then
		local radius = math.min(extents.X, extents.Y, extents.Z)
		return Vector3.new(radius, radius, radius)
	elseif shapeType == CYLINDER_SHAPE_VALUE then
		local radius = math.min(extents.Y, extents.Z)
		return Vector3.new(extents.X, radius, radius)
	end
	return extents
end

local function deriveWorldShape(slot: number)
	local isDynamic = dynamicSlots[slot] == true
	local shapeType = shapeTypes[slot]
	local halfSize = extentsOf(shapeHalfSizes[slot], shapeType)

	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = shapeCFrames[slot]:GetComponents()
	local position = Vector3.new(x, y, z)
	local right = Vector3.new(r00, r10, r20)
	local up = Vector3.new(r01, r11, r21)
	local back = Vector3.new(r02, r12, r22)
	-- Unrotated is the common case, where the bounds are the half size around the position
	local unrotated = r01 == 0 and r02 == 0 and r10 == 0 and r12 == 0 and r20 == 0 and r21 == 0
	local boundsMin, boundsMax
	-- An infinite size, as for a kill plane, goes through getBounds, which keeps it from turning into NaN
	if unrotated and halfSize.X < math.huge and halfSize.Y < math.huge and halfSize.Z < math.huge then
		boundsMin, boundsMax = position - halfSize, position + halfSize
	else
		boundsMin, boundsMax = getBounds(position, right, up, back, halfSize)
	end
	-- A NaN position or size would spread NaN to every tree node above the leaf, hiding other zones
	if boundsMin ~= boundsMin or boundsMax ~= boundsMax then
		boundsMin, boundsMax = EMPTY_MIN, EMPTY_MAX
	end

	local changes = changesOf(isDynamic)
	if not changes.all then
		local oldMin = shapeBoundsMin[slot]
		if oldMin then
			ZoneChanges.add(changes, oldMin, shapeBoundsMax[slot])
		end
		ZoneChanges.add(changes, boundsMin, boundsMax)
	end

	shapeFilledHalfSizes[slot] = halfSize
	shapePositions[slot] = position
	shapeRights[slot] = right
	shapeUps[slot] = up
	shapeBacks[slot] = back
	shapeBoundsMin[slot] = boundsMin
	shapeBoundsMax[slot] = boundsMax
	shapeAxisAligned[slot] = shapeType == BLOCK_SHAPE_VALUE
		and (unrotated or (isAxis(right) and isAxis(up) and isAxis(back)))

	treeExact[slot] = nil
	staleSlots[slot] = true
	hasStale = true

	treeOf(isDynamic).pending = true
end

function ZoneShapes.allocateSlot(zoneId: number): number
	local freed = table.remove(ZoneShapes.freeZoneSlots)
	if freed then
		ZoneShapes.zoneSlotIds[freed] = zoneId
		return freed
	end
	local slot = ZoneShapes.zoneSlotCount + 1
	ZoneShapes.zoneSlotCount = slot
	ZoneShapes.zoneSlotIds[slot] = zoneId
	return slot
end

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
	deriveWorldShape(slot)
end

function ZoneShapes.set(slot: number, cframe: CFrame, halfSize: Vector3, shapeType: number, part: BasePart?)
	-- A late property signal can write to a removed zone
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
	deriveWorldShape(slot)
end

function ZoneShapes.setCFrame(slot: number, cframe: CFrame)
	-- Like set, which a removed zone or an unchanged CFrame leaves alone
	local current = shapeCFrames[slot]
	if not current or current == cframe then
		return
	end
	shapeCFrames[slot] = cframe
	deriveWorldShape(slot)
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
	staleSlots[slot] = true
	hasStale = true

	local min = shapeBoundsMin[slot]
	if min then
		ZoneChanges.add(staticChanges, min, shapeBoundsMax[slot])
		ZoneChanges.add(dynamicChanges, min, shapeBoundsMax[slot])
	end
end

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
	shapeFilledHalfSizes[slot] = nil
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
	staleSlots[slot] = nil

	ZoneShapes.zoneSlotIds[slot] = nil
	table.insert(ZoneShapes.freeZoneSlots, slot)
end

local function markBuilt(slots: { [number]: any })
	for slot in staleSlots do
		if slots[slot] then
			treeExact[slot] = shapeAxisAligned[slot]
			staleSlots[slot] = nil
		end
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
		shapeFilledHalfSizes[slot],
		shapeType,
		shapeParts[slot]
	)
end

-- How far point can move, on every axis, before it might cross the shape in slot. Its box holds point.
local function leafRadius(
	slot: number,
	point: Vector3,
	minX: number,
	minY: number,
	minZ: number,
	maxX: number,
	maxY: number,
	maxZ: number
): number
	if treeExact[slot] then
		local px, py, pz = point.X, point.Y, point.Z
		return math.min(px - minX, maxX - px, py - minY, maxY - py, pz - minZ, maxZ - pz)
	end

	-- A cube of half-width r reaches r * sqrt(3) from its centre, so it clears a shape r * sqrt(3) away
	local shapeType = shapeTypes[slot]
	if shapeType == BALL_SHAPE_VALUE then
		local offset = point - shapePositions[slot]
		return math.abs(shapeFilledHalfSizes[slot].X - math.sqrt(vector.dot(offset, offset))) * INV_SQRT3
	elseif shapeType == BLOCK_SHAPE_VALUE then
		local offset = point - shapePositions[slot]
		local half = shapeFilledHalfSizes[slot]
		local localPoint = vector.abs(
			Vector3.new(
				vector.dot(offset, shapeRights[slot]),
				vector.dot(offset, shapeUps[slot]),
				vector.dot(offset, shapeBacks[slot])
			)
		)
		if vector.min(localPoint, half) == localPoint then
			local inside = half - localPoint
			return math.min(inside.X, inside.Y, inside.Z) * INV_SQRT3
		end
		local outside = vector.max(localPoint - half, Vector3.zero)
		return math.sqrt(vector.dot(outside, outside)) * INV_SQRT3
	end

	return 0
end

--[=[
	The half-width of a cube around point inside which every zone in the trees gives the same answer as at point, up to
	maxRadius; 0 if there is none or a zone changed since the trees were built.
]=]
function ZoneShapes.clearRadius(point: Vector3, maxRadius: number, useStatic: boolean, useDynamic: boolean): number
	if hasStale then
		return 0
	end

	local radius = maxRadius
	if useDynamic then
		radius = clearRadius(dynamicTree, point, radius, leafRadius)
	end
	if useStatic and radius > 0 then
		radius = clearRadius(staticTree, point, radius, leafRadius)
	end

	radius -= CLEAR_MARGIN
	return if radius > 0 then radius else 0
end

function ZoneShapes.leafContainsPoint(slot: number, point: Vector3): boolean
	return treeExact[slot] == true or ZoneShapes.containsPoint(slot, point)
end

function ZoneShapes.leavesAtPoint(point: Vector3, hits: { number }): number
	local hitCount = queryPoint(dynamicTree, point, hits, 0)
	return queryPoint(staticTree, point, hits, hitCount)
end

local function updateTree(tree: Types.Tree, members: { [number]: any })
	if tree.membersChanged or not LinearBVH.tryRefit(tree, shapeBoundsMin, shapeBoundsMax) then
		LinearBVH.build(tree, members, shapeBoundsMin, shapeBoundsMax, shapePositions)
		tree.membersChanged = false
	end
	tree.pending = false
	markBuilt(members)
end

function ZoneShapes.rebuildTrees()
	if dynamicTree.pending then
		updateTree(dynamicTree, dynamicSlots)
	end

	if staticTree.pending then
		updateTree(staticTree, staticSlots)
	end

	if ZoneChanges.commit(dynamicChanges, ZoneShapes.dynamicVersion + 1, (dynamicTree.count + 1) // 2) then
		ZoneShapes.dynamicVersion += 1
	end

	if ZoneChanges.commit(staticChanges, ZoneShapes.staticVersion + 1, (staticTree.count + 1) // 2) then
		ZoneShapes.staticVersion += 1
	end

	if hasStale then
		hasStale = next(staleSlots) ~= nil
	end
end

return ZoneShapes

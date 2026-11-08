--!native
--!optimize 2
--!strict

-- Owns zone slots, geometry, trees and their change logs. Writes go through here to keep them in step

local Geometry = require(script.Parent.Parent.Utils.Geometry)
local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local ZoneChanges = require(script.Parent.ZoneChanges)
local Types = require(script.Parent.Parent.Types)

local BLOCK_SHAPE_VALUE = Geometry.BLOCK_SHAPE_VALUE
local BALL_SHAPE_VALUE = Geometry.BALL_SHAPE_VALUE
local CYLINDER_SHAPE_VALUE = Geometry.CYLINDER_SHAPE_VALUE
-- Bounds that contain nothing and widen nothing they are merged into
local EMPTY_MIN = Vector3.one * math.huge
local EMPTY_MAX = -EMPTY_MIN

local getBounds = Geometry.getBounds
local queryPoint = LinearBVH.queryPoint
local isPointInShape = Geometry.isPointInShape

local ZoneShapes = {}

-- Keyed by reused slots rather than ids, so the tables stay arrays
ZoneShapes.zoneSlotCount = 0
ZoneShapes.freeZoneSlots = {} :: { number }
ZoneShapes.zoneSlotIds = {} :: { [number]: number }
ZoneShapes.staticSlots = {} :: { [number]: true }
ZoneShapes.dynamicSlots = {} :: { [number]: true }
ZoneShapes.shapeCFrames = {} :: { [number]: CFrame }
ZoneShapes.shapeHalfSizes = {} :: { [number]: Vector3 }
-- Half size the shape fills: a Ball its smallest side, a Cylinder its smallest cross-section
ZoneShapes.shapeExtents = {} :: { [number]: Vector3 }
ZoneShapes.shapeTypes = {} :: { [number]: number }
-- The part a Mesh zone queries
ZoneShapes.shapeParts = {} :: { [number]: BasePart }
ZoneShapes.shapePositions = {} :: { [number]: Vector3 }
ZoneShapes.shapeRights = {} :: { [number]: Vector3 }
ZoneShapes.shapeUps = {} :: { [number]: Vector3 }
ZoneShapes.shapeBacks = {} :: { [number]: Vector3 }
ZoneShapes.shapeBoundsMin = {} :: { [number]: Vector3 }
ZoneShapes.shapeBoundsMax = {} :: { [number]: Vector3 }
ZoneShapes.shapeAxisAligned = {} :: { [number]: boolean }
-- Zones whose leaf is exactly their shape
ZoneShapes.treeExact = {} :: { [number]: boolean }
-- Changed since their tree was built, so the trees may miss them
ZoneShapes.staleSlots = {} :: { [number]: true }
ZoneShapes.staticChanges = ZoneChanges.new()
ZoneShapes.dynamicChanges = ZoneChanges.new()
ZoneShapes.staticTree = LinearBVH.new()
ZoneShapes.dynamicTree = LinearBVH.new()
ZoneShapes.staticVersion = 0
ZoneShapes.dynamicVersion = 0

local shapeCFrames = ZoneShapes.shapeCFrames
local shapeHalfSizes = ZoneShapes.shapeHalfSizes
local shapeExtents = ZoneShapes.shapeExtents
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

-- Rebuilt rather than refit
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

local function refresh(slot: number)
	local isDynamic = dynamicSlots[slot] == true
	local shapeType = shapeTypes[slot]
	local halfSize = extentsOf(shapeHalfSizes[slot], shapeType)

	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = shapeCFrames[slot]:GetComponents()
	local position = Vector3.new(x, y, z)
	local right = Vector3.new(r00, r10, r20)
	local up = Vector3.new(r01, r11, r21)
	local back = Vector3.new(r02, r12, r22)
	local boundsMin, boundsMax = getBounds(position, right, up, back, halfSize)
	-- A NaN position or size would spread NaN to every tree node above the leaf, hiding other zones
	if boundsMin ~= boundsMin or boundsMax ~= boundsMax then
		boundsMin, boundsMax = EMPTY_MIN, EMPTY_MAX
	end

	-- Skipped when the log is full, as zones moving every frame soon fill it
	local changes = changesOf(isDynamic)
	if not changes.all then
		local oldMin = shapeBoundsMin[slot]
		if oldMin then
			ZoneChanges.add(changes, oldMin, shapeBoundsMax[slot])
		end
		ZoneChanges.add(changes, boundsMin, boundsMax)
	end

	shapeExtents[slot] = halfSize
	shapePositions[slot] = position
	shapeRights[slot] = right
	shapeUps[slot] = up
	shapeBacks[slot] = back
	shapeBoundsMin[slot] = boundsMin
	shapeBoundsMax[slot] = boundsMax
	-- Unrotated blocks are exactly their bounds
	shapeAxisAligned[slot] = shapeType == BLOCK_SHAPE_VALUE and isAxis(right) and isAxis(up) and isAxis(back)

	treeExact[slot] = nil
	staleSlots[slot] = true

	treeOf(isDynamic).pending = true
end

function ZoneShapes.allocateSlot(zoneId: number): number
	local slot = table.remove(ZoneShapes.freeZoneSlots)
	if not slot then
		slot = ZoneShapes.zoneSlotCount + 1
		ZoneShapes.zoneSlotCount = slot
	end
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
	refresh(slot)
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

-- Logged in both trees, as entities only query the trees their observers have zones in
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

	local min = shapeBoundsMin[slot]
	if min then
		ZoneChanges.add(staticChanges, min, shapeBoundsMax[slot])
		ZoneChanges.add(dynamicChanges, min, shapeBoundsMax[slot])
	end
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
	shapeExtents[slot] = nil
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

	-- Reusable at once, as a stale tree leaf checks the new zone's shape
	ZoneShapes.zoneSlotIds[slot] = nil
	table.insert(ZoneShapes.freeZoneSlots, slot)
end

-- Only stale leaves can have changed, as every write marks its slot
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
		shapeExtents[slot],
		shapeType,
		shapeParts[slot]
	)
end

function ZoneShapes.leafContainsPoint(slot: number, point: Vector3): boolean
	return treeExact[slot] == true or ZoneShapes.containsPoint(slot, point)
end

-- Hits are leaf boxes; check each with leafContainsPoint before the trees change
function ZoneShapes.leavesAtPoint(point: Vector3, hits: { number }): number
	local hitCount = queryPoint(dynamicTree, point, hits, 0)
	return queryPoint(staticTree, point, hits, hitCount)
end

-- Rebuild when members changed or the refit gives up on a degraded tree
local function updateTree(tree: Types.Tree, members: { [number]: any })
	if tree.membersChanged or not LinearBVH.refit(tree, shapeBoundsMin, shapeBoundsMax) then
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
end

return ZoneShapes

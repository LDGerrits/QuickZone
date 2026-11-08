--!native
--!optimize 2
--!strict

local BLOCK_SHAPE_VALUE = Enum.PartType.Block.Value
local BALL_SHAPE_VALUE = Enum.PartType.Ball.Value
local CYLINDER_SHAPE_VALUE = Enum.PartType.Cylinder.Value
local WEDGE_SHAPE_VALUE = Enum.PartType.Wedge.Value
local CORNER_WEDGE_SHAPE_VALUE = Enum.PartType.CornerWedge.Value
local MESH_SHAPE_VALUE = -1 -- Meshes have no Enum.PartType equivalent
local MESH_TOLERANCE_SQ = 1e-2 * 1e-2 -- 0.01 studs to account for float error up to 50k studs

local MORTON_SHIFT16_MASK = 0xFF0000FF
local MORTON_SHIFT8_MASK = 0xF00F00F
local MORTON_SHIFT4_MASK = 0x30C30C3
local MORTON_SHIFT2_MASK = 0x9249249

local expandLUT = table.create(1024) :: { number }
for i = 0, 1023 do
	local value = i
	value = bit32.bor(bit32.lshift(value, 16), value)
	value = bit32.band(value, MORTON_SHIFT16_MASK)
	value = bit32.bor(bit32.lshift(value, 8), value)
	value = bit32.band(value, MORTON_SHIFT8_MASK)
	value = bit32.bor(bit32.lshift(value, 4), value)
	value = bit32.band(value, MORTON_SHIFT4_MASK)
	value = bit32.bor(bit32.lshift(value, 2), value)
	value = bit32.band(value, MORTON_SHIFT2_MASK)
	expandLUT[i + 1] = value
end

local function expandBits(value: number): number
	return expandLUT[bit32.band(value, 0x3FF) + 1]
end

local Geometry = {}

Geometry.BLOCK_SHAPE_VALUE = BLOCK_SHAPE_VALUE
Geometry.BALL_SHAPE_VALUE = BALL_SHAPE_VALUE
Geometry.CYLINDER_SHAPE_VALUE = CYLINDER_SHAPE_VALUE
Geometry.WEDGE_SHAPE_VALUE = WEDGE_SHAPE_VALUE
Geometry.CORNER_WEDGE_SHAPE_VALUE = CORNER_WEDGE_SHAPE_VALUE
Geometry.MESH_SHAPE_VALUE = MESH_SHAPE_VALUE

function Geometry.unionBounds(minA: Vector3, maxA: Vector3, minB: Vector3, maxB: Vector3): (Vector3, Vector3)
	return vector.min(minA, minB), vector.max(maxA, maxB)
end

-- How far a half size reaches along an axis. An infinite one reaches nowhere along an axis it is
-- perpendicular to, where the plain product would be NaN
local function reach(direction: number, half: number): number
	return if direction == 0 then 0 else math.abs(direction) * half
end

-- Bounds of a box from its basis vectors
function Geometry.getBounds(
	position: Vector3,
	right: Vector3,
	up: Vector3,
	back: Vector3,
	halfSize: Vector3
): (Vector3, Vector3)
	-- Calculate the projection of the box extents onto the global axes
	local x = math.abs(right.X) * halfSize.X + math.abs(up.X) * halfSize.Y + math.abs(back.X) * halfSize.Z
	local y = math.abs(right.Y) * halfSize.X + math.abs(up.Y) * halfSize.Y + math.abs(back.Y) * halfSize.Z
	local z = math.abs(right.Z) * halfSize.X + math.abs(up.Z) * halfSize.Y + math.abs(back.Z) * halfSize.Z

	-- Only an infinite size gets here, as for a kill plane
	if x ~= x or y ~= y or z ~= z then
		x = reach(right.X, halfSize.X) + reach(up.X, halfSize.Y) + reach(back.X, halfSize.Z)
		y = reach(right.Y, halfSize.X) + reach(up.Y, halfSize.Y) + reach(back.Y, halfSize.Z)
		z = reach(right.Z, halfSize.X) + reach(up.Z, halfSize.Y) + reach(back.Z, halfSize.Z)
	end

	local extent = Vector3.new(x, y, z)
	return position - extent, position + extent
end

function Geometry.getMortonScale(sceneMin: Vector3, sceneMax: Vector3): (number, number, number)
	local size = sceneMax - sceneMin
	return 1023 / size.X, 1023 / size.Y, 1023 / size.Z
end

function Geometry.positionToMortonCode(
	position: Vector3,
	sceneMin: Vector3,
	scaleX: number,
	scaleY: number,
	scaleZ: number
): number
	local x = math.floor(math.clamp((position.X - sceneMin.X) * scaleX, 0, 1023))
	local y = math.floor(math.clamp((position.Y - sceneMin.Y) * scaleY, 0, 1023))
	local z = math.floor(math.clamp((position.Z - sceneMin.Z) * scaleZ, 0, 1023))

	return bit32.bor(expandBits(x), bit32.lshift(expandBits(y), 1), bit32.lshift(expandBits(z), 2))
end

-- PointToObjectSpace without the engine call
local function toObjectSpace(point: Vector3, position: Vector3, right: Vector3, up: Vector3, back: Vector3): Vector3
	local offset = point - position
	return Vector3.new(vector.dot(offset, right), vector.dot(offset, up), vector.dot(offset, back))
end

-- Takes the position and basis vectors instead of a CFrame
function Geometry.isPointInShape(
	point: Vector3,
	position: Vector3,
	right: Vector3,
	up: Vector3,
	back: Vector3,
	halfSize: Vector3,
	shapeType: number,
	part: BasePart?
): boolean
	if shapeType == BLOCK_SHAPE_VALUE then
		local localPoint = vector.abs(toObjectSpace(point, position, right, up, back))
		return vector.min(localPoint, halfSize) == localPoint
	elseif shapeType == CYLINDER_SHAPE_VALUE then
		-- Along its X axis. Compared without multiplying by the length, which would be NaN for an infinite one
		local localPoint = toObjectSpace(point, position, right, up, back)
		local radius = halfSize.Y
		return math.abs(localPoint.X) <= halfSize.X
			and localPoint.Y * localPoint.Y + localPoint.Z * localPoint.Z <= radius * radius
	elseif shapeType == BALL_SHAPE_VALUE then
		local radiusSq = halfSize.X * halfSize.X
		return vector.dot(position - point, position - point) <= radiusSq
	elseif shapeType == WEDGE_SHAPE_VALUE then
		local localPoint = toObjectSpace(point, position, right, up, back)
		local absolutePoint = vector.abs(localPoint)
		if vector.min(absolutePoint, halfSize) == absolutePoint then
			local size = halfSize * 2
			return (localPoint.Y / size.Y - localPoint.Z / size.Z) <= 0
		end
		return false
	elseif shapeType == CORNER_WEDGE_SHAPE_VALUE then
		local size = halfSize * 2
		local localPoint = toObjectSpace(point, position, right, up, back)
		local plane1_normal = vector.normalize(Vector3.new(0, size.Z, size.Y))
		if vector.dot(localPoint, plane1_normal) > 0 then
			return false
		end
		local plane2_normal = vector.normalize(Vector3.new(-size.Y, size.X, 0))
		if vector.dot(localPoint, plane2_normal) > 0 then
			return false
		end
		local absolute_point = vector.abs(localPoint)
		return vector.min(absolute_point, halfSize) == absolute_point
	elseif shapeType == MESH_SHAPE_VALUE then
		if not part then
			return false
		end
		-- The part's shape placed and sized where the zone is, so a zone that was moved or resized away from
		-- its part agrees with the trees, which only know the zone
		local scale = part.ExtentsSize / (halfSize * 2)
		local partCFrame = part.CFrame
		local query = partCFrame:PointToWorldSpace(toObjectSpace(point, position, right, up, back) * scale)
		-- Measured at the zone's size, so the tolerance doesn't grow with it
		local offset = partCFrame:VectorToObjectSpace(part:GetClosestPointOnSurface(query) - query) / scale
		return vector.dot(offset, offset) <= MESH_TOLERANCE_SQ
	end

	return false
end

return Geometry

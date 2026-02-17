--!native
--!strict

local State = require(script.Parent.Parent.State)

local staticCFrames = State.staticCFrames
local staticHalfSizes = State.staticHalfSizes
local staticTypes = State.staticTypes

local dynamicCFrames = State.dynamicCFrames
local dynamicHalfSizes = State.dynamicHalfSizes
local dynamicTypes = State.dynamicTypes

local BLOCK_SHAPE_VALUE = Enum.PartType.Block.Value
local BALL_SHAPE_VALUE = Enum.PartType.Ball.Value
local CYLINDER_SHAPE_VALUE = Enum.PartType.Cylinder.Value
local WEDGE_SHAPE_VALUE = Enum.PartType.Wedge.Value
local CORNER_WEDGE_SHAPE_VALUE = Enum.PartType.CornerWedge.Value

local MORTON_SHIFT16_MASK = 0xFF0000FF
local MORTON_SHIFT8_MASK = 0xF00F00F
local MORTON_SHIFT4_MASK = 0x30C30C3
local MORTON_SHIFT2_MASK = 0x9249249

local expandLUT = table.create(1024)
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

function Geometry.unionBounds(minA: Vector3, maxA: Vector3, minB: Vector3, maxB: Vector3): (Vector3, Vector3)
	return vector.min(minA, minB), vector.max(maxA, maxB)
end

function Geometry.getObjectBounds(cframe: CFrame, halfSize: Vector3): (Vector3, Vector3)
	local pos = cframe.Position
	local right = cframe.RightVector
	local up = cframe.UpVector
	local look = cframe.LookVector

	-- Calculate the projection of the box extents onto the global axes
	local x = math.abs(right.X) * halfSize.X + math.abs(up.X) * halfSize.Y + math.abs(look.X) * halfSize.Z
	local y = math.abs(right.Y) * halfSize.X + math.abs(up.Y) * halfSize.Y + math.abs(look.Y) * halfSize.Z
	local z = math.abs(right.Z) * halfSize.X + math.abs(up.Z) * halfSize.Y + math.abs(look.Z) * halfSize.Z

	local extent = Vector3.new(x, y, z)
	return pos - extent, pos + extent
end

function Geometry.positionToMortonCode(position: Vector3, sceneMin: Vector3, sceneMax: Vector3): number
	local size = sceneMax - sceneMin
	local scaleX = 1023 / size.X
	local scaleY = 1023 / size.Y
	local scaleZ = 1023 / size.Z

	local localPos = position - sceneMin
	local x = math.floor(math.clamp(localPos.X * scaleX, 0, 1023))
	local y = math.floor(math.clamp(localPos.Y * scaleY, 0, 1023))
	local z = math.floor(math.clamp(localPos.Z * scaleZ, 0, 1023))

	return bit32.bor(expandBits(x), bit32.lshift(expandBits(y), 1), bit32.lshift(expandBits(z), 2))
end

function Geometry.isPointInZone(point: Vector3, zoneId: number, isDynamic: boolean): boolean
	local cframe, halfSize, shapeType
	if isDynamic then
		cframe = dynamicCFrames[zoneId]
		halfSize = dynamicHalfSizes[zoneId]
		shapeType = dynamicTypes[zoneId]
	else
		cframe = staticCFrames[zoneId]
		halfSize = staticHalfSizes[zoneId]
		shapeType = staticTypes[zoneId]
	end

	if shapeType == BLOCK_SHAPE_VALUE then
		local localPoint = vector.abs(cframe:PointToObjectSpace(point))
		return vector.min(localPoint, halfSize) == localPoint
	elseif shapeType == CYLINDER_SHAPE_VALUE then
		local position = cframe.Position
		local halfHeight = halfSize.X
		local start = position - cframe.RightVector * halfHeight
		local toPoint = point - start
		local axis = cframe.RightVector
		local projection = vector.dot(toPoint, axis)
		if projection >= 0 and projection <= halfHeight * 2 :: number then
			local closestPointOnAxis = start :: Vector3 + axis :: Vector3 * projection
			local distanceSq = vector.dot(point - closestPointOnAxis, point - closestPointOnAxis)
			local radiusSq = halfSize.Y * halfSize.Y
			return distanceSq <= radiusSq
		end
		return false
	elseif shapeType == BALL_SHAPE_VALUE then
		local radiusSq = halfSize.X * halfSize.X
		local position = cframe.Position
		return vector.dot(position - point, position - point) <= radiusSq
	elseif shapeType == WEDGE_SHAPE_VALUE then
		local localPoint = cframe:PointToObjectSpace(point)
		local absolutePoint = vector.abs(localPoint)
		if vector.min(absolutePoint, halfSize) == absolutePoint then
			local size = halfSize * 2
			return (localPoint.Y / size.Y - localPoint.Z / size.Z) <= 0
		end
		return false
	elseif shapeType == CORNER_WEDGE_SHAPE_VALUE then
		local size = halfSize * 2
		local localPoint = cframe:PointToObjectSpace(point)
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
	end

	return false
end

return Geometry

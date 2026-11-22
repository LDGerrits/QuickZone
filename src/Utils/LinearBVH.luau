--!native
--!optimize 2
--!strict

local Geometry = require(script.Parent.Geometry)
local Types = require(script.Parent.Parent.Types)

local HUGE_VECTOR = vector.one * math.huge
local NEGATIVE_HUGE_VECTOR = -HUGE_VECTOR

local getMortonScale = Geometry.getMortonScale
local positionToMortonCode = Geometry.positionToMortonCode

local readf32 = buffer.readf32
local readu32 = buffer.readu32
local writef32 = buffer.writef32
local writeu32 = buffer.writeu32
local extract = bit32.extract

local NODE_SIZE = 32
local MIN_Y_OFFSET = 4
local MIN_Z_OFFSET = 8
local MAX_X_OFFSET = 12
local MAX_Y_OFFSET = 16
local MAX_Z_OFFSET = 20
local SKIP_OFFSET = 24
local ID_OFFSET = 28

local RADIX_BITS = 10
local RADIX_SIZE = 1024
local RADIX_PASSES = 3
local INSERTION_SORT_LIMIT = 32

local REFIT_LIMIT = 1.5
local REFIT_BACKOFF = 8

local SHRINK_MIN_NODES = 64
local SHRINK_FACTOR = 4
-- Spare room kept when a buffer grows, as a share of what it needs: 1/8, so one more zone rarely reallocates it
local GROWTH_SHARE = 8

local LinearBVH = {}

function LinearBVH.new(): Types.Tree
	return { buffer = buffer.create(0), count = 0, cost = 0, refitSkips = 0, pendingUpdate = 'none' }
end

local EMPTY_BUFFER = buffer.create(0)
local EMPTY_BOUNDS = table.freeze({}) :: { [number]: Vector3 }
local NO_BOXES: Types.LeafBoxes = {
	min = EMPTY_BOUNDS,
	max = EMPTY_BOUNDS,
	centers = EMPTY_BOUNDS,
	halfSizes = EMPTY_BOUNDS,
}

local codesA = EMPTY_BUFFER
local idsA = EMPTY_BUFFER
local codesB = EMPTY_BUFFER
local idsB = EMPTY_BUFFER
local radixCounts = table.create(RADIX_SIZE, 0) :: { number }
local scratchOwner: Types.Tree? = nil

local sortedCodes = codesA
local sortedIds = idsA
local buildBoxes = NO_BOXES
local buildBuffer = EMPTY_BUFFER
local buildCost = 0

-- 0 when infinite, else the cost goes inf/NaN and refit never asks for a rebuild
local function halfArea(dx: number, dy: number, dz: number): number
	local area = dx * dy + dy * dz + dz * dx
	return if area < math.huge then area else 0
end

local function prepareScratch(tree: Types.Tree, count: number)
	local capacity = buffer.len(codesA) // 4
	if capacity >= count then
		if tree ~= scratchOwner or capacity <= SHRINK_MIN_NODES or capacity <= count * SHRINK_FACTOR then
			return
		end
	end

	scratchOwner = tree
	local size = (count + count // GROWTH_SHARE) * 4
	codesA = buffer.create(size)
	idsA = buffer.create(size)
	codesB = buffer.create(size)
	idsB = buffer.create(size)
	sortedCodes, sortedIds = codesA, idsA
end

function LinearBVH.scratchSize(): number
	return buffer.len(codesA)
end

-- Frees the space builds sort in, which the next build allocates again. Worth it after a build that is large and
-- rare, like the static tree's.
function LinearBVH.releaseScratch()
	codesA, idsA, codesB, idsB = EMPTY_BUFFER, EMPTY_BUFFER, EMPTY_BUFFER, EMPTY_BUFFER
	sortedCodes, sortedIds = codesA, idsA
	scratchOwner = nil
end

local function insertionSort(count: number)
	for i = 1, count - 1 do
		local code = readu32(codesA, i * 4)
		local id = readu32(idsA, i * 4)
		local j = i - 1
		while j >= 0 and readu32(codesA, j * 4) > code do
			writeu32(codesA, (j + 1) * 4, readu32(codesA, j * 4))
			writeu32(idsA, (j + 1) * 4, readu32(idsA, j * 4))
			j -= 1
		end
		writeu32(codesA, (j + 1) * 4, code)
		writeu32(idsA, (j + 1) * 4, id)
	end

	sortedCodes, sortedIds = codesA, idsA
end

local function radixSort(count: number)
	if count <= INSERTION_SORT_LIMIT then
		insertionSort(count)
		return
	end

	local srcCodes, srcIds, dstCodes, dstIds = codesA, idsA, codesB, idsB

	for pass = 0, RADIX_PASSES - 1 do
		local shift = pass * RADIX_BITS

		for digit = 1, RADIX_SIZE do
			radixCounts[digit] = 0
		end
		for i = 0, count - 1 do
			local digit = extract(readu32(srcCodes, i * 4), shift, RADIX_BITS) + 1
			radixCounts[digit] += 1
		end

		local first = extract(readu32(srcCodes, 0), shift, RADIX_BITS) + 1
		if radixCounts[first] == count then
			continue
		end

		local sum = 0
		for digit = 1, RADIX_SIZE do
			local digitCount = radixCounts[digit]
			radixCounts[digit] = sum
			sum += digitCount
		end

		for i = 0, count - 1 do
			local code = readu32(srcCodes, i * 4)
			local digit = extract(code, shift, RADIX_BITS) + 1
			local position = radixCounts[digit]
			radixCounts[digit] = position + 1
			writeu32(dstCodes, position * 4, code)
			writeu32(dstIds, position * 4, readu32(srcIds, i * 4))
		end

		srcCodes, srcIds, dstCodes, dstIds = dstCodes, dstIds, srcCodes, srcIds
	end

	sortedCodes, sortedIds = srcCodes, srcIds
end

local function getSplitPos(beginIndex: number, endIndex: number): number
	if endIndex == beginIndex + 1 then
		return beginIndex + 1
	end

	local first = readu32(sortedCodes, beginIndex * 4)
	local last = readu32(sortedCodes, endIndex * 4)

	if first == last then
		return (beginIndex + endIndex) // 2
	end

	local xor_val = bit32.bxor(first, last)
	local highest_bit = 31 - bit32.countlz(xor_val)
	local mask = bit32.lshift(1, highest_bit)
	local first_mask = bit32.band(first, mask)

	local left, right = beginIndex, endIndex
	while right - left > 1 do
		local m = (left + right) // 2
		if bit32.band(readu32(sortedCodes, m * 4), mask) == first_mask then
			left = m
		else
			right = m
		end
	end
	return left + 1
end

-- The leaf's box, or nil when the leaf has no box any more
local function boxOf(boxes: Types.LeafBoxes, id: number): (Vector3?, Vector3?)
	local min = boxes.min[id]
	if min then
		return min, boxes.max[id]
	end
	local center = boxes.centers[id]
	if center then
		local halfSize = boxes.halfSizes[id]
		return center - halfSize, center + halfSize
	end
	return nil, nil
end

local function writeNode(buf: buffer, offset: number, min: Vector3, max: Vector3, skip: number, id: number)
	writef32(buf, offset, min.X)
	writef32(buf, offset + MIN_Y_OFFSET, min.Y)
	writef32(buf, offset + MIN_Z_OFFSET, min.Z)
	writef32(buf, offset + MAX_X_OFFSET, max.X)
	writef32(buf, offset + MAX_Y_OFFSET, max.Y)
	writef32(buf, offset + MAX_Z_OFFSET, max.Z)
	writeu32(buf, offset + SKIP_OFFSET, skip)
	writeu32(buf, offset + ID_OFFSET, id)
end

local function buildFlatTree(beginIndex: number, endIndex: number, offset: number): (number, Vector3, Vector3)
	if beginIndex == endIndex then
		local id = readu32(sortedIds, beginIndex * 4)
		local min, max = boxOf(buildBoxes, id)
		local nextOffset = offset + NODE_SIZE

		writeNode(buildBuffer, offset, min, max, nextOffset, id)

		return nextOffset, min, max
	else
		local mid = getSplitPos(beginIndex, endIndex)

		local rightOffset, lMin, lMax = buildFlatTree(beginIndex, mid - 1, offset + NODE_SIZE)
		local nextOffset, rMin, rMax = buildFlatTree(mid, endIndex, rightOffset)

		local min, max = vector.min(lMin, rMin), vector.max(lMax, rMax)
		writeNode(buildBuffer, offset, min, max, nextOffset, 0)

		local extent = max - min
		buildCost += halfArea(extent.X, extent.Y, extent.Z)

		return nextOffset, min, max
	end
end

local function prepareBuffer(tree: Types.Tree, nodeCount: number): buffer
	local buf = tree.buffer
	local capacity = buffer.len(buf) // NODE_SIZE
	if capacity < nodeCount or (capacity > SHRINK_MIN_NODES and capacity > nodeCount * SHRINK_FACTOR) then
		buf = buffer.create((nodeCount + nodeCount // GROWTH_SHARE) * NODE_SIZE)
		tree.buffer = buf
	end
	return buf
end

-- Builds the tree over the keys of members, leaving out those in skip
function LinearBVH.build(
	tree: Types.Tree,
	members: { [number]: any },
	boxes: Types.LeafBoxes,
	skip: { [number]: any }?
): ()
	local positions = boxes.centers
	local min = HUGE_VECTOR
	local max = NEGATIVE_HUGE_VECTOR
	local count = 0

	for id in members do
		if skip and skip[id] then
			continue
		end
		local position = positions[id]
		local isFinite = position - position == Vector3.zero
		if isFinite then
			min = vector.min(min, position)
			max = vector.max(max, position)
		end

		count += 1
	end

	prepareScratch(tree, count)

	if count == 0 then
		prepareBuffer(tree, 0)
		tree.count = 0
		tree.cost = 0
		return
	end

	if min.X > max.X then
		min, max = Vector3.zero, Vector3.zero
	end

	local padding = vector.max(vector.one, (max - min) * 0.01)
	local sceneMin, sceneMax = min - padding, max + padding
	local scaleX, scaleY, scaleZ = getMortonScale(sceneMin, sceneMax)

	-- A second pass over members, in the same order as the first, so no list of them is kept
	local offset = 0
	for id in members do
		if skip and skip[id] then
			continue
		end
		writeu32(codesA, offset, positionToMortonCode(positions[id], sceneMin, scaleX, scaleY, scaleZ))
		writeu32(idsA, offset, id)
		offset += 4
	end
	radixSort(count)

	local nodeCount = 2 * count - 1
	buildBuffer = prepareBuffer(tree, nodeCount)
	buildBoxes = boxes
	buildCost = 0

	buildFlatTree(0, count - 1, 0)

	buildBuffer = EMPTY_BUFFER
	buildBoxes = NO_BOXES

	tree.count = nodeCount
	tree.cost = buildCost
end

function LinearBVH.tryRefit(tree: Types.Tree, boxes: Types.LeafBoxes): boolean
	if tree.refitSkips > 0 then
		tree.refitSkips -= 1
		return false
	end

	local buf = tree.buffer
	local cost = 0
	local boxesMin, boxesMax, centers, halfSizes = boxes.min, boxes.max, boxes.centers, boxes.halfSizes

	for offset = (tree.count - 1) * NODE_SIZE, 0, -NODE_SIZE do
		local id = readu32(buf, offset + ID_OFFSET)
		if id ~= 0 then
			-- Like boxOf, inline: a leaf whose box is gone has no zone any more, which only a rebuild drops
			local min, max = boxesMin[id], boxesMax[id]
			if not min then
				local center = centers[id]
				if not center then
					return false
				end
				local halfSize = halfSizes[id]
				min, max = center - halfSize, center + halfSize
			end

			writef32(buf, offset, min.X)
			writef32(buf, offset + MIN_Y_OFFSET, min.Y)
			writef32(buf, offset + MIN_Z_OFFSET, min.Z)
			writef32(buf, offset + MAX_X_OFFSET, max.X)
			writef32(buf, offset + MAX_Y_OFFSET, max.Y)
			writef32(buf, offset + MAX_Z_OFFSET, max.Z)
		else
			local left = offset + NODE_SIZE
			local right = readu32(buf, left + SKIP_OFFSET)

			local minX = math.min(readf32(buf, left), readf32(buf, right))
			local minY = math.min(readf32(buf, left + MIN_Y_OFFSET), readf32(buf, right + MIN_Y_OFFSET))
			local minZ = math.min(readf32(buf, left + MIN_Z_OFFSET), readf32(buf, right + MIN_Z_OFFSET))
			local maxX = math.max(readf32(buf, left + MAX_X_OFFSET), readf32(buf, right + MAX_X_OFFSET))
			local maxY = math.max(readf32(buf, left + MAX_Y_OFFSET), readf32(buf, right + MAX_Y_OFFSET))
			local maxZ = math.max(readf32(buf, left + MAX_Z_OFFSET), readf32(buf, right + MAX_Z_OFFSET))

			writef32(buf, offset, minX)
			writef32(buf, offset + MIN_Y_OFFSET, minY)
			writef32(buf, offset + MIN_Z_OFFSET, minZ)
			writef32(buf, offset + MAX_X_OFFSET, maxX)
			writef32(buf, offset + MAX_Y_OFFSET, maxY)
			writef32(buf, offset + MAX_Z_OFFSET, maxZ)

			cost += halfArea(maxX - minX, maxY - minY, maxZ - minZ)
		end
	end

	if cost > tree.cost * REFIT_LIMIT then
		tree.refitSkips = REFIT_BACKOFF
		return false
	end

	return true
end

function LinearBVH.queryPoint(tree: Types.Tree, point: Vector3, hits: { number }, hitCount: number): number
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z

	local offset = 0
	while offset < endOffset do
		if
			px >= readf32(buf, offset)
			and px <= readf32(buf, offset + MAX_X_OFFSET)
			and py >= readf32(buf, offset + MIN_Y_OFFSET)
			and py <= readf32(buf, offset + MAX_Y_OFFSET)
			and pz >= readf32(buf, offset + MIN_Z_OFFSET)
			and pz <= readf32(buf, offset + MAX_Z_OFFSET)
		then
			local id = readu32(buf, offset + ID_OFFSET)
			if id ~= 0 then
				hitCount += 1
				hits[hitCount] = id
			end
			offset += NODE_SIZE
		else
			offset = readu32(buf, offset + SKIP_OFFSET)
		end
	end

	return hitCount
end

-- The first leaf, in tree order, whose box holds point and that accept takes; nil if none
function LinearBVH.firstLeaf(tree: Types.Tree, point: Vector3, accept: (id: number, point: Vector3) -> boolean): number?
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z

	local offset = 0
	while offset < endOffset do
		if
			px >= readf32(buf, offset)
			and px <= readf32(buf, offset + MAX_X_OFFSET)
			and py >= readf32(buf, offset + MIN_Y_OFFSET)
			and py <= readf32(buf, offset + MAX_Y_OFFSET)
			and pz >= readf32(buf, offset + MIN_Z_OFFSET)
			and pz <= readf32(buf, offset + MAX_Z_OFFSET)
		then
			local id = readu32(buf, offset + ID_OFFSET)
			if id ~= 0 and accept(id, point) then
				return id
			end
			offset += NODE_SIZE
		else
			offset = readu32(buf, offset + SKIP_OFFSET)
		end
	end

	return nil
end

function LinearBVH.anyLeafContains(tree: Types.Tree, point: Vector3): boolean
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z

	local offset = 0
	while offset < endOffset do
		if
			px >= readf32(buf, offset)
			and px <= readf32(buf, offset + MAX_X_OFFSET)
			and py >= readf32(buf, offset + MIN_Y_OFFSET)
			and py <= readf32(buf, offset + MAX_Y_OFFSET)
			and pz >= readf32(buf, offset + MIN_Z_OFFSET)
			and pz <= readf32(buf, offset + MAX_Z_OFFSET)
		then
			if readu32(buf, offset + ID_OFFSET) ~= 0 then
				return true
			end
			offset += NODE_SIZE
		else
			offset = readu32(buf, offset + SKIP_OFFSET)
		end
	end

	return false
end

export type LeafRadius = (
	id: number,
	point: Vector3,
	minX: number,
	minY: number,
	minZ: number,
	maxX: number,
	maxY: number,
	maxZ: number
) -> number

--[=[
	The largest r, up to maxRadius, such that no leaf can change between point and any position closer than r on every
	axis. A leaf whose box doesn't hold the point limits r to its distance from the point. A leaf whose box holds it
	asks leafRadius, which returns how far the point can move before it might cross that leaf's shape (0 if unknown).
]=]
function LinearBVH.clearRadius(tree: Types.Tree, point: Vector3, maxRadius: number, leafRadius: LeafRadius): number
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z
	local radius = maxRadius

	local offset = 0
	while offset < endOffset do
		local minX = readf32(buf, offset)
		local maxX = readf32(buf, offset + MAX_X_OFFSET)
		local minY = readf32(buf, offset + MIN_Y_OFFSET)
		local maxY = readf32(buf, offset + MAX_Y_OFFSET)
		local minZ = readf32(buf, offset + MIN_Z_OFFSET)
		local maxZ = readf32(buf, offset + MAX_Z_OFFSET)
		local gap = math.max(minX - px, px - maxX, minY - py, py - maxY, minZ - pz, pz - maxZ)

		if gap >= radius then
			offset = readu32(buf, offset + SKIP_OFFSET)
		else
			local id = readu32(buf, offset + ID_OFFSET)
			if id ~= 0 then
				if gap > 0 then
					radius = gap
				else
					local limit = leafRadius(id, point, minX, minY, minZ, maxX, maxY, maxZ)
					if not (limit > 0) then
						return 0
					elseif limit < radius then
						radius = limit
					end
				end
			end
			offset += NODE_SIZE
		end
	end

	return radius
end

function LinearBVH.anyLeafIntersects(tree: Types.Tree, min: Vector3, max: Vector3): boolean
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local minX, minY, minZ = min.X, min.Y, min.Z
	local maxX, maxY, maxZ = max.X, max.Y, max.Z

	local offset = 0
	while offset < endOffset do
		if
			maxX >= readf32(buf, offset)
			and minX <= readf32(buf, offset + MAX_X_OFFSET)
			and maxY >= readf32(buf, offset + MIN_Y_OFFSET)
			and minY <= readf32(buf, offset + MAX_Y_OFFSET)
			and maxZ >= readf32(buf, offset + MIN_Z_OFFSET)
			and minZ <= readf32(buf, offset + MAX_Z_OFFSET)
		then
			if readu32(buf, offset + ID_OFFSET) ~= 0 then
				return true
			end
			offset += NODE_SIZE
		else
			offset = readu32(buf, offset + SKIP_OFFSET)
		end
	end

	return false
end

return LinearBVH

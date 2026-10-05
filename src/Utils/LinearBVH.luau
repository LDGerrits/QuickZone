--!native
--!optimize 2
--!strict

local Geometry = require(script.Parent.Geometry)
local Types = require(script.Parent.Parent.Types)

local HUGE_VECTOR = vector.one * math.huge
local NEGATIVE_HUGE_VECTOR = -HUGE_VECTOR

local unionBounds = Geometry.unionBounds
local getMortonScale = Geometry.getMortonScale
local positionToMortonCode = Geometry.positionToMortonCode

local readf32 = buffer.readf32
local readu32 = buffer.readu32
local writef32 = buffer.writef32
local writeu32 = buffer.writeu32
local extract = bit32.extract

-- Nodes are stored depth-first in one buffer, 32 bytes each:
--   0  min X, Y, Z (f32)
--   12 max X, Y, Z (f32)
--   24 byte offset of the node after this subtree (u32)
--   28 zone id, 0 for branches (u32)
local NODE_SIZE = 32
local SKIP_OFFSET = 24
local ID_OFFSET = 28

-- Morton codes are 30 bits, sorted in three 10-bit radix passes
local RADIX_BITS = 10
local RADIX_SIZE = 1024
local RADIX_PASSES = 3
local INSERTION_SORT_LIMIT = 32

-- Rebuild once the cost passes this factor of the built cost
-- Teleporting zones skip refitting for REFIT_BACKOFF updates
local REFIT_LIMIT = 1.5
local REFIT_BACKOFF = 8

-- Buffers above this many nodes shrink once less than a quarter is used
local SHRINK_MIN_NODES = 64
local SHRINK_FACTOR = 4

local LinearBVH = {}

function LinearBVH.new(): Types.Tree
	return { buffer = buffer.create(0), count = 0, cost = 0, refitSkips = 0, membersChanged = false }
end

-- Build scratch space
local memberIds = {} :: { number }
local codesA = buffer.create(0)
local idsA = buffer.create(0)
local codesB = buffer.create(0)
local idsB = buffer.create(0)
local radixCounts = table.create(RADIX_SIZE, 0) :: { number }

-- Set during a build
local sortedCodes = codesA
local sortedIds = idsA
local buildBoundsMin = {} :: { [number]: Vector3 }
local buildBoundsMax = {} :: { [number]: Vector3 }
local buildBuffer = buffer.create(0)
local buildCost = 0

-- Half the surface area, the usual BVH cost
local function halfArea(dx: number, dy: number, dz: number): number
	return dx * dy + dy * dz + dz * dx
end

local function ensureScratch(count: number)
	local size = count * 4
	if buffer.len(codesA) >= size then
		return
	end
	size = (count + count // 2) * 4
	codesA = buffer.create(size)
	idsA = buffer.create(size)
	codesB = buffer.create(size)
	idsB = buffer.create(size)
end

-- Stable insertion sort for small counts
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

-- Stable radix sort, the result ends up in sortedCodes/sortedIds
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

		-- Skip passes where every code shares the digit
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

-- First code whose highest differing bit is set
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

local function writeNode(buf: buffer, offset: number, min: Vector3, max: Vector3, skip: number, id: number)
	writef32(buf, offset, min.X)
	writef32(buf, offset + 4, min.Y)
	writef32(buf, offset + 8, min.Z)
	writef32(buf, offset + 12, max.X)
	writef32(buf, offset + 16, max.Y)
	writef32(buf, offset + 20, max.Z)
	writeu32(buf, offset + SKIP_OFFSET, skip)
	writeu32(buf, offset + ID_OFFSET, id)
end

local function buildFlatTree(beginIndex: number, endIndex: number, offset: number): (number, Vector3, Vector3)
	if beginIndex == endIndex then -- Leaf node
		local id = readu32(sortedIds, beginIndex * 4)
		local min, max = buildBoundsMin[id], buildBoundsMax[id]
		local nextOffset = offset + NODE_SIZE

		writeNode(buildBuffer, offset, min, max, nextOffset, id)

		return nextOffset, min, max
	else -- Branch node
		local mid = getSplitPos(beginIndex, endIndex)

		local rightOffset, lMin, lMax = buildFlatTree(beginIndex, mid - 1, offset + NODE_SIZE)
		local nextOffset, rMin, rMax = buildFlatTree(mid, endIndex, rightOffset)

		local min, max = unionBounds(lMin, lMax, rMin, rMax)
		-- If the point is not in this branch, we skip both subtrees
		writeNode(buildBuffer, offset, min, max, nextOffset, 0)

		local extent = max - min
		buildCost += halfArea(extent.X, extent.Y, extent.Z)

		return nextOffset, min, max
	end
end

-- The buffer to build nodeCount nodes into. A new one if it is too small or mostly unused
local function prepareBuffer(tree: Types.Tree, nodeCount: number): buffer
	local buf = tree.buffer
	local capacity = buffer.len(buf) // NODE_SIZE
	if capacity < nodeCount or (capacity > SHRINK_MIN_NODES and capacity > nodeCount * SHRINK_FACTOR) then
		-- Grow with headroom
		buf = buffer.create((nodeCount + nodeCount // 2) * NODE_SIZE)
		tree.buffer = buf
	end
	return buf
end

-- Builds the tree from the zones in members
function LinearBVH.build(
	tree: Types.Tree,
	members: { [number]: any },
	boundsMin: { [number]: Vector3 },
	boundsMax: { [number]: Vector3 },
	positions: { [number]: Vector3 }
): ()
	local min = HUGE_VECTOR
	local max = NEGATIVE_HUGE_VECTOR
	local count = 0

	-- Collect members and the scene bounds
	for id in members do
		min = vector.min(min, boundsMin[id])
		max = vector.max(max, boundsMax[id])

		count += 1
		memberIds[count] = id
	end

	if count == 0 then
		prepareBuffer(tree, 0)
		tree.count = 0
		tree.cost = 0
		return
	end

	-- Add padding to avoid edge cases with flat scenes
	local padding = vector.max(vector.one, (max - min) * 0.01)
	local sceneMin, sceneMax = min - padding, max + padding
	local scaleX, scaleY, scaleZ = getMortonScale(sceneMin, sceneMax)

	ensureScratch(count)
	for i = 1, count do
		local id = memberIds[i]
		local offset = (i - 1) * 4
		writeu32(codesA, offset, positionToMortonCode(positions[id], sceneMin, scaleX, scaleY, scaleZ))
		writeu32(idsA, offset, id)
	end
	radixSort(count)

	local nodeCount = 2 * count - 1
	buildBuffer = prepareBuffer(tree, nodeCount)
	buildBoundsMin = boundsMin
	buildBoundsMax = boundsMax
	buildCost = 0

	buildFlatTree(0, count - 1, 0)

	tree.count = nodeCount
	tree.cost = buildCost
end

-- Updates node bounds for moved zones. Returns false if the tree should be rebuilt instead
function LinearBVH.refit(tree: Types.Tree, boundsMin: { [number]: Vector3 }, boundsMax: { [number]: Vector3 }): boolean
	if tree.refitSkips > 0 then
		tree.refitSkips -= 1
		return false
	end

	local buf = tree.buffer
	local cost = 0

	-- Children follow their parent, so go backwards
	for offset = (tree.count - 1) * NODE_SIZE, 0, -NODE_SIZE do
		local id = readu32(buf, offset + ID_OFFSET)
		if id ~= 0 then
			local min, max = boundsMin[id], boundsMax[id]
			if not min then
				return false
			end

			writef32(buf, offset, min.X)
			writef32(buf, offset + 4, min.Y)
			writef32(buf, offset + 8, min.Z)
			writef32(buf, offset + 12, max.X)
			writef32(buf, offset + 16, max.Y)
			writef32(buf, offset + 20, max.Z)
		else
			local left = offset + NODE_SIZE
			local right = readu32(buf, left + SKIP_OFFSET)

			local minX = math.min(readf32(buf, left), readf32(buf, right))
			local minY = math.min(readf32(buf, left + 4), readf32(buf, right + 4))
			local minZ = math.min(readf32(buf, left + 8), readf32(buf, right + 8))
			local maxX = math.max(readf32(buf, left + 12), readf32(buf, right + 12))
			local maxY = math.max(readf32(buf, left + 16), readf32(buf, right + 16))
			local maxZ = math.max(readf32(buf, left + 20), readf32(buf, right + 20))

			writef32(buf, offset, minX)
			writef32(buf, offset + 4, minY)
			writef32(buf, offset + 8, minZ)
			writef32(buf, offset + 12, maxX)
			writef32(buf, offset + 16, maxY)
			writef32(buf, offset + 20, maxZ)

			cost += halfArea(maxX - minX, maxY - minY, maxZ - minZ)
		end
	end

	if cost > tree.cost * REFIT_LIMIT then
		tree.refitSkips = REFIT_BACKOFF
		return false
	end

	return true
end

-- Appends the ids of leaves containing the point to the hitCount ids in hits, returns the new count
function LinearBVH.queryPoint(tree: Types.Tree, point: Vector3, hits: { number }, hitCount: number): number
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z

	local offset = 0
	while offset < endOffset do
		if
			px >= readf32(buf, offset)
			and px <= readf32(buf, offset + 12)
			and py >= readf32(buf, offset + 4)
			and py <= readf32(buf, offset + 16)
			and pz >= readf32(buf, offset + 8)
			and pz <= readf32(buf, offset + 20)
		then
			local id = readu32(buf, offset + ID_OFFSET)
			if id ~= 0 then
				hitCount += 1
				hits[hitCount] = id
			end
			offset += NODE_SIZE
		else
			offset = readu32(buf, offset + SKIP_OFFSET) -- Skip branch
		end
	end

	return hitCount
end

-- Whether any leaf contains the point
function LinearBVH.anyLeafContains(tree: Types.Tree, point: Vector3): boolean
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z

	local offset = 0
	while offset < endOffset do
		if
			px >= readf32(buf, offset)
			and px <= readf32(buf, offset + 12)
			and py >= readf32(buf, offset + 4)
			and py <= readf32(buf, offset + 16)
			and pz >= readf32(buf, offset + 8)
			and pz <= readf32(buf, offset + 20)
		then
			if readu32(buf, offset + ID_OFFSET) ~= 0 then
				return true
			end
			offset += NODE_SIZE
		else
			offset = readu32(buf, offset + SKIP_OFFSET) -- Skip branch
		end
	end

	return false
end

return LinearBVH

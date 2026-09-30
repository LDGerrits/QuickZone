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

-- Nodes are stored depth-first in one buffer, 32 bytes each:
--   0  min X, Y, Z (f32)
--   12 max X, Y, Z (f32)
--   24 byte offset of the node after this subtree (u32)
--   28 zone id, 0 for branches (u32)
local NODE_SIZE = 32
local SKIP_OFFSET = 24
local ID_OFFSET = 28

type ListEntity = {
	id: number,
	mortonCode: number,
}

local LinearBVH = {}

local listCache = {} :: { ListEntity }
local entryPool = {} :: { ListEntity }

local function getSplitPos(list: { ListEntity }, beginIndex: number, endIndex: number): number
	if endIndex == beginIndex + 1 then
		return beginIndex + 1
	end

	local first = list[beginIndex].mortonCode
	local last = list[endIndex].mortonCode

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
		if bit32.band(list[m].mortonCode, mask) == first_mask then
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

local function buildFlatTree(
	list: { ListEntity },
	boundsMin: { [number]: Vector3 },
	boundsMax: { [number]: Vector3 },
	beginIndex: number,
	endIndex: number,
	buf: buffer,
	offset: number
): (number, Vector3, Vector3)
	if beginIndex == endIndex then -- Leaf node
		local id = list[beginIndex].id
		local min, max = boundsMin[id], boundsMax[id]
		local nextOffset = offset + NODE_SIZE

		writeNode(buf, offset, min, max, nextOffset, id)

		return nextOffset, min, max
	else -- Branch node
		local mid = getSplitPos(list, beginIndex, endIndex)

		local rightOffset, lMin, lMax =
			buildFlatTree(list, boundsMin, boundsMax, beginIndex, mid - 1, buf, offset + NODE_SIZE)
		local nextOffset, rMin, rMax = buildFlatTree(list, boundsMin, boundsMax, mid, endIndex, buf, rightOffset)

		local min, max = unionBounds(lMin, lMax, rMin, rMax)
		-- If the point is not in this branch, we skip both subtrees
		writeNode(buf, offset, min, max, nextOffset, 0)

		return nextOffset, min, max
	end
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

	-- Calculate scene bounds and update listCache
	for id in members do
		min = vector.min(min, boundsMin[id])
		max = vector.max(max, boundsMax[id])

		count += 1

		local entry = listCache[count]
		if not entry then
			local poolSize = #entryPool
			if poolSize > 0 then
				entry = entryPool[poolSize]
				entryPool[poolSize] = nil
			else
				entry = { id = 0, mortonCode = 0 }
			end
			listCache[count] = entry
		end

		entry.id = id
	end

	if count == 0 then
		tree.count = 0
		return
	end

	-- Push unused entries from the tail into the pool
	local cacheSize = #listCache
	if cacheSize > count then
		local poolSize = #entryPool
		for i = count + 1, cacheSize do
			poolSize += 1
			entryPool[poolSize] = listCache[i]
			listCache[i] = nil
		end
	end

	-- Add padding to avoid edge cases with flat scenes
	local padding = vector.max(vector.one, (max - min) * 0.01)
	local sceneMin, sceneMax = min - padding, max + padding
	local scaleX, scaleY, scaleZ = getMortonScale(sceneMin, sceneMax)

	for i = 1, count do
		local entry = listCache[i]
		entry.mortonCode = positionToMortonCode(positions[entry.id], sceneMin, scaleX, scaleY, scaleZ)
	end

	table.sort(listCache, function(a: ListEntity, b: ListEntity)
		return a.mortonCode < b.mortonCode
	end)

	local nodeCount = 2 * count - 1
	local buf = tree.buffer
	if buffer.len(buf) < nodeCount * NODE_SIZE then
		-- Grow with headroom
		buf = buffer.create((nodeCount + nodeCount // 2) * NODE_SIZE)
		tree.buffer = buf
	end

	buildFlatTree(listCache, boundsMin, boundsMax, 1, count, buf, 0)

	tree.count = nodeCount
end

-- Writes the ids of leaves containing the point to hits, returns the count
function LinearBVH.queryPoint(tree: Types.Tree, point: Vector3, hits: { number }): number
	local buf = tree.buffer
	local endOffset = tree.count * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z
	local hitCount = 0

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

-- Resumable queryPoint. Returns the offset to resume from and the leaf id (0 when done)
function LinearBVH.nextLeaf(buf: buffer, nodeCount: number, point: Vector3, offset: number): (number, number)
	local endOffset = nodeCount * NODE_SIZE
	local px, py, pz = point.X, point.Y, point.Z

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
			offset += NODE_SIZE
			if id ~= 0 then
				return offset, id
			end
		else
			offset = readu32(buf, offset + SKIP_OFFSET) -- Skip branch
		end
	end

	return endOffset, 0
end

return LinearBVH

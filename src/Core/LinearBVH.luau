--!native
--!strict

local Geometry = require(script.Parent.Geometry)
local Types = require(script.Parent.Parent.Types)

local HUGE_VECTOR = Vector3.one * math.huge
local NEGATIVE_HUGE_VECTOR = -HUGE_VECTOR

local unionBounds = Geometry.unionBounds
local getObjectBounds = Geometry.getObjectBounds
local getMortonScale = Geometry.getMortonScale
local positionToMortonCode = Geometry.positionToMortonCode

type ListEntity = {
	id: number,
	mortonCode: number,
}

local LinearBVH = {}
LinearBVH.__index = LinearBVH

local listCache = table.create(2000)
local objMinCache = table.create(2000)
local objMaxCache = table.create(2000)
local traversalStack = table.create(64)
local treePools = {} :: { [any]: {
	nodeCache: { Types.Node },
	nodeCount: number,
} }

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

local function createSubTree(
	list: { ListEntity },
	boundsMin: { Vector3 },
	boundsMax: { Vector3 },
	beginIndex: number,
	endIndex: number,
	pool: {
		nodeCache: { Types.Node },
		nodeCount: number,
	}
): Types.Node
	pool.nodeCount += 1
	local node = pool.nodeCache[pool.nodeCount]
	if not node then
		node = {} :: Types.Node
		pool.nodeCache[pool.nodeCount] = node
	end

	if beginIndex == endIndex then
		local id = list[beginIndex].id
		node.min = boundsMin[id]
		node.max = boundsMax[id]
		node.id = id
		node.left = nil
		node.right = nil
	else
		local mid = getSplitPos(list, beginIndex, endIndex)
		local left = createSubTree(list, boundsMin, boundsMax, beginIndex, mid - 1, pool)
		local right = createSubTree(list, boundsMin, boundsMax, mid, endIndex, pool)
		local min, max = unionBounds(left.min, left.max, right.min, right.max)

		node.min = min
		node.max = max
		node.id = -1
		node.left = left
		node.right = right
	end

	return node
end

function LinearBVH.build(cframes: { [number]: CFrame }, halfSizes: { [number]: Vector3 }): Types.Node?
	-- Pool per unique list reference (static and dynamic) to allow reuse.
	-- We don't need to clear the cache, since we track count separately.
	local pool = treePools[cframes]
	if not pool then
		pool = {
			nodeCache = table.create(4000),
			nodeCount = 0,
		}
		treePools[cframes] = pool
	end
	pool.nodeCount = 0

	table.clear(traversalStack)
	table.clear(objMinCache)
	table.clear(objMaxCache)

	local min = HUGE_VECTOR
	local max = NEGATIVE_HUGE_VECTOR
	local count = 0

	-- Calculate bounds and update listCache
	for id, cframe in cframes do
		local halfSize = halfSizes[id]

		local bMin, bMax = getObjectBounds(cframe, halfSize)

		objMinCache[id] = bMin
		objMaxCache[id] = bMax

		min = vector.min(min, bMin)
		max = vector.max(max, bMax)

		count += 1

		local cachedEntry = listCache[count]
		if cachedEntry then
			cachedEntry.id = id
			cachedEntry.mortonCode = 0
		else
			listCache[count] = { id = id, mortonCode = 0 }
		end
	end

	if count == 0 then
		return nil
	end

	-- Add padding to avoid edge cases with flat scenes
	local padding = vector.max(vector.one, (max - min) * 0.01)
	local sceneMin, sceneMax = min - padding, max + padding
	local scaleX, scaleY, scaleZ = getMortonScale(sceneMin, sceneMax)

	for i = 1, count do
		local entry = listCache[i]
		local pos = cframes[entry.id].Position -- Fast property access
		entry.mortonCode = positionToMortonCode(pos, sceneMin, scaleX, scaleY, scaleZ)
	end

	-- Remove unused cached entries at tail
	for i = count + 1, #listCache do
		listCache[i] = nil
	end

	table.sort(listCache, function(a, b)
		return a.mortonCode < b.mortonCode
	end)

	return createSubTree(listCache, objMinCache, objMaxCache, 1, count, pool)
end

function LinearBVH.queryPoint(root: Types.Node?, point: Vector3, callback: (id: number) -> ())
	if not root then
		return
	end

	local px, py, pz = point.X, point.Y, point.Z
	local rootMin, rootMax = root.min, root.max
	if px < rootMin.X or px > rootMax.X or py < rootMin.Y or py > rootMax.Y or pz < rootMin.Z or pz > rootMax.Z then
		return
	end

	local stackPtr = 1
	traversalStack[1] = root

	while stackPtr > 0 do
		local node = traversalStack[stackPtr]
		stackPtr -= 1

		local min, max = node.min, node.max
		if
			point.X >= min.X
			and point.X <= max.X
			and point.Y >= min.Y
			and point.Y <= max.Y
			and point.Z >= min.Z
			and point.Z <= max.Z
		then
			if node.id > 0 then
				callback(node.id)
			else
				stackPtr += 1
				traversalStack[stackPtr] = node.left :: Types.Node
				stackPtr += 1
				traversalStack[stackPtr] = node.right :: Types.Node
			end
		end
	end
end

return LinearBVH

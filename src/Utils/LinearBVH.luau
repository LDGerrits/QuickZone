--!native
--!optimize 2
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

local listCache = {} :: { ListEntity }
local entryPool = {} :: { ListEntity }
local objMinCache = {} :: { [number]: Vector3 }
local objMaxCache = {} :: { [number]: Vector3 }

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

local function buildFlatTree(
	list: { ListEntity },
	boundsMin: { Vector3 },
	boundsMax: { Vector3 },
	beginIndex: number,
	endIndex: number,
	tree: Types.Tree,
	currentIndex: number
): (number, Vector3, Vector3)
	local node = tree.nodes[currentIndex]
	if not node then
		node = {} :: Types.Node
		tree.nodes[currentIndex] = node
	end

	if beginIndex == endIndex then -- Leaf node
		local id = list[beginIndex].id
		local min, max = boundsMin[id], boundsMax[id]

		node.min = min
		node.max = max
		node.id = id
		node.skipIndex = currentIndex + 1

		return currentIndex + 1, min, max
	else -- Branch node
		local mid = getSplitPos(list, beginIndex, endIndex)
		node.id = -1

		local rightIndex, lMin, lMax =
			buildFlatTree(list, boundsMin, boundsMax, beginIndex, mid - 1, tree, currentIndex + 1)
		local nextIndex, rMin, rMax = buildFlatTree(list, boundsMin, boundsMax, mid, endIndex, tree, rightIndex)

		local min, max = unionBounds(lMin, lMax, rMin, rMax)
		node.min = min
		node.max = max
		node.skipIndex = nextIndex -- If the point is not in this branch, we skip both subtrees

		return nextIndex, min, max
	end
end

function LinearBVH.build(tree: Types.Tree, cframes: { [number]: CFrame }, halfSizes: { [number]: Vector3 }): ()
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

		min = min:Min(bMin)
		max = max:Max(bMax)

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
	local padding = ((max - min) * 0.01):Max(Vector3.one)
	local sceneMin, sceneMax = min - padding, max + padding
	local scaleX, scaleY, scaleZ = getMortonScale(sceneMin, sceneMax)

	for i = 1, count do
		local entry = listCache[i]
		local pos = cframes[entry.id].Position -- Fast property access
		entry.mortonCode = positionToMortonCode(pos, sceneMin, scaleX, scaleY, scaleZ)
	end

	table.sort(listCache, function(a: ListEntity, b: ListEntity)
		return a.mortonCode < b.mortonCode
	end)

	local nextAvailableIndex = buildFlatTree(listCache, objMinCache, objMaxCache, 1, count, tree, 1)

	tree.count = nextAvailableIndex - 1
end

function LinearBVH.queryPoint(tree: Types.Tree, point: Vector3, callback: (id: number) -> ())
	local nodes = tree.nodes
	local count = tree.count
	local px, py, pz = point.X, point.Y, point.Z

	local index = 1
	while index <= count do
		local node = nodes[index]
		local min, max = node.min, node.max
		if px >= min.X and px <= max.X and py >= min.Y and py <= max.Y and pz >= min.Z and pz <= max.Z then
			index += 1
			local nodeId = node.id
			if nodeId > 0 then
				callback(nodeId)
			end
		else
			index = node.skipIndex -- Skip branch
		end
	end
end

return LinearBVH

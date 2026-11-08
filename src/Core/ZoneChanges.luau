--!native
--!optimize 2
--!strict

-- Where a tree's zones changed per version, so entities standing still only re-query near a change

local LinearBVH = require(script.Parent.Parent.Utils.LinearBVH)
local Types = require(script.Parent.Parent.Types)

local anyLeafContains = LinearBVH.anyLeafContains

local HISTORY = 16
-- More boxes than this, or than the tree has zones, counts as everything changed
local MIN_BOXES = 64
local MAX_BOXES = 2048

local boxCenters = {} :: { Vector3 }

local function addAll(log: Types.ZoneChanges)
	log.all = true
	log.boxCount = 0
	table.clear(log.boxesMin)
	table.clear(log.boxesMax)
end

local ZoneChanges = {}

function ZoneChanges.new(): Types.ZoneChanges
	return {
		boxesMin = {},
		boxesMax = {},
		boxCount = 0,
		all = false,
		boxLimit = 0,
		history = {},
	}
end

-- Empty boxes (min above max) are skipped
function ZoneChanges.add(log: Types.ZoneChanges, min: Vector3, max: Vector3)
	if log.all or min.X > max.X then
		return
	end

	local count = log.boxCount + 1
	if count > log.boxLimit then
		addAll(log)
		return
	end

	log.boxesMin[count] = min
	log.boxesMax[count] = max
	log.boxCount = count
end

function ZoneChanges.commit(log: Types.ZoneChanges, version: number, zoneCount: number): boolean
	local count = log.boxCount
	if not log.all and count == 0 then
		return false
	end

	local index = version % HISTORY + 1
	local slot = log.history[index]
	if not slot then
		slot = {
			version = -1,
			all = false,
			tree = LinearBVH.new(),
		}
		log.history[index] = slot
	end

	slot.version = version
	slot.all = log.all

	local boxesMin, boxesMax = log.boxesMin, log.boxesMax
	for i = 1, count do
		boxCenters[i] = (boxesMin[i] + boxesMax[i]) * 0.5
	end

	-- Box indices are the leaf ids; empty when everything changed, freeing the old leaves
	LinearBVH.build(slot.tree, boxesMin, boxesMin, boxesMax, boxCenters)

	table.clear(boxesMin)
	table.clear(boxesMax)
	table.clear(boxCenters)

	log.boxCount = 0
	log.all = false
	log.boxLimit = math.clamp(zoneCount, MIN_BOXES, MAX_BOXES)

	return true
end

-- Whether a change after fromVersion up to toVersion touched a or b
function ZoneChanges.touches(
	log: Types.ZoneChanges,
	fromVersion: number,
	toVersion: number,
	a: Vector3,
	b: Vector3
): boolean
	if fromVersion < 0 or toVersion - fromVersion > HISTORY then
		return true
	end

	local history = log.history
	for version = fromVersion + 1, toVersion do
		local slot = history[version % HISTORY + 1]
		if not slot or slot.version ~= version or slot.all then
			return true
		end

		local tree = slot.tree
		if anyLeafContains(tree, a) or (b ~= a and anyLeafContains(tree, b)) then
			return true
		end
	end

	return false
end

return ZoneChanges

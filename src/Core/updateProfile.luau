local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)

local function updateProfile(entity: Types.Entity)
	local groups = State.entityToGroups[entity]
	if not groups then
		return
	end

	-- Find the highest settings across all subscribed observers
	local minPrecSq = math.huge
	local maxRate = 0
	for groupId in groups do
		local observers = State.groupToObservers[groupId]
		if not observers then
			continue
		end
		for observerId in observers do
			local obsConfig = State.observerConfig[observerId]
			if obsConfig.precisionSq < minPrecSq then
				minPrecSq = obsConfig.precisionSq
			end
			if obsConfig.updateRate > maxRate then
				maxRate = obsConfig.updateRate
			end
		end
	end

	local data = State.entityData[entity]
	local currentRate = data.effectiveRate

	-- Swap buckets
	if currentRate ~= maxRate then
		-- Remove from old bucket
		if currentRate and currentRate > 0 and State.buckets[currentRate] then
			local oldBucket = State.buckets[currentRate]
			local idx = data.bucketIndex
			local lastEntity = oldBucket[#oldBucket]

			-- Swap-remove
			oldBucket[idx] = lastEntity
			if State.entityData[lastEntity] then
				State.entityData[lastEntity].bucketIndex = idx
			end
			oldBucket[#oldBucket] = nil
		end

		-- Add to new bucket
		if maxRate > 0 then
			if not State.buckets[maxRate] then
				State.buckets[maxRate] = {}
			end
			local newBucket = State.buckets[maxRate]
			local newIdx = #newBucket + 1
			newBucket[newIdx] = entity

			data.bucketIndex = newIdx
		else
			data.bucketIndex = 0 -- Entity is not in a bucket, so no processing
		end

		data.effectiveRate = maxRate
	end

	-- 3. Update precision (only matters if it's being processed)
	if maxRate > 0 then
		data.effectivePrecisionSq = minPrecSq
	end
end

return updateProfile

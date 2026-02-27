--!strict

local Types = require(script.Parent.Parent.Types)
local State = require(script.Parent.State)

local function updateProfile(entity: Types.Entity)
	local groups = State.entityToGroups[entity]
	if not groups then
		return
	end

	-- Track linked observers for quick lookup in hot loop
	local linkedObservers = State.entityToObservers[entity]
	if linkedObservers then
		table.clear(linkedObservers)
	else
		linkedObservers = {}
	end

	local minPrecSq = math.huge
	local maxRate = 0

	-- Find the highest settings across all subscribed observers
	for groupId, _ in groups do
		local observers = State.groupToObservers[groupId]
		if not observers then
			continue
		end

		for observerId, _ in observers do
			linkedObservers[observerId] = true

			local prec = State.observerPrecisionSq[observerId]
			local rate = State.observerUpdateRate[observerId]

			if prec < minPrecSq then
				minPrecSq = prec
			end
			if rate > maxRate then
				maxRate = rate
			end
		end
	end

	local data = State.entityData[entity]
	local currentRate = data.updateRate

	-- Swap buckets
	if currentRate ~= maxRate then
		-- Remove from old bucket
		if currentRate and currentRate > 0 and State.buckets[currentRate] then
			local oldBucket = State.buckets[currentRate]
			local idx = data.bucketIndex
			local maxEntities = #oldBucket
			local lastEntity = oldBucket[maxEntities]

			-- We swap and then pop to avoid shifting all entities down
			if idx ~= maxEntities then
				oldBucket[idx] = lastEntity
				if State.entityData[lastEntity] then
					State.entityData[lastEntity].bucketIndex = idx
				end
			end

			oldBucket[maxEntities] = nil

			if maxEntities == 1 then -- destroy empty bucket
				State.buckets[currentRate] = nil
				local listIdx = table.find(State.bucketList, currentRate)
				if listIdx then
					table.remove(State.bucketList, listIdx)
				end
			end
		end

		-- Add to new bucket
		if maxRate > 0 then
			if not State.buckets[maxRate] then
				State.buckets[maxRate] = {}
				table.insert(State.bucketList, maxRate)
				table.sort(State.bucketList, function(a, b)
					return a > b
				end)
			end

			local newBucket = State.buckets[maxRate]
			local newIdx = #newBucket + 1
			newBucket[newIdx] = entity
			data.bucketIndex = newIdx
		else
			data.bucketIndex = 0 -- Entity is not in a bucket, so no processing
		end

		data.updateRate = maxRate
	end

	if maxRate > 0 then
		data.precisionSq = minPrecSq
		State.entityToObservers[entity] = linkedObservers
	else
		State.entityToObservers[entity] = nil
	end
end

return updateProfile

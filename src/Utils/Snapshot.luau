--!strict

-- Survives the table changing mid-loop, where next() errors once a removed key is rehashed away. Removed keys
-- are skipped, added keys are not visited

-- Pooled so repeated loops don't allocate
local spareLists = {} :: { { any } }
local MAX_SPARE_LISTS = 4

local Snapshot = {}

function Snapshot.keys<K, V>(t: { [K]: V }): () -> (K?, V?)
	local list: { any }? = table.remove(spareLists) or {}
	for key in t do
		table.insert(list :: { any }, key)
	end

	local i = 0
	return function(): (K?, V?)
		while list do
			i += 1
			local key = list[i]
			if key == nil then
				table.clear(list)
				if #spareLists < MAX_SPARE_LISTS then
					table.insert(spareLists, list)
				end
				-- The list is back in the pool; a call after the end must not read it
				list = nil
				break
			end

			local value = t[key]
			if value ~= nil then
				return key, value
			end
		end
		return nil, nil
	end
end

return Snapshot

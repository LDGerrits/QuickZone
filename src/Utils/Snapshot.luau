--!strict

-- Survives the table changing mid-loop, where next() errors once a removed key is rehashed away. Removed keys
-- are skipped, added keys are not visited

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
		local current = list
		while current do
			i += 1
			local key = current[i]
			if key == nil then
				table.clear(current)
				if #spareLists < MAX_SPARE_LISTS then
					table.insert(spareLists, current)
				end
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

function Snapshot.collect<T>(iterate: () -> T?): { T }
	local list = {}
	for value in iterate do
		table.insert(list, value)
	end
	return list
end

return Snapshot

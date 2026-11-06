--!strict

-- Iterates a table's keys as they were when the loop started, so the loop survives the table changing under
-- it, also when its body yields. A plain next() would error once a removed key is rehashed away. Keys removed
-- since the start are skipped when reached, keys added are not visited

-- Lists reused once a loop runs to the end, so a loop allocates nothing after the first
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
				-- Called again after the end, must not read a list another loop uses
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

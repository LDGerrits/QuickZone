--!strict
local State = require(script.Parent.State)
local Types = require(script.Parent.Types)
local Config = require(script.Parent.Config)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

local Collection = {}
Collection.__index = Collection

function Collection.new(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
}?): Types.Collection
	local hz = config and config.UpdateRate
	assert(not hz or hz > 0, '[BitZone] UpdateRate must be greater than 0')

	local n = config and config.Precision
	assert(not n or n >= 0, '[BitZone] Precision must be non-negative')

	local id = State.NextCollectionId
	State.NextCollectionId += 1

	local updateRate = hz or Config.Scheduler.UpdateRate
	local precision = n or Config.Scheduler.Precision
	local safetyMode = Config.Scheduler.SafetyMode
	if config and config.SafetyMode ~= nil then
		safetyMode = config.SafetyMode
	end

	local self = (
		setmetatable({
			Id = id,
			_items = {},
			_itemIndices = {},
			_itemData = {},
			_config = {
				UpdateRate = updateRate,
				PrecisionSq = precision ^ 2,
				SafetyMode = safetyMode,
			},
			_lastProcessedIndex = 1,
		}, Collection) :: any
	) :: Types.Collection

	State.Collections[id] = self
	State.CollectionToGroups[id] = {}

	return self
end

function Collection:SetConfig(config: {
	UpdateRate: number?,
	Precision: number?,
	SafetyMode: boolean?,
})
	local hz = config.UpdateRate
	assert(not hz or hz > 0, '[BitZone] UpdateRate must be greater than 0')

	local n = config.Precision
	assert(not n or n >= 0, '[BitZone] Precision must be non-negative')

	if hz then
		self._config.UpdateRate = hz
	end
	if n then
		self._config.Precision = n
	end
	if config.SafetyMode ~= nil then
		self._config.SafetyMode = config.SafetyMode
	end
end

function Collection:SetUpdateRate(hz: number): Types.Collection
	assert(hz > 0, '[BitZone] UpdateRate must be greater than 0')

	self._config.UpdateRate = hz

	return self
end

function Collection:SetPrecision(n: number): Types.Collection
	assert(n >= 0, '[BitZone] Precision must be non-negative')

	self._config.PrecisionSq = n ^ 2
	return self
end

function Collection:SetSafetyMode(enabled: boolean): Types.Collection
	self.Con_configfig.SafetyMode = enabled
	return self
end

function Collection:Add(item: Types.Item, customData: any?): Types.Collection
	local oldColId = State.ItemToCollection[item]
	if oldColId then
		if oldColId == self.Id then
			return self
		end
		local oldCol = State.Collections[oldColId]
		if oldCol then
			oldCol:Remove(item)
		end
	end

	local strat
	if typeof(item) == 'Instance' then
		if item:IsA('BasePart') then
			strat = STRAT_POS
		elseif item:IsA('Attachment') or item:IsA('Bone') then
			strat = STRAT_WORLD
		elseif item:IsA('Camera') then
			strat = STRAT_CFRAME
		elseif item:IsA('Model') then
			strat = item.PrimaryPart and STRAT_PRIM or STRAT_PIVOT
		end
	elseif typeof(item) == 'table' then
		if item.Position then
			strat = STRAT_POS
		elseif item.CFrame then
			strat = STRAT_CFRAME
		elseif item.WorldPosition then
			strat = STRAT_WORLD
		elseif item.GetPivot then
			strat = STRAT_PIVOT
		end
	end

	if not strat then
		error(
			string.format(
				'[BitZone] TrackItem Failed: The provided item (%s) is not a supported type. '
					.. 'Ensure it is a BasePart, Model, Attachment, Bone, Camera, or a table with a Position/CFrame.',
				tostring(item)
			),
			2
		)
	end

	local data = {
		lastPosition = Vector3.zero,
		Strategy = strat,
		IsDirty = true,
		ActiveGroupMemberships = {},
	}

	local idx = #self._items + 1
	self._items[idx] = item
	self._itemIndices[item] = idx
	self._itemData[item] = data

	State.ItemToCollection[item] = self.Id

	if customData then
		if not State.ItemCustomData[item] then
			State.ItemCustomData[item] = {}
		end
		State.ItemCustomData[item] = customData
	end

	return self
end

function Collection:Remove(item: Types.Item): Types.Collection
	if State.ItemToCollection[item] ~= self.Id then
		return self
	end

	local data = self._itemData[item]

	-- Trigger exit
	local safetyMode = self._config.SafetyMode
	for gId, oldZoneIdx in pairs(data.ActiveGroupMemberships) do
		if State.GroupTrackingItems[gId] then
			State.GroupTrackingItems[gId][item] = nil
		end

		local cbs = State.GroupExitedCallbacks[gId]
		if cbs then
			local z = State.ZoneIdToZoneObj[oldZoneIdx]
			local cd = State.ItemCustomData[item] and State.ItemCustomData[item][gId]
			for _, fn in cbs do
				if safetyMode then
					task.spawn(fn, item, z, cd)
				else
					fn(item, z, cd)
				end
			end
		end
	end

	-- Swap-remove from Array
	local idx = self._itemIndices[item]
	local lastIdx = #self._items
	local lastItem = self._items[lastIdx]

	if idx == lastIdx then
		self._items[lastIdx] = nil
		self._itemIndices[item] = nil
	else
		self._items[idx] = lastItem
		self._itemIndices[lastItem] = idx
		self._items[lastIdx] = nil
		self._itemIndices[item] = nil
	end

	self._itemData[item] = nil
	State.ItemToCollection[item] = nil
	State.ItemCustomData[item] = nil

	return self
end

function Collection:GetItems(): { Types.Item }
	local result = table.create(#self._items)
	table.move(self._items, 1, #self._items, 1, result)
	return result
end

function Collection:GetGroups(): { Types.Group }
	local result = {}
	local groupsMap = State.CollectionToGroups[self.Id]

	if groupsMap then
		for groupId, _ in pairs(groupsMap) do
			local group = State.GroupIdToGroupObj[groupId]
			if group then
				table.insert(result, group)
			end
		end
	end

	return result
end

function Collection:GetConfig(): {
	UpdateRate: number,
	Precision: number,
	SafetyMode: boolean,
}
	local config = self._config
	return {
		UpdateRate = config.UpdateRate,
		Precision = math.sqrt(config.PrecisionSq),
		SafetyMode = config.SafetyMode,
	}
end

function Collection:Destroy(): ()
	for i = #self._items, 1, -1 do
		self:Remove(self._items[i])
	end

	State.CollectionToGroups[self.Id] = nil
	State.Collections[self.Id] = nil
	setmetatable(self :: any, nil)
end

return Collection

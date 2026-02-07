--!strict

local Geometry = require(script.Parent.Geometry)
local SpatialIndex = require(script.Parent.SpatialIndex)
local State = require(script.Parent.State)
local Strategy = require(script.Parent.Strategy)
local Types = require(script.Parent.Types)

local STRAT_POS = Strategy.POS
local STRAT_PRIM = Strategy.PRIM
local STRAT_WORLD = Strategy.WORLD
local STRAT_CFRAME = Strategy.CFRAME
local STRAT_PIVOT = Strategy.PIVOT

local Group = {}
Group.__index = Group

function Group.new(priority: number?): Types.Group
	local g = (setmetatable({ UID = State.nextGroupId }, Group) :: any) :: Types.Group

	State.groupPriorityMap[g.UID] = priority or 1e6
	State.groupEnteredCallbacks[g.UID] = {}
	State.groupExitedCallbacks[g.UID] = {}
	State.groupActiveMembers[g.UID] = setmetatable({}, { __mode = 'k' }) :: any
	State.groupUIDToGroupObj[g.UID] = g

	State.nextGroupId += 1
	return g
end

function Group:TrackItem(item: Types.Item, customData: any?): Types.Group
	local data = State.items[item]
	if not data then
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
			error('Invalid item')
			return
		end

		data = {
			activeGroupMemberships = {},
			memberOfGroups = {},
			lastPosition = Vector3.zero,
			strategy = strat,
			isDirty = true,
		}
		State.items[item] = data
	end

	if customData ~= nil then
		if not State.itemCustomData[item] then
			State.itemCustomData[item] = {}
		end
		State.itemCustomData[item][self.UID] = customData
	end

	data.memberOfGroups[self.UID] = true
	data.isDirty = true

	return self
end

function Group:UntrackItem(item: Types.Item): Types.Group
	local data = State.items[item]
	if not data then
		return self
	end

	-- Exit Logic
	local oldZoneIdx = data.activeGroupMemberships[self.UID]
	if oldZoneIdx then
		if State.groupActiveMembers[self.UID] then
			State.groupActiveMembers[self.UID][item] = nil
		end

		local cbs = State.groupExitedCallbacks[self.UID]
		if cbs then
			local z = State.zoneIndexToZoneObj[oldZoneIdx]
			local cd = State.itemCustomData[item] and State.itemCustomData[item][self.UID]
			for _, fn in cbs do
				task.spawn(fn, item, z, cd)
			end
		end
	end

	data.activeGroupMemberships[self.UID] = nil
	data.memberOfGroups[self.UID] = nil

	if State.itemCustomData[item] then
		State.itemCustomData[item][self.UID] = nil
		if next(State.itemCustomData[item]) == nil then
			State.itemCustomData[item] = nil
		end
	end

	if next(data.memberOfGroups) == nil then
		State.items[item] = nil
	end

	return self
end

function Group:SetPriority(p: number): Types.Group
	State.groupPriorityMap[self.UID] = p
	State.isDirty = true
	return self
end

function Group:IsItemInside(item: Types.Item): boolean
	local data = State.items[item]
	if not data then
		return false
	end
	return data.activeGroupMemberships[self.UID] ~= nil
end

function Group:IsItemTracked(item: Types.Item): boolean
	local data = State.items[item]
	if not data then
		return false
	end
	return data.memberOfGroups[self.UID] == true
end

function Group:GetTrackedItems(): { Types.Item }
	local results = {}
	for t, data in pairs(State.items) do
		if data.memberOfGroups[self.UID] then
			table.insert(results, t)
		end
	end
	return results
end

function Group:GetItemsInside(): { Types.Item }
	local members = State.groupActiveMembers[self.UID]
	if not members then
		return {}
	end
	local results = {}
	for t, _ in pairs(members) do
		table.insert(results, t)
	end
	return results
end

function Group:GetZones(): { Types.Zone }
	local results = {}
	for zoneIdx, watchingList in pairs(State.zoneWatchingGroups) do
		if table.find(watchingList, self.UID) then
			local zone = State.zoneIndexToZoneObj[zoneIdx]
			if zone then
				table.insert(results, zone)
			end
		end
	end
	return results
end

function Group:IsPointInside(position: Vector3): boolean
	if not State.rootNode then
		return false
	end
	local isInside = false

	SpatialIndex.QueryPoint(State.rootNode, position, function(zoneId)
		if isInside then
			return
		end
		local groups = State.zoneWatchingGroups[zoneId]
		if groups and table.find(groups, self.UID) then
			if Geometry.IsPointInShape(position, State.objects[zoneId]) then
				isInside = true
			end
		end
	end)
	return isInside
end

function Group:OnEntered(callback)
	table.insert(State.groupEnteredCallbacks[self.UID], callback)
	return function()
		local i = table.find(State.groupEnteredCallbacks[self.UID], callback)
		if i then
			table.remove(State.groupEnteredCallbacks[self.UID], i)
		end
	end
end

function Group:OnExited(callback)
	table.insert(State.groupExitedCallbacks[self.UID], callback)
	return function()
		local i = table.find(State.groupExitedCallbacks[self.UID], callback)
		if i then
			table.remove(State.groupExitedCallbacks[self.UID], i)
		end
	end
end

function Group:Destroy()
	local uid = self.UID

	-- Remove from zones
	for _, watchingList in pairs(State.zoneWatchingGroups) do
		local idx = table.find(watchingList, uid)
		while idx do
			table.remove(watchingList, idx)
			idx = table.find(watchingList, uid)
		end
	end

	for t, data in pairs(State.items) do
		if data.memberOfGroups[uid] then
			self:UntrackItem(t)
		end
	end

	State.groupPriorityMap[uid] = nil
	State.groupEnteredCallbacks[uid] = nil
	State.groupExitedCallbacks[uid] = nil
	State.groupActiveMembers[uid] = nil
	State.groupUIDToGroupObj[uid] = nil

	State.isDirty = true
end

return Group

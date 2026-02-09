--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.State)
local Types = require(script.Parent.Types)

local IS_CLIENT = RunService:IsClient()

local Group = {}
Group.__index = Group

function Group.new(priority: number?): Types.Group
	local group = (
		setmetatable({
			Id = State.NextGroupId,
			_mainConnections = {},
			_playerTrackers = {},
		}, Group) :: any
	) :: Types.Group

	State.GroupPriorityMap[group.Id] = priority or 0
	State.GroupEnteredCallbacks[group.Id] = {}
	State.GroupExitedCallbacks[group.Id] = {}
	State.GroupTrackingItems[group.Id] = {}
	State.GroupIdToGroupObj[group.Id] = group

	State.NextGroupId += 1
	return group
end

function Group:SetPriority(p: number): Types.Group
	State.GroupPriorityMap[self.Id] = p
	State.IsDirty = true
	return self
end

function Group:TrackCollection(collection: Types.Collection): Types.Group
	local colId = collection.Id
	if not State.CollectionToGroups[colId] then
		State.CollectionToGroups[colId] = {}
	end
	State.CollectionToGroups[colId][self.Id] = true
	return self
end

function Group:UntrackCollection(collection: Types.Collection): Types.Group
	local colId = collection.Id
	if State.CollectionToGroups[colId] then
		State.CollectionToGroups[colId][self.Id] = nil
	end

	local safetyMode = collection._config.SafetyMode
	for _, item in collection._items do
		local data = collection._itemData[item]
		local oldZoneIdx = data and data.ActiveGroupMemberships[self.Id]
		if oldZoneIdx then
			data.ActiveGroupMemberships[self.Id] = nil
			State.GroupTrackingItems[self.Id][item] = nil

			local z = State.ZoneIdToZoneObj[oldZoneIdx]
			local cbs = State.GroupExitedCallbacks[self.Id]
			if cbs then
				local cd = State.ItemCustomData[item] and State.ItemCustomData[item][self.Id]
				for _, fn in cbs do
					if safetyMode then
						task.spawn(fn, item, z, cd)
					else
						fn(item, z, cd)
					end
				end
			end
		end
	end

	return self
end

function Group:IsPlayerInside(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local hrp = character:FindFirstChild('HumanoidRootPart')
	if not hrp then
		return false
	end

	return self:IsItemInside(hrp)
end

function Group:IsLocalPlayerInside(): boolean
	if not IS_CLIENT then
		error('[BitZone] IsLocalPlayerInside can only be called on the Client.', 2)
	end

	return self:IsPlayerInside(Players.LocalPlayer)
end

function Group:IsItemInside(item: Types.Item): boolean
	local colId = State.ItemToCollection[item]
	if not colId then
		return false
	end

	local collection = State.Collections[colId]
	local data = collection._itemData[item]
	if not data then
		return false
	end

	return data.ActiveGroupMemberships[self.Id] ~= nil
end

function Group:IsPointInside(position: Vector3): boolean
	if not State.RootNode then
		return false
	end

	local isInside = false
	LinearBVH.QueryPoint(State.RootNode, position, function(zoneId)
		if isInside then
			return
		end
		local groups = State.ZoneBoundGroups[zoneId]
		if groups and table.find(groups, self.Id) then
			if Geometry.IsPointInShape(position, State.Objects[zoneId]) then
				isInside = true
			end
		end
	end)

	return isInside
end

function Group:GetItemsInside(): { Types.Item }
	local items = State.GroupTrackingItems[self.Id]
	if not items then
		return {}
	end
	local results = {}
	for item, _ in pairs(items) do
		table.insert(results, item)
	end
	return results
end

function Group:GetItems(): { Types.Item }
	local results = {}
	for colId, groups in pairs(State.CollectionToGroups) do
		if groups[self.Id] then
			local collection = State.Collections[colId]
			for _, item in ipairs(collection._items) do
				table.insert(results, item)
			end
		end
	end
	return results
end

function Group:GetZones(): { Types.Zone }
	local results = {}
	for zoneIdx, boundList in pairs(State.ZoneBoundGroups) do
		if table.find(boundList, self.Id) then
			local zone = State.ZoneIdToZoneObj[zoneIdx]
			if zone then
				table.insert(results, zone)
			end
		end
	end
	return results
end

function Group:GetCollections(): { Types.Collection }
	local result = {}

	for colId, groupsMap in pairs(State.CollectionToGroups) do
		if groupsMap[self.Id] then
			local collection = State.Collections[colId]
			if collection then
				table.insert(result, collection)
			end
		end
	end

	return result
end

function Group:OnEntered(callback): () -> ()
	table.insert(State.GroupEnteredCallbacks[self.Id], callback)
	return function()
		local i = table.find(State.GroupEnteredCallbacks[self.Id], callback)
		if i then
			table.remove(State.GroupEnteredCallbacks[self.Id], i)
		end
	end
end

function Group:OnExited(callback): () -> ()
	table.insert(State.GroupExitedCallbacks[self.Id], callback)
	return function()
		local i = table.find(State.GroupExitedCallbacks[self.Id], callback)
		if i then
			table.remove(State.GroupExitedCallbacks[self.Id], i)
		end
	end
end

function Group:OnPlayerEntered(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnEntered(function(_item, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Group:OnPlayerExited(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnExited(function(_item, zone, data: { Player: Player }?)
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Group:OnLocalPlayerEntered(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerEntered can only be called on the Client.')
	return self:OnEntered(function(_item, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Group:OnLocalPlayerExited(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerExited can only be called on the Client.')
	return self:OnExited(function(_item, zone, data: { Player: Player }?)
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Group:Destroy(): ()
	local id = self.Id
	for _, groups in pairs(State.CollectionToGroups) do
		groups[id] = nil
	end

	for _, boundList in pairs(State.ZoneBoundGroups) do
		local idx = table.find(boundList, id)
		while idx do
			table.remove(boundList, idx)
			idx = table.find(boundList, id)
		end
	end

	State.GroupPriorityMap[id] = nil
	State.GroupEnteredCallbacks[id] = nil
	State.GroupExitedCallbacks[id] = nil
	State.GroupTrackingItems[id] = nil
	State.GroupIdToGroupObj[id] = nil
	State.IsDirty = true
	setmetatable(self :: any, nil)
end

return Group

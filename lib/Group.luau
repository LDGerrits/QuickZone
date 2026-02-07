--!strict

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Geometry = require(script.Parent.Geometry)
local LinearBVH = require(script.Parent.LinearBVH)
local State = require(script.Parent.State)
local Strategy = require(script.Parent.Strategy)
local Types = require(script.Parent.Types)

local IS_CLIENT = RunService:IsClient()

local STRAT_POS = Strategy.POS
local STRAT_PRIM = Strategy.PRIM
local STRAT_WORLD = Strategy.WORLD
local STRAT_CFRAME = Strategy.CFRAME
local STRAT_PIVOT = Strategy.PIVOT

local Group = {}
Group.__index = Group

local function registerItem(group: Types.Group, item: Types.Item, customData: any?, useVolume: boolean)
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
			error(
				string.format(
					'[BitZone] TrackItem Failed: Item (%s) is not supported. '
						.. 'Must be BasePart, Model, Attachment, Bone, Camera, or table with Position/CFrame.',
					tostring(item)
				),
				2
			)
		end

		if useVolume then
			-- We restrict Volume tracking to BaseParts for now because they have a defined Size.
			-- (Models would need GetBoundingBox which is slow, or a manual size passed in)
			if not (typeof(item) == 'Instance' and item:IsA('BasePart')) then
				warn(
					string.format(
						"[BitZone] Volume tracking requires a BasePart. Defaulting '%s' to point tracking.",
						tostring(item)
					)
				)
				useVolume = false
			elseif strat == STRAT_POS then
				-- If we are tracking volume, we need Rotation (CFrame), not just Position
				strat = STRAT_CFRAME
			end
		end

		data = {
			activeGroupMemberships = {},
			memberOfGroups = {},
			lastPosition = Vector3.zero,
			strategy = strat,
			useVolume = useVolume,
			isDirty = true,
		}
		State.items[item] = data
	else
		-- 2. Update existing item mode if upgraded to Volume
		if useVolume and not data.useVolume then
			if typeof(item) == 'Instance' and item:IsA('BasePart') then
				data.useVolume = true
				-- Upgrade strategy to CFrame if it was just Position, so we get rotation for OBB checks
				if data.strategy == STRAT_POS then
					data.strategy = STRAT_CFRAME
				end
			end
		end
	end

	if customData ~= nil then
		if not State.itemCustomData[item] then
			State.itemCustomData[item] = {}
		end
		State.itemCustomData[item][group.UID] = customData
	end

	data.memberOfGroups[group.UID] = true
	data.isDirty = true
end

function Group.new(priority: number?): Types.Group
	local group = (
		setmetatable({
			UID = State.nextGroupId,
			_mainConnections = {},
			_playerTrackers = {},
		}, Group) :: any
	) :: Types.Group

	State.groupPriorityMap[group.UID] = priority or 0
	State.groupEnteredCallbacks[group.UID] = {}
	State.groupExitedCallbacks[group.UID] = {}
	State.groupTrackingItems[group.UID] = setmetatable({}, { __mode = 'k' }) :: any
	State.groupUIDToGroupObj[group.UID] = group

	State.nextGroupId += 1
	return group
end

function Group:TrackItem(item: Types.Item, customData: any?): Types.Group
	registerItem(self, item, customData, false)
	return self
end

function Group:TrackVolume(part: BasePart, customData: any?): Types.Group
	registerItem(self, part, customData, true)
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
		if State.groupTrackingItems[self.UID] then
			State.groupTrackingItems[self.UID][item] = nil
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

function Group:TrackLocalPlayer(): Types.Group
	assert(IS_CLIENT, '[BitZone] TrackLocalPlayer can only be called on the Client.')

	self:_setupPlayerTracking(Players.LocalPlayer)

	return (self :: any) :: Types.Group
end

function Group:TrackPlayers(): Types.Group
	if #self._mainConnections > 0 then
		return (self :: any) :: Types.Group
	end

	table.insert(
		self._mainConnections,
		Players.PlayerAdded:Connect(function(p)
			self:_setupPlayerTracking(p)
		end)
	)

	table.insert(
		self._mainConnections,
		Players.PlayerRemoving:Connect(function(p)
			self:_teardownPlayerTracking(p)
		end)
	)

	for _, p in Players:GetPlayers() do
		self:_setupPlayerTracking(p)
	end

	return (self :: any) :: Types.Group
end

function Group:IsLocalPlayerInside(): boolean
	if not IS_CLIENT then
		error('[BitZone] IsLocalPlayerInside can only be called on the Client.', 2)
	end

	return self:IsPlayerInside(Players.LocalPlayer)
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

function Group:OnLocalPlayerEntered(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerEntered can only be called on the Client.')

	return self:OnEntered(function(_item, zone, data: { Player: Player })
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Group:OnLocalPlayerExited(callback: (Types.Zone) -> ()): () -> ()
	assert(IS_CLIENT, '[BitZone] OnLocalPlayerExited can only be called on the Client.')

	return self:OnExited(function(_item, zone, data: { Player: Player })
		if data and data.Player == Players.LocalPlayer then
			callback(zone)
		end
	end)
end

function Group:OnPlayerEntered(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnEntered(function(_item, zone, data: { Player: Player })
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
end

function Group:OnPlayerExited(callback: (Player, Types.Zone) -> ()): () -> ()
	return self:OnExited(function(_item, zone, data: { Player: Player })
		if data and data.Player then
			callback(data.Player, zone)
		end
	end)
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
	for item, data in State.items do
		if data.memberOfGroups[self.UID] then
			table.insert(results, item)
		end
	end
	return results
end

function Group:GetItemsInside(): { Types.Item }
	local items = State.groupTrackingItems[self.UID]
	if not items then
		return {}
	end
	local results = {}
	for item, _ in items do
		table.insert(results, item)
	end
	return results
end

function Group:GetZones(): { Types.Zone }
	local results = {}
	for zoneIdx, boundList in State.zoneBoundGroups do
		if table.find(boundList, self.UID) then
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

	LinearBVH.QueryPoint(State.rootNode, position, function(zoneId)
		if isInside then
			return
		end
		local groups = State.zoneBoundGroups[zoneId]
		if groups and table.find(groups, self.UID) then
			if Geometry.IsPointInShape(position, State.objects[zoneId]) then
				isInside = true
			end
		end
	end)
	return isInside
end

function Group:OnEntered(callback): () -> ()
	table.insert(State.groupEnteredCallbacks[self.UID], callback)
	return function()
		local i = table.find(State.groupEnteredCallbacks[self.UID], callback)
		if i then
			table.remove(State.groupEnteredCallbacks[self.UID], i)
		end
	end
end

function Group:OnExited(callback): () -> ()
	table.insert(State.groupExitedCallbacks[self.UID], callback)
	return function()
		local i = table.find(State.groupExitedCallbacks[self.UID], callback)
		if i then
			table.remove(State.groupExitedCallbacks[self.UID], i)
		end
	end
end

function Group:Destroy(): ()
	local uid = self.UID

	self:_cleanupPlayerConnections()

	for _, boundList in State.zoneBoundGroups do
		local idx = table.find(boundList, uid)
		while idx do
			table.remove(boundList, idx)
			idx = table.find(boundList, uid)
		end
	end

	for item, data in State.items do
		if data.memberOfGroups[uid] then
			self:UntrackItem(item)
		end
	end

	State.groupPriorityMap[uid] = nil
	State.groupEnteredCallbacks[uid] = nil
	State.groupExitedCallbacks[uid] = nil
	State.groupTrackingItems[uid] = nil
	State.groupUIDToGroupObj[uid] = nil

	State.isDirty = true

	setmetatable(self :: any, nil)
end

function Group:_setupPlayerTracking(player: Player)
	if self._playerTrackers[player] then
		return
	end

	local charConns: { RBXScriptConnection } = {}
	local currentHrp: BasePart? = nil

	local function cleanCharacter()
		if currentHrp then
			self:UntrackItem(currentHrp)
			currentHrp = nil
		end
		for _, c in charConns do
			c:Disconnect()
		end
		table.clear(charConns)
	end

	local function onCharAdded(char: Model)
		cleanCharacter()

		task.spawn(function()
			local hrp = char:WaitForChild('HumanoidRootPart', 10)

			if not self._playerTrackers[player] then
				return
			end

			if player.Character ~= char then
				return
			end

			if hrp and hrp:IsA('BasePart') then
				currentHrp = hrp
				self:TrackItem(hrp, { Player = player })

				table.insert(
					charConns,
					hrp.AncestryChanged:Connect(function(_child, parent)
						if not parent then
							self:UntrackItem(hrp)
							currentHrp = nil
						end
					end)
				)
			end
		end)
	end

	local addedConn = player.CharacterAdded:Connect(onCharAdded)

	self._playerTrackers[player] = function()
		addedConn:Disconnect()
		cleanCharacter()
	end

	if player.Character then
		onCharAdded(player.Character)
	end
end

function Group:_teardownPlayerTracking(player: Player)
	local cleanup = self._playerTrackers[player]
	if cleanup then
		cleanup()
		self._playerTrackers[player] = nil
	end
end

function Group:_cleanupAllPlayers()
	for _, conn in self._mainConnections do
		conn:Disconnect()
	end
	table.clear(self._mainConnections)

	for _, cleanup in self._playerTrackers do
		cleanup()
	end
	table.clear(self._playerTrackers)
end

return Group

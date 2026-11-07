--!strict

local Players = game:GetService('Players')

local Types = require(script.Parent.Parent.Types)
local State = require(script.Parent.State)

local activeTrackers = {} :: { [Player]: () -> () }
local playerSubscriptions = {} :: { [Player]: { [number]: Types.InternalGroup } }
-- Players whose PlayerRemoving has fired. Their Parent is still Players while it runs
local leaving = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Player]: true }

local PlayerTracker = {}

-- Whether the player is in a group that is not destroyed
local function isInAnyGroup(player: Player): boolean
	local subscriptions = playerSubscriptions[player]
	if subscriptions then
		for groupId in subscriptions do
			if State.groups[groupId] then
				return true
			end
		end
	end
	return false
end

local stopTracking: (player: Player) -> ()

local function trackPlayer(player: Player)
	if activeTrackers[player] then
		return
	end

	local charConn: RBXScriptConnection?
	local charAncestryConn: RBXScriptConnection?
	local hrpConn: RBXScriptConnection?
	local currentCharacter: Model?
	local currentHrp: BasePart?

	local function clearHrp(targetHrp: BasePart?)
		if targetHrp and targetHrp ~= currentHrp then
			return
		end

		if hrpConn then
			hrpConn:Disconnect()
			hrpConn = nil
		end

		local hrp = currentHrp
		if hrp then
			-- Let go first, so an exit callback adding the player to a group doesn't add this part
			currentHrp = nil
			if State.referenceToEntity[player] == hrp then
				State.referenceToEntity[player] = nil
			end

			local subscriptions = playerSubscriptions[player]
			if subscriptions then
				-- Cloned, as exit callbacks may add the player to groups
				for groupId, group in table.clone(subscriptions) do
					if State.groups[groupId] then
						group:_removeEntity(hrp)
					else
						subscriptions[groupId] = nil
					end
				end
			end

			-- Unless a callback gave the part to the player again
			if currentHrp ~= hrp then
				State.entityToReference[hrp] = nil
			end
		end
	end

	local function clearCharacter()
		clearHrp()
		if charConn then
			charConn:Disconnect()
			charConn = nil
		end
		if charAncestryConn then
			charAncestryConn:Disconnect()
			charAncestryConn = nil
		end
		currentCharacter = nil
	end

	local function checkHrp(character: Model)
		if character ~= currentCharacter then
			return
		end

		local hrp = character:FindFirstChild('HumanoidRootPart')

		if hrp and hrp:IsA('BasePart') and hrp ~= currentHrp then
			clearHrp()
			currentHrp = hrp

			State.entityToReference[hrp] = player
			State.referenceToEntity[player] = hrp

			-- Listen for the HRP streaming out or getting destroyed, also by its character leaving
			hrpConn = hrp.AncestryChanged:Connect(function()
				if not hrp:IsDescendantOf(game) then
					clearHrp(hrp)
					-- A new HRP may have been added before this one went
					if currentCharacter and currentCharacter:IsDescendantOf(game) then
						checkHrp(currentCharacter)
					end
				end
			end)

			local subscriptions = playerSubscriptions[player]
			if subscriptions then
				-- Cloned, as enter callbacks may add the player to groups, which adds the part themselves
				for groupId, group in table.clone(subscriptions) do
					if currentHrp ~= hrp then
						break
					elseif State.groups[groupId] then
						group:_addEntity(hrp)
					else
						subscriptions[groupId] = nil
					end
				end
			end
		end
	end

	local function onCharacterAdded(character: Model)
		-- A player in no group is let go here rather than when it leaves its last group, as that may happen in a
		-- callback while its part is being handled
		if not isInAnyGroup(player) then
			stopTracking(player)
			return
		end

		clearCharacter()
		currentCharacter = character
		checkHrp(character)

		-- Listen for the HRP streaming in dynamically
		charConn = character.ChildAdded:Connect(function(child)
			if child.Name == 'HumanoidRootPart' then
				checkHrp(character)
			end
		end)

		-- A character taken out of the world and put back keeps its HRP, so it is picked up again
		charAncestryConn = character.AncestryChanged:Connect(function()
			if character:IsDescendantOf(game) then
				checkHrp(character)
			end
		end)
	end

	local addedConn = player.CharacterAdded:Connect(onCharacterAdded)
	local removingConn = player.CharacterRemoving:Connect(function(character)
		if currentCharacter == character then
			clearCharacter()
		end
	end)

	activeTrackers[player] = function()
		addedConn:Disconnect()
		removingConn:Disconnect()
		clearCharacter()
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

function PlayerTracker.subscribe(player: Player, group: Types.InternalGroup)
	-- A player that is leaving or left would never be let go, as its PlayerRemoving has fired
	if player.Parent ~= Players or leaving[player] then
		return
	end

	if not playerSubscriptions[player] then
		playerSubscriptions[player] = {}
	end

	playerSubscriptions[player][group.id] = group
	trackPlayer(player)

	local currentHrp = State.referenceToEntity[player]
	if currentHrp then
		group:_addEntity(currentHrp)
	end
end

function PlayerTracker.unsubscribe(player: Player, group: Types.InternalGroup)
	if playerSubscriptions[player] then
		playerSubscriptions[player][group.id] = nil
	end

	local currentHrp = State.referenceToEntity[player]
	if currentHrp then
		group:_removeEntity(currentHrp)
	end
end

function PlayerTracker.isSubscribed(player: Player, group: Types.InternalGroup): boolean
	local subscriptions = playerSubscriptions[player]
	return subscriptions ~= nil and subscriptions[group.id] ~= nil
end

-- The live groups the player was added to, also while it has no character
function PlayerTracker.groupsOf(player: Player): { Types.InternalGroup }
	local list = {}
	for groupId, group in playerSubscriptions[player] or {} do
		if State.groups[groupId] then
			table.insert(list, group)
		end
	end
	return list
end

-- Forgets every player added to the group, also those without a character
function PlayerTracker.dropGroup(groupId: number)
	for _, subscriptions in playerSubscriptions do
		subscriptions[groupId] = nil
	end
end

-- Stops following the player's characters and lets go of its part
function stopTracking(player: Player)
	-- First, so its part leaves the groups it is still in
	local cleanup = activeTrackers[player]
	if cleanup then
		cleanup()
	end
	activeTrackers[player] = nil
	playerSubscriptions[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	leaving[player] = true
	stopTracking(player)
end)

return PlayerTracker

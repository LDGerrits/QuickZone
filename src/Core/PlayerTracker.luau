--!strict

-- Follows each player added to a group through its characters: the HumanoidRootPart of its current character is
-- the member, through Members, and the player its reference. Keeps which groups each player was added to

local Players = game:GetService('Players')

local Types = require(script.Parent.Parent.Types)
local Members = require(script.Parent.Members)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)

local activeTrackers = {} :: { [Player]: () -> () }
-- The ids of the groups each player was added to
local playerSubscriptions = {} :: { [Player]: { [number]: true } }
-- Players whose PlayerRemoving has fired. Their Parent is still Players while it runs
local leaving = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Player]: true }

local PlayerTracker = {}

-- Whether the player is in a group. A group being destroyed lets go of its players before it is gone
local function isInAnyGroup(player: Player): boolean
	local subscriptions = playerSubscriptions[player]
	return subscriptions ~= nil and next(subscriptions) ~= nil
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
			References.release(player, hrp)

			local subscriptions = playerSubscriptions[player]
			if subscriptions then
				-- Cloned, as exit callbacks may add the player to groups
				for groupId in table.clone(subscriptions) do
					-- Unless a callback destroyed it meanwhile
					if Registry.groups[groupId] then
						Members.remove(groupId, hrp)
					end
				end
			end

			-- Unless a callback gave the part to the player again
			if currentHrp ~= hrp then
				References.link(hrp, nil)
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

			References.link(hrp, player)

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
				for groupId in table.clone(subscriptions) do
					if currentHrp ~= hrp then
						break
					elseif Registry.groups[groupId] then
						Members.add(groupId, hrp)
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

function PlayerTracker.subscribe(player: Player, groupId: number)
	-- A player that is leaving or left would never be let go, as its PlayerRemoving has fired
	if player.Parent ~= Players or leaving[player] then
		return
	end

	if not playerSubscriptions[player] then
		playerSubscriptions[player] = {}
	end

	playerSubscriptions[player][groupId] = true
	trackPlayer(player)

	local currentHrp = References.referenceToEntity[player]
	if currentHrp then
		Members.add(groupId, currentHrp)
	end
end

function PlayerTracker.unsubscribe(player: Player, groupId: number)
	if playerSubscriptions[player] then
		playerSubscriptions[player][groupId] = nil
	end

	local currentHrp = References.referenceToEntity[player]
	if currentHrp then
		Members.remove(groupId, currentHrp)
	end
end

function PlayerTracker.isSubscribed(player: Player, groupId: number): boolean
	local subscriptions = playerSubscriptions[player]
	return subscriptions ~= nil and subscriptions[groupId] ~= nil
end

-- The groups the player was added to, also while it has no character
function PlayerTracker.groupsOf(player: Player): { Types.InternalGroup }
	local list = {}
	local subscriptions = playerSubscriptions[player]
	if subscriptions then
		for groupId in subscriptions do
			-- A group being destroyed lets go of its players before it is gone
			table.insert(list, Registry.groups[groupId])
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

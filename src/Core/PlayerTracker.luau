--!strict

-- Follows grouped players through their characters: the current HumanoidRootPart is the member, the player its
-- reference

local Players = game:GetService('Players')

local Types = require(script.Parent.Parent.Types)
local Members = require(script.Parent.Members)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)

local activeTrackers = {} :: { [Player]: () -> () }
local playerGroupIds = {} :: { [Player]: { [number]: true } }
-- PlayerRemoving fired. Parent is still Players while it runs
local leaving = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Player]: true }

local PlayerTracker = {}

local function isInAnyGroup(player: Player): boolean
	local subscriptions = playerGroupIds[player]
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
			-- Before exits, so a callback re-adding the player doesn't add this part
			currentHrp = nil
			References.release(player, hrp)

			local subscriptions = playerGroupIds[player]
			if subscriptions then
				-- Cloned: exit callbacks may add the player to groups
				for groupId in table.clone(subscriptions) do
					-- A callback may have destroyed it
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

			hrpConn = hrp.AncestryChanged:Connect(function()
				if not hrp:IsDescendantOf(game) then
					clearHrp(hrp)
					-- A new HRP may have been added before this one went
					if currentCharacter and currentCharacter:IsDescendantOf(game) then
						checkHrp(currentCharacter)
					end
				end
			end)

			local subscriptions = playerGroupIds[player]
			if subscriptions then
				-- Cloned: enter callbacks may add the player to groups, which adds the part itself
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
		-- Let go here, not on leaving its last group, which may happen in a callback mid-handling
		if not isInAnyGroup(player) then
			stopTracking(player)
			return
		end

		clearCharacter()
		currentCharacter = character
		checkHrp(character)

		charConn = character.ChildAdded:Connect(function(child)
			if child.Name == 'HumanoidRootPart' then
				checkHrp(character)
			end
		end)

		-- Put back into the world, a character keeps its HRP without ChildAdded
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
	-- Its PlayerRemoving already fired, so it would never be let go
	if player.Parent ~= Players or leaving[player] then
		return
	end

	if not playerGroupIds[player] then
		playerGroupIds[player] = {}
	end

	playerGroupIds[player][groupId] = true
	trackPlayer(player)

	local currentHrp = References.referenceToEntity[player]
	if currentHrp then
		Members.add(groupId, currentHrp)
	end
end

function PlayerTracker.unsubscribe(player: Player, groupId: number)
	if playerGroupIds[player] then
		playerGroupIds[player][groupId] = nil
	end

	local currentHrp = References.referenceToEntity[player]
	if currentHrp then
		Members.remove(groupId, currentHrp)
	end
end

function PlayerTracker.isSubscribed(player: Player, groupId: number): boolean
	local subscriptions = playerGroupIds[player]
	return subscriptions ~= nil and subscriptions[groupId] ~= nil
end

-- Also while it has no character
function PlayerTracker.groupsOf(player: Player): { Types.InternalGroup }
	local list = {}
	local subscriptions = playerGroupIds[player]
	if subscriptions then
		for groupId in subscriptions do
			-- Never nil: a destroyed group drops its players first
			table.insert(list, Registry.groups[groupId])
		end
	end
	return list
end

function PlayerTracker.dropGroup(groupId: number)
	for _, subscriptions in playerGroupIds do
		subscriptions[groupId] = nil
	end
end

function stopTracking(player: Player)
	-- Before clearing subscriptions, so its part leaves its groups
	local cleanup = activeTrackers[player]
	if cleanup then
		cleanup()
	end
	activeTrackers[player] = nil
	playerGroupIds[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	leaving[player] = true
	stopTracking(player)
end)

return PlayerTracker

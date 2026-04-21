local Players = game:GetService('Players')

local Types = require(script.Parent.Parent.Types)
local State = require(script.Parent.State)

local activeTrackers = {} :: { [Player]: () -> () }
local playerSubscriptions = {} :: { [Player]: { [number]: Types.InternalGroup } }

local PlayerTracker = {}

local function trackPlayer(player: Player)
	if activeTrackers[player] then
		return
	end

	local charConn: RBXScriptConnection?
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

		if currentHrp then
			local subscriptions = playerSubscriptions[player]
			if subscriptions then
				for groupId, group in subscriptions do
					if State.groups[groupId] then
						group:_remove(currentHrp)
					else
						subscriptions[groupId] = nil
					end
				end
			end

			State.entityToReference[currentHrp] = nil
			if State.referenceToEntity[player] == currentHrp then
				State.referenceToEntity[player] = nil
			end
			currentHrp = nil
		end
	end

	local function clearCharacter()
		clearHrp()
		if charConn then
			charConn:Disconnect()
			charConn = nil
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

			local subscriptions = playerSubscriptions[player]
			if subscriptions then
				for groupId, group in subscriptions do
					if State.groups[groupId] then
						group:_add(hrp)
					else
						subscriptions[groupId] = nil
					end
				end
			end

			-- Listen for the HRP streaming out or getting destroyed
			hrpConn = hrp.AncestryChanged:Connect(function(_, parent)
				if not parent then
					clearHrp(hrp)
				end
			end)
		end
	end

	local function onCharacterAdded(character: Model)
		clearCharacter()
		currentCharacter = character
		checkHrp(character)

		-- Listen for the HRP streaming in dynamically
		charConn = character.ChildAdded:Connect(function(child)
			if child.Name == 'HumanoidRootPart' then
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
	if not playerSubscriptions[player] then
		playerSubscriptions[player] = {}
	end

	playerSubscriptions[player][group.id] = group
	trackPlayer(player)

	local currentHrp = State.referenceToEntity[player]
	if currentHrp then
		group:_add(currentHrp)
	end
end

function PlayerTracker.unsubscribe(player: Player, group: Types.InternalGroup)
	if playerSubscriptions[player] then
		playerSubscriptions[player][group.id] = nil
	end

	local currentHrp = State.referenceToEntity[player]
	if currentHrp then
		group:_remove(currentHrp)
	end
end

Players.PlayerRemoving:Connect(function(player)
	local cleanup = activeTrackers[player]
	if cleanup then
		cleanup()
	end
	activeTrackers[player] = nil
	playerSubscriptions[player] = nil
end)

return PlayerTracker

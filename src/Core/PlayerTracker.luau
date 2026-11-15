--!strict

-- Follows grouped players through their characters: the current HumanoidRootPart is the member, the player its
-- reference

local Players = game:GetService('Players')

local Types = require(script.Parent.Parent.Types)
local Members = require(script.Parent.Members)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)

-- A player in a group. Its states: no character, a character without a HumanoidRootPart, or a part linked (hrp set,
-- and the player its reference). Kept after leaving its last group until its next character, as that may happen in a
-- callback mid-handling
type Tracked = {
	groupIds: { [number]: true },
	character: Model?,
	hrp: BasePart?,
	stop: () -> (),
}

local tracked = {} :: { [Player]: Tracked }
-- PlayerRemoving fired. Parent is still Players while it runs
local leaving = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Player]: true }

local PlayerTracker = {}

local stopTracking: (player: Player) -> ()

local function trackPlayer(player: Player, groupIds: { [number]: true }): Tracked
	-- stop is set once the connections it ends exist
	local state: Tracked = { groupIds = groupIds, stop = nil :: any }
	tracked[player] = state

	local charConn: RBXScriptConnection?
	local charAncestryConn: RBXScriptConnection?
	local hrpConn: RBXScriptConnection?

	local function clearHrp(targetHrp: BasePart?)
		if targetHrp and targetHrp ~= state.hrp then
			return
		end

		if hrpConn then
			hrpConn:Disconnect()
			hrpConn = nil
		end

		local hrp = state.hrp
		if hrp then
			-- Before exits, so a callback re-adding the player doesn't add this part
			state.hrp = nil
			References.release(player, hrp)

			-- Cloned: exit callbacks may add the player to groups
			for groupId in table.clone(state.groupIds) do
				-- A callback may have destroyed it
				if Registry.groups[groupId] then
					Members.remove(groupId, hrp)
				end
			end

			-- Unless a callback gave the part to the player again
			if state.hrp ~= hrp then
				References.link(hrp, nil)
			end
		end
	end

	local function clearCharacter()
		-- Before its part leaves, so an exit callback putting the character back can't link the part again
		state.character = nil
		if charConn then
			charConn:Disconnect()
			charConn = nil
		end
		if charAncestryConn then
			charAncestryConn:Disconnect()
			charAncestryConn = nil
		end
		clearHrp()
	end

	local function checkHrp(character: Model)
		if character ~= state.character then
			return
		end

		local hrp = character:FindFirstChild('HumanoidRootPart')

		if hrp and hrp:IsA('BasePart') and hrp ~= state.hrp then
			clearHrp()
			state.hrp = hrp

			References.link(hrp, player)

			hrpConn = hrp.AncestryChanged:Connect(function()
				if not hrp:IsDescendantOf(game) then
					clearHrp(hrp)
					-- A new HRP may have been added before this one went
					local current = state.character
					if current and current:IsDescendantOf(game) then
						checkHrp(current)
					end
				end
			end)

			-- Cloned: enter callbacks may add the player to groups, which adds the part itself
			for groupId in table.clone(state.groupIds) do
				if state.hrp ~= hrp then
					break
				elseif Registry.groups[groupId] then
					Members.add(groupId, hrp)
				end
			end
		end
	end

	local function onCharacterAdded(character: Model)
		if next(state.groupIds) == nil then
			stopTracking(player)
			return
		end

		clearCharacter()
		state.character = character
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
		if state.character == character then
			clearCharacter()
		end
	end)

	state.stop = function()
		addedConn:Disconnect()
		removingConn:Disconnect()
		clearCharacter()
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	return state
end

function PlayerTracker.subscribe(player: Player, groupId: number)
	-- Its PlayerRemoving already fired, so it would never be let go
	if player.Parent ~= Players or leaving[player] then
		return
	end

	local state = tracked[player]
	if state then
		state.groupIds[groupId] = true
	else
		state = trackPlayer(player, { [groupId] = true })
	end

	local hrp = state.hrp
	if hrp then
		Members.add(groupId, hrp)
	end
end

function PlayerTracker.unsubscribe(player: Player, groupId: number)
	local state = tracked[player]
	if not state then
		return
	end

	state.groupIds[groupId] = nil
	local hrp = state.hrp
	if hrp then
		Members.remove(groupId, hrp)
	end
end

function PlayerTracker.isSubscribed(player: Player, groupId: number): boolean
	local state = tracked[player]
	return state ~= nil and state.groupIds[groupId] ~= nil
end

-- Also while it has no character
function PlayerTracker.groupsOf(player: Player): { Types.InternalGroup }
	local list = {}
	local state = tracked[player]
	if state then
		for groupId in state.groupIds do
			-- Never nil: a destroyed group drops its players first
			table.insert(list, Registry.groups[groupId])
		end
	end
	return list
end

function PlayerTracker.dropGroup(groupId: number)
	for _, state in tracked do
		state.groupIds[groupId] = nil
	end
end

function stopTracking(player: Player)
	local state = tracked[player]
	if state then
		-- Before letting go of its groups, so its part leaves them
		state.stop()
		tracked[player] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	leaving[player] = true
	stopTracking(player)
end)

return PlayerTracker

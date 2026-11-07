--!strict

-- An entity, as given, joining or leaving a group, with everything that follows from it in the order it must
-- happen. Also keeps the removal watches of autoClean groups. Only this module writes its tables

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local Memberships = require(script.Parent.Memberships)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local Routing = require(script.Parent.Routing)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Log = require(script.Parent.Parent.Utils.Log)

local Members = {}

-- Groups that let go of members once they leave the game, and the connection that watches each such member
Members.autoCleanGroups = {} :: { [number]: true }
Members.cleanups = {} :: { [number]: { [Instance]: RBXScriptConnection } }

local autoCleanGroups = Members.autoCleanGroups
local cleanups = Members.cleanups

-- Whether the group's destroy has begun. A group takes on nothing new from then on
local function isDestroyed(groupId: number): boolean
	local group = Registry.groups[groupId]
	return group == nil or Destroyed.isDestroyed(group)
end

-- Removes an instance from the group once it leaves the game
local function watchRemoval(groupId: number, entity: Types.Entity)
	local groupCleanups = cleanups[groupId]
	if typeof(entity) == 'Instance' and not groupCleanups[entity] then
		groupCleanups[entity] = entity.AncestryChanged:Connect(function(_, parent)
			if not parent then
				Members.remove(groupId, entity)
			end
		end)
	end
end

function Members.addGroup(groupId: number, autoClean: boolean)
	if autoClean then
		autoCleanGroups[groupId] = true
	end
	cleanups[groupId] = {}
end

function Members.dropGroup(groupId: number)
	local groupCleanups = cleanups[groupId]
	if groupCleanups then
		for _, conn in groupCleanups do
			conn:Disconnect()
		end
	end
	autoCleanGroups[groupId] = nil
	cleanups[groupId] = nil
end

function Members.setAutoClean(groupId: number, enabled: boolean)
	if (autoCleanGroups[groupId] == true) == enabled then
		return
	end
	local groupCleanups = cleanups[groupId]
	if enabled then
		autoCleanGroups[groupId] = true
		for _, entity in Entities.groupEntities[groupId] do
			watchRemoval(groupId, entity)
		end
	else
		autoCleanGroups[groupId] = nil
		for entity, conn in groupCleanups do
			conn:Disconnect()
			groupCleanups[entity] = nil
		end
	end
end

-- Adds the entity as given, never through the reference map
function Members.add(groupId: number, entity: Types.Entity)
	if isDestroyed(groupId) then
		return
	end
	if entity == nil then
		Log.nonFatal('Cannot add nil to Group %d.', nil, groupId)
		return
	end

	if not Entities.join(entity, groupId) then
		return
	end

	Routing.recheck(entity)

	if autoCleanGroups[groupId] then
		watchRemoval(groupId, entity)
	end

	-- Its group may arrive in observers it is already in
	Memberships.groupsChanged(entity)
end

-- Removes the entity as given, never through the reference map. Exit callbacks run in the middle and may change
-- anything, so whether the entity is dropped is decided after them
function Members.remove(groupId: number, entity: Types.Entity)
	if not Entities.isIn(entity, groupId) then
		return
	end

	local groupCleanups = cleanups[groupId]
	local cleanupConn = groupCleanups and groupCleanups[entity :: any]
	if cleanupConn then
		cleanupConn:Disconnect()
		groupCleanups[entity :: any] = nil
	end

	Entities.leave(entity, groupId)
	local data = Entities.entityData[entity]

	Routing.recheck(entity)

	Memberships.exitUnsubscribed(entity, data)
	-- Its group may leave observers it stays in through other groups
	Memberships.groupsChanged(entity)

	-- Unless exit callbacks added it back. Routing goes first, as it reads the data of the entity swapped into its
	-- bucket slot, which may be this one
	if Entities.isGroupless(entity, data) then
		Routing.forget(entity, data :: Types.EntityData)
		Entities.drop(entity)
		References.forget(entity)
	end
end

return Members

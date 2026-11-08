--!strict

-- An entity joining or leaving a group, with its follow-on steps in required order, and autoClean removal
-- watches. Only this module writes its tables

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local Memberships = require(script.Parent.Memberships)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local Routing = require(script.Parent.Routing)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Log = require(script.Parent.Parent.Utils.Log)

local Members = {}

Members.autoCleanGroups = {} :: { [number]: true }
Members.cleanups = {} :: { [number]: { [Instance]: RBXScriptConnection } }

local autoCleanGroups = Members.autoCleanGroups
local cleanups = Members.cleanups

-- True from the start of destroy, so nothing new joins mid-teardown
function Members.isGroupDestroyed(groupId: number): boolean
	local group = Registry.groups[groupId]
	return group == nil or Destroyed.isDestroyed(group)
end

local isDestroyed = Members.isGroupDestroyed

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

-- Takes the entity as given, without resolving references
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

	-- Observers it is already in may now count this group
	Memberships.groupsChanged(entity)
end

-- Takes the entity as given. Exit callbacks run mid-way, so dropping is decided after them
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
	-- Observers it stays in through other groups may no longer count this group
	Memberships.groupsChanged(entity)

	-- Routing first: it reads the data of the entity swapped into its bucket slot, possibly this one
	if Entities.isGroupless(entity, data) then
		Routing.forget(entity, data :: Types.EntityData)
		Entities.drop(entity)
		References.forget(entity)
	end
end

return Members

--!strict

-- An entity joining or leaving a group, with its follow-on steps in required order, and autoClean removal
-- watches. Only this module writes the groups' autoClean and removalWatches

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local GroupPresence = require(script.Parent.GroupPresence)
local Memberships = require(script.Parent.Memberships)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local Routing = require(script.Parent.Routing)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)
local Log = require(script.Parent.Parent.Utils.Log)

local groups = Registry.groups

local Members = {}

-- True from the start of destroy, so nothing new joins mid-teardown
function Members.isGroupDestroyed(groupId: number): boolean
	local group = groups[groupId]
	return group == nil or Destroyed.isDestroyed(group)
end

local isDestroyed = Members.isGroupDestroyed

local function watchRemoval(group: Types.InternalGroup, entity: Types.Entity)
	local watches = group.removalWatches
	if typeof(entity) == 'Instance' and not watches[entity] then
		local groupId = group.id
		watches[entity] = entity.AncestryChanged:Connect(function(_, parent)
			if not parent then
				Members.remove(groupId, entity :: any)
			end
		end)
	end
end

local function unwatchAll(group: Types.InternalGroup)
	for _, conn in group.removalWatches do
		conn:Disconnect()
	end
	table.clear(group.removalWatches)
end

Members.dropGroup = unwatchAll

function Members.setAutoClean(groupId: number, enabled: boolean)
	local group = groups[groupId]
	if group.autoClean == enabled then
		return
	end
	group.autoClean = enabled
	if enabled then
		for _, entity in group.members do
			watchRemoval(group, entity)
		end
	else
		unwatchAll(group)
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

	local group = groups[groupId]
	if group.autoClean then
		watchRemoval(group, entity)
	end

	-- Observers it is already in may now count this group
	GroupPresence.groupsChanged(entity)
end

-- Takes the entity as given. Exit callbacks run mid-way, so dropping is decided after them
function Members.remove(groupId: number, entity: Types.Entity)
	if not Entities.isIn(entity, groupId) then
		return
	end

	local group = groups[groupId]
	local watches = group and group.removalWatches
	local watch = watches and watches[entity :: any]
	if watch then
		watch:Disconnect()
		watches[entity :: any] = nil
	end

	local data = Entities.entityData[entity] :: Types.EntityData
	Entities.leave(entity, groupId)

	Routing.recheck(entity)

	Memberships.exitUnsubscribed(entity, data)
	-- Observers it stays in through other groups may no longer count this group
	GroupPresence.groupsChanged(entity)

	-- Routing first: it reads the data of the entity swapped into its bucket slot, possibly this one
	if Entities.isGroupless(data) then
		Routing.forget(entity, data)
		Entities.drop(entity, data)
		References.forget(entity)
	end
end

return Members

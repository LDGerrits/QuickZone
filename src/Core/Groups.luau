--!strict

-- The group operations the Group class offers, by group id. A member is given as the user gives it: a player,
-- followed through its characters, or a reference or entity, resolved to its entity. Classes change group
-- membership only through here, and read it from Entities

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local Links = require(script.Parent.Links)
local Members = require(script.Parent.Members)
local Memberships = require(script.Parent.Memberships)
local PlayerTracker = require(script.Parent.PlayerTracker)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)
local Destroyed = require(script.Parent.Parent.Utils.Destroyed)

local isPlayer = References.isPlayer

local Groups = {}

local isDestroyed = Members.isGroupDestroyed

-- Whether the group's destroy has ended
local function isDead(groupId: number): boolean
	local group = Registry.groups[groupId]
	return group == nil or Destroyed.isDead(group)
end

-- Removes a member. A character part of a player goes through the player as well, so the player's next
-- character is not added back
local function removeMember(groupId: number, entity: Types.Entity)
	local reference = References.entityToReference[entity]
	if isPlayer(reference) then
		PlayerTracker.unsubscribe(reference, groupId)
	end
	-- Unless an exit callback destroyed the group meanwhile
	if not isDead(groupId) then
		Members.remove(groupId, entity)
	end
end

-- Sets up a new group, once the Group class has registered it
function Groups.create(groupId: number, autoClean: boolean)
	Links.addGroup(groupId)
	Entities.addGroup(groupId)
	Members.addGroup(groupId, autoClean)
end

function Groups.add(groupId: number, reference: any)
	-- A callback during destroy must not add entities that are never removed
	if isDestroyed(groupId) then
		return
	end

	if isPlayer(reference) then
		PlayerTracker.subscribe(reference, groupId)
	else
		Members.add(groupId, References.entityOf(reference))
	end
end

function Groups.addBulk(groupId: number, references: { any })
	for _, reference in references do
		-- A callback may have destroyed the group
		if isDestroyed(groupId) then
			break
		end
		Groups.add(groupId, reference)
	end
end

function Groups.remove(groupId: number, reference: any)
	if isPlayer(reference) then
		PlayerTracker.unsubscribe(reference, groupId)
		return
	end

	-- An entity is removed itself, also when it is another entity's reference, as contains finds it. A player's
	-- part is removed as the player
	removeMember(groupId, References.entityOf(reference))
end

function Groups.removeBulk(groupId: number, references: { any })
	for _, reference in references do
		-- An exit callback may have destroyed the group
		if isDead(groupId) then
			break
		end
		Groups.remove(groupId, reference)
	end
end

-- Adds or removes the entity as given, never through the reference map, for groups that follow instances. These
-- are Members' own, so the classes can keep to this one module
Groups.addEntity = Members.add
Groups.removeEntity = Members.remove
Groups.setAutoClean = Members.setAutoClean

function Groups.clear(groupId: number)
	-- Held once and walked backwards, as exit callbacks may remove members after this one, or destroy the group,
	-- which empties the list
	local members = Entities.groupEntities[groupId]
	if members then
		for idx = #members, 1, -1 do
			local entity = members[idx]
			if entity ~= nil then
				removeMember(groupId, entity)
			end
		end
	end
	-- Players without a character have no member to remove
	PlayerTracker.dropGroup(groupId)
end

function Groups.contains(groupId: number, reference: any): boolean
	-- A player is a member while it has no character too
	return Entities.isIn(References.entityOf(reference), groupId)
		or (isPlayer(reference) and PlayerTracker.isSubscribed(reference, groupId))
end

-- Lets go of everything the group has, once its onDestroy callbacks have run. The Group class forgets the object
function Groups.destroy(groupId: number)
	Groups.clear(groupId)
	Memberships.groupDestroyed(groupId)

	Links.dropGroup(groupId)
	Entities.dropGroup(groupId)
	Members.dropGroup(groupId)
end

return Groups

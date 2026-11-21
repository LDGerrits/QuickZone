--!strict

local Types = require(script.Parent.Parent.Types)
local Entities = require(script.Parent.Entities)
local GroupPresence = require(script.Parent.GroupPresence)
local Members = require(script.Parent.Members)
local PlayerTracker = require(script.Parent.PlayerTracker)
local References = require(script.Parent.References)
local Registry = require(script.Parent.Registry)

local isPlayer = References.isPlayer

local Groups = {}

local isDestroyed = Members.isGroupDestroyed

local function removeMember(groupId: number, entity: Types.Entity)
	local reference = References.entityToReference[entity]
	if isPlayer(reference) then
		PlayerTracker.unsubscribe(reference, groupId)
	end
	Members.remove(groupId, entity)
end

function Groups.add(groupId: number, reference: any)
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
		Groups.add(groupId, reference)
	end
end

function Groups.remove(groupId: number, reference: any)
	if isPlayer(reference) then
		PlayerTracker.unsubscribe(reference, groupId)
		return
	end

	removeMember(groupId, References.entityOf(reference))
end

function Groups.removeBulk(groupId: number, references: { any })
	for _, reference in references do
		Groups.remove(groupId, reference)
	end
end

Groups.addEntity = Members.add
Groups.removeEntity = Members.remove
Groups.setAutoClean = Members.setAutoClean

function Groups.clear(groupId: number)
	local group = Registry.groups[groupId]
	local members = group and group.members
	if members then
		for idx = #members, 1, -1 do
			local entity = members[idx]
			if entity ~= nil then
				removeMember(groupId, entity)
			end
		end
	end
	PlayerTracker.dropGroup(groupId)
end

function Groups.contains(groupId: number, reference: any): boolean
	return Entities.isIn(References.entityOf(reference), groupId)
		or (isPlayer(reference) and PlayerTracker.isSubscribed(reference, groupId))
end

function Groups.create(group: Types.InternalGroup)
	Registry.groups[group.id] = group
end

function Groups.destroy(group: Types.InternalGroup)
	local groupId = group.id
	Groups.clear(groupId)
	GroupPresence.groupDestroyed(groupId)

	Entities.dropGroup(group)
	Members.dropGroup(group)
	Registry.groups[groupId] = nil
end

return Groups

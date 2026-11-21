--!strict

-- Owns entity group membership and group member lists. Creates and drops each entity's data, whose fields other
-- modules write (see Types.EntityData)

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Log = require(script.Parent.Parent.Utils.Log)
local Registry = require(script.Parent.Registry)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_TRANSFORM = Config.Strategy.TRANSFORM
local STRAT_PIVOT = Config.Strategy.PIVOT

local DEFAULT_PRECISION_SQ = Config.Observer.precision ^ 2

local Entities = {}

-- Entities in a group. Dropped when they leave their last one
Entities.entityData = {} :: { [Types.Entity]: Types.EntityData }

local entityData = Entities.entityData
local groups = Registry.groups

local function strategyOf(entity: any): number?
	if typeof(entity) == 'Instance' then
		local instance: Instance = entity
		if instance:IsA('BasePart') then
			return STRAT_POS
		elseif instance:IsA('Attachment') or instance:IsA('Bone') then
			return STRAT_WORLD
		elseif instance:IsA('Camera') then
			return STRAT_CFRAME
		elseif instance:IsA('Model') then
			return instance.PrimaryPart and STRAT_PRIM or STRAT_PIVOT
		end
	elseif typeof(entity) == 'table' then
		if entity.Position then
			return STRAT_POS
		elseif entity.CFrame then
			return STRAT_CFRAME
		elseif entity.Transform then
			return STRAT_TRANSFORM
		elseif entity.WorldPosition then
			return STRAT_WORLD
		elseif entity.GetPivot then
			return STRAT_PIVOT
		end
	end
	return nil
end

function Entities.canTrack(x: any): boolean
	return strategyOf(x) ~= nil
end

-- Emptied in place so a loop still holding the list ends
function Entities.dropGroup(group: Types.InternalGroup)
	table.clear(group.members)
	table.clear(group.memberIndices)
end

function Entities.groupsOf(entity: Types.Entity): { [number]: true }?
	local data = entityData[entity]
	return data and data.groups
end

function Entities.isIn(entity: Types.Entity, groupId: number): boolean
	local data = entityData[entity]
	return data ~= nil and data.groups[groupId] == true
end

-- False when already in the group or untrackable
function Entities.join(entity: Types.Entity, groupId: number): boolean
	if Entities.isIn(entity, groupId) then
		return false
	end

	local data = entityData[entity]
	if not data then
		local strat = strategyOf(entity)
		if not strat then
			Log.nonFatal(
				'Invalid entity (%s). Expected BasePart, Model, Bone, Attachment, Camera, or a valid EntityTable.',
				nil,
				tostring(entity)
			)
			return false
		end

		local newData: Types.EntityData = {
			strategy = strat,
			groups = {},
			dropped = false,
			linkedObservers = nil,
			lastPosition = Vector3.zero,
			activeObserverMemberships = {},
			precisionSq = DEFAULT_PRECISION_SQ,
			updateRate = -1,
			bucketIndex = 0,
			dynamicVersion = -1,
			staticVersion = -1,
			logicVersion = -1,
			needsStatic = false,
			needsDynamic = false,
		}
		entityData[entity] = newData
		data = newData
	end
	local memberOf = (data :: Types.EntityData).groups
	memberOf[groupId] = true

	-- Only live groups are joined
	local group = groups[groupId]
	local members = group.members
	local idx = #members + 1
	members[idx] = entity
	group.memberIndices[entity] = idx
	return true
end

-- Keeps the entity's data until dropped, as exit callbacks still read it
function Entities.leave(entity: Types.Entity, groupId: number)
	local data = entityData[entity]
	if data then
		data.groups[groupId] = nil
	end

	local group = groups[groupId]
	local indices = group and group.memberIndices
	local idx = indices and indices[entity]
	if idx then
		-- Also right when it is the last, as its own entries are cleared after
		local members = (group :: Types.InternalGroup).members
		local lastIdx = #members
		local lastEntity = members[lastIdx]
		members[idx] = lastEntity
		indices[lastEntity] = idx
		members[lastIdx] = nil
		indices[entity] = nil
	end
end

-- Left its last group, and exit callbacks didn't re-add it or drop it
function Entities.isGroupless(data: Types.EntityData): boolean
	return not data.dropped and next(data.groups) == nil
end

-- Only after Routing.forget
function Entities.drop(entity: Types.Entity, data: Types.EntityData)
	data.dropped = true
	entityData[entity] = nil
end

return Entities

--!strict

-- Owns entity group membership, group member lists and per-entity scheduler data. Only this module writes them

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Log = require(script.Parent.Parent.Utils.Log)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_TRANSFORM = Config.Strategy.TRANSFORM
local STRAT_PIVOT = Config.Strategy.PIVOT

local DEFAULT_PRECISION_SQ = Config.Observer.precision ^ 2

local Entities = {}

Entities.entityToGroups = {} :: { [Types.Entity]: { [number]: boolean } }
Entities.entityData = {} :: { [Types.Entity]: Types.EntityData }
Entities.groupEntities = {} :: { [number]: { Types.Entity } }
Entities.groupEntityIndices = {} :: { [number]: { [Types.Entity]: number } }

local entityData = Entities.entityData
local entityToGroups = Entities.entityToGroups
local groupEntities = Entities.groupEntities
local groupEntityIndices = Entities.groupEntityIndices

local function strategyOf(entity: any): number?
	if typeof(entity) == 'Instance' then
		if entity:IsA('BasePart') then
			return STRAT_POS
		elseif entity:IsA('Attachment') or entity:IsA('Bone') then
			return STRAT_WORLD
		elseif entity:IsA('Camera') then
			return STRAT_CFRAME
		elseif entity:IsA('Model') then
			return entity.PrimaryPart and STRAT_PRIM or STRAT_PIVOT
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

function Entities.addGroup(groupId: number)
	groupEntities[groupId] = {}
	groupEntityIndices[groupId] = {}
end

-- Emptied in place so a loop still holding the list ends
function Entities.dropGroup(groupId: number)
	local members = groupEntities[groupId]
	if members then
		table.clear(members)
	end
	groupEntities[groupId] = nil
	groupEntityIndices[groupId] = nil
end

function Entities.isIn(entity: Types.Entity, groupId: number): boolean
	local groups = entityToGroups[entity]
	return groups ~= nil and groups[groupId] == true
end

-- False when already in the group or untrackable
function Entities.join(entity: Types.Entity, groupId: number): boolean
	if Entities.isIn(entity, groupId) then
		return false
	end

	if not entityData[entity] then
		local strat = strategyOf(entity)
		if not strat then
			Log.nonFatal(
				'Invalid entity (%s). Expected BasePart, Model, Bone, Attachment, Camera, or a valid EntityTable.',
				nil,
				tostring(entity)
			)
			return false
		end

		entityData[entity] = {
			strategy = strat,
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
	end

	local groups = entityToGroups[entity]
	if not groups then
		groups = {}
		entityToGroups[entity] = groups
	end
	groups[groupId] = true

	local members = groupEntities[groupId]
	local idx = #members + 1
	members[idx] = entity
	groupEntityIndices[groupId][entity] = idx
	return true
end

-- Keeps the entity's data until dropped, as exit callbacks still read it
function Entities.leave(entity: Types.Entity, groupId: number)
	local groups = entityToGroups[entity]
	if groups then
		groups[groupId] = nil
	end

	local indices = groupEntityIndices[groupId]
	local idx = indices and indices[entity]
	if idx then
		-- Also right when it is the last, as its own entries are cleared after
		local members = groupEntities[groupId]
		local lastIdx = #members
		local lastEntity = members[lastIdx]
		members[idx] = lastEntity
		indices[lastEntity] = idx
		members[lastIdx] = nil
		indices[entity] = nil
	end
end

-- Left its last group, and exit callbacks didn't re-add it or replace its data
function Entities.isGroupless(entity: Types.Entity, data: Types.EntityData?): boolean
	local groups = entityToGroups[entity]
	return data ~= nil and entityData[entity] == data and groups ~= nil and next(groups) == nil
end

-- Only after Routing.forget
function Entities.drop(entity: Types.Entity)
	entityData[entity] = nil
	entityToGroups[entity] = nil
end

return Entities

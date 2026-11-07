--!strict

-- Owns which groups each entity is in and the data the scheduler keeps on it. An entity exists while it is in a
-- group. Others read the tables, only this module adds or drops entities

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

-- The groups each entity is in, and what the scheduler keeps on it
Entities.entityToGroups = {} :: { [Types.Entity]: { [number]: boolean } }
Entities.entityData = {} :: { [Types.Entity]: Types.EntityData }

local entityData = Entities.entityData
local entityToGroups = Entities.entityToGroups

-- How the scheduler reads the entity's position, or nil when it can't be tracked
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

function Entities.isIn(entity: Types.Entity, groupId: number): boolean
	local groups = entityToGroups[entity]
	return groups ~= nil and groups[groupId] == true
end

-- Puts the entity in the group, and creates its data when it is new. False when it was in the group already, or
-- can't be tracked
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
	return true
end

-- Takes the entity out of the group. It stays until dropped, as exit callbacks still see it
function Entities.leave(entity: Types.Entity, groupId: number)
	local groups = entityToGroups[entity]
	if groups then
		groups[groupId] = nil
	end
end

-- Whether the entity with this data left its last group, and exit callbacks didn't add it back or replace its data
function Entities.isGroupless(entity: Types.Entity, data: Types.EntityData?): boolean
	local groups = entityToGroups[entity]
	return data ~= nil and entityData[entity] == data and groups ~= nil and next(groups) == nil
end

-- Drops an entity that left its last group, once its routing is gone
function Entities.drop(entity: Types.Entity)
	entityData[entity] = nil
	entityToGroups[entity] = nil
end

return Entities

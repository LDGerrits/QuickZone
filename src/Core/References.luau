--!strict

-- Owns the links between entities and the references they were given with setReference, or the player whose
-- HumanoidRootPart they are. Others read the tables, only this module writes them

local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

local entityData = State.entityData

local References = {}

-- Only the entity side is weak: a reference lives as long as its entity, also when nothing else holds it,
-- and an entity nothing else holds can still go
References.entityToReference = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Types.Entity]: any }
References.referenceToEntity = (setmetatable({}, { __mode = 'v' }) :: any) :: { [any]: Types.Entity }

local entityToReference = References.entityToReference
local referenceToEntity = References.referenceToEntity

function References.isPlayer(x: any): boolean
	return typeof(x) == 'Instance' and x:IsA('Player')
end

-- The entity x stands for: x itself when it is an entity, else the entity it is the reference of. An entity can
-- also be another entity's reference, like a model that is the reference of its hitbox part
function References.entityOf(x: any): Types.Entity
	if entityData[x] then
		return x
	end
	return referenceToEntity[x] or x
end

-- Gives the entity a reference, or none when reference is nil
function References.link(entity: Types.Entity, reference: any?)
	local oldReference = entityToReference[entity]
	-- The old reference no longer leads to this entity, unless another entity has taken it since
	if oldReference ~= nil and oldReference ~= reference and referenceToEntity[oldReference] == entity then
		referenceToEntity[oldReference] = nil
	end
	entityToReference[entity] = reference
	if reference ~= nil then
		referenceToEntity[reference] = entity
	end
end

-- The reference no longer leads to the entity, while the entity keeps it for the callbacks it still fires
function References.release(reference: any, entity: Types.Entity)
	if referenceToEntity[reference] == entity then
		referenceToEntity[reference] = nil
	end
end

return References

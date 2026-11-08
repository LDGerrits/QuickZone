--!strict

-- Owns entity-reference links: setReference, or a HumanoidRootPart's player. Only this module writes them

local Entities = require(script.Parent.Entities)
local Types = require(script.Parent.Parent.Types)

local entityData = Entities.entityData

local References = {}

-- Only the entity side is weak, so a reference lives as long as its entity
References.entityToReference = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Types.Entity]: any }
References.referenceToEntity = (setmetatable({}, { __mode = 'v' }) :: any) :: { [any]: Types.Entity }

local entityToReference = References.entityToReference
local referenceToEntity = References.referenceToEntity

function References.isPlayer(x: any): boolean
	return typeof(x) == 'Instance' and x:IsA('Player')
end

-- An entity wins over the reference map, as it can also be another's reference (a model of its hitbox part)
function References.entityOf(x: any): Types.Entity
	if entityData[x] then
		return x
	end
	return referenceToEntity[x] or x
end

function References.referenceOf(entity: Types.Entity): any
	return entityToReference[entity] or entity
end

function References.link(entity: Types.Entity, reference: any?)
	local oldReference = entityToReference[entity]
	-- Unless another entity has taken the old reference since
	if oldReference ~= nil and oldReference ~= reference and referenceToEntity[oldReference] == entity then
		referenceToEntity[oldReference] = nil
	end
	entityToReference[entity] = reference
	if reference ~= nil then
		referenceToEntity[reference] = entity
	end
end

-- A player's part keeps its player, as PlayerTracker releases it itself
function References.forget(entity: Types.Entity)
	if not References.isPlayer(entityToReference[entity]) then
		References.link(entity, nil)
	end
end

-- The entity keeps the reference for the callbacks it still fires
function References.release(reference: any, entity: Types.Entity)
	if referenceToEntity[reference] == entity then
		referenceToEntity[reference] = nil
	end
end

return References

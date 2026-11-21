--!strict

local Entities = require(script.Parent.Entities)
local Types = require(script.Parent.Parent.Types)

local entityData = Entities.entityData

local References = {}

References.entityToReference = (setmetatable({}, { __mode = 'k' }) :: any) :: { [Types.Entity]: any }
References.referenceToEntity = (setmetatable({}, { __mode = 'v' }) :: any) :: { [any]: Types.Entity }

local entityToReference = References.entityToReference
local referenceToEntity = References.referenceToEntity

function References.isPlayer(x: any): boolean
	return typeof(x) == 'Instance' and (x :: Instance):IsA('Player')
end

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
	if oldReference ~= nil and oldReference ~= reference and referenceToEntity[oldReference] == entity then
		referenceToEntity[oldReference] = nil
	end
	entityToReference[entity] = reference
	if reference ~= nil then
		referenceToEntity[reference] = entity
	end
end

function References.forget(entity: Types.Entity)
	if not References.isPlayer(entityToReference[entity]) then
		References.link(entity, nil)
	end
end

function References.release(reference: any, entity: Types.Entity)
	if referenceToEntity[reference] == entity then
		referenceToEntity[reference] = nil
	end
end

return References

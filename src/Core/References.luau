--!strict

-- Resolves what the API is given, an entity or the reference an entity was given with setReference

local State = require(script.Parent.State)
local Types = require(script.Parent.Parent.Types)

local entityData = State.entityData
local referenceToEntity = State.referenceToEntity

local References = {}

-- The entity x stands for: x itself when it is an entity, else the entity it is the reference of. An entity can
-- also be another entity's reference, like a model that is the reference of its hitbox part
function References.entityOf(x: any): Types.Entity
	if entityData[x] then
		return x
	end
	return referenceToEntity[x] or x
end

return References

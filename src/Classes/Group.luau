--!strict

local State = require(script.Parent.Parent.State)
local Types = require(script.Parent.Parent.Types)
local Config = require(script.Parent.Parent.Config)

local STRAT_POS = Config.Strategy.POS
local STRAT_PRIM = Config.Strategy.PRIM
local STRAT_WORLD = Config.Strategy.WORLD
local STRAT_CFRAME = Config.Strategy.CFRAME
local STRAT_PIVOT = Config.Strategy.PIVOT

local Group = {}
Group.__index = Group

function Group.new(config: {
	updateRate: number?,
	precision: number?,
	safety: boolean?,
}?): Types.Group
	local hz = config and config.updateRate
	assert(not hz or hz > 0, '[QuickZone] updateRate must be greater than 0')

	local n = config and config.precision
	assert(not n or n >= 0, '[QuickZone] precision must be non-negative')

	local id = State.nextGroupId
	State.nextGroupId += 1

	local updateRate = hz or Config.Scheduler.updateRate
	local precision = n or Config.Scheduler.precision
	local safety = Config.Scheduler.safety
	if config and config.safety ~= nil then
		safety = config.safety
	end

	local self: Types.InternalGroup = setmetatable({
		id = id,
		entities = {},
		entityIndices = {},
		entityData = {},
		config = {
			updateRate = updateRate,
			precisionSq = precision ^ 2,
			safety = safety,
		},
	}, Group) :: any

	State.groups[id] = self
	State.groupToObservers[id] = {}
	table.insert(State.groupList, self)

	return self
end

function Group.setConfig(
	self: Types.InternalGroup,
	config: {
		updateRate: number?,
		precision: number?,
		safety: boolean?,
	}
): Types.Group
	local hz = config.updateRate
	assert(not hz or hz > 0, '[QuickZone] updateRate must be greater than 0')

	local n = config.precision
	assert(not n or n >= 0, '[QuickZone] precision must be non-negative')

	if hz then
		self.config.updateRate = hz
	end
	if n then
		self.config.precisionSq = n ^ 2
	end
	if config.safety ~= nil then
		self.config.safety = config.safety
	end

	return self
end

function Group.add(self: Types.InternalGroup, entity: Types.Entity, customData: any?): Types.Group
	local oldGroupId = State.entityToGroup[entity]
	if oldGroupId then
		if oldGroupId == self.id then
			return self
		end
		local oldGroup = State.groups[oldGroupId]
		if oldGroup then
			oldGroup:remove(entity)
		end
	end

	local strat
	if typeof(entity) == 'Instance' then
		if entity:IsA('BasePart') then
			strat = STRAT_POS
		elseif entity:IsA('Attachment') or entity:IsA('Bone') then
			strat = STRAT_WORLD
		elseif entity:IsA('Camera') then
			strat = STRAT_CFRAME
		elseif entity:IsA('Model') then
			strat = entity.PrimaryPart and STRAT_PRIM or STRAT_PIVOT
		end
	elseif typeof(entity) == 'table' then
		if entity.Position then
			strat = STRAT_POS
		elseif entity.CFrame then
			strat = STRAT_CFRAME
		elseif entity.WorldPosition then
			strat = STRAT_WORLD
		elseif entity.GetPivot then
			strat = STRAT_PIVOT
		end
	end

	if not strat then
		warn(
			string.format(
				'[QuickZone] Group:add skipped invalid entity (%s). Expected BasePart, Model, etc.',
				tostring(entity)
			)
		)
		return self
	end

	local data = {
		lastPosition = Vector3.zero,
		strategy = strat,
		isDirty = true,
		activeObserverMemberships = {},
	}

	local idx = #self.entities + 1
	self.entities[idx] = entity
	self.entityIndices[entity] = idx
	self.entityData[entity] = data

	State.entityToGroup[entity] = self.id

	if customData then
		if not State.entityCustomData[entity] then
			State.entityCustomData[entity] = {}
		end
		State.entityCustomData[entity] = customData
	end

	return self
end

function Group.remove(self: Types.InternalGroup, ...: Types.Entity): Types.Group
	for _, entity in { ... } do
		if State.entityToGroup[entity] ~= self.id then
			continue
		end

		local data = self.entityData[entity]

		-- Trigger exit
		local safety = self.config.safety
		for observerId, oldZoneId in data.activeObserverMemberships do
			if State.observerTrackingEntities[observerId] then
				State.observerTrackingEntities[observerId][entity] = nil
			end

			local cbs = State.observerExitedCallbacks[observerId]
			if not cbs then
				continue
			end

			local z = State.zoneIdToZoneObj[oldZoneId]
			local cd = State.entityCustomData[entity] and State.entityCustomData[entity][observerId]
			for _, fn in cbs do
				if safety then
					task.spawn(fn, entity, z, cd)
				else
					fn(entity, z, cd)
				end
			end
		end

		-- Swap-remove from Array
		local idx = self.entityIndices[entity]
		local lastIdx = #self.entities
		local lastEntity = self.entities[lastIdx]

		if idx == lastIdx then
			self.entities[lastIdx] = nil
			self.entityIndices[entity] = nil
		else
			self.entities[idx] = lastEntity
			self.entityIndices[lastEntity] = idx
			self.entities[lastIdx] = nil
			self.entityIndices[entity] = nil
		end

		self.entityData[entity] = nil
		State.entityToGroup[entity] = nil
		State.entityCustomData[entity] = nil
	end

	return self
end

function Group.getId(self: Types.InternalGroup): number
	return self.id
end

function Group.getEntities(self: Types.InternalGroup): { Types.Entity }
	local result = table.create(#self.entities)
	table.move(self.entities, 1, #self.entities, 1, result)
	return result
end

function Group.getObservers(self: Types.InternalGroup): { Types.Observer }
	local result = {}
	local observersMap = State.groupToObservers[self.id]

	if not observersMap then
		return result
	end

	for observerId, _ in observersMap do
		local observer = State.observerIdToObserverObj[observerId]
		if observer then
			table.insert(result, observer)
		end
	end

	return result
end

function Group.getConfig(self: Types.InternalGroup): {
	updateRate: number,
	precision: number,
	safety: boolean,
}
	local config = self.config
	return {
		updateRate = config.updateRate,
		precision = math.sqrt(config.precisionSq),
		safety = config.safety,
	}
end

function Group.contains(self: Types.InternalGroup, entity: Types.Entity): boolean
	local groupId = State.entityToGroup[entity]
	return groupId and groupId == self.id
end

function Group.destroy(self: Types.InternalGroup): ()
	-- Must iterate backwards because remove() modifies array length
	for i = #self.entities, 1, -1 do
		self:remove(self.entities[i])
	end

	State.groupToObservers[self.id] = nil
	State.groups[self.id] = nil

	local listIdx = table.find(State.groupList, self)
	if listIdx then
		table.remove(State.groupList, listIdx)
	end

	setmetatable(self :: any, nil)
end

return Group

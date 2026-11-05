--!strict
-- Random sequences of API calls, checked against a brute-force model of what QuickZone should report.
-- Callbacks change state too, the way games do. A failure prints the seed, the step and the last calls made.
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest

local Util = require(TestFolder.Util)

local QuickZone = require(ReplicatedStorage.QuickZone)
local State = require(ReplicatedStorage.QuickZone.Core.State)
local ZoneShapes = require(ReplicatedStorage.QuickZone.Core.ZoneShapes)
local Zone = QuickZone.Zone
local Group = QuickZone.Group
local Observer = QuickZone.Observer

type Tiniest = typeof(require(TiniestFolder.tiniest_for_roblox).configure({}))

local SPREAD = 30
local ENTITY_COUNT = 40
local MAX_ZONES = 40
local MAX_GROUPS = 4
local MAX_OBSERVERS = 4
local SHAPES = { 'Block', 'Ball', 'Cylinder', 'Wedge', 'CornerWedge' }

-- Tables with a Position or CFrame, parts and models
type Entity = any

type ObserverModel = {
	observer: any,
	index: number,
	zones: { [any]: true },
	groups: { [any]: true },
	enabled: boolean,
	priority: number,
	-- Set while its destroy runs, as its callbacks can still call it
	destroying: boolean,
	destroyed: boolean,
	-- Zone of each entity, replayed from enter, transition and exit callbacks
	shadow: { [Entity]: any },
	-- observe() scopes that have not been cleaned up
	scopes: { [Entity]: number },
	-- Whether the last group event for each group was an enter
	groupInside: { [any]: boolean },
	previous: { [Entity]: any },
}

type World = {
	seed: number,
	rng: Random,
	origin: Vector3,
	step: number,
	log: { string },
	entities: { Entity },
	entityIndex: { [Entity]: number },
	zones: { any },
	groups: { any },
	members: { [any]: { [Entity]: true } },
	autoClean: { [any]: boolean },
	references: { [Entity]: any },
	-- Instance entities in the world, which auto-clean groups drop when they leave it
	parented: { [Entity]: boolean },
	-- Zones that follow a part
	partOf: { [any]: BasePart },
	-- Callbacks connected and disconnected at random
	extras: { { dead: boolean, disconnect: () -> () } },
	instances: { Instance },
	observers: { ObserverModel },
	-- Callbacks change state while set
	mutating: boolean,
	-- Set once a callback changed state in the current update
	changedInCallback: boolean,
	callbackDepth: number,
	callbackCount: number,
	failure: string?,
}

local function fail(world: World, message: string)
	if world.failure then
		return
	end

	local from = math.max(1, #world.log - 15)
	local recent = table.concat(world.log, '\n  ', from)
	world.failure = `seed {world.seed}, step {world.step}: {message}\nlast calls:\n  {recent}`
end

local function record(world: World, message: string)
	table.insert(world.log, `[{world.step}] {message}`)
end

local function describeZone(zone: any): string
	if zone == nil then
		return 'nil'
	end
	-- Read directly, as destroyed zones lose their methods
	return `zone {zone.id}`
end

local function describeZones(zones: { [any]: any }): string
	local list = {}
	for zone in zones do
		table.insert(list, `{describeZone(zone)} ({zone:getShape()}, dynamic {zone:isDynamic()})`)
	end
	return if #list > 0 then table.concat(list, ', ') else 'none'
end

-- Within float error of a zone's surface, the tree and the shape check may round differently
local SURFACE_TOLERANCE = 0.01
local NUDGES = {
	Vector3.xAxis * SURFACE_TOLERANCE,
	-Vector3.xAxis * SURFACE_TOLERANCE,
	Vector3.yAxis * SURFACE_TOLERANCE,
	-Vector3.yAxis * SURFACE_TOLERANCE,
	Vector3.zAxis * SURFACE_TOLERANCE,
	-Vector3.zAxis * SURFACE_TOLERANCE,
}

local function nearSurface(zone: any, point: Vector3): boolean
	local inside = zone:isPointInside(point)
	for _, nudge in NUDGES do
		if zone:isPointInside(point + nudge) ~= inside then
			return true
		end
	end
	return false
end

local function describeEntity(world: World, entity: Entity): string
	return `entity {world.entityIndex[entity]}`
end

local function positionOf(entity: Entity): Vector3
	if typeof(entity) == 'Instance' then
		if entity:IsA('Model') then
			local primary = entity.PrimaryPart
			return if primary then primary.Position else entity:GetPivot().Position
		end
		return entity.Position
	end
	return if entity.CFrame then entity.CFrame.Position else entity.Position
end

local function setPositionOf(entity: Entity, position: Vector3)
	if typeof(entity) == 'Instance' then
		if entity:IsA('Model') then
			entity:PivotTo(CFrame.new(position))
		else
			entity.Position = position
		end
	elseif entity.CFrame then
		entity.CFrame = CFrame.new(position)
	else
		entity.Position = position
	end
end

-- What the API hands out for the entity
local function refOf(world: World, entity: Entity): any
	return world.references[entity] or entity
end

local function pick<T>(rng: Random, list: { T }): T?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

local function liveObservers(world: World): { ObserverModel }
	local list = {}
	for _, model in world.observers do
		if not model.destroyed then
			table.insert(list, model)
		end
	end
	return list
end

local function removeFrom<T>(list: { T }, value: T)
	local index = table.find(list, value)
	if index then
		table.remove(list, index)
	end
end

local function subscribedTo(model: ObserverModel, world: World, entity: Entity): boolean
	for group in model.groups do
		if world.members[group][entity] then
			return true
		end
	end
	return false
end

local function tracked(world: World, entity: Entity): boolean
	for _, group in world.groups do
		if world.members[group][entity] then
			return true
		end
	end
	return false
end

-- Operations. Each one calls the API and updates the model, returning false when it doesn't apply
local runOperation: (world: World, name: string, rng: Random) -> boolean

-- An entity may only enter a zone of an enabled observer that watches it, and that contains it unless a
-- callback changed things since the entity was checked
local function checkEntry(world: World, model: ObserverModel, kind: string, entity: Entity, zone: any)
	local what = `observer {model.index} {kind} {describeEntity(world, entity)} into {describeZone(zone)}`
	if not model.zones[zone] then
		fail(world, `{what}, which is not attached`)
	elseif not model.enabled then
		fail(world, `{what} while disabled`)
	elseif not subscribedTo(model, world, entity) then
		fail(world, `{what} without watching any of its groups`)
	elseif
		not world.changedInCallback
		and not zone:isPointInside(positionOf(entity))
		and not nearSurface(zone, positionOf(entity))
	then
		fail(world, `{what}, which does not contain it`)
	end
end

local function connectObserver(world: World, model: ObserverModel)
	local observer = model.observer

	-- Every callback runs through here, so an error in one fails the test instead of only printing
	local function guarded(kind: string, entity: Entity, body: () -> ())
		if model.destroyed then
			fail(
				world,
				`observer {model.index} fired {kind} for {describeEntity(world, entity)} after it was destroyed`
			)
			return
		end

		local ok, err = pcall(body)
		if not ok then
			fail(world, `{kind} callback errored: {err}`)
			return
		end

		-- Some callbacks change state, decided by what fired so a run doesn't depend on callback order
		if not world.mutating or world.callbackDepth > 0 then
			return
		end
		world.callbackCount += 1
		local hash = world.seed * 7919 + world.step * 104729 + model.index * 1543 + world.entityIndex[entity] * 31
		if kind == 'exit' then
			hash += 7
		elseif kind == 'transition' then
			hash += 13
		end
		if hash % 3 ~= 0 then
			return
		end

		local rng = Random.new(hash)
		local names = {
			'destroyZone',
			'reshapeZone',
			'createZone',
			'attach',
			'detach',
			'addToGroup',
			'removeFromGroup',
			'destroyGroup',
			'subscribe',
			'unsubscribe',
			'toggleEnabled',
			'setPriority',
			'destroyObserver',
			'teleportEntity',
			'removeEntity',
			'setReference',
			'unparentEntity',
			'reparentEntity',
			'movePart',
			'connectCallback',
			'disconnectCallback',
			'nestedUpdate',
		}
		world.callbackDepth += 1
		world.changedInCallback = true
		local name = names[rng:NextInteger(1, #names)]
		record(world, `  in {kind} callback of observer {model.index} for {describeEntity(world, entity)}:`)
		local okMutate, mutateErr = pcall(runOperation, world, name, rng)
		world.callbackDepth -= 1
		if not okMutate then
			fail(world, `{name} from a {kind} callback errored: {mutateErr}`)
		end
	end

	observer:onEnter(function(reference: any, zone: any, entity: any)
		guarded('enter', entity, function()
			if reference ~= refOf(world, entity) then
				fail(world, `enter got reference {reference} for {describeEntity(world, entity)}`)
			end
			if model.shadow[entity] ~= nil then
				fail(
					world,
					`observer {model.index} entered {describeEntity(world, entity)} into {describeZone(zone)} while in {describeZone(
						model.shadow[entity]
					)}`
				)
			end
			checkEntry(world, model, 'entered', entity, zone)
			model.shadow[entity] = zone
		end)
	end)

	observer:onTransition(function(_, zone: any, entity: any)
		guarded('transition', entity, function()
			local from = model.shadow[entity]
			if from == nil or from == zone then
				fail(
					world,
					`observer {model.index} moved {describeEntity(world, entity)} from {describeZone(from)} to {describeZone(
						zone
					)}`
				)
			end
			checkEntry(world, model, 'moved', entity, zone)
			model.shadow[entity] = zone
		end)
	end)

	observer:onExit(function(_, zone: any, entity: any)
		guarded('exit', entity, function()
			if model.shadow[entity] ~= zone then
				fail(
					world,
					`observer {model.index} exited {describeEntity(world, entity)} from {describeZone(zone)} while in {describeZone(
						model.shadow[entity]
					)}`
				)
			end
			model.shadow[entity] = nil
		end)
	end)

	observer:observe(function(_, _, entity: any)
		model.scopes[entity] = (model.scopes[entity] or 0) + 1
		return function()
			model.scopes[entity] = (model.scopes[entity] or 0) - 1
		end
	end)

	observer:onGroupEnter(function(group: any)
		if model.groupInside[group] then
			fail(world, `observer {model.index} fired a second group enter for group {group:getId()}`)
		end
		model.groupInside[group] = true
	end)

	observer:onGroupExit(function(group: any)
		if not model.groupInside[group] then
			fail(world, `observer {model.index} fired a group exit for group {group:getId()} that never entered`)
		end
		model.groupInside[group] = nil
	end)
end

-- Rarely 0, as an observer with precision 0 checks its entities every update, never as standing still
local function randomPrecision(rng: Random): number
	return if rng:NextNumber() < 0.1 then 0 else ({ 0.05, 0.1, 0.5 })[rng:NextInteger(1, 3)]
end

local function randomZoneConfig(world: World, rng: Random): { [string]: any }
	return Util.randomZoneConfig(rng, world.origin, SPREAD, rng:NextNumber() < 0.5)
end

local OPERATIONS: { [string]: (world: World, rng: Random) -> boolean } = {
	createZone = function(world, rng)
		if #world.zones >= MAX_ZONES then
			return false
		end
		local zone
		if rng:NextNumber() < 0.25 then
			-- Follows a part
			local shape = ({ 'Block', 'Ball', 'Cylinder' })[rng:NextInteger(1, 3)]
			local part = Util.createPart({
				Shape = (Enum.PartType :: any)[shape],
				Size = Util.randomSize(rng, shape),
				CFrame = Util.randomCFrame(rng, world.origin, SPREAD),
			})
			table.insert(world.instances, part)
			zone = Zone.fromPart(part, { autoSync = true, isDynamic = true })
			world.partOf[zone] = part
		else
			zone = Zone.new(randomZoneConfig(world, rng))
		end
		table.insert(world.zones, zone)
		record(
			world,
			`create {describeZone(zone)} ({zone:getShape()}, dynamic {zone:isDynamic()}{if world.partOf[zone]
				then ', following a part'
				else ''})`
		)
		for _, model in liveObservers(world) do
			if rng:NextNumber() < 0.5 then
				model.observer:attach(zone)
				model.zones[zone] = true
				record(world, `  attached to observer {model.index}`)
			end
		end
		return true
	end,

	destroyZone = function(world, rng)
		local zone = pick(rng, world.zones)
		if not zone then
			return false
		end
		record(world, `destroy {describeZone(zone)}`)
		removeFrom(world.zones, zone)
		world.partOf[zone] = nil
		for _, model in world.observers do
			model.zones[zone] = nil
		end
		zone:destroy()
		return true
	end,

	reshapeZone = function(world, rng)
		local zone = pick(rng, world.zones)
		if not zone then
			return false
		end
		local kind = rng:NextInteger(1, 6)
		if kind == 1 then
			record(world, `teleport {describeZone(zone)}`)
			zone:setCFrame(Util.randomCFrame(rng, world.origin, SPREAD))
		elseif kind == 2 then
			record(world, `nudge {describeZone(zone)}`)
			zone:setCFrame(zone:getCFrame() + Util.randomOffset(rng, 3))
		elseif kind == 3 then
			record(world, `set position of {describeZone(zone)}`)
			zone:setPosition(world.origin + Util.randomOffset(rng, SPREAD))
		elseif kind == 4 then
			record(world, `resize {describeZone(zone)}`)
			zone:setSize(Util.randomSize(rng, zone:getShape()))
		elseif kind == 5 then
			local shape = SHAPES[rng:NextInteger(1, #SHAPES)]
			record(world, `reshape {describeZone(zone)} to {shape}`)
			zone:setShape(shape)
			zone:setSize(Util.randomSize(rng, shape))
		else
			record(world, `make {describeZone(zone)} dynamic {not zone:isDynamic()}`)
			zone:setDynamic(not zone:isDynamic())
		end
		return true
	end,

	attach = function(world, rng)
		local model = pick(rng, liveObservers(world))
		local zone = pick(rng, world.zones)
		if not model or not zone then
			return false
		end
		record(world, `attach {describeZone(zone)} to observer {model.index}`)
		model.observer:attach(zone)
		model.zones[zone] = true
		return true
	end,

	detach = function(world, rng)
		local model = pick(rng, liveObservers(world))
		if not model then
			return false
		end
		local attached = {}
		for _, zone in world.zones do
			if model.zones[zone] then
				table.insert(attached, zone)
			end
		end
		local zone = pick(rng, attached)
		if not zone then
			return false
		end
		record(world, `detach {describeZone(zone)} from observer {model.index}`)
		model.zones[zone] = nil
		model.observer:detach(zone)
		return true
	end,

	createGroup = function(world, rng)
		if #world.groups >= MAX_GROUPS then
			return false
		end
		local entities = {}
		local members = {}
		for _, entity in world.entities do
			if rng:NextNumber() < 0.5 then
				table.insert(entities, entity)
				members[entity] = true
			end
		end
		local autoClean = rng:NextNumber() < 0.5
		local group = Group.new({ entities = entities, autoClean = autoClean })
		world.members[group] = members
		world.autoClean[group] = autoClean
		table.insert(world.groups, group)
		record(world, `create group {group:getId()} with {#entities} entities`)
		for _, model in liveObservers(world) do
			if rng:NextNumber() < 0.5 then
				model.observer:subscribe(group)
				model.groups[group] = true
				record(world, `  subscribed by observer {model.index}`)
			end
		end
		return true
	end,

	destroyGroup = function(world, rng)
		local group = pick(rng, world.groups)
		if not group then
			return false
		end
		record(world, `destroy group {group:getId()}`)
		removeFrom(world.groups, group)
		for _, model in world.observers do
			model.groups[group] = nil
		end
		world.members[group] = nil
		world.autoClean[group] = nil
		group:destroy()
		return true
	end,

	addToGroup = function(world, rng)
		local group = pick(rng, world.groups)
		if not group then
			return false
		end
		local count = if rng:NextNumber() < 0.2 then rng:NextInteger(2, 6) else 1
		local added = {}
		for _ = 1, count do
			local entity = world.entities[rng:NextInteger(1, #world.entities)]
			world.members[group][entity] = true
			table.insert(added, entity)
		end
		record(world, `add {#added} entities to group {group:getId()}, first {describeEntity(world, added[1])}`)
		if count > 1 then
			group:addBulk(added)
		else
			group:add(added[1])
		end
		return true
	end,

	removeFromGroup = function(world, rng)
		local group = pick(rng, world.groups)
		if not group then
			return false
		end
		local kind = rng:NextInteger(1, 10)
		if kind == 1 then
			record(world, `clear group {group:getId()}`)
			world.members[group] = {}
			group:clear()
			return true
		end
		local count = if kind <= 3 then rng:NextInteger(2, 6) else 1
		local removed = {}
		for _ = 1, count do
			local entity = world.entities[rng:NextInteger(1, #world.entities)]
			world.members[group][entity] = nil
			table.insert(removed, entity)
		end
		record(
			world,
			`remove {#removed} entities from group {group:getId()}, first {describeEntity(world, removed[1])}`
		)
		if count > 1 then
			group:removeBulk(removed)
		else
			group:remove(removed[1])
		end
		return true
	end,

	removeEntity = function(world, rng)
		local entity = world.entities[rng:NextInteger(1, #world.entities)]
		record(world, `remove {describeEntity(world, entity)} from QuickZone`)
		for _, members in world.members do
			members[entity] = nil
		end
		QuickZone:removeEntity(entity)
		return true
	end,

	setReference = function(world, rng)
		local entity = world.entities[rng:NextInteger(1, #world.entities)]
		if typeof(entity) == 'Instance' or not tracked(world, entity) then
			return false
		end
		if world.references[entity] and rng:NextNumber() < 0.4 then
			record(world, `clear the reference of {describeEntity(world, entity)}`)
			world.references[entity] = nil
			QuickZone:setReference(entity, nil)
		else
			local reference = { of = world.entityIndex[entity] }
			record(world, `set a new reference for {describeEntity(world, entity)}`)
			world.references[entity] = reference
			QuickZone:setReference(entity, reference)
		end
		return true
	end,

	unparentEntity = function(world, rng)
		local entity = world.entities[rng:NextInteger(1, #world.entities)]
		if typeof(entity) ~= 'Instance' or not world.parented[entity] then
			return false
		end
		record(world, `take {describeEntity(world, entity)} out of the world`)
		-- Auto-clean groups drop it right away
		for group, autoClean in world.autoClean do
			if autoClean then
				world.members[group][entity] = nil
			end
		end
		world.parented[entity] = false
		entity.Parent = nil
		return true
	end,

	reparentEntity = function(world, rng)
		local entity = world.entities[rng:NextInteger(1, #world.entities)]
		if typeof(entity) ~= 'Instance' or world.parented[entity] then
			return false
		end
		record(world, `put {describeEntity(world, entity)} back in the world`)
		world.parented[entity] = true
		entity.Parent = workspace
		return true
	end,

	movePart = function(world, rng)
		local zones = {}
		for _, zone in world.zones do
			if world.partOf[zone] then
				table.insert(zones, zone)
			end
		end
		local zone = pick(rng, zones)
		if not zone then
			return false
		end
		local part = world.partOf[zone]
		if rng:NextNumber() < 0.7 then
			record(world, `move the part of {describeZone(zone)}`)
			part.CFrame = if rng:NextNumber() < 0.5
				then Util.randomCFrame(rng, world.origin, SPREAD)
				else part.CFrame + Util.randomOffset(rng, 3)
		else
			record(world, `resize the part of {describeZone(zone)}`)
			part.Size = Util.randomSize(rng, zone:getShape())
		end
		return true
	end,

	connectCallback = function(world, rng)
		local model = pick(rng, liveObservers(world))
		if not model then
			return false
		end
		local kind = ({ 'onEnter', 'onExit', 'onTransition' })[rng:NextInteger(1, 3)]
		record(world, `connect another {kind} callback to observer {model.index}`)
		local extra = { dead = false, disconnect = function() end }
		extra.disconnect = model.observer[kind](model.observer, function()
			if extra.dead then
				fail(world, `a disconnected {kind} callback of observer {model.index} fired`)
			end
		end)
		table.insert(world.extras, extra)
		return true
	end,

	disconnectCallback = function(world, rng)
		local live = {}
		for _, extra in world.extras do
			if not extra.dead then
				table.insert(live, extra)
			end
		end
		local extra = pick(rng, live)
		if not extra then
			return false
		end
		record(world, 'disconnect a callback')
		extra.dead = true
		extra.disconnect()
		return true
	end,

	-- Skipped while a tick runs, a full tick otherwise
	nestedUpdate = function(world)
		record(world, 'update from a callback')
		QuickZone:update(1)
		return true
	end,

	teleportEntity = function(world, rng)
		local entity = world.entities[rng:NextInteger(1, #world.entities)]
		record(world, `teleport {describeEntity(world, entity)}`)
		setPositionOf(entity, world.origin + Util.randomOffset(rng, SPREAD + 5))
		return true
	end,

	createObserver = function(world, rng)
		if #liveObservers(world) >= MAX_OBSERVERS then
			return false
		end
		local model: ObserverModel = {
			observer = nil,
			index = #world.observers + 1,
			zones = {},
			groups = {},
			enabled = rng:NextNumber() < 0.85,
			priority = rng:NextInteger(0, 2),
			destroying = false,
			destroyed = false,
			shadow = {},
			scopes = {},
			groupInside = {},
			previous = {},
		}
		local zones, groups = {}, {}
		for _, zone in world.zones do
			if rng:NextNumber() < 0.4 then
				table.insert(zones, zone)
				model.zones[zone] = true
			end
		end
		for _, group in world.groups do
			if rng:NextNumber() < 0.5 then
				table.insert(groups, group)
				model.groups[group] = true
			end
		end

		-- Callbacks are connected before anything can enter
		model.observer = Observer.new({
			priority = model.priority,
			precision = randomPrecision(rng),
			updateRate = ({ 1, 30, 60 })[rng:NextInteger(1, 3)],
			safety = rng:NextNumber() < 0.5,
			enabled = model.enabled,
		})
		connectObserver(world, model)
		for _, zone in zones do
			model.observer:attach(zone)
		end
		for _, group in groups do
			model.observer:subscribe(group)
		end
		table.insert(world.observers, model)
		record(
			world,
			`create observer {model.index}, priority {model.priority}, enabled {model.enabled}, {#zones} zones, {#groups} groups`
		)
		return true
	end,

	destroyObserver = function(world, rng)
		local model = pick(rng, liveObservers(world))
		if not model then
			return false
		end
		if model.destroying then
			record(world, `destroy observer {model.index} again while it is being destroyed`)
			model.observer:destroy()
			return true
		end
		record(world, `destroy observer {model.index}`)
		model.destroying = true
		model.observer:destroy()
		model.destroyed = true
		for entity, zone in model.shadow do
			fail(
				world,
				`destroying observer {model.index} left {describeEntity(world, entity)} in {describeZone(zone)}`
			)
		end
		for entity, count in model.scopes do
			if count ~= 0 then
				fail(
					world,
					`destroying observer {model.index} left {count} observe scopes of {describeEntity(world, entity)}`
				)
			end
		end
		return true
	end,

	subscribe = function(world, rng)
		local model = pick(rng, liveObservers(world))
		local group = pick(rng, world.groups)
		if not model or not group then
			return false
		end
		record(world, `observer {model.index} subscribes group {group:getId()}`)
		model.groups[group] = true
		model.observer:subscribe(group)
		return true
	end,

	unsubscribe = function(world, rng)
		local model = pick(rng, liveObservers(world))
		local group = pick(rng, world.groups)
		if not model or not group or not model.groups[group] then
			return false
		end
		record(world, `observer {model.index} unsubscribes group {group:getId()}`)
		model.groups[group] = nil
		model.observer:unsubscribe(group)
		return true
	end,

	toggleEnabled = function(world, rng)
		local model = pick(rng, liveObservers(world))
		if not model then
			return false
		end
		model.enabled = not model.enabled
		record(world, `observer {model.index} enabled {model.enabled}`)
		model.observer:setEnabled(model.enabled)
		return true
	end,

	setPriority = function(world, rng)
		local model = pick(rng, liveObservers(world))
		if not model then
			return false
		end
		model.priority = rng:NextInteger(0, 2)
		record(world, `observer {model.index} priority {model.priority}`)
		model.observer:setPriority(model.priority)
		return true
	end,

	tuneObserver = function(world, rng)
		local model = pick(rng, liveObservers(world))
		if not model then
			return false
		end
		local kind = rng:NextInteger(1, 3)
		if kind == 1 then
			local precision = randomPrecision(rng)
			record(world, `observer {model.index} precision {precision}`)
			model.observer:setPrecision(precision)
		elseif kind == 2 then
			local rate = ({ 1, 30, 60 })[rng:NextInteger(1, 3)]
			record(world, `observer {model.index} update rate {rate}`)
			model.observer:setUpdateRate(rate)
		else
			local safe = not model.observer:isSafe()
			record(world, `observer {model.index} safety {safe}`)
			model.observer:setSafety(safe)
		end
		return true
	end,
}

local WEIGHTS: { { any } } = {
	{ 'createZone', 4 },
	{ 'destroyZone', 2 },
	{ 'reshapeZone', 6 },
	{ 'attach', 3 },
	{ 'detach', 2 },
	{ 'createGroup', 1 },
	{ 'destroyGroup', 0.6 },
	{ 'addToGroup', 4 },
	{ 'removeFromGroup', 3 },
	{ 'removeEntity', 0.5 },
	{ 'createObserver', 1.2 },
	{ 'destroyObserver', 0.6 },
	{ 'subscribe', 2 },
	{ 'unsubscribe', 1.5 },
	{ 'toggleEnabled', 1.5 },
	{ 'setPriority', 1.5 },
	{ 'tuneObserver', 1 },
	{ 'setReference', 1 },
	{ 'unparentEntity', 0.8 },
	{ 'reparentEntity', 0.8 },
	{ 'movePart', 2 },
	{ 'connectCallback', 0.8 },
	{ 'disconnectCallback', 0.8 },
}

local TOTAL_WEIGHT = 0
for _, entry in WEIGHTS do
	TOTAL_WEIGHT += entry[2]
end

local function randomOperationName(rng: Random): string
	local roll = rng:NextNumber() * TOTAL_WEIGHT
	for _, entry in WEIGHTS do
		roll -= entry[2]
		if roll <= 0 then
			return entry[1]
		end
	end
	return WEIGHTS[#WEIGHTS][1]
end

runOperation = function(world: World, name: string, rng: Random): boolean
	local applied = OPERATIONS[name](world, rng)
	-- Entities that left every group lose their reference
	for entity in world.references do
		if not tracked(world, entity) then
			world.references[entity] = nil
		end
	end
	return applied
end

local function setOf(list: { any }): { [any]: true }
	local set = {}
	for _, value in list do
		set[value] = true
	end
	return set
end

local function sameSet(a: { [any]: any }, b: { [any]: any }): boolean
	for key in a do
		if b[key] == nil then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Holds after every call and update: the callbacks fired add up to what the observers report, and the
-- internal maps agree with each other
local function checkConsistency(world: World)
	if world.failure then
		return
	end

	local observerOf = {}
	for _, model in liveObservers(world) do
		local observer = model.observer
		observerOf[observer:getId()] = model

		for _, entity in world.entities do
			local zone = observer:getZoneOfEntity(entity)
			if zone ~= model.shadow[entity] then
				fail(
					world,
					`observer {model.index} reports {describeEntity(world, entity)} in {describeZone(zone)}, its callbacks put it in {describeZone(
						model.shadow[entity]
					)}`
				)
				return
			end
			local scopes = model.scopes[entity] or 0
			if scopes ~= (if zone then 1 else 0) then
				fail(
					world,
					`observer {model.index} has {scopes} observe scopes for {describeEntity(world, entity)} in {describeZone(
						zone
					)}`
				)
				return
			end
		end

		if not sameSet(setOf(observer:getZones()), model.zones) then
			fail(world, `observer {model.index} getZones disagrees with the zones attached`)
			return
		end
		if not sameSet(setOf(observer:getGroups()), model.groups) then
			fail(world, `observer {model.index} getGroups disagrees with the groups subscribed`)
			return
		end
		if observer:isEnabled() ~= model.enabled or observer:getPriority() ~= model.priority then
			fail(world, `observer {model.index} reports the wrong enabled state or priority`)
			return
		end

		-- Group events add up to the subscribed groups that have a member inside
		for group in model.groupInside do
			if not table.find(world.groups, group) then
				fail(world, `observer {model.index} has a destroyed group inside`)
				return
			end
		end
		for _, group in world.groups do
			local expected = false
			if model.groups[group] then
				for entity in world.members[group] do
					if model.shadow[entity] ~= nil then
						expected = true
						break
					end
				end
			end
			if (model.groupInside[group] == true) ~= expected then
				fail(
					world,
					`observer {model.index} has group {group:getId()} inside {model.groupInside[group] == true}, members inside {expected}`
				)
				return
			end
		end
	end

	for _, group in world.groups do
		local expected = {}
		for entity in world.members[group] do
			expected[refOf(world, entity)] = true
		end
		if not sameSet(setOf(group:getEntities()), expected) then
			fail(world, `group {group:getId()} getEntities disagrees with the entities added`)
			return
		end
	end

	-- Memberships, the observers' tracked maps and the zones' occupant counts
	local occupants = {}
	for _, entity in world.entities do
		local data = State.entityData[entity]
		if (data ~= nil) ~= tracked(world, entity) then
			fail(
				world,
				`{describeEntity(world, entity)} tracked {data ~= nil}, but in a group {tracked(world, entity)}`
			)
			return
		end
		if not data then
			continue
		end
		for observerId, zoneId in data.activeObserverMemberships do
			local trackedMap = State.observerTrackingEntities[observerId]
			if not trackedMap or trackedMap[entity] ~= zoneId then
				fail(
					world,
					`{describeEntity(world, entity)} is in zone {zoneId} for observer id {observerId}, its tracked map disagrees`
				)
				return
			end
			if not State.zoneIdToZoneObj[zoneId] then
				fail(world, `{describeEntity(world, entity)} is in destroyed zone {zoneId}`)
				return
			end
			occupants[zoneId] = (occupants[zoneId] or 0) + 1
		end
	end
	for _, model in liveObservers(world) do
		local observerId = model.observer:getId()
		for entity, zoneId in State.observerTrackingEntities[observerId] or {} do
			local data = State.entityData[entity]
			if not data or data.activeObserverMemberships[observerId] ~= zoneId then
				fail(world, `observer {model.index} tracks an entity in zone {zoneId} that has no such membership`)
				return
			end
		end
	end
	for _, zone in world.zones do
		local id = zone:getId()
		if State.zoneOccupants[id] ~= occupants[id] then
			fail(world, `{describeZone(zone)} counts {State.zoneOccupants[id]} occupants, has {occupants[id]}`)
			return
		end
	end
end

-- Holds after an update in which nothing changed: each entity is in a zone containing it, of the highest
-- priority observers watching it, and keeps its zone while it still fits
local function nearAnySurface(world: World, point: Vector3): boolean
	for _, zone in world.zones do
		if nearSurface(zone, point) then
			return true
		end
	end
	return false
end

-- The leaves the trees return for a point, and what each zone's leaf and shape say about it
local function describeLeaves(zones: { [any]: any }, point: Vector3): string
	local hits = {}
	local hitSlots = {}
	for i = 1, ZoneShapes.leavesAtPoint(point, hits) do
		hitSlots[hits[i]] = true
	end

	local parts = {}
	for zone in zones do
		local slot = zone.slot
		local leaf = hitSlots[slot] == true and ZoneShapes.leafContainsPoint(slot, point)
		table.insert(
			parts,
			`{describeZone(zone)} ({zone:getShape()}, dynamic {zone:isDynamic()}, slot {slot}, cframe {zone:getCFrame()}, size {zone:getSize()}): shape {zone:isPointInside(
				point
			)}, leaf {leaf}, exact leaf {State.treeExact[slot]}`
		)
		hitSlots[slot] = nil
	end
	for slot in hitSlots do
		local zone = State.zoneSlotToZoneObj[slot]
		table.insert(
			parts,
			`other leaf at slot {slot} ({if zone then describeZone(zone) else 'no zone'}, attached to observer ids {table.concat(
				State.zoneAttachedObservers[slot] or {},
				','
			)}): leaf {ZoneShapes.leafContainsPoint(slot, point)}`
		)
	end
	return table.concat(parts, '; ')
end

-- What is wrong with the entity after an update in which nothing changed, or nil. It is in a zone containing
-- it, of the highest priority observers watching it, and keeps its zone while it still fits
local function entityProblem(world: World, live: { ObserverModel }, entity: Entity): string?
	local position = positionOf(entity)
	local candidates = {}
	local best = -math.huge
	for _, model in live do
		local inside = {}
		for zone in model.zones do
			if zone:isPointInside(position) then
				inside[zone] = true
			end
		end
		candidates[model] = inside
		if model.enabled and next(inside) and subscribedTo(model, world, entity) and model.priority > best then
			best = model.priority
		end
	end

	local zonesOfEntity = {}
	for _, model in live do
		local zone = model.observer:getZoneOfEntity(entity)
		local inside = candidates[model]
		local wins = model.enabled
			and next(inside) ~= nil
			and subscribedTo(model, world, entity)
			and model.priority == best
		local previous = model.previous[entity]
		local expected = if not wins
			then 'no zone'
			elseif previous and inside[previous] then describeZone(previous)
			else 'a zone containing it'

		if
			(not wins and zone ~= nil)
			or (wins and (zone == nil or not inside[zone]))
			or (wins and previous and inside[previous] and zone ~= previous)
		then
			return `observer {model.index} (priority {model.priority}, best {best}) has {describeEntity(world, entity)} in {describeZone(
				zone
			)}, expected {expected}, previously {describeZone(previous)}, inside {describeZones(inside)}`
		end

		if zone then
			zonesOfEntity[zone] = true
		end
		if model.observer:isPointInside(position) ~= (next(inside) ~= nil) then
			return `observer {model.index} (id {model.observer:getId()}) isPointInside disagrees for {describeEntity(
				world,
				entity
			)} at {position}: {describeLeaves(model.zones, position)}`
		end
	end

	if tracked(world, entity) and not sameSet(setOf(QuickZone:getZonesOfEntity(entity)), zonesOfEntity) then
		return `QuickZone:getZonesOfEntity disagrees for {describeEntity(world, entity)}`
	end

	local found = setOf(QuickZone:getZonesAtPoint(position))
	for _, zone in world.zones do
		if zone:isPointInside(position) ~= (found[zone] == true) then
			return `QuickZone:getZonesAtPoint disagrees at {position}, found {found[zone] == true}: {describeLeaves(
				{ [zone] = true },
				position
			)}`
		end
	end

	return nil
end

local function checkModel(world: World)
	if world.failure then
		return
	end

	local live = liveObservers(world)
	for _, entity in world.entities do
		local problem = entityProblem(world, live, entity)
		if problem and not nearAnySurface(world, positionOf(entity)) then
			fail(world, problem)
			return
		end
	end

	-- Zones following a part are where it is after an update
	for zone, part in world.partOf do
		if (zone :: any).autoSync and (zone:getCFrame().Position - part.Position).Magnitude > 1e-3 then
			fail(world, `{describeZone(zone)} is at {zone:getCFrame().Position}, its part at {part.Position}`)
			return
		end
	end

	-- Queries by zone agree with the zone of each entity
	for _, model in live do
		local observer = model.observer
		-- Keyed by what the API hands out
		local inside = {}
		local byZone = {}
		for _, entity in world.entities do
			local zone = observer:getZoneOfEntity(entity)
			if zone then
				local ref = refOf(world, entity)
				inside[ref] = zone
				byZone[zone] = byZone[zone] or {}
				byZone[zone][ref] = true
				if observer:getZoneOfEntity(ref) ~= zone then
					fail(
						world,
						`observer {model.index} getZoneOfEntity disagrees for the reference of {describeEntity(
							world,
							entity
						)}`
					)
					return
				end
			end
		end

		if not sameSet(setOf(observer:getEntitiesInside()), inside) then
			fail(world, `observer {model.index} getEntitiesInside disagrees with getZoneOfEntity`)
			return
		end
		local iterated = {}
		for entity, zone in observer:iterEntitiesInside() do
			if inside[entity] ~= zone then
				fail(world, `observer {model.index} iterEntitiesInside yields {describeZone(zone)} for an entity`)
				return
			end
			iterated[entity] = true
		end
		if not sameSet(iterated, inside) then
			fail(world, `observer {model.index} iterEntitiesInside misses entities`)
			return
		end
		for zone in model.zones do
			if not sameSet(setOf(observer:getEntitiesInZone(zone)), byZone[zone] or {}) then
				fail(world, `observer {model.index} getEntitiesInZone disagrees for {describeZone(zone)}`)
				return
			end
		end
	end
end

local function update(world: World)
	for _, model in liveObservers(world) do
		for _, entity in world.entities do
			model.previous[entity] = model.observer:getZoneOfEntity(entity)
		end
	end
	record(world, `update{if world.mutating then ' with callbacks changing state' else ''}`)
	world.changedInCallback = false
	QuickZone:update(1)
	checkConsistency(world)
end

local function moveEntities(world: World)
	local rng = world.rng
	for _, entity in world.entities do
		local roll = rng:NextNumber()
		if roll < 0.1 then
			setPositionOf(entity, world.origin + Util.randomOffset(rng, SPREAD + 5))
		elseif roll < 0.5 then
			-- Further than any precision, so it is always checked again
			setPositionOf(entity, positionOf(entity) + Util.randomOffset(rng, 1).Unit * rng:NextNumber(1, 4))
		end
	end
end

-- Keys of every plain State table, to find what a run leaves behind
local function snapshotState(): { [string]: { [any]: true } }
	local snapshot = {}
	for name, value in State :: any do
		if type(value) ~= 'table' or getmetatable(value) ~= nil then
			continue
		end
		if name == 'freeZoneSlots' or name == 'staticTree' or name == 'dynamicTree' then
			continue
		end
		if name == 'staticChanges' or name == 'dynamicChanges' then
			continue
		end
		local keys = {}
		for key in value do
			keys[key] = true
		end
		snapshot[name] = keys
	end
	return snapshot
end

local function run(seed: number, steps: number): string?
	local rng = Random.new(seed)
	local world: World = {
		seed = seed,
		rng = rng,
		origin = Vector3.new(20000 + seed * 300, 0, 20000),
		step = 0,
		log = {},
		entities = {},
		entityIndex = {},
		zones = {},
		groups = {},
		members = {},
		autoClean = {},
		references = {},
		parented = {},
		partOf = {},
		extras = {},
		instances = {},
		observers = {},
		mutating = false,
		changedInCallback = false,
		callbackDepth = 0,
		callbackCount = 0,
		failure = nil,
	}
	for i = 1, ENTITY_COUNT do
		local position = world.origin + Util.randomOffset(rng, SPREAD + 5)
		local entity
		local kind = i % 4
		if kind == 0 then
			entity = { Position = position }
		elseif kind == 1 then
			entity = { CFrame = CFrame.new(position) }
		elseif kind == 2 then
			entity = Util.createPart({ Position = position })
		else
			-- Half with a primary part, half followed by their pivot
			entity = Instance.new('Model')
			local part = Util.createPart({ Position = position })
			part.Parent = entity
			if i % 8 == 3 then
				entity.PrimaryPart = part
			end
			entity.Parent = workspace
			entity:PivotTo(CFrame.new(position))
		end
		if typeof(entity) == 'Instance' then
			table.insert(world.instances, entity)
			world.parented[entity] = true
		end
		world.entities[i] = entity
		world.entityIndex[entity] = i
	end

	local before = snapshotState()

	for _ = 1, 12 do
		OPERATIONS.createZone(world, rng)
	end
	OPERATIONS.createGroup(world, rng)
	OPERATIONS.createGroup(world, rng)
	OPERATIONS.createObserver(world, rng)
	OPERATIONS.createObserver(world, rng)

	for step = 1, steps do
		world.step = step
		-- Quiet steps make one call with everything standing still, so only that call can change zones
		local quiet = rng:NextNumber() < 0.4
		world.mutating = not quiet and rng:NextNumber() < 0.4

		for _ = 1, if quiet then 1 else rng:NextInteger(0, 4) do
			local name = randomOperationName(rng)
			local ok, err = pcall(runOperation, world, name, rng)
			if not ok then
				fail(world, `{name} errored: {err}`)
			end
			checkConsistency(world)
		end
		if not quiet then
			moveEntities(world)
		end

		-- Some steps first run ticks cut short by the budget, or with odd time steps
		if not quiet and rng:NextNumber() < 0.25 then
			for _ = 1, rng:NextInteger(1, 4) do
				local budget = ({ 1e-6, 0.05, 1000 })[rng:NextInteger(1, 3)]
				local dt = ({ 0, 1 / 60, 1 / 30, 0.5 })[rng:NextInteger(1, 4)]
				record(world, `partial update, budget {budget} ms, dt {dt}`)
				QuickZone:setFrameBudget(budget)
				world.changedInCallback = false
				local ok, err = pcall(QuickZone.update, QuickZone, dt)
				QuickZone:setFrameBudget(1000)
				if not ok then
					fail(world, `partial update errored: {err}`)
				end
				checkConsistency(world)
			end
		end
		update(world)

		-- Callbacks may have left changes for the next update to pick up
		if world.mutating then
			world.mutating = false
			update(world)
		end
		checkModel(world)

		if world.failure then
			break
		end
	end

	-- Tear down in a random order, then nothing may be left behind
	world.mutating = false
	while not world.failure do
		local kinds = {}
		if #world.zones > 0 then
			table.insert(kinds, 'destroyZone')
		end
		if #world.groups > 0 then
			table.insert(kinds, 'destroyGroup')
		end
		if #liveObservers(world) > 0 then
			table.insert(kinds, 'destroyObserver')
		end
		if #kinds == 0 then
			break
		end
		world.step += 1
		runOperation(world, kinds[rng:NextInteger(1, #kinds)], rng)
		checkConsistency(world)
	end
	QuickZone:update(1)

	if not world.failure then
		for name, keys in snapshotState() do
			for key in keys do
				if not (before[name] and before[name][key]) then
					fail(world, `State.{name}[{key}] is left behind after everything was destroyed`)
					break
				end
			end
		end
	end

	-- Clean up after a failed run so later tests start clean
	for _, zone in world.zones do
		pcall(zone.destroy, zone)
	end
	for _, group in world.groups do
		pcall(group.destroy, group)
	end
	for _, model in liveObservers(world) do
		pcall(model.observer.destroy, model.observer)
	end
	for _, instance in world.instances do
		instance:Destroy()
	end

	return world.failure
end

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect

	Describe('Random use against a model', function()
		Test(
			'Observers, groups and zones changed at random agree with a brute-force model after every update.',
			function()
				-- Every entity is evaluated in one tick
				QuickZone:setFrameBudget(1000)
				local failures = {}
				for seed = 1, 20 do
					local failure = run(seed, 120)
					if failure then
						table.insert(failures, failure)
					end
				end
				QuickZone:setFrameBudget(1)

				Expect(table.concat(failures, '\n\n')).is('')
			end
		)
	end)
end

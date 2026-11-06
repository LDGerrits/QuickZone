--!strict
-- Misuse and odd timing that a game hits sooner or later: callbacks that destroy what fired them, zones that go
-- away together, values of the wrong type, iterators whose tables change under them, entities that are also
-- references, players whose parts are swapped, and a check of every shape against the engine's own geometry
local CollectionService = game:GetService('CollectionService')
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest

local Util = require(TestFolder.Util)

local QuickZone = require(ReplicatedStorage.QuickZone)
local State = require(ReplicatedStorage.QuickZone.Core.State)
local Zone = QuickZone.Zone
local Group = QuickZone.Group
local Observer = QuickZone.Observer

type Tiniest = typeof(require(TiniestFolder.tiniest_for_roblox).configure({}))

local NAN = 0 / 0
local INF = math.huge
local AWAY = Vector3.new(0, 5000, 0)

-- Calls fn, then destroys whatever it registered, so a failing expectation leaves nothing behind. Every entity
-- is checked in each update
local function withCleanup(fn: (track: (any) -> any) -> ())
	local tracked = {}
	local function track(object: any): any
		table.insert(tracked, object)
		return object
	end

	QuickZone:setFrameBudget(1000)
	local ok, err = pcall(fn, track)
	QuickZone:setFrameBudget(1)
	for i = #tracked, 1, -1 do
		local object = tracked[i]
		if typeof(object) == 'Instance' then
			object:Destroy()
		elseif type(object) == 'table' and not object.destroyed and type(object.destroy) == 'function' then
			pcall(object.destroy, object)
		end
	end
	if not ok then
		error(err, 0)
	end
end

local function cube(position: Vector3, size: number?): { cframe: CFrame, size: Vector3 }
	return { cframe = CFrame.new(position), size = Vector3.one * (size or 10) }
end

-- Whether pcall(fn, ...) failed with a message containing text
local function refuses(text: string, fn: (...any) -> ...any, ...: any): boolean
	local ok, err = pcall(fn, ...)
	return not ok and string.find(tostring(err), text, 1, true) ~= nil
end

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect

	local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()

	Describe('Callbacks that change what fired them', function()
		Test(
			'An observer destroyed by an exit callback still tells every other exit callback, and its group cleanups run.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-41000, 0, 41000)
					local entity = { Position = position }
					local zone = track(Zone.new(cube(position)))
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
					local events = {}
					observer:onExit(function()
						table.insert(events, 'destroy')
						observer:destroy()
					end)
					observer:onExit(function()
						table.insert(events, 'exit')
					end)
					observer:observe(function()
						return function()
							table.insert(events, 'observe cleanup')
						end
					end)
					observer:observeGroup(function()
						return function()
							table.insert(events, 'group cleanup')
						end
					end)
					observer:onGroupExit(function()
						table.insert(events, 'group exit')
					end)

					QuickZone:update(1)
					entity.Position = position + AWAY
					QuickZone:update(1)

					-- The observe cleanup runs as the observer is destroyed, the rest hear the exit after
					Expect(table.concat(events, ', ')).is('destroy, observe cleanup, exit, group cleanup, group exit')
				end)
			end
		)

		Test(
			'A zone destroyed by an enter callback hands the entry on to an overlapping zone, where later callbacks see it.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-41100, 0, 41000)
					local entity = { Position = position + AWAY }
					local zoneA = track(Zone.new(cube(position)))
					local zoneB = track(Zone.new(cube(position)))
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer =
						track(Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false }))
					QuickZone:update(1)

					local destroyed = nil
					local function name(zone: any): string
						return if zone == destroyed then 'destroyed' else 'other'
					end
					local events = {}
					observer:onEnter(function(_, zone)
						if not destroyed then
							destroyed = zone
							table.insert(events, 'destroy')
							zone:destroy()
						end
					end)
					observer:onTransition(function(_, zone)
						table.insert(events, `transition {name(zone)}`)
					end)
					observer:onEnter(function(_, zone)
						table.insert(events, `enter {name(zone)}`)
					end)
					observer:observe(function(_, zone)
						table.insert(events, `observe {name(zone)}`)
						return function()
							table.insert(events, 'cleanup')
						end
					end)

					entity.Position = position
					QuickZone:update(1)
					QuickZone:update(1)
					entity.Position = position + AWAY
					QuickZone:update(1)

					Expect(table.concat(events, ', ')).is(
						'destroy, transition other, enter other, observe other, cleanup'
					)
				end)
			end
		)

		Test('Callbacks connected while an event fires get the next event, not that one.', function()
			withCleanup(function(track)
				local position = Vector3.new(-41200, 0, 41000)
				local entity = { Position = position }
				local zone = track(Zone.new(cube(position)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				local events = {}
				local connected = false
				observer:onEnter(function()
					table.insert(events, 'first')
					if not connected then
						connected = true
						observer:onEnter(function()
							table.insert(events, 'late')
						end)
					end
				end)
				observer:onEnter(function()
					table.insert(events, 'second')
				end)

				QuickZone:update(1)
				entity.Position = position + AWAY
				QuickZone:update(1)
				entity.Position = position
				QuickZone:update(1)

				Expect(table.concat(events, ', ')).is('first, second, first, second, late')
			end)
		end)

		Test('Connecting tens of thousands of callbacks stays fast, and each fires once.', function()
			withCleanup(function(track)
				local position = Vector3.new(-41300, 0, 41000)
				local entity = { Position = position + AWAY }
				local zone = track(Zone.new(cube(position)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)

				local count = 0
				local function onEnter()
					count += 1
				end
				local disconnects = {}
				local start = os.clock()
				for i = 1, 50000 do
					disconnects[i] = observer:onEnter(onEnter)
				end
				local elapsed = os.clock() - start

				entity.Position = position
				QuickZone:update(1)
				local first = count

				-- Some disconnected, the others still fire
				for i = 1, 10 do
					disconnects[i]()
				end
				entity.Position = position + AWAY
				QuickZone:update(1)
				entity.Position = position
				QuickZone:update(1)

				Expect(if elapsed < 0.5 then 'fast' else string.format('%.2f s', elapsed)).is('fast')
				Expect(first).is(50000)
				Expect(count - first).is(49990)
			end)
		end)

		Test('An unsafe callback that yields holds updates back with one warning, and they resume after it.', function()
			withCleanup(function(track)
				local position = Vector3.new(-41400, 0, 41000)
				local entity = { Position = position }
				local zone = track(Zone.new(cube(position)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				local resumed = false
				observer:onEnter(function()
					task.wait(0.1)
					resumed = true
				end)
				local exits = 0
				observer:onExit(function()
					exits += 1
				end)

				QuickZone:setEnabled(false)
				local ok, err = pcall(function()
					task.spawn(QuickZone.update, QuickZone, 1)
					local warnings = Util.captureWarnings(function()
						QuickZone:update(1)
						QuickZone:update(1)
					end)
					local waited = 0
					while not resumed and waited < 2 do
						waited += task.wait()
					end
					entity.Position = position + AWAY
					QuickZone:update(1)

					Expect(#warnings).is(1)
					Expect(string.find(warnings[1], 'yielded', 1, true) ~= nil).is_true()
					Expect(resumed).is_true()
					Expect(exits).is(1)
				end)
				QuickZone:setEnabled(true)
				if not ok then
					error(err, 0)
				end
			end)
		end)
	end)

	Describe('Zones going away', function()
		Test(
			'An entity in a destroyed zone moves to a zone made, attached or moved there since the last update.',
			function()
				withCleanup(function(track)
					local results = {}
					for i, how in { 'made', 'moved', 'made dynamic' } do
						local position = Vector3.new(-42000 + i * 100, 0, 41000)
						local entity = { Position = position }
						local zoneA = track(Zone.new(cube(position)))
						local far = track(Zone.new(cube(position + AWAY)))
						local group = track(Group.new({ entities = { entity }, autoClean = false }))
						local observer =
							track(Observer.new({ zones = { zoneA, far }, groups = { group }, safety = false }))
						QuickZone:update(1)

						local events = {}
						observer:onEnter(function()
							table.insert(events, 'enter')
						end)
						observer:onExit(function()
							table.insert(events, 'exit')
						end)
						observer:onTransition(function()
							table.insert(events, 'transition')
						end)

						if how == 'made' then
							observer:attach(track(Zone.new(cube(position))))
						elseif how == 'moved' then
							far:setCFrame(CFrame.new(position))
						else
							observer:attach(track(Zone.new({
								cframe = CFrame.new(position),
								size = Vector3.one * 10,
								isDynamic = true,
							})))
						end
						zoneA:destroy()
						QuickZone:update(1)
						table.insert(results, `{how}: {table.concat(events, ' ')}`)
					end

					Expect(table.concat(results, ', ')).is(
						'made: transition, moved: transition, made dynamic: transition'
					)
				end)
			end
		)

		Test(
			'Destroying a Zones whose zones overlap exits once, rather than moving through zones about to go.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-42500, 0, 41000)
					local entity = { Position = position }
					local parts = {}
					for _ = 1, 5 do
						table.insert(
							parts,
							track(Util.createPart({ CFrame = CFrame.new(position), Size = Vector3.one * 10 }))
						)
					end
					local zones = track(Zone.fromParts(parts))
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer = track(Observer.new({ zones = { zones }, groups = { group }, safety = false }))
					QuickZone:update(1)

					local events = {}
					observer:onExit(function()
						table.insert(events, 'exit')
					end)
					observer:onTransition(function()
						table.insert(events, 'transition')
					end)
					zones:destroy()

					Expect(table.concat(events, ' ')).is('exit')
					Expect(next(State.zonesBeingDestroyed)).is(nil)
				end)
			end
		)

		Test('Destroying a Zones moves an entity to a zone of the observer outside it, once.', function()
			withCleanup(function(track)
				local position = Vector3.new(-42600, 0, 41000)
				local entity = { Position = position }
				local parts = {}
				for _ = 1, 3 do
					table.insert(
						parts,
						track(Util.createPart({ CFrame = CFrame.new(position), Size = Vector3.one * 10 }))
					)
				end
				local zones = track(Zone.fromParts(parts))
				local outside = track(Zone.new(cube(position)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zones }, groups = { group }, safety = false }))
				QuickZone:update(1)
				-- Attached after the update, so the entity is in one of the container's zones
				observer:attach(outside)
				QuickZone:update(1)
				local before = observer:getZoneOfEntity(entity)

				local events = {}
				observer:onExit(function()
					table.insert(events, 'exit')
				end)
				observer:onTransition(function(_, zone)
					table.insert(events, if zone == outside then 'transition outside' else 'transition inside')
				end)
				zones:destroy()

				Expect(before ~= outside).is_true()
				Expect(table.concat(events, ' ')).is('transition outside')
				Expect(observer:getZoneOfEntity(entity)).is(outside)
			end)
		end)

		Test(
			'Destroying the folder of fromChildren or fromDescendants removes its zones, and their entities exit.',
			function()
				withCleanup(function(track)
					local results = {}
					for i, how in { 'fromChildren', 'fromDescendants' } do
						local position = Vector3.new(-42700 + i * 100, 0, 41000)
						local folder = track(Instance.new('Folder'))
						folder.Parent = workspace
						local holder = folder
						if how == 'fromDescendants' then
							holder = Instance.new('Folder')
							holder.Parent = folder
						end
						Util.createPart({ CFrame = CFrame.new(position), Size = Vector3.one * 10 }).Parent = holder
						local zones = track((Zone :: any)[how](folder))
						local entity = { Position = position }
						local group = track(Group.new({ entities = { entity }, autoClean = false }))
						local observer = track(Observer.new({ zones = { zones }, groups = { group }, safety = false }))
						local exits = 0
						observer:onExit(function()
							exits += 1
						end)
						QuickZone:update(1)
						local inside = #observer:getEntitiesInside()

						folder:Destroy()
						task.wait()
						QuickZone:update(1)
						table.insert(results, `{how}: {inside} in, {#zones:getZones()} zones, {exits} exit`)
					end

					Expect(table.concat(results, ', ')).is(
						'fromChildren: 1 in, 0 zones, 1 exit, fromDescendants: 1 in, 0 zones, 1 exit'
					)
				end)
			end
		)
	end)

	Describe('Values of the wrong type', function()
		Test('Zone setters refuse wrong types and leave the zone as it was, so later changes still apply.', function()
			withCleanup(function(track)
				local position = Vector3.new(-43000, 0, 41000)
				local zone =
					track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10, isDynamic = true }))
				local refused = {}
				for _, case in
					{
						{ 'setCFrame', nil },
						{ 'setCFrame', position },
						{ 'setSize', 10 },
						{ 'setSize', nil },
						{ 'setPosition', CFrame.new() },
						{ 'setReference', 'Part' },
					}
				do
					local method = case[1]
					if not pcall((zone :: any)[method], zone, case[2]) then
						table.insert(refused, method)
					end
				end

				local unchanged = zone:getCFrame() == CFrame.new(position)
					and zone:getSize() == Vector3.one * 10
					and zone:getReference() == nil
				local moved = position + Vector3.new(100, 0, 0)
				zone:setCFrame(CFrame.new(moved))
				zone:setSize(Vector3.one * 4)
				QuickZone:rebuild()

				Expect(table.concat(refused, ', ')).is(
					'setCFrame, setCFrame, setSize, setSize, setPosition, setReference'
				)
				Expect(unchanged).is_true()
				Expect(zone:isPointInside(moved + Vector3.new(1.9, 0, 0))).is_true()
				Expect(zone:isPointInside(moved + Vector3.new(2.1, 0, 0))).is(false)
				Expect(table.find(QuickZone:getZonesAtPoint(moved), zone) ~= nil).is_true()
			end)
		end)

		Test('Zone constructors refuse bad input before taking a slot.', function()
			withCleanup(function()
				local position = Vector3.new(-43100, 0, 41000)
				local function used(): number
					return State.zoneSlotCount - #State.freeZoneSlots
				end
				local before = used()
				local zoneCount = #QuickZone:getZones()

				local refusals = {
					refuses(
						'reference',
						Zone.new,
						{ cframe = CFrame.new(position), size = Vector3.one, reference = 'Part' }
					),
					refuses('config', Zone.new, nil),
					refuses('BasePart', Zone.fromPart, nil),
					refuses('BasePart', Zone.fromPart, Instance.new('Folder')),
				}

				Expect(table.find(refusals, false)).is(nil)
				Expect(used()).is(before)
				Expect(#QuickZone:getZones()).is(zoneCount)
			end)
		end)

		Test('Flags given as non-booleans count as true or false, and keep the observers working.', function()
			withCleanup(function(track)
				local position = Vector3.new(-43200, 0, 41000)
				local entity = { Position = position }
				local static = track(Zone.new(cube(position + AWAY)))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { static }, groups = { group } }))

				-- Left static, so the observer's zone counts stay right and it finds the dynamic zone below
				static:setDynamic(nil :: any)
				local dynamic =
					track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10, isDynamic = true }))
				observer:attach(dynamic)
				QuickZone:update(1)
				local entered = #observer:getEntitiesInside()

				static:setDynamic(1 :: any)
				local truthy = static:isDynamic()

				observer:setEnabled(nil :: any)
				QuickZone:update(1)
				local disabled = not observer:isEnabled() and #observer:getEntitiesInside() == 0
				observer:setSafety(nil :: any)

				Expect(static:isDynamic() == truthy and truthy).is(true)
				Expect(entered).is(1)
				Expect(disabled).is_true()
				Expect(observer:isSafe()).is(false)
			end)
		end)

		Test('Every callback method refuses what is not a function when it is connected.', function()
			withCleanup(function(track)
				local observer = track(Observer.new({ zones = {}, groups = {} }))
				local accepted = {}
				for _, method in
					{
						'observe',
						'onEnter',
						'onExit',
						'observePlayer',
						'onPlayerEnter',
						'onPlayerExit',
						'observeGroup',
						'onGroupEnter',
						'onGroupExit',
						'onTransition',
						'onPlayerTransition',
						'onDestroy',
					}
				do
					if not refuses('callback', (observer :: any)[method], observer, nil) then
						table.insert(accepted, method)
					end
				end

				Expect(table.concat(accepted, ', ')).is('')
			end)
		end)

		Test('attach and detach take only a Zone or Zones, and refuse an Observer or Group.', function()
			withCleanup(function(track)
				local observer = track(Observer.new({ zones = {}, groups = {} }))
				local other = track(Observer.new({ zones = {}, groups = {} }))
				local group = track(Group.new())

				Expect(refuses('Zone', observer.attach, observer, other)).is_true()
				Expect(refuses('Zone', observer.detach, observer, other)).is_true()
				Expect(refuses('Zone', observer.attach, observer, group)).is_true()
				Expect(refuses('Zone', observer.attach, observer, {})).is_true()
				Expect(refuses('Zone', observer.getEntitiesInZone, observer, other)).is_true()
				Expect(#observer:getZones()).is(0)
				Expect(#other:getZones()).is(0)
			end)
		end)

		Test(
			'Detaching a destroyed zone and unsubscribing a destroyed group do nothing, also from callbacks.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-43300, 0, 41000)
					local entity = { Position = position }
					local zone = track(Zone.new(cube(position)))
					local zones = track(Zone.fromParts({ track(Util.createPart({ CFrame = CFrame.new(position) })) }))
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer =
						track(Observer.new({ zones = { zone, zones }, groups = { group }, safety = false }))
					QuickZone:update(1)

					-- The entity moves to the zone of zones, then the group's destroy exits it
					local fromCallback = {}
					observer:onExit(function()
						table.insert(fromCallback, (pcall(observer.unsubscribe, observer, group)))
						table.insert(fromCallback, (pcall(observer.detach, observer, zone)))
					end)
					zone:destroy()
					group:destroy()
					zones:destroy()

					Expect(pcall(observer.detach, observer, zone)).is_true()
					Expect(pcall(observer.detach, observer, zones)).is_true()
					Expect(pcall(observer.unsubscribe, observer, group)).is_true()
					Expect(#fromCallback).is(2)
					Expect(table.find(fromCallback, false)).is(nil)
					-- Subscribing a destroyed group is still a mistake
					Expect(refuses('destroyed', observer.subscribe, observer, group)).is_true()
				end)
			end
		)

		Test(
			'A zone with an infinite size, like a kill plane, is found by queries and observers everywhere on it.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-43400, -2000, 41000)
					local flat = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.new(INF, 10, INF) }))
					local turned = track(Zone.new({
						cframe = CFrame.new(position - Vector3.new(0, 100, 0)) * CFrame.Angles(0, math.pi / 4, 0),
						size = Vector3.new(INF, 10, INF),
					}))
					local small = track(Zone.new(cube(position + Vector3.new(0, 300, 0))))
					local far = position + Vector3.new(1e5, 0, -1e5)
					local entity = { Position = far }
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer =
						track(Observer.new({ zones = { flat, turned }, groups = { group }, safety = false }))
					QuickZone:update(1)
					local inFlat = observer:getZoneOfEntity(entity) == flat
					entity.Position = far - Vector3.new(0, 100, 0)
					QuickZone:update(1)
					local inTurned = observer:getZoneOfEntity(entity) == turned
					entity.Position = far + Vector3.new(0, 20, 0)
					QuickZone:update(1)

					Expect(inFlat).is_true()
					Expect(inTurned).is_true()
					Expect(observer:getZoneOfEntity(entity)).is(nil)
					Expect(table.find(QuickZone:getZonesAtPoint(far), flat) ~= nil).is_true()
					Expect(table.find(QuickZone:getZonesAtPoint(position + Vector3.new(0, 300, 0)), small) ~= nil).is_true()
					Expect(#QuickZone:getZonesAtPoint(position + Vector3.new(0, 50, 0))).is(0)
				end)
			end
		)

		Test('A kill plane does not slow down queries for the other zones.', function()
			withCleanup(function(track)
				local rng = Random.new(3)
				local origin = Vector3.new(-48000, 0, 48000)
				for _ = 1, 3000 do
					local offset = Vector3.new(rng:NextNumber(0, 3000), rng:NextNumber(0, 100), rng:NextNumber(0, 3000))
					track(Zone.new(cube(origin + offset, 8)))
				end
				local points = {}
				for _ = 1, 3000 do
					table.insert(
						points,
						origin + Vector3.new(rng:NextNumber(0, 3000), rng:NextNumber(0, 100), rng:NextNumber(0, 3000))
					)
				end
				-- The fastest of a few runs, so a hitch doesn't decide
				local function timeQueries(): number
					QuickZone:rebuild()
					local best = math.huge
					for _ = 1, 3 do
						local start = os.clock()
						for _, point in points do
							QuickZone:getZonesAtPoint(point)
						end
						best = math.min(best, os.clock() - start)
					end
					return best
				end

				local without = timeQueries()
				track(
					Zone.new({ cframe = CFrame.new(origin - Vector3.new(0, 500, 0)), size = Vector3.new(INF, 10, INF) })
				)
				local with = timeQueries()

				-- An infinite size once put every zone in the same Morton cell, about six times slower
				local ratio = with / without
				Expect(if ratio < 3 then 'about as fast' else string.format('%.1f times slower', ratio)).is(
					'about as fast'
				)
			end)
		end)

		Test(
			'Global settings refuse bad values without applying the others, and update takes a missing step.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-43500, 0, 41000)
					local entity = { Position = position + AWAY }
					local zone = track(Zone.new(cube(position)))
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))

					local refusals = {
						refuses('autoSyncRate', QuickZone.setAutoSyncRate, QuickZone, NAN),
						refuses('autoSyncRate', QuickZone.setAutoSyncRate, QuickZone, 'fast'),
						refuses('frameBudget', QuickZone.setFrameBudget, QuickZone, 'fast'),
						refuses('frameBudget', QuickZone.setFrameBudget, QuickZone, 0),
						refuses('frameBudget', QuickZone.configure, QuickZone, { enabled = false, frameBudget = -1 }),
						refuses(
							'autoSyncRate',
							QuickZone.configure,
							QuickZone,
							{ enabled = false, autoSyncRate = NAN }
						),
					}
					-- Off rather than refused, as 0 is
					QuickZone:setAutoSyncRate(-1)
					QuickZone:setAutoSyncRate(30)
					local missingStep = pcall(QuickZone.update, QuickZone, nil)

					-- Still enabled, so it updates by itself
					entity.Position = position
					local waited = 0
					while #observer:getEntitiesInside() == 0 and waited < 1 do
						waited += task.wait()
					end

					Expect(table.find(refusals, false)).is(nil)
					Expect(missingStep).is_true()
					Expect(#observer:getEntitiesInside()).is(1)
				end)
			end
		)

		Test('Zones:sync follows the parts also when the zones are static.', function()
			withCleanup(function(track)
				local position = Vector3.new(-43600, 0, 41000)
				local part = track(Util.createPart({ CFrame = CFrame.new(position), Size = Vector3.one * 10 }))
				local zones = track(Zone.fromParts({ part }))
				local moved = position + Vector3.new(0, 100, 0)
				part.CFrame = CFrame.new(moved)
				zones:sync()

				Expect(zones:isDynamic()).is(false)
				Expect(zones:isPointInside(moved)).is_true()
				Expect(zones:isPointInside(position)).is(false)
			end)
		end)
	end)

	Describe('Iterators while their tables change', function()
		-- Starts the loop, then removes half of ours, including the one just returned when it is ours, and grows
		-- the table enough to rehash it. Ours that stayed must each come once, removed ones never
		local function check(
			name: string,
			iterate: () -> () -> any,
			ours: { any },
			remove: (any) -> (),
			grow: () -> ()
		): string
			local isOurs = {}
			for _, item in ours do
				isOurs[item] = true
			end

			local nextItem = iterate()
			local seen = {}
			local first = nextItem()
			if first ~= nil then
				seen[first] = 1
			end
			local removed = {}
			local removedCount = 0
			local function take(item: any)
				removed[item] = true
				removedCount += 1
				remove(item)
			end
			if isOurs[first] then
				take(first)
			end
			for _, item in ours do
				if removedCount >= #ours // 2 then
					break
				elseif not seen[item] and not removed[item] then
					take(item)
				end
			end
			grow()

			local ok, err = pcall(function()
				while true do
					local item = nextItem()
					if item == nil then
						break
					end
					seen[item] = (seen[item] or 0) + 1
				end
			end)
			if not ok then
				return `{name}: {err}`
			end
			for _, item in ours do
				local count = seen[item] or 0
				if removed[item] and count ~= (if item == first then 1 else 0) then
					return `{name}: a removed item came`
				elseif not removed[item] and count ~= 1 then
					return `{name}: an item came {count} times`
				end
			end
			return `{name}: ok`
		end

		Test('Every plain iterator survives its table shrinking and growing during the loop.', function()
			withCleanup(function(track)
				local origin = Vector3.new(-44000, 0, 41000)
				local results = {}
				local function spot(i: number): Vector3
					return origin + Vector3.new(i * 20, 0, 0)
				end
				local function many(count: number, make: (number) -> ())
					for i = 1, count do
						make(i)
					end
				end

				do -- Group:iterEntities
					local group = track(Group.new({ autoClean = false }))
					local ours = {}
					for i = 1, 8 do
						local entity = { Position = spot(i) }
						group:add(entity)
						table.insert(ours, entity)
					end
					table.insert(
						results,
						check(
							'Group:iterEntities',
							function()
								return group:iterEntities()
							end,
							ours,
							function(entity)
								group:remove(entity)
							end,
							function()
								many(300, function(i)
									group:add({ Position = spot(i) })
								end)
							end
						)
					)
				end

				do -- QuickZone:iterEntities
					local group = track(Group.new({ autoClean = false }))
					local ours = {}
					for i = 1, 8 do
						local entity = { Position = spot(i) }
						group:add(entity)
						table.insert(ours, entity)
					end
					local entityCount = 0
					for _ in State.entityData do
						entityCount += 1
					end
					table.insert(
						results,
						check(
							'QuickZone:iterEntities',
							function()
								return QuickZone:iterEntities()
							end,
							ours,
							function(entity)
								QuickZone:removeEntity(entity)
							end,
							function()
								many(math.max(300, entityCount * 2), function(i)
									group:add({ Position = spot(i) })
								end)
							end
						)
					)
				end

				do -- QuickZone:iterGroups
					local ours = {}
					for _ = 1, 8 do
						table.insert(ours, track(Group.new()))
					end
					table.insert(
						results,
						check(
							'QuickZone:iterGroups',
							function()
								return QuickZone:iterGroups()
							end,
							ours,
							function(group)
								group:destroy()
							end,
							function()
								many(300, function()
									track(Group.new())
								end)
							end
						)
					)
				end

				do -- QuickZone:iterZones
					local ours = {}
					for i = 1, 8 do
						table.insert(ours, track(Zone.new(cube(spot(i), 1))))
					end
					table.insert(
						results,
						check(
							'QuickZone:iterZones',
							function()
								return QuickZone:iterZones()
							end,
							ours,
							function(zone)
								zone:destroy()
							end,
							function()
								many(300, function(i)
									track(Zone.new(cube(spot(i), 1)))
								end)
							end
						)
					)
				end

				do -- QuickZone:iterObservers
					local ours = {}
					for _ = 1, 8 do
						table.insert(ours, track(Observer.new({ zones = {}, groups = {} })))
					end
					table.insert(
						results,
						check(
							'QuickZone:iterObservers',
							function()
								return QuickZone:iterObservers()
							end,
							ours,
							function(observer)
								observer:destroy()
							end,
							function()
								many(300, function()
									track(Observer.new({ zones = {}, groups = {} }))
								end)
							end
						)
					)
				end

				do -- QuickZone:iterGroupsOfEntity
					local entity = { Position = spot(1) }
					local ours = {}
					for _ = 1, 8 do
						table.insert(ours, track(Group.new({ entities = { entity }, autoClean = false })))
					end
					table.insert(
						results,
						check(
							'QuickZone:iterGroupsOfEntity',
							function()
								return QuickZone:iterGroupsOfEntity(entity)
							end,
							ours,
							function(group)
								group:remove(entity)
							end,
							function()
								many(300, function()
									track(Group.new({ entities = { entity }, autoClean = false }))
								end)
							end
						)
					)
				end

				do -- QuickZone:iterZonesOfEntity
					local position = spot(40)
					local entity = { Position = position }
					local group = track(Group.new({ entities = { entity }, autoClean = false }))
					local ours = {}
					for _ = 1, 8 do
						local zone = track(Zone.new(cube(position)))
						table.insert(ours, zone)
						track(Observer.new({ zones = { zone }, groups = { group } }))
					end
					QuickZone:update(1)
					table.insert(
						results,
						check(
							'QuickZone:iterZonesOfEntity',
							function()
								return QuickZone:iterZonesOfEntity(entity)
							end,
							ours,
							function(zone)
								zone:destroy()
							end,
							function()
								many(100, function()
									track(
										Observer.new({ zones = { track(Zone.new(cube(position))) }, groups = { group } })
									)
								end)
								QuickZone:update(1)
							end
						)
					)
				end

				do -- Observer:iterZones
					local observer = track(Observer.new({ zones = {}, groups = {} }))
					local ours = {}
					for i = 1, 8 do
						local zone = track(Zone.new(cube(spot(i), 1)))
						observer:attach(zone)
						table.insert(ours, zone)
					end
					table.insert(
						results,
						check(
							'Observer:iterZones',
							function()
								return observer:iterZones()
							end,
							ours,
							function(zone)
								observer:detach(zone)
							end,
							function()
								many(300, function(i)
									observer:attach(track(Zone.new(cube(spot(i), 1))))
								end)
							end
						)
					)
				end

				do -- Observer:iterGroups
					local observer = track(Observer.new({ zones = {}, groups = {} }))
					local ours = {}
					for _ = 1, 8 do
						local group = track(Group.new())
						observer:subscribe(group)
						table.insert(ours, group)
					end
					table.insert(
						results,
						check(
							'Observer:iterGroups',
							function()
								return observer:iterGroups()
							end,
							ours,
							function(group)
								group:destroy()
							end,
							function()
								many(300, function()
									observer:subscribe(track(Group.new()))
								end)
							end
						)
					)
				end

				for _, method in { 'iterZones', 'iterReferences' } do -- Zones
					local folder = track(Instance.new('Folder'))
					folder.Parent = workspace
					for i = 1, 8 do
						Util.createPart({ CFrame = CFrame.new(spot(i)) }).Parent = folder
					end
					local zones = track(Zone.fromChildren(folder))
					local ours = if method == 'iterZones' then zones:getZones() else zones:getReferences()
					table.insert(
						results,
						check(
							`Zones:{method}`,
							function()
								return (zones :: any)[method](zones)
							end,
							ours,
							function(item)
								local part = if method == 'iterZones' then item:getReference() else item
								part:Destroy()
							end,
							function()
								many(300, function(i)
									Util.createPart({ CFrame = CFrame.new(spot(i)) }).Parent = folder
								end)
							end
						)
					)
				end

				Expect(table.concat(results, '\n')).is(table.concat({
					'Group:iterEntities: ok',
					'QuickZone:iterEntities: ok',
					'QuickZone:iterGroups: ok',
					'QuickZone:iterZones: ok',
					'QuickZone:iterObservers: ok',
					'QuickZone:iterGroupsOfEntity: ok',
					'QuickZone:iterZonesOfEntity: ok',
					'Observer:iterZones: ok',
					'Observer:iterGroups: ok',
					'Zones:iterZones: ok',
					'Zones:iterReferences: ok',
				}, '\n'))
			end)
		end)
	end)

	Describe('Entities that are also references', function()
		Test("An entity that is another entity's reference is found and removed as itself.", function()
			withCleanup(function(track)
				local position = Vector3.new(-45000, 0, 41000)
				local npc = { Position = position }
				local hitbox = { Position = position }
				local zone = track(Zone.new(cube(position)))
				local npcs = track(Group.new({ entities = { npc }, autoClean = false }))
				local hitboxes = track(Group.new({ entities = { hitbox }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { npcs } }))
				QuickZone:setReference(hitbox, npc)
				QuickZone:update(1)

				local groupsOfNpc = QuickZone:getGroupsOfEntity(npc)
				local iterated = {}
				for group in QuickZone:iterGroupsOfEntity(npc) do
					table.insert(iterated, group)
				end

				Expect(npcs:contains(npc)).is_true()
				Expect(hitboxes:contains(npc)).is(false)
				Expect(#groupsOfNpc == 1 and groupsOfNpc[1] == npcs).is_true()
				Expect(#iterated == 1 and iterated[1] == npcs).is_true()
				Expect(observer:getZoneOfEntity(npc)).is(zone)
				Expect(QuickZone:getZonesOfEntity(npc)[1]).is(zone)
				Expect(QuickZone:iterZonesOfEntity(npc)()).is(zone)
				-- The reference map itself still leads from the reference to its entity
				Expect(QuickZone:getEntityOfReference(npc)).is(hitbox)

				QuickZone:removeEntity(npc)
				Expect(#npcs:getEntities()).is(0)
				Expect(#hitboxes:getEntities()).is(1)
				Expect(hitboxes:getEntities()[1]).is(npc)
			end)
		end)

		Test(
			"A tag group adds the tagged instance itself, also when it is another entity's reference, and lets it go.",
			function()
				withCleanup(function(track)
					local position = Vector3.new(-45100, 0, 41000)
					local npc = track(Util.createPart({ CFrame = CFrame.new(position) }))
					local hitbox = track(Util.createPart({ CFrame = CFrame.new(position) }))
					track(Group.new({ entities = { hitbox }, autoClean = false }))
					QuickZone:setReference(hitbox, npc)
					local tag = `QuickZoneRobustness{math.random(1e9)}`
					local tagged = track(Group.fromTag(tag))

					CollectionService:AddTag(npc, tag)
					task.wait()
					local added = tagged:contains(npc) and not tagged:contains(hitbox)
					CollectionService:RemoveTag(npc, tag)
					task.wait()

					Expect(added).is_true()
					Expect(#tagged:getEntities()).is(0)
				end)
			end
		)

		Test('Adding nil to a group reports it and adds nothing.', function()
			withCleanup(function(track)
				local group = track(Group.new())
				Expect(pcall(group.add, group, nil)).is_true()
				Expect(pcall(group.addBulk, group, { nil, nil })).is_true()
				Expect(#group:getEntities()).is(0)
			end)
		end)
	end)

	Describe('Observers resolve priorities and rates at the extremes', function()
		Test('Infinite and negative priorities take entities in order.', function()
			withCleanup(function(track)
				local position = Vector3.new(-45200, 0, 41000)
				local entity = { Position = position }
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local zone = track(Zone.new(cube(position)))
				local observers = {}
				for _, priority in { -INF, -5, 0, 1e300, INF } do
					table.insert(
						observers,
						track(Observer.new({ zones = { zone }, groups = { group }, priority = priority }))
					)
				end
				local winners = {}
				for i = #observers, 1, -1 do
					QuickZone:update(1)
					for j = 1, i do
						if observers[j]:getZoneOfEntity(entity) then
							table.insert(winners, j)
						end
					end
					observers[i]:destroy()
				end

				Expect(table.concat(winners, ' ')).is('5 4 3 2 1')
			end)
		end)

		Test('An entity watched at two rates is checked at the higher one.', function()
			withCleanup(function(track)
				local position = Vector3.new(-45300, 0, 41000)
				local entity = { Position = position + AWAY }
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local zone = track(Zone.new(cube(position)))
				local slow = track(Observer.new({ zones = { zone }, groups = { group }, updateRate = 1 }))
				track(Observer.new({ zones = { zone }, groups = { group }, updateRate = 60, priority = -1 }))
				QuickZone:update(1)

				entity.Position = position
				QuickZone:update(1 / 60)
				Expect(slow:getZoneOfEntity(entity)).is(zone)
			end)
		end)
	end)

	Describe('Zones moving between trees from callbacks', function()
		Test(
			'A zone made dynamic and rebuilt from a callback in the middle of a tick is found by later entities.',
			function()
				withCleanup(function(track)
					local position = Vector3.new(-45400, 0, 41000)
					local target = position + Vector3.new(100, 0, 0)
					local a = { Position = position + AWAY }
					local b = { Position = position + AWAY }
					local zone = track(Zone.new(cube(position)))
					local keepStatic = track(Zone.new(cube(position + Vector3.new(0, 500, 0))))
					local trigger = track(Zone.new(cube(target)))
					local group = track(Group.new({ entities = { a, b }, autoClean = false }))
					local watcher =
						track(Observer.new({ zones = { zone, keepStatic }, groups = { group }, updateRate = 37.25 }))
					local switcher = track(
						Observer.new({ zones = { trigger }, groups = { group }, updateRate = 37.25, safety = false })
					)
					QuickZone:update(1)

					switcher:onEnter(function()
						if not zone:isDynamic() then
							zone:setDynamic(true)
							QuickZone:rebuild()
						end
					end)
					-- The first in the bucket runs the callback, the second is checked after it in the same tick
					local bucket = State.buckets[37.25]
					bucket[1].Position = target
					bucket[2].Position = position
					for _ = 1, 3 do
						QuickZone:update(1)
					end

					Expect(#watcher:getEntitiesInside()).is(1)
				end)
			end
		)
	end)

	Describe('Shapes against the engine', function()
		Test('Every part shape holds the points the engine says the part holds.', function()
			withCleanup(function(track)
				local rng = Random.new(31)
				local specs: { { any } } = {
					{ 'Block', 'Part', Enum.PartType.Block },
					{ 'Ball', 'Part', Enum.PartType.Ball },
					{ 'Cylinder', 'Part', Enum.PartType.Cylinder },
					{ 'Wedge', 'Part', Enum.PartType.Wedge },
					{ 'CornerWedge', 'Part', Enum.PartType.CornerWedge },
					{ 'WedgePart', 'WedgePart' },
					{ 'CornerWedgePart', 'CornerWedgePart' },
				}
				local results = {}
				for s, spec in specs do
					local mismatch: string? = nil
					local checked = 0
					for trial = 1, 3 do
						local properties: { [string]: any } = {
							Size = Vector3.new(rng:NextNumber(2, 20), rng:NextNumber(2, 20), rng:NextNumber(2, 20)),
							CFrame = CFrame.new(-46000 + s * 100, 200, 41000 + trial * 50) * CFrame.fromOrientation(
								rng:NextNumber(-3, 3),
								rng:NextNumber(-3, 3),
								rng:NextNumber(-3, 3)
							),
						}
						if spec[3] then
							properties.Shape = spec[3]
						end
						local part = track(Util.create({ className = spec[2], properties = properties })) :: BasePart
						local zone = track(Zone.fromPart(part))

						local function engineHolds(point: Vector3): boolean
							return (part:GetClosestPointOnSurface(point) - point).Magnitude < 1e-4
						end
						for _ = 1, 200 do
							local offset = Vector3.new(
								rng:NextNumber(-0.6, 0.6),
								rng:NextNumber(-0.6, 0.6),
								rng:NextNumber(-0.6, 0.6)
							)
							local point = part.CFrame * (offset * part.Size)
							local holds = engineHolds(point)
							-- Skipped within 0.02 studs of the surface, where float error may decide
							local clear = true
							for _, step in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
								for _, sign in { 0.02, -0.02 } do
									clear = clear and engineHolds(point + step * sign) == holds
								end
							end
							if clear then
								checked += 1
								if zone:isPointInside(point) ~= holds then
									mismatch = mismatch or `{offset * part.Size} in {part.Size}, engine says {holds}`
								end
							end
						end
					end
					table.insert(
						results,
						`{spec[1]}: {mismatch or 'agrees'}{if checked < 300 then ' (too few points)' else ''}`
					)
				end

				Expect(table.concat(results, '\n')).is(table.concat({
					'Block: agrees',
					'Ball: agrees',
					'Cylinder: agrees',
					'Wedge: agrees',
					'CornerWedge: agrees',
					'WedgePart: agrees',
					'CornerWedgePart: agrees',
				}, '\n'))
			end)
		end)
	end)

	Describe('Players', function()
		local function waitForCharacter(): Model
			local character = player.Character
			while not (character and character:FindFirstChild('HumanoidRootPart')) do
				character = player.CharacterAdded:Wait()
				task.wait()
			end
			return character :: Model
		end

		Test('A HumanoidRootPart replaced by a new one added first keeps the player in its groups.', function()
			withCleanup(function(track)
				local character = waitForCharacter()
				local group = track(Group.new({ entities = { player } }))
				local old = character:FindFirstChild('HumanoidRootPart') :: BasePart
				local before = group:contains(player)

				local new = old:Clone()
				new.Parent = character
				old:Destroy()
				task.wait()

				Expect(before).is_true()
				Expect(group:contains(player)).is_true()
				Expect(QuickZone:getEntityOfReference(player)).is(new)
				Expect(group:getEntities()[1]).is(player)
			end)
			player:LoadCharacter()
		end)

		Test('An exit callback adding the player to a group while its part goes leaves that part out.', function()
			withCleanup(function(track)
				local character = waitForCharacter()
				local hrp = character:FindFirstChild('HumanoidRootPart') :: BasePart
				-- Without autoClean, so the player tracker is what takes the part out, not a group seeing it go
				local first = track(Group.new({ entities = { player }, autoClean = false }))
				local second = track(Group.new({ autoClean = false }))
				local zone = track(Zone.new(cube(hrp.Position, 50)))
				local observer = track(Observer.new({ zones = { zone }, groups = { first }, safety = false }))
				QuickZone:update(1)
				local wasInside = observer:getZoneOfPlayer(player) == zone
				observer:onExit(function(reference)
					if reference == player then
						second:add(player)
					end
				end)

				hrp.Parent = nil
				task.wait()
				local secondWhileGone = #second:getEntities()
				local groupsOfOld = #QuickZone:getGroupsOfEntity(hrp)

				player:LoadCharacter()
				waitForCharacter()
				task.wait()

				Expect(wasInside).is_true()
				Expect(secondWhileGone).is(0)
				Expect(groupsOfOld).is(0)
				Expect(second:contains(player)).is_true()
				Expect(first:contains(player)).is_true()
			end)
		end)

		Test('removeEntity on a player in a managed group warns once and keeps it there.', function()
			withCleanup(function(track)
				waitForCharacter()
				local players = track(Group.players())
				local manual = track(Group.new({ entities = { player } }))
				task.wait()
				local warnings = Util.captureWarnings(function()
					QuickZone:removeEntity(player)
				end)
				local managed = 0
				for _, message in warnings do
					if string.find(message, 'Managed Group', 1, true) then
						managed += 1
					end
				end

				Expect(managed).is(1)
				Expect(players:contains(player)).is_true()
				Expect(manual:contains(player)).is(false)
			end)
		end)
	end)
end

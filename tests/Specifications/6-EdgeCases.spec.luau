--!strict
-- Inputs and situations that random use rarely produces: non-finite and degenerate geometry, exact boundaries,
-- extreme scales, odd entities, starved ticks, callbacks that yield or disconnect each other, containers, group
-- events, bad input and players
local CollectionService = game:GetService('CollectionService')
local LogService = game:GetService('LogService')
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest

local Util = require(TestFolder.Util)
local withCleanup = Util.withCleanup
local setOf = Util.setOf

local QuickZone = require(ReplicatedStorage.QuickZone)
local Destroyed = require(ReplicatedStorage.QuickZone.Utils.Destroyed)
local State = require(ReplicatedStorage.QuickZone.Core.State)
local Zone = QuickZone.Zone
local Group = QuickZone.Group
local Observer = QuickZone.Observer

type Tiniest = typeof(require(TiniestFolder.tiniest_for_roblox).configure({}))

local NAN = 0 / 0
local INF = math.huge
local SHAPES = Util.SHAPES

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect

	local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()

	Describe('Degenerate zones', function()
		Test('Zones with non-finite or degenerate geometry never break queries for other zones.', function()
			withCleanup(function(track)
				local rng = Random.new(77)
				local origin = Vector3.new(-30000, 0, -30000)
				local normal = {}
				for i = 1, 30 do
					table.insert(normal, track(Zone.new(Util.randomZoneConfig(rng, origin, 40, i % 2 == 0))))
				end

				local configs = {
					{ cframe = CFrame.new(NAN, NAN, NAN), size = Vector3.one * 10 },
					{ cframe = CFrame.new(INF, 0, 0), size = Vector3.one * 10 },
					{ cframe = CFrame.new(-INF, -INF, -INF), size = Vector3.one * 10 },
					{ cframe = CFrame.new(origin), size = Vector3.new(NAN, 1, 1) },
					{ cframe = CFrame.new(origin), size = Vector3.new(INF, INF, INF) },
					{ cframe = CFrame.new(origin), size = Vector3.zero },
					{ cframe = CFrame.new(origin), size = Vector3.new(-5, -5, -5) },
					{ cframe = CFrame.new(1e9, 1e9, 1e9), size = Vector3.one },
					{ cframe = CFrame.new(origin), size = Vector3.one * 1e7 },
				}
				-- Each one static and dynamic. Creating may refuse them, but must not break anything
				local degenerate = {}
				for _, config in configs do
					for _, isDynamic in { false, true } do
						local ok, zone = pcall(Zone.new, {
							cframe = config.cframe,
							size = config.size,
							shape = 'Block',
							isDynamic = isDynamic,
						})
						if ok then
							table.insert(degenerate, track(zone))
						end
					end
				end
				Expect(#degenerate > 0).is_true()

				local entities = {}
				for i = 1, 60 do
					entities[i] = { Position = origin + Util.randomOffset(rng, 45) }
				end
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer =
					track(Observer.new({ zones = normal, groups = { group }, precision = 0, safety = false }))
				for _, zone in degenerate do
					observer:attach(zone)
				end

				local function check(label: string)
					local ok, err = pcall(QuickZone.update, QuickZone, 1)
					Expect(`{label}: update {if ok then 'ran' else err}`).is(`{label}: update ran`)

					for _, entity in entities do
						Expect(Util.findMismatch(normal, entity.Position, QuickZone:getZonesAtPoint(entity.Position))).is(
							nil
						)
						local zone = observer:getZoneOfEntity(entity)
						if zone then
							Expect(zone:isPointInside(entity.Position)).is(true)
						else
							for _, candidate in normal do
								Expect(candidate:isPointInside(entity.Position)).is(false)
							end
						end
					end
				end

				check('created')
				for _, entity in entities do
					entity.Position = origin + Util.randomOffset(rng, 45)
				end
				for _, zone in normal do
					if zone:isDynamic() then
						zone:setCFrame(Util.randomCFrame(rng, origin, 40))
					end
				end
				check('moved')
				for _, zone in degenerate do
					zone:destroy()
				end
				check('degenerate zones destroyed')
			end)
		end)

		Test('Many zones at the same place are all found, also after half are destroyed.', function()
			withCleanup(function(track)
				local center = Vector3.new(-30000, 0, -29000)
				local zones = {}
				for i = 1, 600 do
					table.insert(
						zones,
						track(Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 4, isDynamic = i % 2 == 0 }))
					)
				end
				QuickZone:rebuild()
				Expect(#QuickZone:getZonesAtPoint(center)).is(600)
				Expect(#QuickZone:getZonesAtPoint(center + Vector3.new(2.5, 0, 0))).is(0)

				for i = 1, 600, 2 do
					zones[i]:destroy()
				end
				QuickZone:rebuild()
				local found = setOf(QuickZone:getZonesAtPoint(center))
				local missing = 0
				for i = 2, 600, 2 do
					if not found[zones[i]] then
						missing += 1
					end
				end
				Expect(missing).is(0)
				Expect(#QuickZone:getZonesAtPoint(center)).is(300)
			end)
		end)

		Test('Tiny zones far out and huge zones are found.', function()
			withCleanup(function(track)
				local spots = {
					Vector3.new(1e6, 0, 0),
					Vector3.new(-1e6, 1e6, 0),
					Vector3.new(0, -1e6, 1e6),
					Vector3.new(123456.5, 0.25, -654321.75),
				}
				local tiny = {}
				for i, spot in spots do
					tiny[i] =
						track(Zone.new({ cframe = CFrame.new(spot), size = Vector3.one * 0.1, isDynamic = i % 2 == 0 }))
				end
				local huge = track(Zone.new({ cframe = CFrame.new(0, 3e6, 0), size = Vector3.one * 1e6 }))
				QuickZone:rebuild()

				for i, spot in spots do
					Expect(setOf(QuickZone:getZonesAtPoint(spot))[tiny[i]]).is(true)
					Expect(setOf(QuickZone:getZonesAtPoint(spot + Vector3.new(0.2, 0, 0)))[tiny[i]]).is(nil)
				end
				Expect(setOf(QuickZone:getZonesAtPoint(Vector3.new(4.9e5, 3e6 - 4.9e5, 4.9e5)))[huge]).is(true)
			end)
		end)

		Test('Every shape agrees with the trees and observers on every point of a grid, faces included.', function()
			-- Integer positions and half steps keep every coordinate exact, so faces are hit exactly
			local center = Vector3.new(-29000, 64, -29000)
			-- Rotated a quarter turn with exact axes
			local turned = CFrame.fromMatrix(center, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0))
			local sizes = {
				Block = Vector3.new(8, 4, 6),
				Ball = Vector3.new(6, 6, 6),
				Cylinder = Vector3.new(8, 6, 6),
				Wedge = Vector3.new(8, 4, 6),
				CornerWedge = Vector3.new(8, 4, 6),
			}

			local disagreements = {}
			for _, shape in SHAPES do
				for _, cframe in { CFrame.new(center), turned } do
					for _, isDynamic in { false, true } do
						withCleanup(function(track)
							local zone = track(
								Zone.new({ cframe = cframe, size = sizes[shape], shape = shape, isDynamic = isDynamic })
							)
							local entities = {}
							for x = -5, 5, 0.5 do
								for y = -5, 5, 0.5 do
									for z = -5, 5, 0.5 do
										table.insert(entities, { Position = center + Vector3.new(x, y, z) })
									end
								end
							end
							local group = track(Group.new({ entities = entities, autoClean = false }))
							local observer = track(
								Observer.new({ zones = { zone }, groups = { group }, precision = 0, safety = false })
							)
							QuickZone:update(1)

							local label = `{shape} {if cframe == turned then 'turned' else 'unrotated'} {if isDynamic
								then 'dynamic'
								else 'static'}`
							for _, entity in entities do
								local point = entity.Position
								local inside = zone:isPointInside(point)
								local found = setOf(QuickZone:getZonesAtPoint(point))[zone] == true
								local observed = observer:isPointInside(point)
								local entered = observer:getZoneOfEntity(entity) == zone
								if found ~= inside or observed ~= inside or entered ~= inside then
									table.insert(
										disagreements,
										`{label} at {point - center}: shape {inside}, tree {found}, observer {observed}, entered {entered}`
									)
									break
								end
							end
						end)
					end
				end
			end

			Expect(table.concat(disagreements, '\n')).is('')
		end)
	end)

	Describe('Odd entities', function()
		Test('Entities at non-finite positions leave their zones without stopping other entities.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -28000)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local entities = {}
				for i = 1, 8 do
					entities[i] = { Position = position + Vector3.new(i * 0.5, 0, 0) }
				end
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)
				Expect(#observer:getEntitiesInside()).is(8)

				entities[1].Position = Vector3.new(NAN, NAN, NAN)
				entities[2].Position = Vector3.new(INF, 0, 0)
				entities[3].Position = Vector3.new(position.X, NAN, position.Z)
				local ok, err = pcall(QuickZone.update, QuickZone, 1)
				Expect(if ok then 'ran' else err).is('ran')

				for i, entity in entities do
					Expect(`entity {i} in {observer:getZoneOfEntity(entity)}`).is(
						`entity {i} in {if i <= 3 then 'nil' else tostring(zone)}`
					)
				end

				-- Coming back from nowhere enters again
				entities[1].Position = position
				QuickZone:update(1)
				Expect(observer:getZoneOfEntity(entities[1])).is(zone)
			end)
		end)

		Test('An entity table that loses its position leaves its zone without stopping other entities.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27900)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local entities = { { Position = position }, { Position = position }, { Position = position } }
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)

				entities[1].Position = nil :: any
				local ok, err = pcall(QuickZone.update, QuickZone, 1)
				Expect(if ok then 'ran' else err).is('ran')

				-- Every entity is checked, the others are moved out to show it
				entities[2].Position = position + Vector3.new(100, 0, 0)
				entities[3].Position = position + Vector3.new(100, 0, 0)
				ok, err = pcall(QuickZone.update, QuickZone, 1)
				Expect(if ok then 'ran' else err).is('ran')
				Expect(observer:getZoneOfEntity(entities[1])).is(nil)
				Expect(observer:getZoneOfEntity(entities[2])).is(nil)
				Expect(observer:getZoneOfEntity(entities[3])).is(nil)
			end)
		end)

		Test('Every kind of entity enters and leaves as it moves.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27800)
				local outside = position + Vector3.new(100, 0, 0)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))

				local function part(): Part
					return track(Util.createPart({ Position = outside }))
				end
				local primaryModel = track(Instance.new('Model'))
				local primary = part()
				primary.Parent = primaryModel
				primaryModel.PrimaryPart = primary
				primaryModel.Parent = workspace
				local pivotModel = track(Instance.new('Model'))
				part().Parent = pivotModel
				pivotModel.Parent = workspace
				local holder = part()
				local attachment = Instance.new('Attachment')
				attachment.Parent = holder
				local boneHolder = part()
				local bone = Instance.new('Bone')
				bone.Parent = boneHolder
				local camera = track(Instance.new('Camera'))
				camera.CFrame = CFrame.new(outside)
				local pivotTable = { pivot = CFrame.new(outside) }
				function pivotTable.GetPivot(self: any): CFrame
					return self.pivot
				end

				local kinds: { { name: string, entity: any, move: (Vector3) -> () } } = {}
				local function kind(name: string, entity: any, move: (Vector3) -> ())
					table.insert(kinds, { name = name, entity = entity, move = move })
				end
				local basePart = part()
				kind('part', basePart, function(p)
					basePart.Position = p
				end)
				kind('model with a primary part', primaryModel, function(p)
					primaryModel:PivotTo(CFrame.new(p))
				end)
				kind('model without one', pivotModel, function(p)
					pivotModel:PivotTo(CFrame.new(p))
				end)
				kind('attachment', attachment, function(p)
					holder.Position = p
				end)
				kind('bone', bone, function(p)
					boneHolder.Position = p
				end)
				kind('camera', camera, function(p)
					camera.CFrame = CFrame.new(p)
				end)
				local cframeTable = { CFrame = CFrame.new(outside) }
				kind('table with a CFrame', cframeTable, function(p)
					cframeTable.CFrame = CFrame.new(p)
				end)
				local worldTable = { WorldPosition = outside }
				kind('table with a WorldPosition', worldTable, function(p)
					worldTable.WorldPosition = p
				end)
				kind('table with GetPivot', pivotTable, function(p)
					pivotTable.pivot = CFrame.new(p)
				end)

				local entities = {}
				for _, k in kinds do
					table.insert(entities, k.entity)
				end
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)

				local results = {}
				for _, k in kinds do
					k.move(position)
				end
				QuickZone:update(1)
				for _, k in kinds do
					table.insert(results, `{k.name}: {observer:getZoneOfEntity(k.entity) == zone}`)
				end
				for _, k in kinds do
					k.move(outside)
				end
				QuickZone:update(1)
				for _, k in kinds do
					table.insert(results, `{k.name}: {observer:getZoneOfEntity(k.entity) == zone}`)
				end

				local expected = {}
				for _, k in kinds do
					table.insert(expected, `{k.name}: true`)
				end
				for _, k in kinds do
					table.insert(expected, `{k.name}: false`)
				end
				Expect(table.concat(results, ', ')).is(table.concat(expected, ', '))
			end)
		end)

		Test('A model that loses its primary part still follows its pivot.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27700)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local model = track(Instance.new('Model'))
				local primary = track(Util.createPart({ Position = position }))
				primary.Parent = model
				model.PrimaryPart = primary
				model.Parent = workspace
				local group = track(Group.new({ entities = { model }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)
				Expect(observer:getZoneOfEntity(model)).is(zone)

				model.PrimaryPart = nil
				model:PivotTo(CFrame.new(position + Vector3.new(100, 0, 0)))
				QuickZone:update(1)
				Expect(observer:getZoneOfEntity(model)).is(nil)
			end)
		end)
	end)

	Describe('References', function()
		Test('Pointing an entity at a new reference releases the old one.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27600)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local entity = { Position = position }
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				local old, new = {}, {}
				QuickZone:setReference(entity, old)
				QuickZone:setReference(entity, new)
				QuickZone:update(1)

				Expect(QuickZone:getEntityOfReference(new)).is(entity)
				-- A plain table that leads nowhere is no entity
				Expect(QuickZone:getEntityOfReference(old)).is(nil)
				Expect(observer:getZoneOfEntity(new)).is(zone)
				Expect(observer:getZoneOfEntity(old)).is(nil)

				-- Removing through the old reference does nothing
				group:remove(old)
				Expect(group:contains(entity)).is(true)
			end)
		end)
	end)

	Describe('Zones going away and queries', function()
		Test('Destroying the zone an entity is in moves it to another zone of the observer that holds it.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27410)
				local entity = { Position = position }
				local alone = { Position = position + Vector3.new(30, 0, 0) }
				local group = track(Group.new({ entities = { entity, alone }, autoClean = false }))
				local first = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local second = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local only = track(Zone.new({ cframe = CFrame.new(alone.Position), size = Vector3.one * 10 }))
				local observer =
					track(Observer.new({ zones = { first, second, only }, groups = { group }, safety = false }))
				QuickZone:update(1)
				local events = {}
				observer:onEnter(function()
					table.insert(events, 'enter')
				end)
				observer:onExit(function()
					table.insert(events, 'exit')
				end)
				observer:onTransition(function(_, zone)
					table.insert(events, if zone == observer:getZoneOfEntity(entity) then 'transition' else 'stray')
				end)
				local current = observer:getZoneOfEntity(entity)
				local other = if current == first then second else first
				current:destroy()
				local moved = observer:getZoneOfEntity(entity)
				only:destroy()
				QuickZone:update(1)

				Expect(moved).is(other)
				Expect(table.concat(events, ',')).is('transition,exit')
				Expect(observer:getZoneOfEntity(entity)).is(other)
				Expect(observer:getZoneOfEntity(alone)).is(nil)
			end)
		end)

		Test('Observer iterators survive entities entering and leaving during the loop.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27400)
				local away = position + Vector3.new(500, 0, 0)
				local entities = {}
				for i = 1, 6 do
					entities[i] = { Position = if i <= 3 then position else away }
				end
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)
				local function churn()
					-- The inside ones leave and the outside ones come in, reusing their slots
					for i, entity in entities do
						entity.Position = if entity.Position == position then away else position
						if i == 1 then
							group:remove(entity)
							group:add(entity)
						end
					end
					QuickZone:update(1)
				end
				local results = {}
				for _, make in
					{
						function()
							return observer:iterEntitiesInside()
						end,
						function()
							return observer:iterEntitiesInZone(zone)
						end,
					}
				do
					local ok, err = pcall(function()
						local count = 0
						for _ in make() do
							count += 1
							churn()
							if count > 20 then
								error('never ends')
							end
						end
					end)
					table.insert(results, if ok then 'ok' else tostring(err))
				end

				Expect(table.concat(results, ', ')).is('ok, ok')
			end)
		end)

		Test('Loops over the same observer, nested or one after another, each see every entity once.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27395)
				local entities = {}
				for i = 1, 5 do
					entities[i] = { Position = position }
				end
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)

				-- Nested loops, then a loop broken out of
				local pairsSeen = 0
				for _ in observer:iterEntitiesInside() do
					for _ in observer:iterEntitiesInZone(zone) do
						pairsSeen += 1
					end
				end
				for _ in observer:iterEntitiesInside() do
					break
				end
				-- A finished loop hands its list to the next one
				local finished = observer:iterEntitiesInside()
				for _ in finished do
					continue
				end
				local seen = {}
				local repeats = 0
				local iterate = observer:iterEntitiesInside()
				local entity = iterate()
				-- The finished iterator must not read the list this loop now uses
				local stale = finished()
				while entity do
					repeats += if seen[entity] then 1 else 0
					seen[entity] = true
					entity = iterate()
				end
				local count = 0
				for _ in seen do
					count += 1
				end

				Expect(pairsSeen).is(25)
				Expect(stale).is(nil)
				Expect(count).is(5)
				Expect(repeats).is(0)
			end)
		end)

		Test('Zone queries accept a Zones container, and a destroyed zone has nothing in it.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27390)
				local a = track(Util.createPart({ Position = position, Size = Vector3.one * 4 }))
				local b =
					track(Util.createPart({ Position = position + Vector3.new(20, 0, 0), Size = Vector3.one * 4 }))
				local zones = track(Zone.fromParts({ a, b }))
				local inA = { Position = position }
				local inB = { Position = b.Position }
				local group = track(Group.new({ entities = { inA, inB }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zones }, groups = { group }, safety = false }))
				QuickZone:update(1)
				local found = setOf(observer:getEntitiesInZone(zones))
				local iterated = 0
				for _ in observer:iterEntitiesInZone(zones) do
					iterated += 1
				end
				local players = observer:getPlayersInZone(zones)
				local dead = Zone.new({ cframe = CFrame.new(position), size = Vector3.one })
				dead:destroy()

				Expect(found[inA]).is_true()
				Expect(found[inB]).is_true()
				Expect(iterated).is(2)
				Expect(#players).is(0)
				Expect(#observer:getEntitiesInZone(dead)).is(0)
			end)
		end)
	end)

	Describe('Shared and member references', function()
		Test('A table reference nothing else holds survives garbage collection.', function()
			withCleanup(function(track)
				local part = track(Util.createPart({ Position = Vector3.new(-28000, 0, -27450) }))
				local group = track(Group.new({ entities = { part } }))
				QuickZone:setReference(part, { kind = 'Coin' })
				-- Waits until a table held only weakly is collected, so a collection ran
				local probe = setmetatable({ {} }, { __mode = 'v' })
				local frames = 0
				while probe[1] ~= nil and frames < 600 do
					local _ = table.create(1e5, frames)
					task.wait()
					frames += 1
				end
				local reference = QuickZone:getReferenceOfEntity(part)

				Expect(probe[1]).is(nil)
				Expect(type(reference)).is('table')
				Expect(group:getEntities()[1]).is(reference)
			end)
		end)

		Test("A member that is another entity's reference is removed itself.", function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27440)
				local function part(): BasePart
					return track(Util.createPart({ Position = position }))
				end
				local a, a2, b, c = part(), part(), part(), part()
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local first = track(Group.new({ entities = { a, a2 } }))
				local second = Group.new({ entities = { b, c } })
				local observer = track(Observer.new({ zones = { zone }, groups = { second }, safety = false }))
				local exits = 0
				observer:onExit(function()
					exits += 1
				end)
				QuickZone:update(1)
				-- b and c are members of second, and the references of a and a2
				QuickZone:setReference(a, b)
				QuickZone:setReference(a2, c)
				second:remove(b)
				local afterRemove = exits
				second:destroy()

				Expect(afterRemove).is(1)
				Expect(exits).is(2)
				Expect(#observer:getEntitiesInside()).is(0)
				Expect(State.entityData[b]).is(nil)
				Expect(State.entityData[c]).is(nil)
				Expect(first:contains(a)).is_true()
				Expect(first:contains(a2)).is_true()
			end)
		end)

		Test('Removing one of several entities that share a reference removes only that one.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27430)
				local a = track(Util.createPart({ Position = position }))
				local b = track(Util.createPart({ Position = position }))
				local npc = track(Instance.new('Model'))
				local group = track(Group.new({ entities = { a, b } }))
				QuickZone:setReference(a, npc)
				QuickZone:setReference(b, npc)
				QuickZone:removeEntity(a)

				Expect(State.entityData[a]).is(nil)
				Expect(State.entityData[b]).exists()
				Expect(#group:getEntities()).is(1)
			end)
		end)

		Test('A table with only a Transform is an entity.', function()
			local entity = { Transform = CFrame.new() }
			Expect(QuickZone:getEntityOfReference(entity)).is(entity)
		end)
	end)

	Describe('Update rates and budgets', function()
		Test('Every entity is checked eventually when the frame budget is far too small.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27400)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local entities = {}
				for i = 1, 500 do
					entities[i] = { Position = position }
				end
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				-- Moving zones make every tick rebuild a tree
				local movers = {}
				for i = 1, 50 do
					movers[i] = track(Zone.new({
						cframe = CFrame.new(position + Vector3.new(0, 500, i)),
						isDynamic = true,
						size = Vector3.one,
					}))
				end

				QuickZone:setFrameBudget(1e-6)
				for _ = 1, 200 do
					for _, mover in movers do
						mover:setCFrame(mover:getCFrame() + Vector3.new(0, 0, 0.1))
					end
					QuickZone:update(1 / 60)
				end
				QuickZone:setFrameBudget(1)

				Expect(#observer:getEntitiesInside()).is(500)
			end)
		end)

		Test('A tick with no time passed, or a long one, checks a sensible number of entities.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27300)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local entities = {}
				for i = 1, 100 do
					entities[i] = { Position = position }
				end
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))

				-- No time passed still checks one entity per update. Other tests may have left entities behind
				local updates = 0
				repeat
					QuickZone:update(0)
					updates += 1
				until #observer:getEntitiesInside() == 100 or updates > 10000
				local afterZero = #observer:getEntitiesInside()
				for _, entity in entities do
					entity.Position += Vector3.new(100, 0, 0)
				end
				-- A long hitch checks everyone once
				QuickZone:update(60)
				QuickZone:setFrameBudget(1)

				Expect(afterZero).is(100)
				Expect(#observer:getEntitiesInside()).is(0)
			end)
		end)
	end)

	Describe('Callbacks', function()
		Test('A callback disconnected by an earlier one during the same event never fires.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27200)
				local entity = { Position = position }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				local fired = 0
				local disconnectSecond
				observer:onEnter(function()
					disconnectSecond()
				end)
				disconnectSecond = observer:onEnter(function()
					fired += 1
				end)
				QuickZone:update(1)
				entity.Position += Vector3.new(100, 0, 0)
				QuickZone:update(1)
				entity.Position = position
				QuickZone:update(1)

				Expect(fired).is(0)
			end)
		end)

		Test('A safe callback that yields and then changes state leaves everything consistent.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27100)
				local entities = {}
				for i = 1, 6 do
					entities[i] = { Position = position + Vector3.new(i * 0.5, 0, 0) }
				end
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = true }))
				local enters, exits, resumed = 0, 0, 0
				observer:onEnter(function(entity)
					enters += 1
					task.wait()
					resumed += 1
					-- By now the zone may already be gone
					if entity == entities[1] and not Destroyed.isDestroyed(zone) then
						zone:destroy()
					end
				end)
				observer:onExit(function()
					exits += 1
				end)
				QuickZone:update(1)
				task.wait()
				task.wait()
				QuickZone:update(1)

				Expect(enters).is(6)
				Expect(resumed).is(6)
				Expect(exits).is(6)
				Expect(#observer:getEntitiesInside()).is(0)
				Expect(State.zoneOccupants[zone.id]).is(nil)
			end)
		end)

		Test('An unsafe callback that yields is reported without losing the entry.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27000)
				local entities = { { Position = position }, { Position = position } }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local group = track(Group.new({ entities = entities, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				observer:onEnter(function()
					task.wait()
				end)
				local ok, err = pcall(QuickZone.update, QuickZone, 1)

				Expect(if ok then 'ran' else err).is('ran')
				Expect(#observer:getEntitiesInside()).is(2)
			end)
		end)
	end)

	Describe('Containers', function()
		Test('A tagged part keeps one zone however often it moves, and loses it with its tag.', function()
			withCleanup(function(track)
				local tag = 'QZ_EDGE_MOVING_TAG'
				local folder = track(Instance.new('Folder'))
				folder.Parent = workspace
				local part = track(Util.createPart({ Position = Vector3.new(-28000, 0, -29000) }))
				CollectionService:AddTag(part, tag)
				local zones = track(Zone.fromTag(tag))

				for _ = 1, 3 do
					part.Parent = folder
					task.wait()
					part.Parent = workspace
					task.wait()
				end
				local afterMoves = #zones:getZones()
				CollectionService:RemoveTag(part, tag)
				task.wait()
				local afterUntag = #zones:getZones()

				CollectionService:AddTag(part, tag)
				task.wait()
				part.Parent = folder
				task.wait()
				part.Parent = nil
				task.wait()
				local outOfWorld = #zones:getZones()
				part.Parent = workspace
				task.wait()
				local backInWorld = #zones:getZones()

				-- Claimed by its own tag and by a tagged folder, it keeps its zone until both let go
				part.Parent = folder
				CollectionService:AddTag(folder, tag)
				task.wait()
				local bothTagged = #zones:getZones()
				CollectionService:RemoveTag(folder, tag)
				task.wait()
				local ownTagOnly = #zones:getZones()
				CollectionService:RemoveTag(part, tag)
				task.wait()

				Expect(afterMoves).is(1)
				Expect(afterUntag).is(0)
				Expect(outOfWorld).is(0)
				Expect(backInWorld).is(1)
				Expect(bothTagged).is(1)
				Expect(ownTagOnly).is(1)
				Expect(#zones:getZones()).is(0)
			end)
		end)

		Test("A container's zones follow its settings however they were toggled.", function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -28900)
				local folder = track(Instance.new('Folder'))
				folder.Parent = workspace
				local function addPart(): BasePart
					local part = Util.createPart({ Position = position })
					part.Parent = folder
					return part
				end
				local zones = track(Zone.fromChildren(folder, { isDynamic = true, autoSync = true }))
				local function zoneOf(part: BasePart): any
					for _, inner in zones:getZones() do
						if inner:getReference() == part then
							return inner
						end
					end
					return nil
				end
				local function moved(part: BasePart): boolean
					part.Position += Vector3.new(50, 0, 0)
					QuickZone:update(1)
					return (zoneOf(part):getPosition() - part.Position).Magnitude < 1e-3
				end

				local first = addPart()
				-- Static zones don't auto-sync, also the parts added later
				zones:setDynamic(false)
				local demoted = addPart()
				local firstStatic = not zoneOf(first):isDynamic()
				local demotedStatic = not zoneOf(demoted):isDynamic()
				local demotedMoved = moved(demoted)

				zones:setDynamic(true)
				zones:setAutoSync(true)
				local firstMoved = moved(first)

				zones:setAutoSync(false)
				local late = addPart()
				local lateDynamic = zoneOf(late):isDynamic()
				local lateMoved = moved(late)

				-- Auto-synced parts are dynamic, so the container says so
				local synced = track(Zone.fromParts({ track(Util.createPart({ Position = position })) }, {
					autoSync = true,
				}))

				Expect(firstStatic).is_true()
				Expect(demotedStatic).is_true()
				Expect(demotedMoved).is(false)
				Expect(firstMoved).is_true()
				Expect(lateDynamic).is_true()
				Expect(lateMoved).is(false)
				Expect(synced:isDynamic()).is_true()
			end)
		end)

		Test('Auto-syncing to something without a CFrame warns instead of breaking every tick.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -28800)
				local model = track(Instance.new('Model'))
				model.Parent = workspace
				local warnings = Util.captureWarnings(function()
					track(Zone.new({
						cframe = CFrame.new(position),
						size = Vector3.one,
						reference = model :: any,
						autoSync = true,
					}))
				end)
				local part = track(Util.createPart({ Position = position }))
				local zone = track(Zone.fromPart(part, { autoSync = true }))
				part.Position += Vector3.new(50, 0, 0)
				local ok, err = pcall(QuickZone.update, QuickZone, 1)

				Expect(if ok then 'ran' else err).is('ran')
				Expect(zone:getPosition()).is(part.Position)
				Expect(#warnings).is(1)
			end)
		end)

		Test('An onDestroy callback that an earlier one disconnected does not fire.', function()
			withCleanup(function(track)
				local zone = Zone.new({ cframe = CFrame.new(-28000, 0, -28700), size = Vector3.one })
				local fired = false
				local disconnectSecond
				zone:onDestroy(function()
					disconnectSecond()
				end)
				disconnectSecond = zone:onDestroy(function()
					fired = true
				end)
				zone:destroy()

				-- Zones attached to an observer that destroys them as it is destroyed
				local part = track(Util.createPart({ Position = Vector3.new(-28000, 0, -28700) }))
				local zones = Zone.fromParts({ part })
				local observer = Observer.new({})
				observer:onDestroy(function()
					zones:destroy()
				end)
				observer:attach(zones)
				local errors = {}
				local connection = LogService.MessageOut:Connect(function(message, kind)
					if kind == Enum.MessageType.MessageError then
						table.insert(errors, message)
					end
				end)
				observer:destroy()
				task.wait()
				connection:Disconnect()

				Expect(fired).is(false)
				Expect(table.concat(errors, '\n')).is('')
			end)
		end)
	end)

	Describe('Shapes fill what a part of their size fills', function()
		Test('Balls and cylinders of uneven or negative size agree with the trees and observers everywhere.', function()
			withCleanup(function(track)
				local origin = Vector3.new(-28000, 0, -28500)
				local sizes = {
					Vector3.new(10, 4, 4),
					Vector3.new(4, 10, 6),
					Vector3.new(6, 6, 12),
					Vector3.new(-10, -10, -10),
					Vector3.new(10, -2, 4),
					Vector3.zero,
				}
				local zones = {}
				for i, size in sizes do
					for j, shape in { 'Ball', 'Cylinder' } do
						local center = origin + Vector3.new(i * 30, j * 30, 0)
						local cframe = CFrame.new(center) * CFrame.fromOrientation(0.3 * i, 0.5 * j, 0)
						table.insert(zones, track(Zone.new({ cframe = cframe, size = size, shape = shape })))
					end
				end
				local observer = track(Observer.new({ zones = zones, groups = {} }))
				QuickZone:rebuild()

				local mismatch
				for _, zone in zones do
					local center = zone:getPosition()
					for x = -6, 6 do
						for y = -6, 6 do
							for z = -6, 6 do
								local point = center + Vector3.new(x, y, z)
								mismatch = mismatch or Util.findMismatch(zones, point, QuickZone:getZonesAtPoint(point))
								local inside = false
								for _, other in zones do
									inside = inside or other:isPointInside(point)
								end
								if not mismatch and observer:isPointInside(point) ~= inside then
									mismatch = `observer isPointInside disagrees at {point}`
								end
							end
						end
					end
				end

				-- A Ball fills its smallest side, a Cylinder its smallest cross-section
				local ball = zones[1]
				local cylinder = zones[2]
				local ballCenter = ball:getPosition()
				local cylinderCFrame = cylinder:getCFrame()
				local uneven = zones[4]:getCFrame()

				Expect(mismatch).is(nil)
				Expect(ball:isPointInside(ballCenter + ball:getCFrame().RightVector * 1.9)).is_true()
				Expect(ball:isPointInside(ballCenter + ball:getCFrame().RightVector * 2.1)).is(false)
				Expect(cylinder:isPointInside(cylinderCFrame * Vector3.new(4.9, 0, 0))).is_true()
				Expect(cylinder:isPointInside(cylinderCFrame * Vector3.new(0, 0, 2.1))).is(false)
				-- 4 by 10 by 6 is 6 across
				Expect(zones[4]:isPointInside(uneven * Vector3.new(1.9, 2.9, 0))).is_true()
				Expect(zones[4]:isPointInside(uneven * Vector3.new(0, 3.5, 0))).is(false)
				Expect(zones[4]:isPointInside(uneven * Vector3.new(0, 0, 3.5))).is(false)
				Expect(zones[7]:isPointInside(zones[7]:getPosition() + Vector3.new(0.5, 0, 0))).is(false)
			end)
		end)

		Test("A mesh zone moved or resized away from its part has the part's shape where the zone is.", function()
			withCleanup(function(track)
				local partPosition = Vector3.new(-28000, 0, -28300)
				local zonePosition = partPosition + Vector3.new(0, 0, 100)
				local part = track(Util.createPart({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 10,
					Position = partPosition,
				}))
				local zone = track(Zone.new({
					cframe = part.CFrame,
					size = part.Size,
					shape = 'Mesh',
					reference = part,
				}))
				zone:setCFrame(CFrame.new(zonePosition))
				local entity = { Position = zonePosition + Vector3.new(4, 0, 0) }
				local corner = { Position = zonePosition + Vector3.new(4.5, 4.5, 0) }
				local group = track(Group.new({ entities = { entity, corner }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)

				local atPart = zone:isPointInside(partPosition)
				local found = setOf(QuickZone:getZonesAtPoint(entity.Position))
				local cornerBefore = observer:getZoneOfEntity(corner)

				zone:setSize(Vector3.one * 20)
				QuickZone:update(1)

				Expect(atPart).is(false)
				Expect(found[zone]).is_true()
				Expect(observer:getZoneOfEntity(entity)).is(zone)
				-- Inside the box but outside the ball, until the ball grows
				Expect(cornerBefore).is(nil)
				Expect(observer:getZoneOfEntity(corner)).is(zone)
				Expect(zone:isPointInside(zonePosition + Vector3.new(9, 0, 0))).is_true()
				Expect(zone:isPointInside(zonePosition + Vector3.new(8, 8, 0))).is(false)
			end)
		end)

		Test('A mesh zone larger than its part is no larger than its box.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -28200)
				local part =
					track(Util.createPart({ Size = Vector3.one * 4, Position = position + Vector3.new(0, 50, 0) }))
				local zone = track(Zone.new({
					cframe = CFrame.new(position),
					size = Vector3.one * 20,
					shape = 'Mesh',
					reference = part,
				}))
				QuickZone:rebuild()
				local outside = position + Vector3.new(10.03, 0, 0)
				local inside = position + Vector3.new(9.97, 0, 0)

				Expect(zone:isPointInside(outside)).is(false)
				Expect(setOf(QuickZone:getZonesAtPoint(outside))[zone]).is(nil)
				Expect(zone:isPointInside(inside)).is_true()
				Expect(setOf(QuickZone:getZonesAtPoint(inside))[zone]).is_true()
			end)
		end)
	end)

	Describe('Group events', function()
		Test('Group events follow entities that change groups while inside.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -28100)
				local away = position + Vector3.new(100, 0, 0)
				local a = { Position = position }
				local b = { Position = away }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local first = track(Group.new({ entities = { a }, autoClean = false }))
				local second = track(Group.new({ entities = { b }, autoClean = false }))
				local third = track(Group.new({ autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { first, second }, safety = false }))
				local names = { [first] = 'first', [second] = 'second', [third] = 'third' }
				local events = {}
				observer:onGroupEnter(function(group)
					table.insert(events, `+{names[group]}`)
				end)
				observer:onGroupExit(function(group)
					table.insert(events, `-{names[group]}`)
				end)
				local function step(label: string, change: () -> ())
					change()
					QuickZone:update(1)
					table.insert(events, label)
				end

				step('|', function() end)
				-- a joins second while inside
				step('|', function()
					second:add(a)
				end)
				-- b comes and goes, second stays through a
				step('|', function()
					b.Position = position
				end)
				step('|', function()
					b.Position = away
				end)
				-- a leaves first while staying inside through second
				step('|', function()
					first:remove(a)
				end)
				-- Subscribing a group a is in, then dropping it again
				step('|', function()
					third:add(a)
					observer:subscribe(third)
				end)
				step('|', function()
					observer:unsubscribe(third)
				end)
				step('|', function()
					observer:subscribe(third)
				end)
				step('|', function()
					third:destroy()
				end)
				step('|', function()
					a.Position = away
				end)

				Expect(table.concat(events, ' ')).is(
					'+first | +second | | | -first | +third | -third | +third | -third | -second |'
				)
			end)
		end)

		Test('A group callback that errors fires again the next time.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -28000)
				local entity = { Position = position }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				local observed, entered, cleaned = 0, 0, 0
				observer:observeGroup(function()
					observed += 1
					if observed == 1 then
						error('An expected error from a test')
					end
					return function()
						cleaned += 1
					end
				end)
				observer:onGroupEnter(function()
					entered += 1
					if entered == 1 then
						error('An expected error from a test')
					end
				end)
				for _ = 1, 2 do
					QuickZone:update(1)
					entity.Position += Vector3.new(100, 0, 0)
					QuickZone:update(1)
					entity.Position = position
				end

				Expect(observed).is(2)
				Expect(entered).is(2)
				Expect(cleaned).is(1)
			end)
		end)

		Test('A group destroyed by an exit callback ahead of the group events still leaves.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27920)
				local entity = { Position = position }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				observer:onExit(function()
					group:destroy()
				end)
				local left, leftZone = 0, nil
				observer:onGroupExit(function(_, exitZone)
					left += 1
					leftZone = exitZone
				end)
				QuickZone:update(1)
				entity.Position += Vector3.new(100, 0, 0)
				QuickZone:update(1)

				Expect(left).is(1)
				Expect(leftZone).is(zone)
			end)
		end)

		Test('A group callback disconnected by an earlier one, or by itself, fires no further.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27910)
				local entity = { Position = position }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local first = track(Group.new({ autoClean = false }))
				local second = track(Group.new({ autoClean = false }))
				local third = track(Group.new({ autoClean = false }))
				local observer =
					track(Observer.new({ zones = { zone }, groups = { first, second, third }, safety = false }))
				-- Entering through two groups at once
				local own, disconnectOwn = 0, nil
				disconnectOwn = observer:onGroupEnter(function()
					own += 1
					disconnectOwn()
				end)
				first:add(entity)
				second:add(entity)
				QuickZone:update(1)
				-- Joining a group while inside, with the later callback disconnected by the earlier one
				local late, disconnectLate = 0, nil
				observer:onGroupEnter(function(group)
					if group == third then
						disconnectLate()
					end
				end)
				disconnectLate = observer:onGroupEnter(function(group)
					if group == third then
						late += 1
					end
				end)
				third:add(entity)

				Expect(own).is(1)
				Expect(late).is(0)
			end)
		end)

		Test('Groups already inside arrive when the callback is connected.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27900)
				local entity = { Position = position }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)
				local entered, exited = 0, 0
				observer:onGroupEnter(function()
					entered += 1
				end)
				observer:onGroupExit(function()
					exited += 1
				end)
				local afterConnect = entered
				entity.Position += Vector3.new(100, 0, 0)
				QuickZone:update(1)

				Expect(afterConnect).is(1)
				Expect(exited).is(1)
			end)
		end)
	end)

	Describe('Group events from calls', function()
		Test('A safe group callback that yields does not hold up the call that brought its group in.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27950)
				local entity = { Position = position }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local first = track(Group.new({ entities = { entity }, autoClean = false }))
				local second = track(Group.new({ autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { first, second }, safety = true }))
				QuickZone:update(1)
				local resumed = false
				observer:onGroupEnter(function(group)
					if group == second then
						task.wait()
						resumed = true
					end
				end)
				local thread = coroutine.create(function()
					second:add(entity)
				end)
				coroutine.resume(thread)
				local status = coroutine.status(thread)
				task.wait()
				task.wait()

				Expect(status).is('dead')
				Expect(resumed).is_true()
			end)
		end)
	end)

	Describe('Groups changed from callbacks', function()
		Test('Clearing or removing in bulk stops once an exit callback destroys the group.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27800)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local observer = track(Observer.new({ zones = { zone }, groups = {}, safety = false }))
				local results = {}
				for _, call in { 'clear', 'removeBulk' } do
					local entities = { { Position = position }, { Position = position }, { Position = position } }
					local group = Group.new({ entities = entities, autoClean = false })
					observer:subscribe(group)
					QuickZone:update(1)
					local disconnectExit = observer:onExit(function()
						if not Destroyed.isDestroyed(group) then
							group:destroy()
						end
					end)
					local ok, err = pcall(function()
						if call == 'clear' then
							group:clear()
						else
							group:removeBulk(entities)
						end
					end)
					disconnectExit()
					table.insert(results, if ok then 'ok' else `{call}: {err}`)
				end

				Expect(table.concat(results, ', ')).is('ok, ok')
				Expect(#observer:getEntitiesInside()).is(0)
			end)
		end)

		Test('Adding in bulk stops once a group enter callback destroys the group.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27850)
				local inside = { Position = position }
				local other = { Position = position }
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local first = track(Group.new({ entities = { inside }, autoClean = false }))
				local second = track(Group.new({ autoClean = false }))
				local observer = track(Observer.new({ zones = { zone }, groups = { first, second }, safety = false }))
				QuickZone:update(1)
				-- Joining second while inside brings second in at once
				observer:onGroupEnter(function(group)
					if group == second and not Destroyed.isDestroyed(second) then
						second:destroy()
					end
				end)
				local ok, err = pcall(function()
					second:addBulk({ inside, other })
				end)
				QuickZone:update(1)

				Expect(if ok then 'ok' else err).is('ok')
				Expect(observer:getZoneOfEntity(other)).is(nil)
				Expect(State.entityData[other]).is(nil)
			end)
		end)

		Test('An entity that is not valid leaves nothing behind.', function()
			withCleanup(function(track)
				local group = track(Group.new({ autoClean = true }))
				local folder = track(Instance.new('Folder'))
				local ok = pcall(function()
					group:add(folder :: any)
				end)

				Expect(ok).is_true()
				Expect(group:contains(folder)).is(false)
				Expect(State.entityToGroups[folder]).is(nil)
			end)
		end)
	end)

	Describe('Bad input', function()
		Test('An entity that errors when read neither stops other entities nor freezes observers.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27700)
				local away = position + Vector3.new(100, 0, 0)
				local exact =
					track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10, isDynamic = true }))
				local ball = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10, shape = 'Ball' }))
				local group = track(Group.new({ autoClean = false }))
				local first = track(Observer.new({ zones = { exact }, groups = { group }, safety = false }))
				local second = track(Observer.new({ zones = { ball }, groups = { group }, safety = false }))
				-- A CFrame errors in the ball's check, after the exact zone already counted a hit
				local bad = { Position = CFrame.new(position) }
				local badPivot = {
					GetPivot = function()
						return nil
					end,
				}
				local good = {}
				for i = 1, 5 do
					good[i] = { Position = position }
				end
				group:add(bad :: any)
				group:add(badPivot :: any)
				group:addBulk(good)
				local function settle()
					for _ = 1, 8 do
						pcall(QuickZone.update, QuickZone, 1)
					end
				end
				local function count(observer: any, zone: any): number
					local n = 0
					for _, entity in good do
						if observer:getZoneOfEntity(entity) == zone then
							n += 1
						end
					end
					return n
				end

				settle()
				local entered = count(first, exact) + count(second, ball)
				for _, entity in good do
					entity.Position = away
				end
				settle()
				local leftWhileBad = count(first, exact) + count(second, ball)
				group:remove(bad :: any)
				group:remove(badPivot :: any)
				for _, entity in good do
					entity.Position = position
				end
				QuickZone:update(1)

				Expect(entered).is(10)
				Expect(leftWhileBad).is(0)
				Expect(count(first, exact) + count(second, ball)).is(10)
			end)
		end)

		Test('A NaN or negative time step does not stop auto-syncing.', function()
			withCleanup(function(track)
				local part = track(Util.createPart({ Position = Vector3.new(-28000, 0, -27600) }))
				local zone = track(Zone.fromPart(part, { autoSync = true }))
				QuickZone:update(0 / 0)
				QuickZone:update(-1)
				QuickZone:update(-math.huge)
				part.Position += Vector3.new(50, 0, 0)
				QuickZone:update(1)

				Expect(zone:getPosition()).is(part.Position)
			end)
		end)

		Test('An observer given a bad zone or group is refused without leaving anything behind.', function()
			withCleanup(function(track)
				local position = Vector3.new(-28000, 0, -27420)
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local group = track(Group.new({ entities = { { Position = position } }, autoClean = false }))
				local deadGroup = Group.new({})
				local deadGroupId = deadGroup:getId()
				deadGroup:destroy()
				local deadZone = Zone.new({ cframe = CFrame.new(position), size = Vector3.one })
				deadZone:destroy()
				local before = #QuickZone:getObservers()
				local refused = {}
				for label, config in
					{
						group = { zones = { zone }, groups = { group, 'oops' :: any } },
						zone = { zones = { zone, group :: any }, groups = { group } },
						deadGroup = { zones = { zone }, groups = { group, deadGroup } },
						deadZone = { zones = { zone, deadZone }, groups = { group } },
					}
				do
					if not pcall(Observer.new, config :: any) then
						table.insert(refused, label)
					end
				end
				table.sort(refused)
				local observer = track(Observer.new({ zones = {}, groups = {} }))
				local subscribeDead = pcall(observer.subscribe, observer, deadGroup)
				local attachDead = pcall(observer.attach, observer, deadZone)

				Expect(table.concat(refused, ', ')).is('deadGroup, deadZone, group, zone')
				Expect(#QuickZone:getObservers()).is(before + 1)
				Expect(#(State.zoneAttachedObservers[zone.slot] or {})).is(0)
				Expect(subscribeDead).is(false)
				Expect(attachDead).is(false)
				Expect(State.groupToObservers[deadGroupId]).is(nil)
			end)
		end)

		Test('Observer settings that are NaN, negative or not numbers are refused where they are given.', function()
			withCleanup(function(track)
				local observer = track(Observer.new({ zones = {}, groups = {} }))
				local zone = track(Zone.new({ cframe = CFrame.new(-28000, 0, -27500), size = Vector3.one }))
				local refused = {}
				local function mustRefuse(label: string, fn: () -> ())
					if not pcall(fn) then
						table.insert(refused, label)
					end
				end
				mustRefuse('new priority', function()
					track(Observer.new({ priority = 0 / 0 }))
				end)
				mustRefuse('new rate', function()
					track(Observer.new({ updateRate = -1 }))
				end)
				mustRefuse('new rate 0', function()
					track(Observer.new({ updateRate = 0 }))
				end)
				mustRefuse('new precision', function()
					track(Observer.new({ precision = 0 / 0 }))
				end)
				mustRefuse('priority', function()
					observer:setPriority(0 / 0)
				end)
				mustRefuse('rate', function()
					observer:setUpdateRate(0 / 0)
				end)
				mustRefuse('rate 0', function()
					observer:setUpdateRate(0)
				end)
				mustRefuse('precision', function()
					observer:setPrecision(0 / 0)
				end)
				mustRefuse('subscribe', function()
					observer:subscribe(zone :: any)
				end)
				mustRefuse('budget', function()
					QuickZone:setFrameBudget(0 / 0)
				end)

				Expect(table.concat(refused, ', ')).is(
					'new priority, new rate, new rate 0, new precision, priority, rate, rate 0, precision, subscribe, budget'
				)
				Expect(observer:getPriority()).is(0)
				Expect(#observer:getGroups()).is(0)
				-- A zone's id is no group's, also when a group has the same number
				Expect((State.groupToObservers[zone:getId()] or {})[observer:getId()]).is(nil)
			end)
		end)
	end)

	Describe('Players', function()
		Test('A character taken out of the world and put back is tracked again.', function()
			withCleanup(function(track)
				local group = track(Group.players())
				local character = player.Character or player.CharacterAdded:Wait()
				local before = QuickZone:getEntityOfReference(player)
				character.Parent = nil
				task.wait()
				local away = QuickZone:getEntityOfReference(player)
				character.Parent = workspace
				task.wait()

				Expect(before ~= nil).is_true()
				Expect(away).is(nil)
				Expect(QuickZone:getEntityOfReference(player)).is(character:FindFirstChild('HumanoidRootPart'))
				-- Still a member while away, as it was added
				Expect(group:contains(player)).is_true()
			end)
		end)

		Test('A player without a character is cleared or removed for good.', function()
			withCleanup(function(track)
				local cleared = track(Group.new({}))
				local removed = track(Group.new({}))
				-- removeEntity first, as it would also undo a clear that did nothing
				local function withoutCharacter(change: () -> ())
					Players.CharacterAutoLoads = false
					local ok, err = pcall(function()
						local character = player.Character
						if character then
							character:Destroy()
						end
						task.wait()
						change()
						player:LoadCharacter()
					end)
					Players.CharacterAutoLoads = true
					if not ok then
						error(err, 0)
					end
				end
				withoutCharacter(function()
					removed:add(player)
					QuickZone:removeEntity(player)
				end)
				withoutCharacter(function()
					cleared:add(player)
					cleared:clear()
				end)

				Expect(cleared:contains(player)).is(false)
				Expect(removed:contains(player)).is(false)
			end)
		end)

		Test('A player cleared from a group or removed from QuickZone stays out after respawning.', function()
			withCleanup(function(track)
				local cleared = track(Group.new({ entities = { player } }))
				local removed = track(Group.new({ entities = { player } }))
				local destroyed = Group.new({ entities = { player } })
				local destroyedId = destroyed:getId()
				cleared:clear()
				QuickZone:removeEntity(player)
				destroyed:destroy()
				player:LoadCharacter()

				Expect(cleared:contains(player)).is(false)
				Expect(removed:contains(player)).is(false)
				Expect(State.groups[destroyedId]).is(nil)
			end)
		end)
	end)
end

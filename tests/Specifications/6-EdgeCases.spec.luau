--!strict
-- Inputs and situations that random use rarely produces: non-finite and degenerate geometry, exact boundaries,
-- extreme scales, odd entities, starved ticks, callbacks that yield or disconnect each other, containers, group
-- events, bad input and players
local CollectionService = game:GetService('CollectionService')
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
local SHAPES = { 'Block', 'Ball', 'Cylinder', 'Wedge', 'CornerWedge' }

local function setOf(list: { any }): { [any]: true }
	local set = {}
	for _, value in list do
		set[value] = true
	end
	return set
end

-- Calls fn, then destroys whatever it registered, so a failing expectation leaves nothing behind. Every entity
-- is checked in each update unless fn sets its own budget
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
		elseif not object.destroyed then
			pcall(object.destroy, object)
		end
	end
	if not ok then
		error(err, 0)
	end
end

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect

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

	Describe('Update rates and budgets', function()
		Test('A suspended observer is not entered while another observer checks the same entity.', function()
			withCleanup(function(track)
				local position = Vector3.new(-29000, 0, -27500)
				local entity = { Position = position + Vector3.new(100, 0, 0) }
				local group = track(Group.new({ entities = { entity }, autoClean = false }))
				local zone = track(Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 }))
				local suspended =
					track(Observer.new({ zones = { zone }, groups = { group }, updateRate = 0, safety = false }))
				local running = track(Observer.new({ zones = { zone }, groups = { group }, safety = false }))
				QuickZone:update(1)

				entity.Position = position
				QuickZone:update(1)
				Expect(running:getZoneOfEntity(entity)).is(zone)
				Expect(suspended:getZoneOfEntity(entity)).is(nil)

				-- Resuming catches up
				suspended:setUpdateRate(30)
				QuickZone:update(1)
				Expect(suspended:getZoneOfEntity(entity)).is(zone)

				-- Nor does it lose the entity while suspended
				suspended:setUpdateRate(0)
				entity.Position = position + Vector3.new(100, 0, 0)
				QuickZone:update(1)
				Expect(running:getZoneOfEntity(entity)).is(nil)
				Expect(suspended:getZoneOfEntity(entity)).is(zone)

				suspended:setUpdateRate(30)
				QuickZone:update(1)
				Expect(suspended:getZoneOfEntity(entity)).is(nil)
			end)
		end)

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
					if entity == entities[1] and not zone.destroyed then
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
	end)
end

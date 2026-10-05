--!strict
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

return function(Tiniest: Tiniest)
	local Describe = Tiniest.describe
	local Test = Tiniest.test
	local Expect = Tiniest.expect
	local CreatePart = Util.createPart

	local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()

	Describe('QuickZone:update', function()
		Test('A tick handles pending observer callbacks.', function()
			local enters = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onEnter(function()
				enters += 1
			end)

			Expect(enters).is(0)
			Expect(QuickZone:update(1 / 10)).is(QuickZone)
			Expect(enters).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Keeps ticking when callbacks remove entities from the bucket being ticked.', function()
			local position = Vector3.new(9000, 0, -9000)
			local entities = {}
			for i = 1, 6 do
				entities[i] = { Position = position + Vector3.new(i, 0, 0) }
			end
			local group = Group.new({ entities = entities, autoClean = false })
			local zone = Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 20 })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })
			local entered = {}
			observer:onEnter(function(entity)
				entered[entity] = true
				group:remove(entity)
			end)

			-- Every entity is evaluated in one tick
			QuickZone:setFrameBudget(1000)
			local ok, err = pcall(function()
				QuickZone:update(1)
				QuickZone:update(1)
			end)
			QuickZone:setFrameBudget(1)

			Expect(if ok then true else err).is(true)
			for _, entity in entities do
				Expect(entered[entity]).is(true)
			end

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('QuickZone:setAutoSyncRate', function()
		Test('Globally halts auto-syncing at rate 0 and resumes when above.', function()
			local rateStopped, rateResumed
			local testCFrame = CFrame.new(50, 0, 0)
			local part = CreatePart({ CFrame = CFrame.identity })
			local zone = Zone.fromPart(part, { autoSync = true })

			Expect(QuickZone:setAutoSyncRate(0)).is(QuickZone)

			part.CFrame = testCFrame
			rateStopped = zone:getCFrame()
			QuickZone:setAutoSyncRate(30):update(1 / 10)
			rateResumed = zone:getCFrame()

			Expect(rateResumed).is(testCFrame)
			Expect(rateStopped).never_is(testCFrame)
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('QuickZone:rebuild', function()
		Test('Forces new static zones to become queryable immediately.', function()
			local center = Vector3.new(5000, 0, 0)
			local zone = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 5 })

			Expect(QuickZone:rebuild()).is(QuickZone)
			Expect(QuickZone:getZonesAtPoint(center)).has_value(zone)
			zone:destroy()
		end)
	end)

	Describe('QuickZone:setReference', function()
		Test('Sets a new reference for the entity and clears it.', function()
			local id = 'QZ_SET_ENTITY_REF'
			local part = CreatePart()

			Expect(QuickZone:setReference(part, id)).is(QuickZone)
			Expect(QuickZone:getEntityOfReference(id)).is(part)
			Expect(QuickZone:getReferenceOfEntity(part)).is(id)

			QuickZone:setReference(part, nil)

			Expect(QuickZone:getEntityOfReference(id)).never_exists()
			Expect(QuickZone:getReferenceOfEntity(part)).is(part)
			part:Destroy()
		end)

		Test('Player remains tracked after being used and cleared as a reference.', function()
			local part = CreatePart()
			local first = Group.players()
			local second

			Expect(first:contains(player)).is_true()

			QuickZone:setReference(part, player)
			QuickZone:setReference(part, nil)
			first:destroy()
			second = Group.players()

			Expect(second:contains(player)).is_true()
			second:destroy()
			part:Destroy()
		end)
	end)

	Describe('QuickZone:removeEntity', function()
		Test('Removes the entity from every group and fires onExit once per observer.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB }, safety = false })

			observer:onExit(function()
				exits += 1
			end)
			QuickZone:update(1 / 10)

			Expect(QuickZone:removeEntity(part)).is(QuickZone)
			Expect(exits).is(1)
			Expect(groupA:contains(part)).never_is_true()
			Expect(groupB:contains(part)).never_is_true()

			observer:destroy()
			groupA:destroy()
			groupB:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Accepts a mapped reference in place of the raw entity.', function()
			local id = 'QZ_REMOVE_ENTITY_REF'
			local part = CreatePart()
			local group = Group.new({ entities = { part } })

			QuickZone:setReference(part, id)
			QuickZone:removeEntity(id)
			QuickZone:setReference(part, nil)

			Expect(group:contains(part)).never_is_true()
			group:destroy()
			part:Destroy()
		end)
	end)

	Describe('QuickZone:getEntityOfReference', function()
		Test('An unmapped entity is returned as-is.', function()
			local part = CreatePart()

			Expect(QuickZone:getEntityOfReference(part)).is(part)
			part:Destroy()
		end)
	end)

	Describe('QuickZone:getReferenceOfEntity', function()
		Test('Resolves to the mapped reference or the entity when unmapped.', function()
			local id = 'QZ_MAPPED_REF'
			local part = CreatePart()

			Expect(QuickZone:getReferenceOfEntity(part)).is(part)

			QuickZone:setReference(part, id)

			Expect(QuickZone:getReferenceOfEntity(part)).is(id)

			QuickZone:setReference(part, nil)

			Expect(QuickZone:getReferenceOfEntity(part)).is(part)
			part:Destroy()
		end)
	end)

	Describe('QuickZone:getObservers', function()
		Test('Registry gains the new observer and loses it when destroyed.', function()
			local before, after
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer

			before = #QuickZone:getObservers()
			observer = Observer.new({ zones = { zone } })
			after = QuickZone:getObservers()

			Expect(#after).is(before + 1)
			Expect(after).has_value(observer)

			observer:destroy()
			Expect(#QuickZone:getObservers()).is(before)
			zone:destroy()
		end)
	end)

	Describe('QuickZone:getGroups', function()
		Test('Registry gains the new group and loses it when destroyed.', function()
			local before, after
			local group

			before = #QuickZone:getGroups()
			group = Group.new()
			after = QuickZone:getGroups()

			Expect(#after).is(before + 1)
			Expect(after).has_value(group)
			group:destroy()
			Expect(#QuickZone:getGroups()).is(before)
		end)
	end)

	Describe('QuickZone:getZones', function()
		Test('Registry gains the new zone and loses it when destroyed.', function()
			local before, afterCreate
			local zone

			before = #QuickZone:getZones()
			zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			afterCreate = QuickZone:getZones()

			Expect(#afterCreate).is(before + 1)
			Expect(afterCreate).has_value(zone)
			zone:destroy()
			Expect(#QuickZone:getZones()).is(before)
		end)
	end)

	Describe('QuickZone:getEntities', function()
		Test('Mapped entities appear as their reference, unmapped entities appear as themselves.', function()
			local entities
			local id = 'QZ_GET_ENTITIES_REF'
			local partA = CreatePart()
			local partB = CreatePart()
			local group = Group.new({ entities = { partA, partB } })

			QuickZone:setReference(partA, id)
			entities = QuickZone:getEntities()
			QuickZone:setReference(partA, nil)

			Expect(entities).has_value(id)
			Expect(entities).has_value(partB)
			Expect(entities).never_has_value(partA)

			group:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('QuickZone:getZonesAtPoint', function()
		Test('Returns zones from both the static and dynamic trees that contain the point.', function()
			local hits, misses
			local center = Vector3.new(10000, 0, 0)
			local staticZone = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10 })
			local dynamicZone = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10, isDynamic = true })

			QuickZone:rebuild()
			hits = QuickZone:getZonesAtPoint(center)
			misses = QuickZone:getZonesAtPoint(center + Vector3.new(10, 0, 0))

			Expect(hits).has_value(staticZone)
			Expect(hits).has_value(dynamicZone)
			Expect(misses).never_has_value(staticZone)
			Expect(misses).never_has_value(dynamicZone)

			staticZone:destroy()
			dynamicZone:destroy()
		end)

		Test('Agrees with every zone checked on its own while zones are moved, reshaped, added and removed.', function()
			local rng = Random.new(20260930)
			local origin = Vector3.new(-7000, 0, 3000)
			local zones = {}
			local observer = Observer.new()

			local function addZone(isDynamic: boolean)
				local zone = Zone.new(Util.randomZoneConfig(rng, origin, 60, isDynamic))
				observer:attach(zone)
				table.insert(zones, zone)
			end

			local function checkPoints()
				QuickZone:rebuild()
				for _ = 1, 200 do
					local point = origin + Util.randomOffset(rng, 75)

					Expect(Util.findMismatch(zones, point, QuickZone:getZonesAtPoint(point))).is(nil)

					local iterated = {}
					for zone in QuickZone:iterZonesAtPoint(point) do
						table.insert(iterated, zone)
					end
					Expect(Util.findMismatch(zones, point, iterated)).is(nil)

					local insideAny = false
					for _, zone in zones do
						insideAny = insideAny or zone:isPointInside(point)
					end
					Expect(observer:isPointInside(point)).is(insideAny)
				end
			end

			for i = 1, 160 do
				addZone(i % 2 == 0)
			end
			checkPoints()

			-- Small moves, like a moving platform
			for _ = 1, 5 do
				for _, zone in zones do
					if zone:isDynamic() then
						zone:setCFrame(zone:getCFrame() + Util.randomOffset(rng, 2))
					end
				end
				checkPoints()
			end

			-- Teleports
			for _, zone in zones do
				if zone:isDynamic() then
					zone:setCFrame(Util.randomCFrame(rng, origin, 60))
				end
			end
			checkPoints()

			-- Moving a few static zones
			for i = 1, 20 do
				local zone = zones[i * 2 - 1]
				zone:setCFrame(Util.randomCFrame(rng, origin, 60))
			end
			checkPoints()

			-- Resizing and reshaping
			for i = 1, 40 do
				local zone = zones[rng:NextInteger(1, #zones)]
				local shape = ({ 'Block', 'Ball', 'Cylinder', 'Wedge', 'CornerWedge' })[rng:NextInteger(1, 5)]
				zone:setShape(shape)
				zone:setSize(Util.randomSize(rng, shape))
			end
			checkPoints()

			-- Removing and adding zones
			for _ = 1, 30 do
				table.remove(zones, rng:NextInteger(1, #zones)):destroy()
			end
			for i = 1, 30 do
				addZone(i % 2 == 0)
			end
			checkPoints()

			-- Switching trees
			for i = 1, 20 do
				local zone = zones[i]
				zone:setDynamic(not zone:isDynamic())
			end
			checkPoints()

			observer:destroy()
			for _, zone in zones do
				zone:destroy()
			end
		end)

		Test('Finds zones created after others were destroyed, and never the destroyed ones.', function()
			local rng = Random.new(1001)
			local origin = Vector3.new(-7000, 0, -3000)
			local zones = {}
			local destroyed = {}
			local ids = {}
			local observer = Observer.new()

			local function addZone(isDynamic: boolean)
				local zone = Zone.new(Util.randomZoneConfig(rng, origin, 60, isDynamic))
				Expect(ids[zone:getId()]).is(nil)
				ids[zone:getId()] = true
				observer:attach(zone)
				table.insert(zones, zone)
			end

			local function checkPoints(rebuilt: boolean)
				for _ = 1, 150 do
					local point = origin + Util.randomOffset(rng, 75)
					local found = QuickZone:getZonesAtPoint(point)
					local iterated = {}
					for zone in QuickZone:iterZonesAtPoint(point) do
						table.insert(iterated, zone)
					end

					for _, list in { found, iterated } do
						for _, zone in list do
							Expect(destroyed[zone]).is(nil)
							Expect(zone:isPointInside(point)).is(true)
						end
						if rebuilt then
							Expect(Util.findMismatch(zones, point, list)).is(nil)
						end
					end

					if rebuilt then
						local insideAny = false
						for _, zone in zones do
							insideAny = insideAny or zone:isPointInside(point)
						end
						Expect(observer:isPointInside(point)).is(insideAny)
					end
				end

				local live = {}
				for _, zone in zones do
					live[zone] = true
				end
				for _, list in { QuickZone:getZones(), observer:getZones() } do
					local count = 0
					for _, zone in list do
						if live[zone] then
							count += 1
						end
						Expect(destroyed[zone]).is(nil)
					end
					Expect(count).is(#zones)
				end
			end

			for i = 1, 90 do
				addZone(i % 3 == 0)
			end
			QuickZone:rebuild()
			checkPoints(true)

			for _ = 1, 5 do
				for _ = 1, 30 do
					local zone = table.remove(zones, rng:NextInteger(1, #zones))
					destroyed[zone] = true
					zone:destroy()
				end
				QuickZone:rebuild()

				for i = 1, 30 do
					addZone(i % 3 == 0)
				end
				checkPoints(false)
				QuickZone:rebuild()
				checkPoints(true)
			end

			observer:destroy()
			for _, zone in zones do
				zone:destroy()
			end
		end)
	end)

	Describe('QuickZone:getZonesOfEntity', function()
		Test('Returns zones containing the entity after each tick.', function()
			local resultA, resultB
			local cframeA = CFrame.new(1000, 0, 0)
			local cframeB = CFrame.new(2000, 0, 0)
			local part = CreatePart({ CFrame = cframeA })
			local zoneA = Zone.new({ cframe = cframeA, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = cframeB, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observerA = Observer.new({ zones = { zoneA }, groups = { group }, safety = false })
			local observerB = Observer.new({ zones = { zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)
			resultA = QuickZone:getZonesOfEntity(part)

			Expect(resultA).has_value(zoneA)
			Expect(resultA).never_has_value(zoneB)

			part.CFrame = cframeB
			QuickZone:update(1 / 10)
			resultB = QuickZone:getZonesOfEntity(part)

			Expect(resultB).has_value(zoneB)
			Expect(resultB).never_has_value(zoneA)

			observerA:destroy()
			observerB:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)
	end)

	Describe('QuickZone:getGroupsOfEntity', function()
		Test('Returns every group the entity is in.', function()
			local result
			local part = CreatePart()
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new({ entities = { part } })

			result = QuickZone:getGroupsOfEntity(part)

			Expect(#result).is(2)
			Expect(result).has_value(groupA)
			Expect(result).has_value(groupB)

			groupA:destroy()
			groupB:destroy()
			part:Destroy()
		end)
	end)

	Describe('QuickZone:iterGroups', function()
		Test('Yields every registered group.', function()
			local sawA, sawB
			local groupA = Group.new()
			local groupB = Group.new()

			for group in QuickZone:iterGroups() do
				if group == groupA then
					sawA = true
				elseif group == groupB then
					sawB = true
				end
			end

			Expect(sawA).is_true()
			Expect(sawB).is_true()
			groupA:destroy()
			groupB:destroy()
		end)
	end)

	Describe('QuickZone:iterZones', function()
		Test('Yields every registered zone across both static and dynamic trees.', function()
			local sawA, sawB
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(100, 0, 0), size = Vector3.one * 10 })

			for zone in QuickZone:iterZones() do
				if zone == zoneA then
					sawA = true
				elseif zone == zoneB then
					sawB = true
				end
			end

			Expect(sawA).is_true()
			Expect(sawB).is_true()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('QuickZone:iterEntities', function()
		Test('Reference applies to the iterator, mapped entities appear as their reference.', function()
			local sawReference, sawPart
			local id = 'QZ_ITER_ENTITIES_REF'
			local partA = CreatePart()
			local partB = CreatePart()
			local group = Group.new({ entities = { partA, partB } })

			QuickZone:setReference(partA, id)
			for entity in QuickZone:iterEntities() do
				if entity == id then
					sawReference = true
				elseif entity == partB then
					sawPart = true
				end
			end
			QuickZone:setReference(partA, nil)

			Expect(sawReference).is_true()
			Expect(sawPart).is_true()

			group:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('QuickZone:iterObservers', function()
		Test('Yields every registered observer.', function()
			local sawA, sawB
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observerA = Observer.new({ zones = { zone }, groups = {} })
			local observerB = Observer.new({ zones = { zone }, groups = {} })

			for observer in QuickZone:iterObservers() do
				if observer == observerA then
					sawA = true
				elseif observer == observerB then
					sawB = true
				end
			end

			Expect(sawA).is_true()
			Expect(sawB).is_true()

			observerA:destroy()
			observerB:destroy()
			zone:destroy()
		end)
	end)

	Describe('QuickZone:iterGroupsOfEntity', function()
		Test('Yields every group the entity is in.', function()
			local sawA, sawB
			local part = CreatePart()
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new({ entities = { part } })

			for group in QuickZone:iterGroupsOfEntity(part) do
				if group == groupA then
					sawA = true
				elseif group == groupB then
					sawB = true
				end
			end

			Expect(sawA).is_true()
			Expect(sawB).is_true()

			groupA:destroy()
			groupB:destroy()
			part:Destroy()
		end)
	end)

	Describe('QuickZone:iterZonesOfEntity', function()
		Test('Goes through every observer set, not just the first found.', function()
			local sawA, sawB
			local cframe = CFrame.new(10000, 0, 0)
			local part = CreatePart({ CFrame = cframe })
			local zoneA = Zone.new({ cframe = cframe, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = cframe, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observerA = Observer.new({ zones = { zoneA }, groups = { group }, safety = false })
			local observerB = Observer.new({ zones = { zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)
			for zone in QuickZone:iterZonesOfEntity(part) do
				if zone == zoneA then
					sawA = true
				elseif zone == zoneB then
					sawB = true
				end
			end

			Expect(sawA).is_true()
			Expect(sawB).is_true()

			observerA:destroy()
			observerB:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)
	end)

	Describe('QuickZone:iterZonesAtPoint', function()
		Test('Yields zones from both static and dynamic trees that contain the point.', function()
			local sawStatic, sawDynamic
			local center = Vector3.new(20000, 0, 0)
			local staticZone = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10 })
			local dynamicZone = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10, isDynamic = true })

			QuickZone:rebuild()
			for zone in QuickZone:iterZonesAtPoint(center) do
				if zone == staticZone then
					sawStatic = true
				elseif zone == dynamicZone then
					sawDynamic = true
				end
			end

			Expect(sawStatic).is_true()
			Expect(sawDynamic).is_true()
			staticZone:destroy()
			dynamicZone:destroy()
		end)

		Test('Never yields a zone that moved away from the point while iterating.', function()
			local center = Vector3.new(30000, 0, 0)
			local zoneA = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10 })
			local farZones = {}

			QuickZone:rebuild()
			local iterator = QuickZone:iterZonesAtPoint(center)
			local first = iterator()
			local other = if first == zoneA then zoneB else zoneA

			-- Move the other zone away and grow the tree so it gets a new buffer
			other:setCFrame(CFrame.new(center + Vector3.new(0, 500, 0)))
			for i = 1, 1000 do
				table.insert(
					farZones,
					Zone.new({ cframe = CFrame.new(center + Vector3.new(i * 20, 1000, 0)), size = Vector3.one })
				)
			end
			QuickZone:rebuild()

			for zone in iterator do
				Expect(zone).never_is(other)
			end

			zoneA:destroy()
			zoneB:destroy()
			for _, zone in farZones do
				zone:destroy()
			end
		end)

		Test(
			'Yields every zone at the point exactly once when the trees are rebuilt in place mid-iteration.',
			function()
				local center = Vector3.new(-30000, 0, 0)
				local zoneA = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10, isDynamic = true })
				local zoneB =
					Zone.new({ cframe = CFrame.new(center + Vector3.one), size = Vector3.one * 10, isDynamic = true })
				local otherZones = {}
				-- Sort after both zones, so the first walk covers enough nodes
				for i = 1, 20 do
					table.insert(
						otherZones,
						Zone.new({
							cframe = CFrame.new(center + Vector3.one * (i * 50)),
							size = Vector3.one,
							isDynamic = true,
						})
					)
				end
				QuickZone:rebuild()

				local iterator = QuickZone:iterZonesAtPoint(center)
				local seen = {}
				local first = iterator() :: any
				seen[first] = 1

				-- Sort before both zones, small enough to reuse the buffer
				for i = 1, 3 do
					table.insert(
						otherZones,
						Zone.new({
							cframe = CFrame.new(center - Vector3.one * (i * 50)),
							size = Vector3.one,
							isDynamic = true,
						})
					)
				end
				QuickZone:rebuild()

				for zone in iterator do
					seen[zone] = (seen[zone] or 0) + 1
				end

				Expect(seen[zoneA]).is(1)
				Expect(seen[zoneB]).is(1)

				zoneA:destroy()
				zoneB:destroy()
				for _, zone in otherZones do
					zone:destroy()
				end
			end
		)

		Test('Leaves the tree correct when zones move slightly during an unfinished iteration.', function()
			local center = Vector3.new(-30000, 0, 3000)
			local zones = {}
			for i = 0, 9 do
				local offset = Vector3.new(i * 20, 0, 0)
				table.insert(
					zones,
					Zone.new({ cframe = CFrame.new(center + offset), size = Vector3.one * 10, isDynamic = true })
				)
			end
			local function nudge(step: number)
				for i, zone in zones do
					zone:setCFrame(CFrame.new(center + Vector3.new((i - 1) * 20, step * 0.01, 0)))
				end
				QuickZone:rebuild()
			end

			-- Small moves refit the tree, after any backoff from earlier tests runs out
			for step = 1, 10 do
				nudge(step)
			end
			Expect(State.dynamicTree.refitSkips).is(0)

			local iterator = QuickZone:iterZonesAtPoint(center)
			Expect(iterator()).is(zones[1])
			nudge(11)
			Expect(iterator()).is(nil)

			for i, zone in zones do
				local found = QuickZone:getZonesAtPoint(center + Vector3.new((i - 1) * 20, 0, 0))
				Expect(table.find(found, zone)).never_is(nil)
			end

			for _, zone in zones do
				zone:destroy()
			end
		end)

		Test('Breaking out of an iteration does not make the next tree update allocate.', function()
			local center = Vector3.new(-30000, 0, 6000)
			local zones = {}
			for i = 0, 9 do
				local offset = Vector3.new(i * 20, 0, 0)
				table.insert(
					zones,
					Zone.new({ cframe = CFrame.new(center + offset), size = Vector3.one * 10, isDynamic = true })
				)
			end
			local function nudge(step: number)
				for i, zone in zones do
					zone:setCFrame(CFrame.new(center + Vector3.new((i - 1) * 20, step * 0.01, 0)))
				end
				QuickZone:rebuild()
			end
			for step = 1, 10 do
				nudge(step)
			end

			local reallocations = 0
			for step = 11, 20 do
				local before = State.dynamicTree.buffer
				for _ in QuickZone:iterZonesAtPoint(center) do
					break
				end
				nudge(step)
				if State.dynamicTree.buffer ~= before then
					reallocations += 1
				end
			end

			for _, zone in zones do
				zone:destroy()
			end
			Expect(reallocations).is(0)
		end)

		Test('Never yields a zone destroyed while iterating.', function()
			local center = Vector3.new(-30000, 0, 9000)
			local zoneA = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10 })
			QuickZone:rebuild()

			local iterator = QuickZone:iterZonesAtPoint(center)
			local first = iterator()
			local other = if first == zoneA then zoneB else zoneA
			other:destroy()
			QuickZone:rebuild()
			-- Takes the destroyed zone's slot
			local replacement = Zone.new({ cframe = CFrame.new(center), size = Vector3.one * 10 })

			local rest = {}
			for zone in iterator do
				table.insert(rest, zone)
			end

			Expect(#rest).is(0)
			first:destroy()
			replacement:destroy()
		end)
	end)

	Describe('Tree memory', function()
		Test('Shrinks once most zones are destroyed.', function()
			local trees = { State.staticTree, State.dynamicTree }
			local zones = {}
			for i = 1, 3000 do
				local position = Vector3.new(50000 + i * 4, 0, 0)
				table.insert(
					zones,
					Zone.new({ cframe = CFrame.new(position), size = Vector3.one, isDynamic = i % 2 == 0 })
				)
			end
			QuickZone:rebuild()

			-- One commit with a box per moved zone, building a large change tree
			for i = 1, 900 do
				zones[i]:setCFrame(zones[i]:getCFrame() + Vector3.yAxis)
			end
			QuickZone:rebuild()

			for _, zone in zones do
				zone:destroy()
			end
			QuickZone:rebuild()

			-- Every change slot gets overwritten by a small change
			local zone = Zone.new({ cframe = CFrame.new(50000, 0, 0), size = Vector3.one })
			local mover = Zone.new({ cframe = CFrame.new(50000, 0, 0), size = Vector3.one, isDynamic = true })
			for i = 1, 20 do
				zone:setCFrame(CFrame.new(50000, i, 0))
				mover:setCFrame(CFrame.new(50000, i, 0))
				QuickZone:rebuild()
			end

			-- The 3000-zone trees took about 144 KB, one zone needs a few bytes
			local limit = 64 * 1024
			for _, tree in trees do
				Expect(buffer.len(tree.buffer) < limit).is(true)
			end
			for _, changes in { State.staticChanges, State.dynamicChanges } do
				for _, slot in changes.history do
					Expect(buffer.len(slot.tree.buffer) < limit).is(true)
				end
			end

			zone:destroy()
			mover:destroy()
		end)
	end)
end

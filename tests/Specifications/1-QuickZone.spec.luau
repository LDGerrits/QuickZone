--!strict
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')

local TestFolder = ServerScriptService.Test
local TiniestFolder = TestFolder.Tiniest

local Util = require(TestFolder.Util)

local QuickZone = require(ReplicatedStorage.QuickZone)
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
	end)
end
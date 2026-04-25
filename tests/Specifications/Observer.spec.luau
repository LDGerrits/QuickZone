--!strict
local CollectionService = game:GetService('CollectionService')
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local TestFolder = ServerScriptService.Test

local QuickZone = require(ReplicatedStorage.QuickZone)
local Group = QuickZone.Group
local Zone = QuickZone.Zone
local Observer = QuickZone.Observer

type Tiniest = typeof(require(TestFolder.Tiniest.tiniest_for_roblox).configure({}))

local function Create(Properties: { [string]: any }?, ClassName: string?): BasePart
	local Part = Instance.new(ClassName or 'Part') :: BasePart
	if Properties ~= nil then
		for Property, Value in Properties do
			(Part :: any)[Property] = Value
		end
	end
	Part.Anchored = true
	Part.Parent = workspace
	return Part
end

return function(Tiniest: Tiniest)
	local Test = Tiniest.test
	local Describe = Tiniest.describe
	local Expect = Tiniest.expect

	Describe('Observer.new', function()
		Test('Creates an observer with provided config.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({
				zones = { zone },
				groups = { group },
				priority = 5,
				updateRate = 30,
				precision = 0.5,
				enabled = false,
				safety = false,
			})

			Expect(#observer:getZones()).is(1)
			Expect(#observer:getGroups()).is(1)
			Expect(observer:getPriority()).is(5)
			Expect(observer:getUpdateRate()).is(30)
			Expect(observer:getPrecision()).is(0.5)
			Expect(observer:isEnabled()).never_is_true()
			Expect(observer:isSafe()).never_is_true()

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Defaults enabled to true and priority to 0.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new()
			local observer = Observer.new({ zones = { zone }, groups = { group } })

			Expect(observer:isEnabled()).is_true()
			Expect(observer:getPriority()).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:subscribe', function()
		Test('Adds a group.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new()
			local observer = Observer.new({ zones = { zone }, groups = {} })

			Expect(observer:subscribe(group)).is(observer)
			Expect(#observer:getGroups()).is(1)
			Expect(observer:getGroups()[1]).is(group)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:unsubscribe', function()
		Test('Removes a group.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new()
			local observer = Observer.new({ zones = { zone }, groups = { group } })

			Expect(observer:unsubscribe(group)).is(observer)
			Expect(#observer:getGroups()).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)

		Test('Fires exit for entities tracked via the unsubscribed group.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local exits = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function()
				exits += 1
			end)
			QuickZone:update(1 / 10)
			Expect(exits).is(0)

			observer:unsubscribe(group)
			Expect(exits).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:attach', function()
		Test('Adds a zone.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = {}, groups = {} })

			Expect(observer:attach(zone)).is(observer)
			Expect(#observer:getZones()).is(1)
			Expect(observer:getZones()[1]).is(zone)

			observer:destroy()
			zone:destroy()
		end)

		Test('Attaching a Zones attaches every inner zone.', function()
			local parts = { Create(), Create() }
			local zones = Zone.fromParts(parts)
			local observer = Observer.new({ zones = {}, groups = {} })

			Expect(observer:attach(zones)).is(observer)
			Expect(#observer:getZones()).is(#parts)

			observer:destroy()
			zones:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)
	end)

	Describe('Observer:detach', function()
		Test('Removes a zone.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {} })

			Expect(observer:detach(zone)).is(observer)
			Expect(#observer:getZones()).is(0)

			observer:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:onEnter', function()
		Test('Fires when an entity enters an attached zone.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local enters = 0
			local lastEntity, lastZone = nil, nil
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onEnter(function(entity, enteredZone)
				enters += 1
				lastEntity = entity
				lastZone = enteredZone
			end)
			QuickZone:update(1 / 10)

			Expect(enters).is(1)
			Expect(lastEntity).is(part)
			Expect(lastZone).is(zone)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Disconnect stops it from firing.', function()
			local part = Create({ CFrame = CFrame.new(100, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local enters = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onEnter(function()
				enters += 1
			end)()

			part.CFrame = CFrame.identity
			QuickZone:update(1 / 10)

			Expect(enters).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:onExit', function()
		Test('Fires when entity exits all attached zones.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local exits = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function()
				exits += 1
			end)

			QuickZone:update(1 / 10)
			Expect(exits).is(0)

			part.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)
			Expect(exits).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Disconnect stops it from firing.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local exits = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })
			local disconnect = observer:onExit(function()
				exits += 1
			end)

			QuickZone:update(1 / 10)
			disconnect()

			part.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)
			Expect(exits).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:observe', function()
		Test('Clean-up runs on exit.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local entered, cleaned = 0, 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:observe(function()
				entered += 1
				return function()
					cleaned += 1
				end
			end)

			QuickZone:update(1 / 10)
			Expect(entered).is(1)
			Expect(cleaned).is(0)

			part.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)
			Expect(cleaned).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Disconnect runs cleanups for active entities.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local cleaned = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			local disconnect = observer:observe(function()
				return function()
					cleaned += 1
				end
			end)

			QuickZone:update(1 / 10)
			Expect(cleaned).is(0)
			disconnect()

			task.wait()
			Expect(cleaned).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:onTransition', function()
		Test('Fires when entity transitions between overlapping zones.', function()
			local zoneA = Zone.new({ cframe = CFrame.new(-3, 0, 0), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(3, 0, 0), size = Vector3.one * 10 })
			local part = Create({ CFrame = CFrame.new(-6, 0, 0) })
			local group = Group.new({ entities = { part } })
			local transitions = 0
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			observer:onTransition(function()
				transitions += 1
			end)

			QuickZone:update(1 / 10)
			part.CFrame = CFrame.new(0, 0, 0) -- In both zones.
			QuickZone:update(1 / 10)
			part.CFrame = CFrame.new(6, 0, 0) -- In zoneB only.
			QuickZone:update(1 / 10)

			Expect(transitions).is(1)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)

		Test('Disconnect stops it from firing.', function()
			local zoneA = Zone.new({ cframe = CFrame.new(-3, 0, 0), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(3, 0, 0), size = Vector3.one * 10 })
			local part = Create({ CFrame = CFrame.new(-6, 0, 0) })
			local group = Group.new({ entities = { part } })
			local transitions = 0
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			local disconnect = observer:onTransition(function()
				transitions += 1
			end)

			QuickZone:update(1 / 10)
			disconnect()

			part.CFrame = CFrame.new(0, 0, 0)
			QuickZone:update(1 / 10)
			part.CFrame = CFrame.new(6, 0, 0)
			QuickZone:update(1 / 10)

			Expect(transitions).is(0)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:onGroupEnter', function()
		Test('Fires once per group entry cycle.', function()
			local partA = Create({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = Create({ CFrame = CFrame.new(100, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local fires = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onGroupEnter(function()
				fires += 1
			end)

			QuickZone:update(1 / 10)
			Expect(fires).is(1)

			partB.CFrame = CFrame.new(3, 0, 0)
			QuickZone:update(1 / 10)
			Expect(fires).is(1)

			partA.CFrame = CFrame.new(100, 0, 0)
			partB.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)

			partA.CFrame = CFrame.new(-3, 0, 0)
			QuickZone:update(1 / 10)
			Expect(fires).is(2)

			observer:destroy()
			group:destroy()
			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Fires once per subscribed group when an entity in multiple groups enters.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new({ entities = { part } })
			local fires = {}
			local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB }, safety = false })

			observer:onGroupEnter(function(group)
				table.insert(fires, group)
			end)
			QuickZone:update(1 / 10)

			Expect(#fires).is(2)
			Expect(fires).has_value(groupA)
			Expect(fires).has_value(groupB)

			observer:destroy()
			groupA:destroy()
			groupB:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:onGroupExit', function()
		Test('Fires once when last entity exits.', function()
			local partA = Create({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = Create({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local fires = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onGroupExit(function()
				fires += 1
			end)

			QuickZone:update(1 / 10)
			Expect(fires).is(0)

			partA.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)
			Expect(fires).is(0)

			partB.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)
			Expect(fires).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Fires per subscribed group when an entity in multiple groups exits.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new({ entities = { part } })
			local fires = {}
			local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB }, safety = false })

			observer:onGroupExit(function(group)
				table.insert(fires, group)
			end)
			QuickZone:update(1 / 10)
			Expect(#fires).is(0)

			part.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)

			Expect(#fires).is(2)
			Expect(fires).has_value(groupA)
			Expect(fires).has_value(groupB)

			observer:destroy()
			groupA:destroy()
			groupB:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:observeGroup', function()
		Test('Clean-up runs only when last entity of group exits.', function()
			local partA = Create({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = Create({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local entered, cleaned = 0, 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:observeGroup(function()
				entered += 1
				return function()
					cleaned += 1
				end
			end)

			QuickZone:update(1 / 10)
			Expect(entered).is(1)

			partA.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)
			Expect(cleaned).is(0)

			partB.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)
			Expect(cleaned).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test(
			'Enter and clean-up run per subscribed group when an entity in multiple groups enters and exits.',
			function()
				local part = Create()
				local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
				local groupA = Group.new({ entities = { part } })
				local groupB = Group.new({ entities = { part } })
				local entered, cleaned = {}, {}
				local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB }, safety = false })

				observer:observeGroup(function(group)
					table.insert(entered, group)
					return function()
						table.insert(cleaned, group)
					end
				end)

				QuickZone:update(1 / 10)
				Expect(#entered).is(2)
				Expect(entered).has_value(groupA)
				Expect(entered).has_value(groupB)

				part.CFrame = CFrame.new(100, 0, 0)
				QuickZone:update(1 / 10)

				Expect(#cleaned).is(2)
				Expect(cleaned).has_value(groupA)
				Expect(cleaned).has_value(groupB)

				observer:destroy()
				groupA:destroy()
				groupB:destroy()
				zone:destroy()
				part:Destroy()
			end
		)
	end)

	Describe('Observer:setEnabled', function()
		Test('Toggles enabled state.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {} })

			Expect(observer:isEnabled()).is_true()
			Expect(observer:setEnabled(false)).is(observer)
			Expect(observer:isEnabled()).never_is_true()
			Expect(observer:setEnabled(true)).is(observer)
			Expect(observer:isEnabled()).is_true()

			observer:destroy()
			zone:destroy()
		end)

		Test('Disabling fires exit for tracked entities.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local exits = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function()
				exits += 1
			end)

			QuickZone:update(1 / 10)
			observer:setEnabled(false)
			Expect(exits).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:setSafety', function()
		Test('Toggles safety state.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {}, safety = true })

			Expect(observer:isSafe()).is_true()
			Expect(observer:setSafety(false)).is(observer)
			Expect(observer:isSafe()).never_is_true()

			observer:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:setPriority', function()
		Test('Round-trips priority value.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {}, priority = 7 })

			Expect(observer:getPriority()).is(7)
			Expect(observer:setPriority(15)).is(observer)
			Expect(observer:getPriority()).is(15)

			observer:destroy()
			zone:destroy()
		end)

		Test('Higher priority observer outweighs lower in overlap.', function()
			local part = Create()
			local zoneA = Zone.new({ cframe = CFrame.new(-2, 0, 0), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(2, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local lowFires, highFires = 0, 0
			local low = Observer.new({ zones = { zoneA }, groups = { group }, priority = 0, safety = false })
			local high = Observer.new({ zones = { zoneB }, groups = { group }, priority = 10, safety = false })

			low:onEnter(function()
				lowFires += 1
			end)
			high:onEnter(function()
				highFires += 1
			end)

			QuickZone:update(1 / 10)
			Expect(highFires).is(1)
			Expect(lowFires).is(0)

			high:destroy()
			low:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:setUpdateRate', function()
		Test('Round-trips update rate value.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {}, updateRate = 30 })

			Expect(observer:getUpdateRate()).is(30)
			Expect(observer:setUpdateRate(60)).is(observer)
			Expect(observer:getUpdateRate()).is(60)

			observer:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:setPrecision', function()
		Test('Round-trips precision value.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {}, precision = 0.25 })

			Expect(observer:getPrecision()).is(0.25)
			Expect(observer:setPrecision(2)).is(observer)
			Expect(observer:getPrecision()).is(2)

			observer:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:isPointInside', function()
		Test('True for points inside attached zones, false otherwise.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {} })

			QuickZone:rebuild()
			Expect(observer:isPointInside(Vector3.zero)).is_true()
			Expect(observer:isPointInside(Vector3.new(100, 0, 0))).never_is_true()

			observer:destroy()
			zone:destroy()
		end)

		Test('False after detach.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone }, groups = {} })

			QuickZone:rebuild()
			Expect(observer:isPointInside(Vector3.zero)).is_true()
			observer:detach(zone)
			QuickZone:rebuild()
			Expect(observer:isPointInside(Vector3.zero)).never_is_true()

			observer:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:getId', function()
		Test('Returns a unique number per observer.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observerA = Observer.new({ zones = { zone }, groups = {} })
			local observerB = Observer.new({ zones = { zone }, groups = {} })

			Expect(observerA:getId()).is_a('number')
			Expect(observerA:getId()).never_is(observerB:getId())

			observerA:destroy()
			observerB:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:getEntitiesInside', function()
		Test('Returns entities currently tracked inside attached zones.', function()
			local partA = Create({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = Create({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)

			local inside = observer:getEntitiesInside()
			Expect(#inside).is(2)
			Expect(inside).has_value(partA)
			Expect(inside).has_value(partB)

			observer:destroy()
			group:destroy()
			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Observer tracks entities correctly after a tagged part streams out and back in.', function()
			local tag = 'QZStreamOutInBug'

			local part = Create()
			part.Size = Vector3.new(10, 10, 10)
			part.Position = Vector3.new(0, 0, 0)
			part.Parent = workspace
			CollectionService:AddTag(part, tag)

			local zones = Zone.fromTag(tag)

			local entity = { Position = Vector3.new(0, 0, 0) }
			local group = Group.new({ entities = { entity } })

			local observer = Observer.new({
				groups = { group },
				zones = { zones },
			})

			task.wait()

			Expect(#observer:getEntitiesInside()).is(1)

			-- Streaming out
			part.Parent = nil
			task.wait()

			Expect(#observer:getEntitiesInside()).is(0)

			-- Streaming in
			part.Parent = workspace
			task.wait()
			task.wait()

			Expect(#observer:getEntitiesInside()).is(1)

			observer:destroy()
			group:destroy()
			zones:destroy()
			CollectionService:RemoveTag(part, tag)
			part:Destroy()
		end)
	end)

	Describe('Observer:iterEntitiesInside', function()
		Test('Iterates each tracked entity once.', function()
			local partA = Create({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = Create({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local seen = {}
			local count = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)

			for entity in observer:iterEntitiesInside() do
				count += 1
				seen[entity] = (seen[entity] or 0) + 1
			end

			Expect(count).is(2)
			Expect(seen[partA]).is(1)
			Expect(seen[partB]).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('Observer:getZones', function()
		Test('Returns every attached zone once.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = {} })
			local zones = observer:getZones()

			Expect(#zones).is(2)
			Expect(zones).has_value(zoneA)
			Expect(zones).has_value(zoneB)

			observer:destroy()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:iterZones', function()
		Test('Iterates every attached zone once.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local seen = {}
			local count = 0
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = {} })

			for zone in observer:iterZones() do
				count += 1
				seen[zone] = (seen[zone] or 0) + 1
			end

			Expect(count).is(2)
			Expect(seen[zoneA]).is(1)
			Expect(seen[zoneB]).is(1)

			observer:destroy()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:getGroups', function()
		Test('Returns every subscribed group once.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new()
			local groupB = Group.new()
			local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB } })
			local groups = observer:getGroups()

			Expect(#groups).is(2)
			Expect(groups).has_value(groupA)
			Expect(groups).has_value(groupB)

			observer:destroy()
			groupA:destroy()
			groupB:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:iterGroups', function()
		Test('Iterates every subscribed group once.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new()
			local groupB = Group.new()
			local seen = {}
			local count = 0
			local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB } })

			for group in observer:iterGroups() do
				count += 1
				seen[group] = (seen[group] or 0) + 1
			end

			Expect(count).is(2)
			Expect(seen[groupA]).is(1)
			Expect(seen[groupB]).is(1)

			observer:destroy()
			groupA:destroy()
			groupB:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:getZoneOfEntity', function()
		Test('Returns the zone an entity is currently tracked in.', function()
			local part = Create({ CFrame = CFrame.new(20, 0, 0) })
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)
			Expect(observer:getZoneOfEntity(part)).is(zoneB)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)

		Test('Returns nil for an entity not currently inside any zone.', function()
			local part = Create({ CFrame = CFrame.new(100, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)
			Expect(observer:getZoneOfEntity(part)).never_exists()

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:getEntitiesInZone', function()
		Test('Returns entities only in the given zone.', function()
			local partA = Create({ CFrame = CFrame.new(0, 0, 0) })
			local partB = Create({ CFrame = CFrame.new(20, 0, 0) })
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)

			local inA = observer:getEntitiesInZone(zoneA)
			local inB = observer:getEntitiesInZone(zoneB)

			Expect(#inA).is(1)
			Expect(inA).has_value(partA)
			Expect(#inB).is(1)
			Expect(inB).has_value(partB)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('Observer:iterEntitiesInZone', function()
		Test('Iterates entities in the given zone once.', function()
			local partA = Create({ CFrame = CFrame.new(0, 0, 0) })
			local partB = Create({ CFrame = CFrame.new(20, 0, 0) })
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local seen = {}
			local count = 0
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)

			for entity in observer:iterEntitiesInZone(zoneA) do
				count += 1
				seen[entity] = (seen[entity] or 0) + 1
			end

			Expect(count).is(1)
			Expect(seen[partA]).is(1)
			Expect(seen[partB]).never_exists()

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('Observer:onDestroy', function()
		Test("Fires connected callbacks and disconnected doesn't fire.", function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local firedA, firedB = 0, 0
			local observer = Observer.new({ zones = { zone }, groups = {} })

			observer:onDestroy(function()
				firedA += 1
			end)
			observer:onDestroy(function()
				firedB += 1
			end)()
			observer:destroy()

			task.wait()

			Expect(firedA).is(1)
			Expect(firedB).is(0)
			zone:destroy()
		end)
	end)

	Describe('Observer:destroy', function()
		Test('Fires exit for tracked entities.', function()
			local part = Create()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local exits = 0
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function()
				exits += 1
			end)

			QuickZone:update(1 / 10)
			observer:destroy()
			Expect(exits).is(1)

			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)
end

--!strict
local Players = game:GetService('Players')
local CollectionService = game:GetService('CollectionService')
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
	local CreateParts = Util.createParts

	local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local character = player.Character or player.CharacterAdded:Wait()

	Describe('Observer.new', function()
		Test('Each config field is properly set up.', function()
			local part = CreatePart()
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
		Test('Subscribed group appears once.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new()
			local observer = Observer.new({ zones = { zone } })

			Expect(observer:subscribe(group)).is(observer)
			Expect(#observer:getGroups()).is(1)
			Expect(observer:getGroups()[1]).is(group)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)

		Test('Subscribing re-evaluates entities already inside an attached zone.', function()
			local enters = 0
			local lastEntity
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, safety = false })

			observer:onEnter(function(e)
				enters += 1
				lastEntity = e
			end)

			Expect(enters).is(0)

			observer:subscribe(group)
			QuickZone:update(1 / 10)

			Expect(enters).is(1)
			Expect(lastEntity).is(part)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:unsubscribe', function()
		Test('Unsubscribed group no longer appears.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new()
			local observer = Observer.new({ zones = { zone }, groups = { group } })

			Expect(observer:unsubscribe(group)).is(observer)
			Expect(#observer:getGroups()).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)

		Test('Exit fires for entities only tracked via the unsubscribed group.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
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
		Test('Attached zone appears once.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new()

			Expect(observer:attach(zone)).is(observer)
			Expect(#observer:getZones()).is(1)
			Expect(observer:getZones()[1]).is(zone)

			observer:destroy()
			zone:destroy()
		end)

		Test('Inner zones added trigger onEnter for entities inside them.', function()
			local fires = 0
			local seenZone
			local tag = 'QZ_FROM_TAG'
			local part = CreatePart()
			local entity = CreatePart({ CFrame = CFrame.new(500, 0, 0) })
			local zones = Zone.fromTag(tag)
			local group = Group.new({ entities = { entity } })
			local observer = Observer.new({ groups = { group }, safety = false })

			observer:attach(zones)
			observer:onEnter(function(_, z)
				fires += 1
				seenZone = z
			end)

			Expect(fires).is(0)

			part.CFrame = CFrame.new(500, 0, 0)
			CollectionService:AddTag(part, tag)
			task.wait()
			QuickZone:update(1 / 10)

			Expect(fires).is(1)
			Expect(seenZone).exists()
			Expect(zones:contains(seenZone)).is_true()

			observer:destroy()
			group:destroy()
			zones:destroy()
			part:Destroy()
			entity:Destroy()
		end)

		Test('Attaching re-evaluates overlapping entities from already-subscribed groups.', function()
			local enters = 0
			local lastZone
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ groups = { group }, safety = false })

			observer:onEnter(function(_, z)
				enters += 1
				lastZone = z
			end)
			QuickZone:update(1 / 10)

			Expect(enters).is(0)

			observer:attach(zone)
			QuickZone:update(1 / 10)

			Expect(enters).is(1)
			Expect(lastZone).is(zone)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:detach', function()
		Test('Detached zone no longer appears in the list.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone } })

			Expect(observer:detach(zone)).is(observer)
			Expect(#observer:getZones()).is(0)
			observer:destroy()
			zone:destroy()
		end)

		Test('Detaching the only attached zone fires onExit for its entities.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function()
				exits += 1
			end)
			QuickZone:update(1 / 10)

			Expect(exits).is(0)

			observer:detach(zone)
			QuickZone:update(1 / 10)

			Expect(exits).is(1)
			Expect(#observer:getEntitiesInside()).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:observe', function()
		Test('Enter runs the callback, exit runs the cleanup returned.', function()
			local entered, cleaned = 0, 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
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

		Test('Disconnect runs cleanups for entities inside.', function()
			local cleaned = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })
			local disconnect = observer:observe(function()
				return function()
					cleaned += 1
				end
			end)

			QuickZone:update(1 / 10)

			Expect(cleaned).is(0)

			disconnect()

			Expect(cleaned).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Observer cleans up when a tagged container is destroyed.', function()
			local tag = 'QZ_FROM_TAG_OBSERVE_DESTROY'
			local model = Instance.new('Model')
			local part = CreatePart({ CFrame = CFrame.identity, Size = Vector3.one * 10 })

			part.Parent = model
			model.Parent = workspace
			CollectionService:AddTag(model, tag)

			local zones = Zone.fromTag(tag)
			local entity = CreatePart({ CFrame = CFrame.identity })
			local group = Group.new({ entities = { entity } })
			local observer = Observer.new({ zones = { zones }, groups = { group }, safety = false })

			local cleanedUp = false
			observer:observe(function()
				return function()
					cleanedUp = true
				end
			end)

			QuickZone:update(1 / 10)
			Expect(#observer:getEntitiesInside()).is(1)

			model:Destroy()
			task.wait()
			QuickZone:update(1 / 10)

			Expect(cleanedUp).is_true()
			Expect(#observer:getEntitiesInside()).is(0)

			observer:destroy()
			group:destroy()
			zones:destroy()
			entity:Destroy()
		end)
	end)

	Describe('Observer:onEnter', function()
		Test('Callback fires once when an entity enters an attached zone.', function()
			local enters = 0
			local lastEntity, lastZone
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onEnter(function(e, z)
				enters += 1
				lastEntity = e
				lastZone = z
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

		Test('Calling the disconnect function prevents future onEnter callbacks.', function()
			local enters = 0
			local part = CreatePart({ CFrame = CFrame.new(100, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
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

		Test('Every connected callback fires for a single entry event.', function()
			local order = {}
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onEnter(function()
				table.insert(order, 'A')
			end)
			observer:onEnter(function()
				table.insert(order, 'B')
			end)
			observer:onEnter(function()
				table.insert(order, 'C')
			end)
			QuickZone:update(1 / 10)

			Expect(#order).is(3)
			Expect(order).has_value('A')
			Expect(order).has_value('B')
			Expect(order).has_value('C')

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Callback receives the mapped reference, not the raw entity, when one is set.', function()
			local firstArgs = {}
			local id = 'QZ_ON_ENTER_REF'
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new()
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			QuickZone:setReference(part, id)
			group:add(part)
			observer:onEnter(function(e)
				table.insert(firstArgs, e)
			end)
			QuickZone:update(1 / 10)

			Expect(#firstArgs).is(1)
			Expect(firstArgs[1]).is(id)

			QuickZone:setReference(part, nil)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Observer can safely destroy itself from inside its own onEnter callback.', function()
			local entered = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onEnter(function()
				entered += 1
				observer:destroy()
			end)
			QuickZone:update(1 / 10)

			Expect(entered).is(1)

			QuickZone:update(1 / 10)
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:onExit', function()
		Test('Callback fires when the entity leaves every attached zone.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
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

		Test('Calling the disconnect function prevents future onExit callbacks.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function()
				exits += 1
			end)()
			part.CFrame = CFrame.new(100, 0, 0)
			QuickZone:update(1 / 10)

			Expect(exits).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Destroying a subscribed group fires onExit for every entity tracked through it.', function()
			local exited = {}
			local parts = CreateParts(3)
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = parts })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function(e)
				table.insert(exited, e)
			end)
			QuickZone:update(1 / 10)
			group:destroy()

			Expect(#exited).is(#parts)
			for _, part in parts do
				Expect(exited).has_value(part)
			end

			observer:destroy()
			zone:destroy()
			for _, part in parts do
				part:Destroy()
			end
		end)

		Test('Destroying an attached zone fires onExit for every entity tracked inside it.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observer:onExit(function()
				exits += 1
			end)
			QuickZone:update(1 / 10)
			zone:destroy()

			Expect(exits).is(1)

			observer:destroy()
			group:destroy()
			part:Destroy()
		end)

		Test('Destroying a zone exits exactly the entities in it, for each observer that placed them there.', function()
			local origin = Vector3.new(4000, 0, -4000)
			local away = origin + Vector3.new(100, 0, 0)
			local stays = { Position = origin }
			local joins = { Position = away }
			local leaves = { Position = origin }
			local elsewhere = { Position = away }
			local group = Group.new({ entities = { stays, joins, leaves, elsewhere }, autoClean = false })

			local zone = Zone.new({ cframe = CFrame.new(origin), size = Vector3.one * 10 })
			local other = Zone.new({ cframe = CFrame.new(away), size = Vector3.one * 10 })
			local observers = {
				Observer.new({ zones = { zone, other }, groups = { group }, safety = false }),
				Observer.new({ zones = { zone }, groups = { group }, safety = false }),
				Observer.new({ zones = { zone }, groups = { group }, safety = false }),
			}
			QuickZone:update(1)

			-- One entity joins, one leaves, and the third observer detaches
			joins.Position = origin
			leaves.Position = away
			observers[3]:detach(zone)
			QuickZone:update(1)

			local exited = { {}, {}, {} }
			local disconnects = {}
			for index, observer in observers do
				disconnects[index] = observer:onExit(function(entity, exitedZone)
					exited[index][entity] = exitedZone
				end)
			end
			zone:destroy()
			for _, disconnect in disconnects do
				disconnect()
			end

			for index = 1, 2 do
				Expect(exited[index][stays]).is(zone)
				Expect(exited[index][joins]).is(zone)
				Expect(exited[index][leaves]).is(nil)
				Expect(exited[index][elsewhere]).is(nil)
			end
			Expect(next(exited[3])).is(nil)
			Expect(observers[1]:getZoneOfEntity(leaves)).is(other)
			Expect(observers[1]:getZoneOfEntity(elsewhere)).is(other)
			Expect(observers[2]:getZoneOfEntity(stays)).is(nil)

			for _, observer in observers do
				observer:destroy()
			end
			group:destroy()
			other:destroy()
		end)
	end)

	Describe('Observer:observePlayer', function()
		Test('Enter receives the player reference as the first argument.', function()
			local enterPlayer
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 20 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			character:PivotTo(CFrame.new(500, 0, 0))
			observer:observePlayer(function(p)
				enterPlayer = p
				return nil
			end)
			character:PivotTo(CFrame.identity)
			QuickZone:update(1 / 10)

			Expect(enterPlayer).is(player)
			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:onPlayerEnter', function()
		Test('Callback fires when the player enters the zone.', function()
			local fired = 0
			local seenPlayer, seenZone
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 20 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			character:PivotTo(CFrame.new(500, 0, 0))
			observer:onPlayerEnter(function(p, z)
				fired += 1
				seenPlayer = p
				seenZone = z
			end)
			character:PivotTo(CFrame.identity)
			QuickZone:update(1 / 10)

			Expect(fired).is(1)
			Expect(seenPlayer).is(player)
			Expect(seenZone).is(zone)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:onPlayerExit', function()
		Test('Callback fires with the player when they leave every attached zone.', function()
			local fired = 0
			local seenPlayer
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 20 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			character:PivotTo(CFrame.identity)
			observer:onPlayerExit(function(p)
				fired += 1
				seenPlayer = p
			end)
			QuickZone:update(1 / 10)

			Expect(fired).is(0)

			character:PivotTo(CFrame.new(500, 0, 0))
			QuickZone:update(1 / 10)

			Expect(fired).is(1)
			Expect(seenPlayer).is(player)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:observeGroup', function()
		Test('Cleanup is deferred until the last member of the group leaves.', function()
			local entered, cleaned = 0, 0
			local partA = CreatePart({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = CreatePart({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
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
	end)

	Describe('Observer:onGroupEnter', function()
		Test('Fires once when the first member enters and not again until a full exit and re-entry.', function()
			local fires = 0
			local partA = CreatePart({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = CreatePart({ CFrame = CFrame.new(100, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
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

		Test('Multi-group entry fires once per subscribed group.', function()
			local fires = {}
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB }, safety = false })

			observer:onGroupEnter(function(g)
				table.insert(fires, g)
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
		Test('Fires only when the last member leaves, with partial exits silent.', function()
			local fires = 0
			local partA = CreatePart({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = CreatePart({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
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

		Test('Multi-group exit fires once per subscribed group.', function()
			local fires = {}
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new({ entities = { part } })
			local groupB = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { groupA, groupB }, safety = false })

			observer:onGroupExit(function(g)
				table.insert(fires, g)
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

	Describe('Observer:onTransition', function()
		Test('Fires when an entity crosses from one attached zone into an overlapping one.', function()
			local transitions = 0
			local zoneA = Zone.new({ cframe = CFrame.new(-3, 0, 0), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(3, 0, 0), size = Vector3.one * 10 })
			local part = CreatePart({ CFrame = CFrame.new(-6, 0, 0) })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			observer:onTransition(function()
				transitions += 1
			end)
			part.CFrame = CFrame.new(0, 0, 0)
			QuickZone:update(1 / 10)
			part.CFrame = CFrame.new(6, 0, 0)
			QuickZone:update(1 / 10)

			Expect(transitions).is(1)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)

		Test('Calling the disconnect function prevents future callbacks.', function()
			local transitions = 0
			local zoneA = Zone.new({ cframe = CFrame.new(-3, 0, 0), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(3, 0, 0), size = Vector3.one * 10 })
			local part = CreatePart({ CFrame = CFrame.new(-6, 0, 0) })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			observer:onTransition(function()
				transitions += 1
			end)()
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

	Describe('Observer with overlapping Mesh zones', function()
		Test('Moving around the union of two overlapping parts never exits or re-enters it.', function()
			local rotation = CFrame.Angles(0.3, 1.1, 0.7)
			local partA: MeshPart = Util.create({
				className = 'MeshPart',
				properties = { CFrame = CFrame.new(50, 20, 50) * rotation, Size = Vector3.one * 20 },
			})
			local partB: MeshPart = Util.create({
				className = 'MeshPart',
				properties = { CFrame = partA.CFrame * CFrame.new(12, 0, 0), Size = Vector3.one * 20 },
			})
			local zoneA = Zone.fromPart(partA)
			local zoneB = Zone.fromPart(partB)
			local entity = CreatePart({ CFrame = partA.CFrame })
			local group = Group.new({ entities = { entity } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })
			local rng = Random.new(1)
			local enters, exits = 0, 0

			observer:onEnter(function()
				enters += 1
			end)
			observer:onExit(function()
				exits += 1
			end)

			for _ = 1, 200 do
				local localPoint =
					Vector3.new(rng:NextNumber(-9.5, 21.5), rng:NextNumber(-9.5, 9.5), rng:NextNumber(-9.5, 9.5))
				entity.CFrame = partA.CFrame * CFrame.new(localPoint)
				QuickZone:update(1 / 10)
			end

			Expect(enters).is(1)
			Expect(exits).is(0)
			Expect(observer:getEntitiesInside()).has_value(entity)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			entity:Destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('Observer:onPlayerTransition', function()
		Test('Callback fires when the player crosses between zones.', function()
			local seenPlayer, seenZone
			local zoneA = Zone.new({ cframe = CFrame.new(-3, 0, 0), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(3, 0, 0), size = Vector3.one * 10 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			character:PivotTo(CFrame.new(-6, 0, 0))
			observer:onPlayerTransition(function(p, z)
				seenPlayer = p
				seenZone = z
			end)
			character:PivotTo(CFrame.identity)
			QuickZone:update(1 / 10)
			character:PivotTo(CFrame.new(6, 0, 0))
			QuickZone:update(1 / 10)

			Expect(seenPlayer).is(player)
			Expect(seenZone).is(zoneB)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:setEnabled', function()
		Test('Toggle is reflected in isEnabled both ways.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone } })

			Expect(observer:isEnabled()).is_true()
			Expect(observer:setEnabled(false)).is(observer)
			Expect(observer:isEnabled()).never_is_true()

			observer:setEnabled(true)

			Expect(observer:isEnabled()).is_true()
			observer:destroy()
			zone:destroy()
		end)

		Test('Disabling fires onExit for every tracked entity.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
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

		Test('Re-enabling fires onEnter for entities still inside attached zones.', function()
			local enters = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, enabled = false, safety = false })

			observer:onEnter(function()
				enters += 1
			end)
			observer:setEnabled(true)
			QuickZone:update(1 / 10)

			Expect(enters).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:setPriority', function()
		Test('Higher priority observer claims the entity, lower priority never sees onEnter.', function()
			local lowFires, highFires = 0, 0
			local part = CreatePart()
			local zoneA = Zone.new({ cframe = CFrame.new(-2, 0, 0), size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(2, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
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

		Test('Lower priority observer takes over once the entity leaves the higher priority zone.', function()
			local lowFires, highFires = 0, 0
			local lowExits, highExits = 0, 0
			local part = CreatePart({ CFrame = CFrame.new(0, 0, 0) })
			local zoneLow = Zone.new({ cframe = CFrame.new(-3, 0, 0), size = Vector3.one * 10 })
			local zoneHigh = Zone.new({ cframe = CFrame.new(3, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local low = Observer.new({ zones = { zoneLow }, groups = { group }, priority = 0, safety = false })
			local high = Observer.new({ zones = { zoneHigh }, groups = { group }, priority = 10, safety = false })

			Expect(zoneLow:isPointInside(Vector3.zero)).is_true()
			Expect(zoneHigh:isPointInside(Vector3.zero)).is_true()

			low:onEnter(function()
				lowFires += 1
			end)
			low:onExit(function()
				lowExits += 1
			end)
			high:onEnter(function()
				highFires += 1
			end)
			high:onExit(function()
				highExits += 1
			end)
			QuickZone:update(1 / 10)

			Expect(highFires).is(1)
			Expect(lowFires).is(0)

			part.CFrame = CFrame.new(-7, 0, 0)
			QuickZone:update(1 / 10)

			Expect(highExits).is(1)
			Expect(lowFires).is(1)
			Expect(lowExits).is(0)

			high:destroy()
			low:destroy()
			group:destroy()
			zoneLow:destroy()
			zoneHigh:destroy()
			part:Destroy()
		end)

		Test('Swapping priorities at runtime re-resolves overlap ownership on the next update.', function()
			local aFires, aExits, bFires, bExits = 0, 0, 0, 0
			local part = CreatePart({ CFrame = CFrame.new(0, 0, 0) })
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observerA = Observer.new({ zones = { zoneA }, groups = { group }, priority = 0, safety = false })
			local observerB = Observer.new({ zones = { zoneB }, groups = { group }, priority = 10, safety = false })

			observerA:onEnter(function()
				aFires += 1
			end)
			observerA:onExit(function()
				aExits += 1
			end)
			observerB:onEnter(function()
				bFires += 1
			end)
			observerB:onExit(function()
				bExits += 1
			end)
			QuickZone:update(1 / 10)

			Expect(bFires).is(1)
			Expect(aFires).is(0)
			Expect(observerA:setPriority(20)).is(observerA)

			observerB:setPriority(0)
			QuickZone:update(1 / 10)

			Expect(bExits).is(1)
			Expect(aFires).is(1)

			observerA:destroy()
			observerB:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:setUpdateRate', function()
		Test('A zero rate suspends the observer from ticks, and a non-zero rate resumes it.', function()
			local enters = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, updateRate = 0, safety = false })

			observer:onEnter(function()
				enters += 1
			end)
			QuickZone:update(1 / 10)

			Expect(enters).is(0)
			Expect(observer:setUpdateRate(30)).is(observer)

			QuickZone:update(1 / 10)

			Expect(enters).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:setPrecision', function()
		Test('A move smaller than the precision threshold is ignored and does not trigger re-evaluation.', function()
			local exits = 0
			local part = CreatePart({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, precision = 5, safety = false })

			observer:onExit(function()
				exits += 1
			end)
			QuickZone:update(1 / 10)
			part.CFrame = CFrame.new(5.1, 0, 0)
			QuickZone:update(1 / 10)

			Expect(exits).is(0)

			part.CFrame = CFrame.new(9, 0, 0)
			QuickZone:update(1 / 10)

			Expect(exits).is(1)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Raising the precision threshold at runtime immediately starts ignoring small moves.', function()
			local exits = 0
			local part = CreatePart({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, precision = 0.5, safety = false })

			observer:onExit(function()
				exits += 1
			end)
			QuickZone:update(1 / 10)

			Expect(observer:setPrecision(5)).is(observer)

			part.CFrame = CFrame.new(5.1, 0, 0)
			QuickZone:update(1 / 10)

			Expect(exits).is(0)

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('The tighter precision applies when two observers share an entity.', function()
			local laxExits, tightExits = 0, 0
			local part = CreatePart({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local lax = Observer.new({ zones = { zone }, groups = { group }, precision = 5, safety = false })
			local tight = Observer.new({ zones = { zone }, groups = { group }, precision = 0.5, safety = false })

			lax:onExit(function()
				laxExits += 1
			end)
			tight:onExit(function()
				tightExits += 1
			end)
			QuickZone:update(1 / 10)
			part.CFrame = CFrame.new(5.5, 0, 0)
			QuickZone:update(1 / 10)

			Expect(laxExits).is(1)
			Expect(tightExits).is(1)

			tight:destroy()
			lax:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:isPointInside', function()
		Test('Returns true if the point is inside at least one attached zone.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone } })

			QuickZone:rebuild()

			Expect(observer:isPointInside(Vector3.zero)).is_true()
			Expect(observer:isPointInside(Vector3.new(100, 0, 0))).never_is_true()
			observer:destroy()
			zone:destroy()
		end)

		Test('Detaching the zone that covered a point makes that point report outside.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone } })

			QuickZone:rebuild()

			Expect(observer:isPointInside(Vector3.zero)).is_true()

			observer:detach(zone)

			Expect(observer:isPointInside(Vector3.zero)).never_is_true()
			observer:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:getId', function()
		Test('Two observers have different IDs.', function()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observerA = Observer.new({ zones = { zone } })
			local observerB = Observer.new({ zones = { zone } })

			Expect(observerA:getId()).is_a('number')
			Expect(observerA:getId()).never_is(observerB:getId())

			observerA:destroy()
			observerB:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:getEntitiesInside', function()
		Test('Return contains every entity tracked inside any attached zone.', function()
			local inside
			local partA = CreatePart({ CFrame = CFrame.new(-3, 0, 0) })
			local partB = CreatePart({ CFrame = CFrame.new(3, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)
			inside = observer:getEntitiesInside()

			Expect(#inside).is(2)
			Expect(inside).has_value(partA)
			Expect(inside).has_value(partB)

			observer:destroy()
			group:destroy()
			zone:destroy()
			partA:Destroy()
			partB:Destroy()
		end)

		Test('Tracks entities correctly after a tagged part streams out and back in.', function()
			local tag = 'QZ_STREAM_OUT_IN'
			local part = CreatePart({ Size = Vector3.one * 10 })
			local entity = { Position = Vector3.zero }
			local zones, group, observer

			CollectionService:AddTag(part, tag)
			zones = Zone.fromTag(tag)
			group = Group.new({ entities = { entity } })
			observer = Observer.new({ zones = { zones }, groups = { group } })
			task.wait()
			QuickZone:update(1 / 10)

			Expect(#observer:getEntitiesInside()).is(1)

			-- Streaming out
			part.Parent = nil
			task.wait()
			QuickZone:update(1 / 10)

			Expect(#observer:getEntitiesInside()).is(0)

			-- Streaming in
			part.Parent = workspace
			task.wait()
			QuickZone:update(1 / 10)

			Expect(#observer:getEntitiesInside()).is(1)

			CollectionService:RemoveTag(part, tag)

			observer:destroy()
			group:destroy()
			zones:destroy()
			part:Destroy()
		end)
	end)

	Describe('Observer:getPlayersInside', function()
		Test('Return contains the player while inside, and is empty after they leave.', function()
			local inside
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 20 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			character:PivotTo(CFrame.identity)
			QuickZone:update(1 / 10)
			inside = observer:getPlayersInside()

			Expect(#inside).is(1)
			Expect(inside).has_value(player)

			character:PivotTo(CFrame.new(500, 0, 0))
			QuickZone:update(1 / 10)

			Expect(#observer:getPlayersInside()).is(0)
			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:getZones', function()
		Test('Every attached zone appears in the return once.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zoneA, zoneB } })
			local zones = observer:getZones()

			Expect(#zones).is(2)
			Expect(zones).has_value(zoneA)
			Expect(zones).has_value(zoneB)

			observer:destroy()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:getGroups', function()
		Test('Every subscribed group appears in the return once.', function()
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

	Describe('Observer:getZoneOfEntity', function()
		Test('Returns the single zone the observer attributes the entity to.', function()
			local part = CreatePart({ CFrame = CFrame.new(20, 0, 0) })
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

		Test('Returns nil for an entity outside every attached zone.', function()
			local part = CreatePart({ CFrame = CFrame.new(100, 0, 0) })
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			Expect(observer:getZoneOfEntity(part)).never_exists()

			observer:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)

		Test('Sticks to the first zone the entity entered even when it later overlaps a second one.', function()
			local part = CreatePart({ CFrame = CFrame.new(-4, 0, 0) })
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(3, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)

			Expect(observer:getZoneOfEntity(part)).is(zoneA)

			part.CFrame = CFrame.identity
			QuickZone:update(1 / 10)

			Expect(observer:getZoneOfEntity(part)).is(zoneA)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			part:Destroy()
		end)

		Test(
			'Attributes each entity to a zone containing it, keeping its zone while it still fits, as everything moves.',
			function()
				local rng = Random.new(930)
				local origin = Vector3.new(6000, 0, -4000)
				local zones = {}
				for i = 1, 160 do
					table.insert(zones, Zone.new(Util.randomZoneConfig(rng, origin, 50, i % 2 == 0)))
				end

				local entities = {}
				for i = 1, 80 do
					entities[i] = { Position = origin + Util.randomOffset(rng, 55) }
				end

				local group = Group.new({ entities = entities, autoClean = false })
				local observer = Observer.new({ zones = zones, groups = { group }, precision = 0, safety = false })
				local previousZones = {}

				-- Every entity is evaluated in one tick
				QuickZone:setFrameBudget(1000)

				local function checkEntities()
					QuickZone:update(1)
					for i, entity in entities do
						local zone = observer:getZoneOfEntity(entity)
						local containing = {}
						for _, candidate in zones do
							if candidate:isPointInside(entity.Position) then
								containing[candidate] = true
							end
						end

						if zone then
							Expect(containing[zone]).is(true)
						else
							Expect(next(containing)).is(nil)
						end

						local previous = previousZones[i]
						if previous and containing[previous] then
							Expect(zone).is(previous)
						end
						previousZones[i] = zone
					end
				end

				checkEntities()

				for _ = 1, 4 do
					for _, entity in entities do
						entity.Position += Util.randomOffset(rng, 3)
					end
					for _, zone in zones do
						if zone:isDynamic() then
							zone:setCFrame(zone:getCFrame() + Util.randomOffset(rng, 2))
						end
					end
					checkEntities()
				end

				for _, zone in zones do
					if zone:isDynamic() then
						zone:setCFrame(Util.randomCFrame(rng, origin, 50))
					end
				end
				checkEntities()

				for _, entity in entities do
					entity.Position = origin + Util.randomOffset(rng, 55)
				end
				for i = 1, 20 do
					zones[i * 2 - 1]:setCFrame(Util.randomCFrame(rng, origin, 50))
				end
				checkEntities()

				QuickZone:setFrameBudget(1)
				observer:destroy()
				group:destroy()
				for _, zone in zones do
					zone:destroy()
				end
			end
		)

		Test(
			'Keeps entities that stand still in the right zone as zones move, reshape, appear, disappear and are detached.',
			function()
				local rng = Random.new(1207)
				local origin = Vector3.new(-6000, 0, 6000)

				local entities = {}
				for i = 1, 120 do
					entities[i] = { Position = origin + Util.randomOffset(rng, 55) }
				end
				local group = Group.new({ entities = entities, autoClean = false })

				-- Equal priority, some zones are shared
				local observers = {
					Observer.new({ groups = { group }, precision = 1, safety = false }),
					Observer.new({ groups = { group }, precision = 1, safety = false }),
				}
				local watched = { {}, {} } :: { { [any]: boolean } }
				local allZones = {} :: { [any]: boolean }

				local function addZone(isDynamic: boolean)
					local zone = Zone.new(Util.randomZoneConfig(rng, origin, 50, isDynamic))
					allZones[zone] = true
					local which = rng:NextInteger(1, 3)
					for index = 1, 2 do
						if which == 3 or which == index then
							observers[index]:attach(zone)
							watched[index][zone] = true
						end
					end
					return zone
				end

				local function randomZones(count: number): { any }
					local list = {}
					for zone in allZones do
						table.insert(list, zone)
					end
					table.sort(list, function(a, b)
						return a:getId() < b:getId()
					end)
					local picked = {}
					for _ = 1, math.min(count, #list) do
						table.insert(picked, table.remove(list, rng:NextInteger(1, #list)))
					end
					return picked
				end

				for i = 1, 160 do
					addZone(i % 2 == 0)
				end

				-- Every entity is evaluated in one tick
				QuickZone:setFrameBudget(1000)
				local previousZones = { {}, {} }

				local function checkEntities()
					QuickZone:update(1)
					for index, observer in observers do
						for i, entity in entities do
							local zone = observer:getZoneOfEntity(entity)
							local containing = {}
							for candidate in watched[index] do
								if candidate:isPointInside(entity.Position) then
									containing[candidate] = true
								end
							end

							if zone then
								Expect(containing[zone]).is(true)
							else
								Expect(next(containing)).is(nil)
							end

							local previous = previousZones[index][i]
							if previous and containing[previous] then
								Expect(zone).is(previous)
							end
							previousZones[index][i] = zone
						end
					end
				end

				checkEntities()

				-- Moved a little, teleported, resized and reshaped
				for _ = 1, 3 do
					for _, zone in randomZones(12) do
						zone:setCFrame(zone:getCFrame() + Util.randomOffset(rng, 4))
					end
					for _, zone in randomZones(6) do
						zone:setCFrame(Util.randomCFrame(rng, origin, 50))
					end
					for _, zone in randomZones(4) do
						zone:setPosition(origin + Util.randomOffset(rng, 50))
					end
					for _, zone in randomZones(4) do
						zone:setSize(Util.randomSize(rng, zone:getShape()))
					end
					for _, zone in randomZones(3) do
						local shape = ({ 'Block', 'Ball', 'Cylinder', 'Wedge', 'CornerWedge' })[rng:NextInteger(1, 5)]
						zone:setShape(shape)
						zone:setSize(Util.randomSize(rng, shape))
					end
					checkEntities()
				end

				-- Moved away and back within one frame
				for _, zone in randomZones(10) do
					local cframe = zone:getCFrame()
					zone:setCFrame(cframe + Vector3.new(500, 0, 0))
					zone:setCFrame(cframe)
				end
				checkEntities()

				-- Added and destroyed
				for i = 1, 20 do
					addZone(i % 2 == 0)
				end
				checkEntities()
				for _, zone in randomZones(25) do
					allZones[zone] = nil
					watched[1][zone] = nil
					watched[2][zone] = nil
					zone:destroy()
				end
				checkEntities()

				-- Detached from one observer, attached to the other
				for _, zone in randomZones(15) do
					if watched[1][zone] then
						observers[1]:detach(zone)
						watched[1][zone] = nil
					elseif not watched[2][zone] then
						observers[2]:attach(zone)
						watched[2][zone] = true
					end
				end
				checkEntities()

				-- Moved between the static and dynamic trees
				for _, zone in randomZones(12) do
					zone:setDynamic(not zone:isDynamic())
				end
				checkEntities()

				-- Several rebuilds between ticks
				for rebuilds = 1, 40 do
					for _, zone in randomZones(if rebuilds <= 3 then 12 else 2) do
						zone:setCFrame(Util.randomCFrame(rng, origin, 50))
					end
					QuickZone:rebuild()
					if rebuilds == 3 or rebuilds == 40 then
						checkEntities()
					end
				end

				QuickZone:setFrameBudget(1)
				for _, observer in observers do
					observer:destroy()
				end
				group:destroy()
				for zone in allZones do
					zone:destroy()
				end
			end
		)

		Test('Tells the entity about a new zone created where a destroyed zone it was left in stood.', function()
			local position = Vector3.new(-5000, 0, -5000)
			local entity = { Position = position }
			local group = Group.new({ entities = { entity }, autoClean = false })
			local observer = Observer.new({ groups = { group }, safety = false })

			local zoneA = Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 })
			observer:attach(zoneA)
			QuickZone:update(1)
			Expect(observer:getZoneOfEntity(entity)).is(zoneA)

			-- zoneA is destroyed before the entity is evaluated again
			observer:detach(zoneA)
			zoneA:destroy()
			QuickZone:rebuild()

			local reported = {}
			observer:onEnter(function(_, zone)
				table.insert(reported, zone)
			end)
			observer:onTransition(function(_, zone)
				table.insert(reported, zone)
			end)

			local zoneB = Zone.new({ cframe = CFrame.new(position), size = Vector3.one * 10 })
			observer:attach(zoneB)
			QuickZone:update(1)

			Expect(observer:getZoneOfEntity(entity)).is(zoneB)
			Expect(#reported).is(1)
			Expect(reported[1]).is(zoneB)

			observer:destroy()
			group:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:getZoneOfPlayer', function()
		Test('Returns the current zone for a player inside, and nil outside.', function()
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			character:PivotTo(CFrame.new(20, 0, 0))
			QuickZone:update(1 / 10)

			Expect(observer:getZoneOfPlayer(player)).is(zoneB)

			character:PivotTo(CFrame.new(500, 0, 0))
			QuickZone:update(1 / 10)

			Expect(observer:getZoneOfPlayer(player)).never_exists()

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:getEntitiesInZone', function()
		Test('Each zone returns only its own entities, with no cross-zone leakage.', function()
			local inA, inB
			local partA = CreatePart({ CFrame = CFrame.new(0, 0, 0) })
			local partB = CreatePart({ CFrame = CFrame.new(20, 0, 0) })
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)
			inA = observer:getEntitiesInZone(zoneA)
			inB = observer:getEntitiesInZone(zoneB)

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

	Describe('Observer:getPlayersInZone', function()
		Test('A zone containing a player returns the player, with other zones returning empty.', function()
			local inA, inB
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(100, 0, 0), size = Vector3.one * 10 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			character:PivotTo(CFrame.identity)
			QuickZone:update(1 / 10)
			inA = observer:getPlayersInZone(zoneA)
			inB = observer:getPlayersInZone(zoneB)

			Expect(#inA).is(1)
			Expect(inA).has_value(player)
			Expect(#inB).is(0)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:iterZones', function()
		Test('Every attached zone is yielded once.', function()
			local count = 0
			local seen = {}
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zoneA, zoneB } })

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

	Describe('Observer:iterGroups', function()
		Test('Every subscribed group is yielded once.', function()
			local count = 0
			local seen = {}
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local groupA = Group.new()
			local groupB = Group.new()
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

	Describe('Observer:iterEntitiesInside', function()
		Test('Each tracked entity is yielded with the zone the observer attributes it to.', function()
			local count = 0
			local seenZone = {}
			local partA = CreatePart({ CFrame = CFrame.new(0, 0, 0) })
			local partB = CreatePart({ CFrame = CFrame.new(20, 0, 0) })
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
			local group = Group.new({ entities = { partA, partB } })
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			QuickZone:update(1 / 10)
			for entity, zone in observer:iterEntitiesInside() do
				count += 1
				seenZone[entity] = zone
			end

			Expect(count).is(2)
			Expect(seenZone[partA]).is(zoneA)
			Expect(seenZone[partB]).is(zoneB)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
			partA:Destroy()
			partB:Destroy()
		end)
	end)

	Describe('Observer:iterPlayersInside', function()
		Test('Yields the player paired with the zone they are attributed to.', function()
			local count = 0
			local seenPlayer, seenZone
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 20 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			character:PivotTo(CFrame.identity)
			QuickZone:update(1 / 10)
			for p, z in observer:iterPlayersInside() do
				count += 1
				seenPlayer = p
				seenZone = z
			end

			Expect(count).is(1)
			Expect(seenPlayer).is(player)
			Expect(seenZone).is(zone)

			observer:destroy()
			group:destroy()
			zone:destroy()
		end)
	end)

	Describe('Observer:iterEntitiesInZone', function()
		Test(
			'Only entities attributed to the given zone are yielded, with entities from other zones absent.',
			function()
				local count = 0
				local seen = {}
				local partA = CreatePart({ CFrame = CFrame.new(0, 0, 0) })
				local partB = CreatePart({ CFrame = CFrame.new(20, 0, 0) })
				local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
				local zoneB = Zone.new({ cframe = CFrame.new(20, 0, 0), size = Vector3.one * 10 })
				local group = Group.new({ entities = { partA, partB } })
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
			end
		)
	end)

	Describe('Observer:iterPlayersInZone', function()
		Test('A zone containing a player yields them, with other zones yielding nothing.', function()
			local countA, countB = 0, 0
			local seenA
			local zoneA = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local zoneB = Zone.new({ cframe = CFrame.new(100, 0, 0), size = Vector3.one * 10 })
			local group = Group.players()
			local observer = Observer.new({ zones = { zoneA, zoneB }, groups = { group }, safety = false })

			character:PivotTo(CFrame.identity)
			QuickZone:update(1 / 10)
			for p in observer:iterPlayersInZone(zoneA) do
				countA += 1
				seenA = p
			end
			for _ in observer:iterPlayersInZone(zoneB) do
				countB += 1
			end

			Expect(countA).is(1)
			Expect(seenA).is(player)
			Expect(countB).is(0)

			observer:destroy()
			group:destroy()
			zoneA:destroy()
			zoneB:destroy()
		end)
	end)

	Describe('Observer:onDestroy', function()
		Test('Connected callbacks fire on destroy, calling the disconnect function unbinds them.', function()
			local firedA, firedB = 0, 0
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local observer = Observer.new({ zones = { zone } })

			observer:onDestroy(function()
				firedA += 1
			end)
			observer:onDestroy(function()
				firedB += 1
			end)()

			observer:destroy()
			Expect(firedA).is(1)
			Expect(firedB).is(0)
			zone:destroy()
		end)
	end)

	Describe('Observer:destroy', function()
		Test('Destroying the observer fires onExit for every tracked entity.', function()
			local exits = 0
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
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

		Test('Observer keeps tracking the shared entity after destroying another observer.', function()
			local part = CreatePart()
			local zone = Zone.new({ cframe = CFrame.identity, size = Vector3.one * 10 })
			local group = Group.new({ entities = { part } })
			local observerA = Observer.new({ zones = { zone }, groups = { group }, safety = false })
			local observerB = Observer.new({ zones = { zone }, groups = { group }, safety = false })

			observerA:onEnter(function()
				observerB:destroy()
			end)
			QuickZone:update(1 / 10)

			Expect(observerA:getEntitiesInside()).has_value(part)
			Expect(observerA:getZoneOfEntity(part)).is(zone)

			observerA:destroy()
			group:destroy()
			zone:destroy()
			part:Destroy()
		end)
	end)
end
